#!/usr/bin/env bash
# SubagentStop hook for the Auditor. One spawn validates and then audits, and
# each part ends by writing its report file: .draft/validation-report.yaml,
# then — only when that verdict is pass — .draft/audit-report.yaml. Validate
# mode takes its verdicts from those files, never from the agent's closing
# message. The stop is allowed once the audit report is written, or once the
# validation report is written with `verdict: fail` (the audit never runs
# then). Otherwise it is blocked, and the reason names the file still owed;
# Claude Code delivers that reason to the subagent as its next instruction.
#
# Fails open: unreadable input, a missing transcript, or a second stop attempt
# (stop_hook_active) lets the agent finish, so a guard defect never traps it.

set -euo pipefail

INPUT=$(cat)
AGENT=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo true)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.agent_transcript_path // empty' 2>/dev/null || true)

[ "${AGENT##*:}" = "auditor" ] || exit 0

[ "$ACTIVE" = "true" ] && exit 0
TRANSCRIPT="${TRANSCRIPT/#\~/$HOME}"
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0

# wrote <file> [pattern] — the transcript shows a Write/Edit to .draft/<file>,
# whose written content matches <pattern> when one is given.
wrote() {
  jq -e --arg r "/.draft/$1" --arg p "${2:-}" '
    select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use" and (.name == "Write" or .name == "Edit"))
    | select((.input.file_path // "") | endswith($r))
    | select($p == "" or ((.input.content // .input.new_string // "") | test($p)))' \
    "$TRANSCRIPT" >/dev/null 2>&1
}

wrote audit-report.yaml && exit 0
wrote validation-report.yaml '(^|\n)verdict:[[:space:]]*fail' && exit 0

if wrote validation-report.yaml; then
  REPORT="audit-report.yaml"
else
  REPORT="validation-report.yaml"
fi

jq -n --arg r "$REPORT" '{
  decision: "block",
  reason: ("Your protocol ends by writing .draft/" + $r + " in the story directory, and this run has not written it. Validate mode reads the verdict from that file only. Write it now, then finish.")
}'
exit 0
