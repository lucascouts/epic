#!/usr/bin/env bash
# Appends one progress note to <story-dir>/.draft/progress.log: one JSON object
# per line, fields story, task, step, status, evidence, at. Agents call it at
# each protocol step so a stalled run is visible from disk (epico-doctor reads
# the last line's `at`). The log is the only destination: sub-agents carry no
# memory tool, and the doctor is a script that reads files.
#
# One printf of one line under PIPE_BUF onto an O_APPEND descriptor, so two
# writers never interleave inside a line. Evidence is flattened to one line and
# cut to 300 characters, which keeps every line well under that bound.
#
# Exit 0 on success, 2 on bad usage.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: progress-note.sh --story <story-dir> --task <id> --step <name> --status <started|done|failed|skipped> [--evidence <text>]

Appends one JSON line to <story-dir>/.draft/progress.log, creating .draft/ on demand.
Pass the story directory of the main tree, as the spawn prompt names it.
USAGE
}

STORY="" TASK="" STEP="" STATUS="" EVIDENCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --story) STORY="${2-}"; shift 2 ;;
    --task) TASK="${2-}"; shift 2 ;;
    --step) STEP="${2-}"; shift 2 ;;
    --status) STATUS="${2-}"; shift 2 ;;
    --evidence) EVIDENCE="${2-}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "progress-note.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for v in STORY TASK STEP STATUS; do
  [ -n "${!v}" ] || { echo "progress-note.sh: --$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]') is required" >&2; exit 2; }
done
case "$STATUS" in started | done | failed | skipped) ;; *)
  echo "progress-note.sh: --status must be started, done, failed or skipped, got: $STATUS" >&2; exit 2 ;;
esac
[ -d "$STORY" ] || { echo "progress-note.sh: story directory not found: $STORY" >&2; exit 2; }

EVIDENCE=$(printf '%s' "$EVIDENCE" | tr '\r\n\t' '   ' | cut -c1-300)
mkdir -p "$STORY/.draft"
LINE=$(jq -cn --arg story "$(basename "$(cd "$STORY" && pwd)")" --arg task "$TASK" --arg step "$STEP" \
  --arg status "$STATUS" --arg evidence "$EVIDENCE" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{story: $story, task: $task, step: $step, status: $status, evidence: $evidence, at: $at}')
printf '%s\n' "$LINE" >> "$STORY/.draft/progress.log"
