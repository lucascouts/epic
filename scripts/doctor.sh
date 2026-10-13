#!/usr/bin/env bash
# Read-only health check of a project's .epic/ tree. Prints one JSON object
# (default) or one summary line (--summary), and changes nothing on disk.
#
#   error   — something an Epic mode will trip over: no constitution or one
#             missing a required section, a story with no tasks.md, a
#             standard/full story with no story.md.
#   warning — drift that degrades a mode without breaking it: EPIC.md absent
#             or behind the disk, no .gitpolicy, archived stories with no
#             manifest, a leftover .draft/red-scratch/, an untracked .epic/
#             copy inside a git worktree, a dormant draft, and a stall.
#
# .draft/meta.yaml is required only while a story has no tasks.md: it is the
# planning record, and a planned story whose .draft/ was cleaned up is healthy.
#
# A STALL is an in-progress story whose last progress note (.draft/progress.log,
# written by epic-progress) is older than --stall-minutes. A story with no log
# predates the notes and is never called stalled.
#
# --summary is what SessionStart and the story list call: silent when there is
# no .epic/ or nothing to report, one line otherwise. Exit 0 whenever the check
# ran, whatever it found; 2 on bad usage.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: doctor.sh [--epic-dir <dir>] [--stale-days <n>] [--stall-minutes <n>] [--summary]

  --epic-dir <dir>      The .epic directory. Default: the nearest .epic at or above the cwd.
  --stale-days <n>      A story with no boxes untouched this many days is a dormant draft. Default 7.
  --stall-minutes <n>   An in-progress story with no progress note this long is stalled. Default 15.
  --summary             One line instead of JSON; nothing when there is nothing to report.
USAGE
}

EPIC_DIR="" STALE_DAYS=7 STALL_MIN=15 SUMMARY=false
while [ $# -gt 0 ]; do
  case "$1" in
    --epic-dir) EPIC_DIR="${2-}"; shift 2 ;;
    --stale-days) STALE_DAYS="${2-}"; shift 2 ;;
    --stall-minutes) STALL_MIN="${2-}"; shift 2 ;;
    --summary) SUMMARY=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "doctor.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$STALE_DAYS" =~ ^[0-9]+$ ]] || STALE_DAYS=7
[[ "$STALL_MIN" =~ ^[0-9]+$ ]] || STALL_MIN=15

if [ -z "$EPIC_DIR" ]; then
  d=$PWD
  while :; do
    [ -d "$d/.epic" ] && { EPIC_DIR="$d/.epic"; break; }
    [ "$d" = "/" ] && break
    d=$(dirname "$d")
  done
fi
if [ -z "$EPIC_DIR" ] || [ ! -d "$EPIC_DIR" ]; then
  $SUMMARY && exit 0
  jq -n '{epic_dir: null, status: "absent", errors: 0, warnings: 0, findings: []}'
  exit 0
fi
EPIC_DIR=$(cd "$EPIC_DIR" && pwd)
ROOT=$(dirname "$EPIC_DIR")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

FINDINGS=()
add() { FINDINGS+=("$(jq -cn --arg s "$1" --arg c "$2" --arg t "$3" --arg d "$4" '{severity: $s, check: $c, target: $t, detail: $d}')"); }

# front <file> <key> — the value of <key> in the file's leading frontmatter.
front() {
  [ -f "$1" ] || return 0
  awk -v k="$2" 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    NR > 1 { if (index($0, k ":") == 1) { v = substr($0, length(k) + 2); gsub(/^[ \t"]+|[ \t"]+$/, "", v); print v; exit } }' "$1"
}

# --- Project files ---
C="$EPIC_DIR/constitution.md"
if [ ! -f "$C" ]; then
  add error constitution .epic/constitution.md "missing — run init to write it"
else
  for h in Defaults Quality; do
    grep -q "^## ${h}[[:space:]]*$" "$C" || add error constitution .epic/constitution.md "no '## $h' section — re-run init to add it"
  done
fi

[ -f "$EPIC_DIR/.gitpolicy" ] || add warning gitpolicy .epic/.gitpolicy "missing — init records whether .epic/ is tracked"

if [ ! -f "$EPIC_DIR/EPIC.md" ]; then
  add warning index .epic/EPIC.md "missing — run epic-index"
else
  # Regenerate into a scratch copy that sees the same stories/ and archive/.
  T=$(mktemp -d)
  trap 'rm -rf "$T"' EXIT
  mkdir "$T/.epic"
  cp "$EPIC_DIR/EPIC.md" "$T/.epic/EPIC.md"
  for s in stories archive; do [ -e "$EPIC_DIR/$s" ] && ln -s "$EPIC_DIR/$s" "$T/.epic/$s"; done
  if bash "$SCRIPT_DIR/epic-index.sh" --epic-dir "$T/.epic" >/dev/null 2>&1; then
    cmp -s "$EPIC_DIR/EPIC.md" "$T/.epic/EPIC.md" || add warning index .epic/EPIC.md "behind the disk — run epic-index"
  fi
