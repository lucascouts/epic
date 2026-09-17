#!/usr/bin/env bash
# Read-only token and wall-clock telemetry for a Claude Code session transcript.
#
# Usage: story-telemetry.sh [--transcript <path>] [--since <ts>] [--until <ts>]
#                           [--project-dir <dir>] [--help]
#   --transcript  a session transcript JSONL. Default: the most recently
#                 modified transcript for --project-dir under
#                 ~/.claude/projects/<slug>/ (or $CLAUDE_PROJECTS_DIR)
#   --since       ISO-8601 instant; events strictly before it are excluded
#   --until       ISO-8601 instant; events strictly after it are excluded
#   --project-dir the project whose transcripts to search (default: cwd)
#
# Output: one JSON object on stdout —
#   {transcript, window: {since, until}, wall_clock_seconds,
#    events, unique_messages, models: [...],
#    main:     {messages, input, cache_creation, cache_read, output},
#    subagent: {messages, input, cache_creation, cache_read, output},
#    subagent_split_verified}
#
# Exit codes:
#   0  telemetry computed (including an empty window — zeros, not an error)
#   2  invalid input: unknown flag, transcript not found, no transcript for
#      the project, or jq missing. Nothing on stdout.
#
# WHY TOKENS AND NOT DOLLARS. The transcript carries `message.usage` and no
# price. Converting here would mean shipping a price table inside the plugin,
# and a stale table reports a wrong number wearing the clothes of a measured
# one. The reader knows the current prices; this script reports what was
# actually spent in tokens, which does not age.
#
# WHY DEDUPLICATION IS NOT OPTIONAL. The transcript writes one event per
# content block and REPEATS the same `message.usage` on each. Measured on a
# real session: 438 assistant events carrying 179 distinct `message.id`s —
# summing events instead of messages inflates every figure ~2.4x. So usage is
# summed per DISTINCT `message.id`, and both counts are emitted side by side so
# a consumer can see the deduplication happened rather than trust that it did.
#
# TWO STREAM SHAPES MARK A SUB-AGENT DIFFERENTLY, and both are read. An
# interactive session transcript carries `isSidechain` on every assistant event;
# a `claude -p` stream has no `isSidechain` at all and marks a child by a
# non-null `parent_tool_use_id` instead (measured: 135 of 358 assistant events
# in one `-p` run). Reading only the first would attribute every sub-agent token
# to the orchestrator, silently, on exactly the runs where delegation is what
# you are trying to measure.
#
# WHY `subagent_split_verified` EXISTS. It is `true` once this run actually saw
# a child event by either marker, and `false` when it did not — so a zeroed
# `subagent` block means "none seen", never "confirmed none".
#
# This script writes NO files, ever, and makes no network call.

set -euo pipefail

USAGE='Usage: story-telemetry.sh [--transcript <path>] [--since <ts>] [--until <ts>] [--project-dir <dir>]'

die() { printf '%s\n' "$*" >&2; exit 2; }

TRANSCRIPT=""
SINCE=""
UNTIL=""
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      cat <<'HELP'
Usage: story-telemetry.sh [--transcript <path>] [--since <ts>] [--until <ts>] [--project-dir <dir>]

Read-only token and wall-clock telemetry for a Claude Code session transcript.
Reports tokens, never money: the transcript carries usage and no price, and a
price table shipped here would age into a confident wrong answer.

  --transcript <path>   session transcript JSONL (default: the most recently
                        modified one for the project)
  --since <ts>          ISO-8601 instant; drop events before it
  --until <ts>          ISO-8601 instant; drop events after it
  --project-dir <dir>   project whose transcripts to search (default: cwd)

Output: one JSON object on stdout. Usage sums are deduplicated by message.id —
the transcript repeats the same usage on every content block of a message, and
`events` beside `unique_messages` is how you can see that happened.

