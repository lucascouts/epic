#!/usr/bin/env bash
# SessionStart hook: detect CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS mismatch.
#
# A common pitfall: the user writes the flag to .claude/settings.local.json
# (via `epic:epic teams enable` or manually) but does NOT restart the
# session. The flag is only picked up at session boot, so the current
# session still runs without teams support — silently.
#
# This hook:
#   1. Reads .claude/settings.local.json via jq.
#   2. Reads the actual runtime env var.
#   3. If settings says "1" but the env is empty/other → mismatch.
#   4. On mismatch:
#      - Writes sentinel .epic/.teams-mismatch so UserPromptSubmit hook can
#        escalate on subsequent prompts.
#      - Emits additionalContext so Claude sees the warning up-front.
#
# SessionStart hooks cannot force session termination — that is enforced
# on the next UserPromptSubmit via hook-teams-prompt-submit.sh.

set -euo pipefail

SETTINGS_FILE=".claude/settings.local.json"
ENV_KEY="CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
SENTINEL_DIR=".epic"
SENTINEL_FILE="${SENTINEL_DIR}/.teams-mismatch"

# Clean stale sentinel from previous session
rm -f "$SENTINEL_FILE" 2>/dev/null || true

# No settings file → nothing to check
[ -f "$SETTINGS_FILE" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0

SETTINGS_FLAG=$(jq -r --arg k "$ENV_KEY" '.env[$k] // ""' "$SETTINGS_FILE" 2>/dev/null || echo "")
RUNTIME_FLAG="${!ENV_KEY:-}"

# Only the "settings says 1 / runtime doesn't" case is actionable
if [ "$SETTINGS_FLAG" = "1" ] && [ "$RUNTIME_FLAG" != "1" ]; then
  mkdir -p "$SENTINEL_DIR" 2>/dev/null || true
  printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SENTINEL_FILE" 2>/dev/null || true

  MSG=$(cat <<'CTX'
Agent-teams flag mismatch detected.

CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is set to "1" in .claude/settings.local.json,
but the current session was NOT started with the flag applied to its environment.
Team tools (TeamCreate, TeamDelete, SendMessage) are therefore unavailable.

A restart is MANDATORY to pick up the flag. The next time the user submits a
prompt, the Epic plugin will block that prompt with a restart notice. If the
user submits again after that, Epic will automatically disable the flag via
scripts/teams-config.sh so the session can continue without teams.
CTX
)

  jq -n --arg ctx "$MSG" '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: $ctx
    }
  }'
fi

exit 0