fi

if [ -d "$EPIC_DIR/archive" ] && [ -n "$(find "$EPIC_DIR/archive" -mindepth 1 -maxdepth 1 -type d -print -quit)" ] &&
   [ ! -f "$EPIC_DIR/archive/manifest.yaml" ]; then
  add warning manifest .epic/archive/manifest.yaml "missing while archived stories exist"
fi

# --- Stories ---
NOW=$(date +%s)
# newest_mtime <dir> — epoch of the most recently modified file under <dir>
# (GNU stat, then BSD stat); NOW when there is no file, so empty reads as fresh.
newest_mtime() {
  local m
  m=$( { find "$1" -type f -exec stat -c %Y {} + 2>/dev/null || find "$1" -type f -exec stat -f %m {} + 2>/dev/null; } | sort -n | tail -n 1)
  printf '%s' "${m:-$NOW}"
}
if [ -d "$EPIC_DIR/stories" ]; then
  for S in "$EPIC_DIR"/stories/*/; do
    [ -d "$S" ] || continue
    S=${S%/}
    N=".epic/stories/$(basename "$S")"
    TASKS="$S/tasks.md"
    SCALE=$(front "$TASKS" scale)
    STATUS=$(front "$TASKS" status)

    BOXES=0
    [ -f "$TASKS" ] && BOXES=$(grep -cE '^[[:space:]]*- \[[ x~]\]' "$TASKS" || true)
    if [ "$BOXES" -eq 0 ]; then
      AGE_D=$(( (NOW - $(newest_mtime "$S")) / 86400 ))
      if [ "$AGE_D" -ge "$STALE_DAYS" ]; then
        add warning dormant "$N" "no boxes and untouched for $AGE_D days — resume it or remove it"
      elif [ ! -f "$TASKS" ] && [ ! -f "$S/.draft/meta.yaml" ]; then
        add error tasks "$N" "no tasks.md"
      fi
    fi

    case "$SCALE" in
      standard | full)
        [ -f "$S/story.md" ] || add error story "$N" "scale '$SCALE' but no story.md"
        ;;
    esac

    [ -d "$S/.draft/red-scratch" ] && add warning red-scratch "$N" "leftover .draft/red-scratch/ — Red scratch belongs under ${TMPDIR:-/tmp}/epic-red/, safe to delete"

    LOG="$S/.draft/progress.log"
    if [ "$STATUS" = "in-progress" ] && [ -s "$LOG" ]; then
      LAST=$(tail -n 1 "$LOG")
      T_AT=$(printf '%s' "$LAST" | jq -r '.at | fromdateiso8601' 2>/dev/null || true)
      if [[ "$T_AT" =~ ^[0-9]+$ ]]; then
        AGE=$(( (NOW - T_AT) / 60 ))
        if [ "$AGE" -ge "$STALL_MIN" ]; then
          WHERE=$(printf '%s' "$LAST" | jq -r '"task \(.task), step \(.step) (\(.status))"' 2>/dev/null || echo "unknown step")
          add warning stall "$N" "in progress, last progress note ${AGE} min ago at $WHERE"
        fi
      fi
    fi
  done
fi

# --- Worktrees: an untracked .epic/ copy diverges from the main tree's ---
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  MAIN=$(git -C "$ROOT" rev-parse --show-toplevel)
  while IFS= read -r line; do
    WT=${line#worktree }
    [ "$WT" = "$MAIN" ] && continue
    if [ -d "$WT/.epic" ] && [ -z "$(git -C "$WT" ls-files -- .epic 2>/dev/null | head -n 1)" ]; then
      add warning worktree-copy "$WT/.epic" "untracked .epic/ copy inside a worktree — the main tree's is the one modes read"
    fi
  done < <(git -C "$ROOT" worktree list --porcelain 2>/dev/null | grep '^worktree ' || true)
fi

# --- Report ---
if [ ${#FINDINGS[@]} -eq 0 ]; then
  JSON=$(jq -n --arg e "$EPIC_DIR" '{epic_dir: $e, status: "ok", errors: 0, warnings: 0, findings: []}')
else
  JSON=$(printf '%s\n' "${FINDINGS[@]}" | jq -s --arg e "$EPIC_DIR" '{
    epic_dir: $e,
    status: (if any(.severity == "error") then "error" else "warning" end),
    errors: (map(select(.severity == "error")) | length),
    warnings: (map(select(.severity == "warning")) | length),
    findings: .}')
fi

if $SUMMARY; then
  printf '%s' "$JSON" | jq -r 'select(.findings | length > 0)
    | "epic-doctor: \(.errors) error(s), \(.warnings) warning(s) — "
      + ([.findings[] | "\(.target): \(.detail)"] | .[:3] | join("; "))
      + (if (.findings | length) > 3 then "; … run epic-doctor for all \(.findings | length)" else "" end)'
else
  printf '%s\n' "$JSON"
fi
exit 0
