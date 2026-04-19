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

STORIES_ROOT=".epic/stories"
[ -d "$STORIES_ROOT" ] || exit 0

ACTIVE_STORY=$(
  find "$STORIES_ROOT" -mindepth 2 -maxdepth 2 -name tasks.md \
    -printf '%T@ %h\n' 2>/dev/null \
    | sort -rn | head -1 | awk '{print $2}'
)
[ -n "${ACTIVE_STORY:-}" ] && [ -d "$ACTIVE_STORY" ] || exit 0

# Only validate stories past Phase 3 (tasks.md must have at least one
# explicit task). Prevents false positives during story generation.
if ! grep -qE '^\s*- \[[ x]\]\s+[0-9]+\s+-\s+' "$ACTIVE_STORY/tasks.md" 2>/dev/null; then
  exit 0
fi

OUTPUT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-story.sh" "$ACTIVE_STORY" 2>&1)
STATUS=$?

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
