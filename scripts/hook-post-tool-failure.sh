#!/usr/bin/env bash
# PostToolUseFailure hook (matcher: Bash): when a Bash command fails during
# an active Epic story run, inject the executor protocol reminder so the
# model does not auto-fix the failure. Per executor Step 4: "If fail: STOP".
#
# Filters silently when:
#   - There's no .epic/stories/ in the project
#   - There's no active in-progress story (one with both [x] and [ ] tasks)
#   - The tool is not Bash
#
# Output: structured JSON with hookSpecificOutput.additionalContext, which
# the platform feeds back to Claude. PostToolUseFailure cannot undo the
# failure — only orient the next reasoning step.
#
# Exit 0 always.

set -euo pipefail

STORIES_ROOT=".epic/stories"
[ -d "$STORIES_ROOT" ] || exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL" = "Bash" ] || exit 0

ACTIVE_STORY=$(
  find "$STORIES_ROOT" -mindepth 2 -maxdepth 2 -name tasks.md \
    -printf '%T@ %h\n' 2>/dev/null \
    | sort -rn | head -1 | awk '{print $2}'
)
[ -n "${ACTIVE_STORY:-}" ] && [ -d "$ACTIVE_STORY" ] || exit 0

# Only surface for stories mid-run: at least one [x] AND one [ ].
grep -qE '^\s*- \[x\]' "$ACTIVE_STORY/tasks.md" 2>/dev/null || exit 0
grep -qE '^\s*- \[ \]' "$ACTIVE_STORY/tasks.md" 2>/dev/null || exit 0

STORY_NAME=$(basename "$ACTIVE_STORY")
NEXT=$(grep -nE '^\s*- \[ \]' "$ACTIVE_STORY/tasks.md" 2>/dev/null | head -1 || true)

CONTEXT="Bash failure during active Epic story '${STORY_NAME}'. Per executor Step 4 protocol: report the FULL command output and STOP — do not attempt fixes autonomously."
if [ -n "$NEXT" ]; then
  CONTEXT="${CONTEXT} Next pending entry in tasks.md: ${NEXT}"
fi

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUseFailure",
    additionalContext: $ctx
  }
}'

exit 0