Exit: 0 computed (an empty window is zeros, not an error) · 2 invalid input.
HELP
      exit 0
      ;;
    --transcript) [[ $# -ge 2 ]] || die "--transcript needs a value"; TRANSCRIPT="$2"; shift 2 ;;
    --since)      [[ $# -ge 2 ]] || die "--since needs a value";      SINCE="$2";      shift 2 ;;
    --until)      [[ $# -ge 2 ]] || die "--until needs a value";      UNTIL="$2";      shift 2 ;;
    --project-dir)[[ $# -ge 2 ]] || die "--project-dir needs a value";PROJECT_DIR="$2";shift 2 ;;
    *) die "unknown argument: $1"$'\n'"$USAGE" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is required and was not found on PATH"

# --- Resolve the transcript -------------------------------------------------
# Claude Code stores a project's transcripts under a slug of its absolute path
# with every non-alphanumeric run collapsed to a single '-'. Derived here, not
# guessed: the caller can always override with --transcript.
if [[ -z "$TRANSCRIPT" ]]; then
  PROJECT_DIR="${PROJECT_DIR:-$PWD}"
  [[ -d "$PROJECT_DIR" ]] || die "not a directory: $PROJECT_DIR"
  abs=$(cd "$PROJECT_DIR" && pwd)
  slug=$(printf '%s' "$abs" | sed 's/[^a-zA-Z0-9]/-/g')
  root="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}/$slug"
  [[ -d "$root" ]] || die "no transcript directory for $abs (looked in $root)"
  # Most recently modified .jsonl, portable: no GNU find -printf, no ls parsing.
  newest=""
  while IFS= read -r -d '' f; do
    [[ -z "$newest" || "$f" -nt "$newest" ]] && newest="$f"
  done < <(find "$root" -maxdepth 1 -type f -name '*.jsonl' -print0 2>/dev/null)
  [[ -n "$newest" ]] || die "no .jsonl transcript found in $root"
  TRANSCRIPT="$newest"
fi

[[ -f "$TRANSCRIPT" ]] || die "transcript not found: $TRANSCRIPT"
[[ -r "$TRANSCRIPT" ]] || die "transcript not readable: $TRANSCRIPT"

# --- Compute ----------------------------------------------------------------
# One jq pass. `--slurp` is deliberate: the deduplication needs every event in
# hand at once, and a transcript is a session's worth of lines, not a stream.
# A malformed line is SKIPPED rather than fatal (`fromjson? // empty`) — a
# transcript can be truncated mid-write by a session that is still running, and
# refusing to report anything because the last line is half-written would make
# this unusable exactly while a session is live.
jq -R -s \
  --arg transcript "$TRANSCRIPT" \
  --arg since "$SINCE" \
  --arg until "$UNTIL" \
  '
  # `fromdateiso8601` refuses fractional seconds and a numeric offset, and a
  # transcript carries both (`2026-09-16T18:16:06.296Z`). Normalise before
  # parsing rather than after failing: a timestamp this script cannot read is a
  # wall clock it would silently report as 0.
  def ts2epoch:
    sub("\\.[0-9]+"; "") | sub("\\+00:?00$"; "Z") | fromdateiso8601;

  def within($ts):
    ($since == "" or ($ts != null and $ts >= $since)) and
    ($until == "" or ($ts != null and $ts <= $until));

  def sums:
    { messages: length,
      input:          (map(.input_tokens // 0)                | add // 0),
      cache_creation: (map(.cache_creation_input_tokens // 0) | add // 0),
      cache_read:     (map(.cache_read_input_tokens // 0)     | add // 0),
      output:         (map(.output_tokens // 0)               | add // 0) };

  [ split("\n")[] | select(length > 0) | (fromjson? // empty) ]
  | map(select(.type == "assistant" and (.message.usage != null) and within(.timestamp)))
  as $events
  |
  # One entry per distinct message.id — the usage is identical on every event
  # that repeats it, so the first is representative. An event with no id is
  # kept on its own (it cannot be a repeat of anything).
  ( $events
    | group_by(.message.id // .uuid)
    | map({ sidechain: (.[0].isSidechain == true or (.[0].parent_tool_use_id != null)),
            model:     .[0].message.model,
            usage:     .[0].message.usage }) ) as $messages
  |
  ( [ $events[] | .timestamp | select(. != null) ] | sort ) as $stamps
  |
  { transcript: $transcript,
    window: { since: (if $since == "" then null else $since end),
              until: (if $until == "" then null else $until end) },
    started: ($stamps | first),
    ended:   ($stamps | last),
    wall_clock_seconds:
      (if ($stamps | length) > 1
       then (($stamps | last | ts2epoch) - ($stamps | first | ts2epoch))
       else 0 end),
    events: ($events | length),
    unique_messages: ($messages | length),
    models: ([ $messages[] | .model | select(. != null) ] | unique),
    main:     ([ $messages[] | select(.sidechain | not) | .usage ] | sums),
    subagent: ([ $messages[] | select(.sidechain)       | .usage ] | sums),
    subagent_split_verified: ([ $messages[] | .sidechain ] | any)
  }
  ' "$TRANSCRIPT"

exit 0
