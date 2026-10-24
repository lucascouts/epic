#!/usr/bin/env bash
# Writes the skeleton of a story's .draft/run-report.md from what is already on
# disk — the recorded line, the census, one line per closed box, the gates and
# the commits — so the model writes only what no file knows (Red, decisions).
#
#   run-report.sh --story <dir> [--force]
#
# Reads tasks.md, .draft/validation-run.json when epico-validate-run ran, and
# git log for the story's `(NNN)` commits. Leaves an existing report alone
# unless --force. Output: one JSON line {report, boxes, closed, written}.
# Exit 0, or 2 on bad usage.

set -euo pipefail

STORY="" FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --story) STORY="${2-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) echo "run-report.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$STORY" ] || [ ! -f "$STORY/tasks.md" ]; then
  echo "run-report.sh: --story <dir> is required and must hold tasks.md" >&2; exit 2
fi
STORY="$(cd "$STORY" && pwd)"
ROOT="$(cd "$STORY/../../.." && pwd)"
NAME="$(basename "$STORY")" NNN="${NAME%%-*}"
OUT="$STORY/.draft/run-report.md"
mkdir -p "$STORY/.draft"

front() { awk -v k="$1" '/^---$/ { n++; next } n == 1 && $0 ~ "^" k ":" { sub("^" k ":[[:space:]]*", ""); print; exit }' "$STORY/tasks.md"; }
# The census every other consumer reads: a terminal [~] (waived, n-a,
# superseded-by) is closed; only a [~] (deferred: …) stays apart.
boxes=$(grep -cE '^[[:space:]]*- \[[ x~]\] [0-9]+\.[0-9]+' "$STORY/tasks.md" || true)
done_x=$(grep -cE '^[[:space:]]*- \[x\] [0-9]+\.[0-9]+' "$STORY/tasks.md" || true)
tilde=$(grep -cE '^[[:space:]]*- \[~\] [0-9]+\.[0-9]+' "$STORY/tasks.md" || true)
deferred=$(grep -cE '^[[:space:]]*- \[~\] [0-9]+\.[0-9]+.*\(deferred:' "$STORY/tasks.md" || true)
closed=$((done_x + tilde - deferred))
open=$((boxes - closed - deferred))

if [ -f "$OUT" ] && [ "$FORCE" -eq 0 ]; then
  printf '{"report": "%s", "boxes": %d, "closed": %d, "written": false}\n' "$OUT" "$boxes" "$closed"; exit 0
fi

{
  printf '# Run Report — %s\n\n' "$NAME"
  printf '%s · %s · %s · %d boxes — %d closed, %d deferred, %d open\n\n' \
    "$(front scale)" "$(front requester)" "$(front engineering)" "$boxes" "$closed" "$deferred" "$open"
  printf '## Steps\n'
  grep -E '^[[:space:]]*- \[[x~]\] [0-9]+\.[0-9]+' "$STORY/tasks.md" | sed -E 's/^[[:space:]]*- \[([x~])\] /- [\1] /' || true
  printf '\n## Quality gates\n'
  if [ -f "$STORY/.draft/validation-run.json" ]; then
    jq -r '.entries[] | select(.kind == "gate") | "- \(.result) — \(.id | split(":")[0]): \(.detail)"' "$STORY/.draft/validation-run.json"
  else
    sed -n '/^## Quality Gates/,/^## /p' "$STORY/tasks.md" | grep -E '^- \[' | sed -E 's/^- \[(.)\] /- /' || true
  fi
  printf '\n## Commits\n'
  git -C "$ROOT" log --oneline --fixed-strings --grep="($NNN)" 2>/dev/null | sed 's/^/- /' || true
} > "$OUT"
printf '{"report": "%s", "boxes": %d, "closed": %d, "written": true}\n' "$OUT" "$boxes" "$closed"
