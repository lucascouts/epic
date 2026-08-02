#!/usr/bin/env bash
# TaskCompleted hook: runs validate-story.sh against the active story when
# a TodoWrite-tracked task is marked complete. Surfaces validation errors
# back to the model so it can fix before proceeding.
#
# Active-story heuristic matches hook-precompact.sh: most-recently-modified
# tasks.md under .epic/stories/.
#
# Exit 2 blocks the completion and pipes stderr to the model.
# Exit 0 allows it (no errors found, or no active Epic story).

set -euo pipefail

# Resolve the plugin root even when CLAUDE_PLUGIN_ROOT is unset (set -u).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

STORIES_ROOT=".epic/stories"
[ -d "$STORIES_ROOT" ] || exit 0

# Most-recently-modified tasks.md, portable (no GNU find -printf) and safe
# for paths containing spaces.
ACTIVE_STORY=""
NEWEST=0
while IFS= read -r f; do
  ts=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
  if [ "$ts" -gt "$NEWEST" ]; then
    NEWEST=$ts
    ACTIVE_STORY=$(dirname "$f")
  fi
done < <(find "$STORIES_ROOT" -mindepth 2 -maxdepth 2 -name tasks.md 2>/dev/null)
[ -n "${ACTIVE_STORY:-}" ] && [ -d "$ACTIVE_STORY" ] || exit 0

# Only validate stories past Phase 3 (tasks.md must have at least one
# explicit task). Prevents false positives during story generation.
if ! grep -qE '^\s*- \[[ x]\]\s+[0-9]+\s+-\s+' "$ACTIVE_STORY/tasks.md" 2>/dev/null; then
  exit 0
fi

# Capture the validator's exit status without tripping set -e: a bare
# OUTPUT=$(...) inherits a non-zero status and aborts the hook on the
# assignment itself, so the blocking exit 2 below never runs (fail-open).
STATUS=0
OUTPUT=$(bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$ACTIVE_STORY" 2>&1) || STATUS=$?

if [ "$STATUS" -eq 1 ]; then
  {
    echo "Epic story '$(basename "$ACTIVE_STORY")' failed validation after task completion:"
    echo "$OUTPUT" | jq -r '.error_details[]' 2>/dev/null \
      || echo "$OUTPUT"
    echo
    echo "Fix the reported issues before continuing."
  } >&2
  exit 2
fi

exit 0
