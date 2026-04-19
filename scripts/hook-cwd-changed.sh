#!/usr/bin/env bash
# CwdChanged hook: detects when Claude moves into a directory that contains
# Epic state (.epic/) and surfaces the relevant context (story count,
# constitution head). Helps the model orient itself after a `cd` command
# instead of having to re-discover the project layout from scratch.
#
# Silent when:
#   - Hook input has no new_cwd field
#   - The new directory has no .epic/ folder
#
# Exit 0 always — CwdChanged cannot block.

set -euo pipefail

INPUT=$(cat)
NEW_CWD=$(echo "$INPUT" | jq -r '.new_cwd // empty')
[ -n "$NEW_CWD" ] || exit 0
[ -d "$NEW_CWD/.epic" ] || exit 0

STORIES_DIR="$NEW_CWD/.epic/stories"
CONSTITUTION="$NEW_CWD/.epic/constitution.md"

STORIES_COUNT=0
if [ -d "$STORIES_DIR" ]; then
  # shellcheck disable=SC2012
  STORIES_COUNT=$(ls -1d "$STORIES_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')
fi

ARCHIVE_COUNT=0
if [ -d "$NEW_CWD/.epic/archive" ]; then
  # shellcheck disable=SC2012
  ARCHIVE_COUNT=$(ls -1d "$NEW_CWD/.epic/archive"/*/ 2>/dev/null | wc -l | tr -d ' ')
fi

echo "Epic context detected at ${NEW_CWD}/.epic/."
echo "  Active stories: ${STORIES_COUNT}"
echo "  Archived stories: ${ARCHIVE_COUNT}"

if [ -f "$CONSTITUTION" ]; then
  echo "  Constitution head:"
  head -10 "$CONSTITUTION" | sed 's/^/    /'
else
  echo "  No constitution.md (run /epic:task init to create one)."
fi

exit 0
