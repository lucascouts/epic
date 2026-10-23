#!/usr/bin/env bash
# PreToolUse hook: enforces the two things the Executor must never do.
#   - run `git commit`: commits are the orchestrator's, after the merge, with
#     the pre-authored message;
#   - edit or write a story's tasks.md: boxes are closed only by epico-close,
#     which takes the census and validates the story in one transaction.
# It acts only inside the Executor (agent_type), so the orchestrator and every
# other agent are untouched. hooks.json narrows the Edit/Write calls with `if`
# filters, which are best-effort, so the path is re-checked here. The Bash
# handler has no filter: `Bash(git commit *)` misses `git -C dir commit` and
# `git -c k=v commit`, which the regex below catches.

set -euo pipefail

INPUT=$(cat)
AGENT=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)
[ "${AGENT##*:}" = "executor" ] || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
REASON=""
case "$TOOL" in
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|(`[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)'; then
      REASON="The Executor never commits: report the pre-authored message in the closing block's commit field, and the orchestrator commits after the merge."
    fi
    ;;
  Edit | Write)
    FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
    case "$FILE" in
      *".epico/stories/"*"/tasks.md")
        REASON="The Executor never edits tasks.md: report the outcome in the closing block, and the orchestrator closes the box with epic-close."
        ;;
    esac
    ;;
esac

[ -n "$REASON" ] || exit 0
jq -n --arg r "$REASON" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
