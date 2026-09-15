#!/usr/bin/env bash
# Scores ONE trigger-eval transcript: did the skill fire, and did the run that
# was supposed to fire it actually happen? (design.md, Fix Approach 1; story 021)
#
# Usage: bash scripts/trigger-detect.sh [skill-id] < transcript.stream-json
#
# Output: ONE JSON object on stdout, diagnostics on stderr — the convention
# close-subtask.sh, validate-story.sh and next-story-number.sh already share.
#
#   {"verdict":"triggered","skill":"epic:epic","runs_completed":true,"reason":""}
#
# Exit codes:
#   0  a verdict was reached and emitted — INCLUDING `error` (see below)
#   1  the detector could not measure at all (no jq, or jq gave up); no JSON
#   2  the call is malformed (unknown flag, extra argument, --help); no JSON
#
# WHY THERE ARE THREE VERDICTS AND NOT A BOOLEAN. The detector this replaces
# answered true/false, so "the skill did not fire" and "the run never happened"
# were the same `false`. Every `should_not_trigger` query therefore scored as a
# PASS whenever the API errored — a green built on a measurement nobody took.
# `error` is not a nicety, it is the defect (R1.4). So `triggered` and
# `not-triggered` BOTH require the terminal `{"type":"result","is_error":false}`
# event: the completion itself is the evidence that a run occurred, and without
# it the honest answer is neither a pass nor a failure (R1.3).
#
# WHY `error` STILL EXITS 0. Exit 1 is "the world is not in a state I can work
# with"; that is not what happened here. The transcript was read, the question
# was answered, and the answer is `error` — a successful measurement whose
# content is "this query was not measured". The caller is run-evals.sh, a
# `set -euo pipefail` loop that must COUNT these and carry on; a non-zero exit
# would abort the suite on the first network hiccup, which is the failure mode
# this script exists to remove. The verdict travels in the JSON, where the
# caller can act on it. Exit 1 is kept for the one thing that really does stop
# the measurement: no parser.
#
# WHY `runs_completed` IS FALSE ON AN ERRORED RUN. It reports the gate, not the
# transcript's last byte: "did a run happen that can be scored". A run that
# ended `is_error: true` completed in the wall-clock sense and completed nothing
# in the measurable one. Keeping it as the gate makes one invariant hold in both
# directions — `verdict == "error"` if and only if `runs_completed == false` —
# so a caller may branch on either field and never on both. `reason` is what
# distinguishes the two causes (no result event vs. an errored one).
#
# WHY A NON-JSON LINE IS SKIPPED RATHER THAN FATAL. A real transcript is
# captured with `2>&1`, so the CLI's own stderr is interleaved with the event
# stream. `fromjson? // empty` drops those lines; a parser that dies on the
# first one is a parser that reports `error` for every run on a chatty host.
#
# WHY THE REASON DOES NOT ALSO GO TO STDERR. Every statement about a VERDICT
# travels in the JSON — that is the contract, and a second copy on stderr is a
# second place for the two to disagree. stderr carries only the paths that reach
# NO verdict: a malformed call, and a detector that could not run. (This is
# close-subtask.sh's rule read exactly: it prints on stderr when it REFUSES, and
# says nothing there when it answers.)
#
# THIS SCRIPT CONSUMES STDIN WHOLE. A caller invoking it inside a `while read`
# loop must redirect its input explicitly — an inherited stdin makes the
# detector eat the loop's remaining queries. That is not hypothetical: the same
# shape made run-evals.sh measure one query out of twenty-seven.

set -euo pipefail

DEFAULT_SKILL="epic:epic"
USAGE='Usage: trigger-detect.sh [skill-id] < transcript.stream-json'

print_help() {
  cat <<'HELP'
Usage: trigger-detect.sh [skill-id] < transcript.stream-json

Reads a `claude -p --output-format stream-json --verbose` transcript on stdin
and answers whether it invoked the skill, or whether it ran at all.

Arguments:
  [skill-id]    The skill whose invocation counts, e.g. epic:epic (the default).
                Matched against the `input.skill` of a `Skill` tool_use event
                inside an `assistant` message.

Flags:
  --help, -h    Show this help (on stderr, exit 2 — stdout is JSON or nothing)

Output: one JSON object — {verdict, skill, runs_completed, reason} — on stdout.
  verdict = triggered      the skill fired and the run completed
          | not-triggered  the run completed and the skill did not fire
          | error          the run did not complete, or completed in error;
                           NEITHER a pass nor a failure, and `reason` says why

Exit codes:
  0  a verdict was reached (all three are verdicts)
  1  the detector could not measure at all (jq missing or failing)
  2  malformed call
HELP
}

# usage_error: the command line is malformed. No JSON — nothing was measured,
# so there is nothing to report on. This and --help are the only exit-2 paths.
usage_error() {
  printf 'Error: %s\n' "$1" >&2
  printf '%s\n' "$USAGE" >&2
  exit 2
}

