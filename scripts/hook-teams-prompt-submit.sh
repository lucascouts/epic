#!/usr/bin/env bash
# UserPromptSubmit hook: escalate agent-teams flag mismatch.
#
# Two-step behavior, gated by the sentinel written by
# hook-teams-session-start.sh:
#
#   1st prompt after session start: block the prompt, tell the user to
#   restart. Write "attempt" marker so the next prompt knows this is the
#   second one.
#
#   2nd prompt: disable the flag via teams-config.sh (so the settings
#   file stops claiming it's active), remove sentinel, let the prompt
#   through with additionalContext notifying disable.
#
# If no sentinel → no-op.

set -euo pipefail

SENTINEL_FILE=".epic/.teams-mismatch"
ATTEMPT_FILE=".epic/.teams-mismatch-attempt"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"

[ -f "$SENTINEL_FILE" ] || exit 0

if [ ! -f "$ATTEMPT_FILE" ]; then
  # First prompt since session start → block with restart notice
  touch "$ATTEMPT_FILE" 2>/dev/null || true

  REASON=$(cat <<'MSG'
Blocked: agent-teams flag mismatch.

CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 is in .claude/settings.local.json but was
NOT applied to this session. A RESTART is required for the flag to take effect.

Action: close this Claude Code session and start a new one.

If you prefer to continue without agent-teams, submit your prompt AGAIN — Epic
will then automatically disable the flag and let you proceed.
MSG
)

  jq -n --arg reason "$REASON" '{
    decision: "block",
    reason: $reason,
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit"
    }
  }'
  exit 0
fi

# Second prompt → user chose to continue. Disable the flag.
if [ -n "$PLUGIN_ROOT" ] && [ -x "$PLUGIN_ROOT/scripts/teams-config.sh" ]; then
  bash "$PLUGIN_ROOT/scripts/teams-config.sh" disable >/dev/null 2>&1 || true
fi

rm -f "$SENTINEL_FILE" "$ATTEMPT_FILE" 2>/dev/null || true

MSG=$(cat <<'CTX'
Agent-teams flag has been disabled for this project (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
removed from .claude/settings.local.json). The session continues without teams
support — sequential/worktree execution will be used instead.

To re-enable later: /epic:epic teams enable, then restart the session.
CTX
)

jq -n --arg ctx "$MSG" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'

exit 0
