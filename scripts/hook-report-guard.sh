#!/usr/bin/env bash
# SubagentStop hook for the Auditor. One spawn validates and then audits, and
# each part ends by writing its report file: .draft/validation-report.yaml,
# then — only when that verdict is pass — .draft/audit-report.yaml. Validate
# mode takes its verdicts from those files, never from the agent's closing
# message. The stop is allowed once the audit report is on disk, or once the
# validation report is on disk with `verdict: fail` (the audit never runs
# then). Otherwise it is blocked, and the reason names the file still owed;
# Claude Code delivers that reason to the subagent as its next instruction.
#
# The files are read from disk, not inferred from the transcript: a Write the
# transcript shows may have failed, and a report written through Bash never
# shows as a Write. The transcript is read for one thing only — the spawn
# prompt's `Story directory:` line, which says whose .draft/ to look in.
# Validate mode deletes both files right before the spawn, so a file present
# now was written by this spawn.
#
# Fails open: unreadable input, a missing transcript, a prompt naming no story
# directory, or a second stop attempt (stop_hook_active, the documented loop
# guard) lets the agent finish, so a guard defect never traps it.

set -euo pipefail

INPUT=$(cat)
AGENT=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo true)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.agent_transcript_path // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)

[ "${AGENT##*:}" = "auditor" ] || exit 0

[ "$ACTIVE" = "true" ] && exit 0
TRANSCRIPT="${TRANSCRIPT/#\~/$HOME}"
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0

# The spawn prompt: the first user entry, its content a string or text blocks.
PROMPT=$(jq -rs '
  [.[] | select(.type == "user")][0].message.content
  | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join("\n")) end
  // empty' "$TRANSCRIPT" 2>/dev/null || true)

field() { printf '%s\n' "$PROMPT" | sed -n "s/^[>[:space:]]*$1:[[:space:]]*//p" | head -n 1 | tr -d '`"'"'" | sed 's/[[:space:]]*$//'; }
STORY=$(field 'Story directory')
[ -n "$STORY" ] || exit 0
if [ "${STORY#/}" = "$STORY" ]; then
  ROOT=$(field 'Project root')
  STORY="${ROOT:-${CWD:-.}}/$STORY"
fi
DRAFT="$STORY/.draft"

[ -s "$DRAFT/audit-report.yaml" ] && exit 0
if [ -s "$DRAFT/validation-report.yaml" ]; then
  grep -Eq '^verdict:[[:space:]]*"?fail' "$DRAFT/validation-report.yaml" && exit 0
  REPORT="audit-report.yaml"
else
  REPORT="validation-report.yaml"
fi

jq -n --arg r "$REPORT" '{
  decision: "block",
  reason: ("Your protocol ends by writing .draft/" + $r + " in the story directory, and it is not on disk. Validate mode reads the verdict from that file only. Write it now, then finish.")
}'
exit 0
