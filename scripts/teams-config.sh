#!/usr/bin/env bash
# Manages the agent-teams experimental flag for the current project.
#
# Writes/reads `.claude/settings.local.json` (auto-gitignored by Claude
# Code itself — no .gitignore management needed). Only manipulates the
# single env key CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS; other keys in the
# file are preserved verbatim via jq merge.
#
# Usage:
#   bash scripts/teams-config.sh status    # inspect current state
#   bash scripts/teams-config.sh enable    # set env flag to "1"
#   bash scripts/teams-config.sh disable   # remove the env flag
#
# Exit codes:
#   0  success (idempotent — enable-when-already-enabled is OK)
#   1  invalid input or filesystem/merge error
#   2  dependency missing (jq)

set -euo pipefail

SETTINGS_DIR=".claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.local.json"
ENV_KEY="CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
DOCS_URL="https://code.claude.com/docs/en/agent-teams"
LIMITS_URL="https://code.claude.com/docs/en/agent-teams#limitations"

command -v jq >/dev/null 2>&1 || {
  echo "Error: 'jq' is required. Install it and retry." >&2
  exit 2
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || "${1:-}" == "" ]]; then
  cat <<HELP
Usage: teams-config.sh <status|enable|disable>

Manages the experimental agent-teams flag in $SETTINGS_FILE.

Commands:
  status    Report whether $ENV_KEY is active in this project.
  enable    Set $ENV_KEY=1 (merges into existing settings).
  disable   Remove $ENV_KEY (preserves other keys and the file itself).

Docs:        $DOCS_URL
Limitations: $LIMITS_URL

The file is auto-gitignored by Claude Code. No .gitignore edits needed.
HELP
  exit 0
fi

CMD="$1"

read_flag() {
  # Emits "1" if the env key is set to "1", empty otherwise.
  [ -f "$SETTINGS_FILE" ] || { echo ""; return; }
  jq -r --arg k "$ENV_KEY" '.env[$k] // ""' "$SETTINGS_FILE" 2>/dev/null || echo ""
}

case "$CMD" in
  status)
    FLAG=$(read_flag)
    if [ -f "$SETTINGS_FILE" ]; then
      if [ "$FLAG" = "1" ]; then
        STATE="active"
      else
        STATE="inactive"
      fi
    else
      STATE="not-configured"
    fi
    cat <<JSON
{
  "command": "status",
  "settings_file": "$SETTINGS_FILE",
  "state": "$STATE",
  "env_key": "$ENV_KEY",
  "env_value": "$FLAG",
  "docs": "$DOCS_URL",
  "limitations": "$LIMITS_URL"
}
JSON
    ;;

  enable)
    if [ "$(read_flag)" = "1" ]; then
      echo "Agent teams already active for this project ($SETTINGS_FILE)."
      echo "Nothing to do. Use 'status' to inspect, or 'disable' to turn off."
      exit 0
    fi

    mkdir -p "$SETTINGS_DIR"

    TMP=$(mktemp)
    trap 'rm -f "$TMP"' EXIT

    if [ -f "$SETTINGS_FILE" ]; then
      jq --arg k "$ENV_KEY" --arg v "1" \
         '. + {env: ((.env // {}) + {($k): $v})}' \
         "$SETTINGS_FILE" > "$TMP"
    else
      jq -n --arg k "$ENV_KEY" --arg v "1" \
         '{env: {($k): $v}}' > "$TMP"
    fi

    mv "$TMP" "$SETTINGS_FILE"
    trap - EXIT

    cat <<MSG
Wrote $ENV_KEY=1 to $SETTINGS_FILE.

This file is auto-gitignored — safe from accidental commits.

Next step: restart your Claude Code session so the flag takes effect.
(Hot-reload of env vars is not guaranteed; a fresh session is the safe path.)

  Docs:        $DOCS_URL
  Limitations: $LIMITS_URL
  Disable:     bash scripts/teams-config.sh disable
MSG
    ;;

  disable)
    if [ ! -f "$SETTINGS_FILE" ]; then
      echo "Agent teams not configured for this project ($SETTINGS_FILE missing)."
      echo "Nothing to do."
      exit 0
    fi

    if [ "$(read_flag)" != "1" ]; then
      echo "Agent teams already inactive. Nothing to do."
      exit 0
    fi

    TMP=$(mktemp)
    trap 'rm -f "$TMP"' EXIT

    # Remove the env key; if env is then empty, remove the whole env object.
    jq --arg k "$ENV_KEY" '
      if (.env | has($k)) then
        (.env |= del(.[$k]))
        | (if (.env // {} | length) == 0 then del(.env) else . end)
      else . end
    ' "$SETTINGS_FILE" > "$TMP"

    mv "$TMP" "$SETTINGS_FILE"
    trap - EXIT

    cat <<MSG
Removed $ENV_KEY from $SETTINGS_FILE.
Other keys in the file (if any) were preserved.

Restart your Claude Code session for the change to take effect.
MSG
    ;;

  *)
    echo "Error: unknown command '$CMD'. Use: status | enable | disable" >&2
    exit 1
    ;;
esac