# unmeasurable: the detector itself could not run. Also no JSON: a verdict was
# never reached, and inventing an `error` object here would be indistinguishable
# from one measured off a real transcript.
unmeasurable() {
  printf 'trigger-detect: %s\n' "$1" >&2
  exit 1
}

# --- Argument parsing --------------------------------------------------------
SKILL=""
POSITIONAL=0

# A counter, not `[[ -z "$SKILL" ]]`: an explicitly empty first argument must
# land in the slot and be judged by the emptiness check below, never be treated
# as "no argument given" and silently replaced by the default.
take_positional() {
  if [[ "$POSITIONAL" -gt 0 ]]; then
    usage_error "unexpected extra argument '$1' — one skill id per invocation"
  fi
  SKILL="$1"
  POSITIONAL=$((POSITIONAL + 1))
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help | -h)
      print_help >&2
      exit 2
      ;;
    --)
      # End of options, so a skill id starting with `-` is reachable at all.
      shift
      while [[ $# -gt 0 ]]; do
        take_positional "$1"
        shift
      done
      ;;
    -*)
      usage_error "unknown flag '$1'"
      ;;
    *)
      take_positional "$1"
      shift
      ;;
  esac
done

if [[ "$POSITIONAL" -eq 0 ]]; then
  SKILL="$DEFAULT_SKILL"
fi

# An empty id matches no event, so the answer would be `not-triggered` whatever
# the transcript holds — a measurement that cannot succeed, reported as one that
# ran. Refused as a malformed call instead.
if [[ -z "$SKILL" ]]; then
  usage_error "the skill id must not be empty — an empty id matches no Skill event, so every transcript would score 'not-triggered'"
fi

# --- The verdict -------------------------------------------------------------
command -v jq > /dev/null 2>&1 ||
  unmeasurable "'jq' is not on PATH — a stream-json transcript cannot be parsed without it, so no verdict was reached"

# ONE jq pass over stdin, and ONE emitter: the object below is the only thing
# this script ever writes to stdout. `--arg` carries the skill id in, so the id
# is DATA to jq and its escaping in the output is jq's own — there is no string
# in this script that gets concatenated into JSON by hand.
#
# The event list is filtered to objects once, up front, so nothing downstream
# has to guard against `.type` on a bare number that some stray line parsed to.
#
# `last` picks the TERMINAL result event rather than requiring it to be the
# final line of the file: a transcript captured with `2>&1` can carry trailing
# noise after it, and that noise is not evidence the run failed.
VERDICT_JSON=$(
  jq -c -n -R --arg skill "$SKILL" '
    # The transcript, as the events it actually carries: a line that is not
    # JSON is dropped, and a line that is JSON but not an object cannot be one
    # of the events this reads — filtering both here is what lets everything
    # below index freely.
    def events: [inputs | fromjson? // empty | select(type == "object")];

    # The run outcome. `last`, not "the final line": trailing noise after it is
    # not evidence that the run failed.
    def terminal_result: map(select(.type == "result")) | last;

    # Every skill named by a Skill tool_use inside an assistant message — the
    # one event that says the skill was actually invoked. Each `select` on the
    # way down is a shape guard, so a transcript whose events are shaped
    # differently yields nothing instead of failing.
    def invoked_skills:
      .[]
      | select(.type == "assistant")
      | .message | select(type == "object")
      | .content | select(type == "array")
      | .[]      | select(type == "object")
      | select(.type == "tool_use" and .name == "Skill")
      | .input   | select(type == "object")
      | .skill;

    events as $events
    | ($events | terminal_result) as $result
    | ($result != null and $result.is_error == false) as $completed
    | ([$events | invoked_skills] | any(. == $skill)) as $fired
    | (if $completed then (if $fired then "triggered" else "not-triggered" end)
       else "error"
       end) as $verdict
    | (if $completed then ""
       elif ($events | length) == 0 then
         "no JSON object on stdin — the transcript is empty, or no line on it parsed as an event"
       elif $result == null then
         "no terminal result event — the run did not complete, so this query was not measured"
       elif $result.is_error == true then
         "the run completed in error"
         + (if ($result.subtype | type) == "string" then " (subtype: " + $result.subtype + ")" else "" end)
         + " — so this query was not measured"
       else
         "the terminal result event does not report is_error: false — the run cannot be scored"
       end) as $reason
    | {
        verdict: $verdict,
        skill: $skill,
        runs_completed: $completed,
        reason: $reason
      }
  '
) || VERDICT_JSON=""

# Captured first and printed after, so a jq that dies mid-write cannot leave a
# half-object on stdout: the contract is one whole JSON object, or nothing.
if [[ -z "$VERDICT_JSON" ]]; then
  unmeasurable "jq could not read the transcript on stdin — no verdict was reached"
fi

printf '%s\n' "$VERDICT_JSON"
