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

# Portable newest-tasks.md (no GNU find -printf), space-safe.
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

# Only surface for stories mid-run: at least one CLOSED box AND one open [ ].
#
# Closed is `[x]` plus terminal `[~]` (waived:/n-a:/superseded-by:) — the single
# definition in references/tasks.md#completion. This guard read the binary
# grammar until story 004 Task 6: a story whose finished boxes were all closed
# without execution had no `[x]` at all, so it read as "not mid-run" and the
# executor Step-4 reminder was silently suppressed on a Bash failure — the
# quietest failure mode in the set, since a swallowed reminder looks exactly
# like no failure.
#
# `deferred:` does NOT close a box here: that work is still owed by someone
# else, so it is not evidence this run has produced anything yet.
#
# Same census form as validate-story.sh and hook-precompact.sh (token-anchored
# qualifiers, one parse loop) — deliberately, so a sixth dialect cannot drift
# away from the other five. tests/checkbox-grammar.bats pins the agreement.
has_closed_box() {
  local file="$1" line
  local box_re='^[[:space:]]*- \[([x~])\]'
  local deferred_re='(^|[^[:alnum:]_-])deferred:'
  local terminal_re='(^|[^[:alnum:]_-])(waived|n-a|superseded-by):'
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ $box_re ]] || continue
    if [[ "${BASH_REMATCH[1]}" == "x" ]]; then
      return 0
    fi
    if [[ "$line" =~ $deferred_re ]]; then
      continue
    fi
    if [[ "$line" =~ $terminal_re ]]; then
      return 0
    fi
  done < "$file"
  return 1
}

has_closed_box "$ACTIVE_STORY/tasks.md" || exit 0
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
