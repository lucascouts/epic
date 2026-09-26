#!/usr/bin/env bash
# SubagentStop hook for the Validator and the Auditor: each one's protocol ends
# by writing its report file (.draft/validation-report.yaml or
# .draft/audit-report.yaml), and validate mode takes its verdict from that file,
# never from the agent's closing message. When the agent's transcript shows no
# write to its report, the stop is blocked and the reason tells the agent to
# write it. Claude Code delivers that reason to the subagent as its next
# instruction.
#
# Fails open: unreadable input, a missing transcript, or a second stop attempt
# (stop_hook_active) lets the agent finish, so a guard defect never traps it.

set -euo pipefail

INPUT=$(cat)
AGENT=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo true)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.agent_transcript_path // empty' 2>/dev/null || true)

case "${AGENT##*:}" in
  validator) REPORT="validation-report.yaml" ;;
  auditor)   REPORT="audit-report.yaml" ;;
  *) exit 0 ;;
esac

[ "$ACTIVE" = "true" ] && exit 0
TRANSCRIPT="${TRANSCRIPT/#\~/$HOME}"
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0

if jq -e --arg r "/.draft/$REPORT" '
     select(.type == "assistant") | .message.content[]?
     | select(.type == "tool_use" and (.name == "Write" or .name == "Edit"))
     | select((.input.file_path // "") | endswith($r))' "$TRANSCRIPT" >/dev/null 2>&1; then
  exit 0
fi

jq -n --arg r "$REPORT" '{
  decision: "block",
  reason: ("Your protocol ends by writing .draft/" + $r + " in the story directory, and this run has not written it. Validate mode reads the verdict from that file only. Write it now, then finish.")
}'
exit 0
