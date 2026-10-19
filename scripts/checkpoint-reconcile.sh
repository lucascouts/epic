#!/usr/bin/env bash
# The mechanical step of a stage checkpoint: a stage's ROADMAP tasks against
# the stories that worked on them.
#
# Usage: checkpoint-reconcile.sh --stage <N> [--root <dir>]
#
# Reads, read-only:
#   - the tasks of stage N, wherever the project keeps them: task lines
#     `- [x] **N.2.1 Title** …` and table rows `| N.2.1 | Title | … |` in
#     ROADMAP.md, docs/ROADMAP.md and docs/stages/*.md;
#   - the stories that name them: `roadmap:` in each archived entry of
#     .epic/archive/manifest.yaml, and in the tasks.md of each open story.
#
# Each task gets one state:
#   closed     an archived story names it and no open story does
#   in-work    an open story names it
#   unmapped   the checkbox is [x] and no story names it — a story from before
#              `roadmap:` existed, or work done outside a story; the checkpoint
#              maps it or the user confirms it
#   mismatch   the checkbox is [ ] and an archived story closed it — the two
#              records disagree
#   open       nothing names it and the checkbox is not [x]
# A task with no checkbox (a table row only) is judged by the stories alone.
#
# Also listed: IDs of stage N that a story names but no ROADMAP holds, and the
# stories with no `roadmap:` at all — the first checkpoint maps those by title.
# Partial coverage is never inferred: the checkpoint asks.
#
# Output: one JSON object. Exit 0; 2 on bad usage or when no ROADMAP holds a
# task of stage N.

set -euo pipefail

usage() { sed -n '6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

STAGE="" ROOT=$PWD
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE="${2-}"; shift 2 ;;
    --root) ROOT="${2-}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "checkpoint-reconcile.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$STAGE" =~ ^[0-9]+$ ]] || { echo "checkpoint-reconcile.sh: --stage <N> is required (a number)" >&2; exit 2; }
[ -d "$ROOT" ] || { echo "checkpoint-reconcile.sh: root not found: $ROOT" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd)
command -v jq >/dev/null 2>&1 || { echo "checkpoint-reconcile.sh: jq is required" >&2; exit 2; }

DOCS=()
for f in "$ROOT/ROADMAP.md" "$ROOT/docs/ROADMAP.md" "$ROOT"/docs/stages/*.md; do
  [ -f "$f" ] && DOCS+=("$f")
done

# tasks: one TSV line per task of stage N — id, title, checkbox (x, space, ~ or -), file.
# A task line wins over a table row for the same ID: it carries the checkbox.
TASKS=$(
  for f in ${DOCS[@]+"${DOCS[@]}"}; do
    rel=${f#"$ROOT"/}
    awk -v st="$STAGE" -v rel="$rel" '
      match($0, /^[[:space:]]*- \[.\] \*\*[0-9]+(\.[0-9]+)+ /) {
        box = substr($0, index($0, "[") + 1, 1)
        rest = $0; sub(/^[[:space:]]*- \[.\] \*\*/, "", rest)
        id = rest; sub(/ .*/, "", id)
        title = rest; sub(/^[^ ]+ /, "", title); sub(/\*\*.*/, "", title)
        if (index(id, st ".") == 1) print id "\t" title "\t" box "\t" rel "\t1"
        next
      }
      /^\| [0-9]+(\.[0-9]+)+ \|/ {
        n = split($0, c, "|"); id = c[2]; title = c[3]
        gsub(/^ +| +$/, "", id); gsub(/^ +| +$/, "", title)
        if (index(id, st ".") == 1) print id "\t" title "\t-\t" rel "\t0"
      }
    ' "$f"
  done | sort -t "$(printf '\t')" -k1,1 -k5,5r | awk -F'\t' '!seen[$1]++' | cut -f1-4
)
[ -n "$TASKS" ] || { echo "checkpoint-reconcile.sh: no ROADMAP or stage file holds a task of stage $STAGE" >&2; exit 2; }

# refs: one TSV line per (story, where, id); stories without roadmap: listed apart.
REFS="" UNMAPPED=()
MANIFEST="$ROOT/.epic/archive/manifest.yaml"
if [ -f "$MANIFEST" ]; then
  REFS+=$(awk '
    /^  - story: / { s = $0; sub(/^  - story: /, "", s); gsub(/"/, "", s); stories[++n] = s; next }
    /^    roadmap: / && n { r = $0; sub(/^    roadmap: /, "", r); gsub(/[][ ]/, "", r); roadmap[n] = r }
    END {
      for (i = 1; i <= n; i++) {
        if (roadmap[i] == "") { print stories[i] "\tarchived\t-"; continue }
        k = split(roadmap[i], ids, ",")
        for (j = 1; j <= k; j++) print stories[i] "\tarchived\t" ids[j]
      }
    }' "$MANIFEST")$'\n'
fi
for t in "$ROOT"/.epic/stories/*/tasks.md; do
  [ -f "$t" ] || continue
  s=$(basename "$(dirname "$t")")
  r=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } /^roadmap:/ { sub(/^roadmap:[[:space:]]*/, ""); gsub(/[][ ]/, ""); print; exit }' "$t")
  if [ -z "$r" ]; then
    REFS+="$s"$'\topen\t-\n'
  else
    for id in ${r//,/ }; do REFS+="$s"$'\topen\t'"$id"$'\n'; done
  fi
done
while IFS=$'\t' read -r s where id; do
  [ -n "$s" ] && [ "$id" = "-" ] && UNMAPPED+=("$s ($where)")
done <<< "$REFS"

TASK_IDS=$(cut -f1 <<< "$TASKS")
UNKNOWN=$(awk -F'\t' -v st="$STAGE" '$3 != "-" && index($3, st ".") == 1 { print $3 }' <<< "$REFS" | sort -u | command grep -vxF -f <(printf '%s\n' "$TASK_IDS") || true)

{
  while IFS=$'\t' read -r id title box file; do
    closed=$(awk -F'\t' -v id="$id" '$2 == "archived" && $3 == id { print $1 }' <<< "$REFS" | sort -u)
    inwork=$(awk -F'\t' -v id="$id" '$2 == "open" && $3 == id { print $1 }' <<< "$REFS" | sort -u)
    if [ -n "$inwork" ]; then state=in-work
    elif [ -n "$closed" ]; then
      if [ "$box" = " " ]; then state=mismatch; else state=closed; fi
    elif [ "$box" = "x" ]; then state=unmapped
    else state=open
    fi
    jq -cn --arg id "$id" --arg title "$title" --arg box "$box" --arg file "$file" --arg state "$state" \
      --arg closed "$closed" --arg inwork "$inwork" \
      '{id: $id, title: $title, checkbox: (if $box == "-" then null else $box end), file: $file, state: $state,
        closed_by: ($closed | split("\n") | map(select(. != ""))), in_work_by: ($inwork | split("\n") | map(select(. != "")))}'
  done <<< "$TASKS"
} | jq -s --arg stage "$STAGE" --arg unknown "$UNKNOWN" --argjson unmapped "$(printf '%s\n' ${UNMAPPED[@]+"${UNMAPPED[@]}"} | jq -R . | jq -s 'map(select(. != ""))')" '
  {stage: ($stage | tonumber),
   tasks: .,
   counts: (reduce .[] as $t ({closed: 0, "in-work": 0, unmapped: 0, mismatch: 0, open: 0}; .[$t.state] += 1)),
   unknown_ids: ($unknown | split("\n") | map(select(. != ""))),
   stories_without_roadmap: $unmapped}'
