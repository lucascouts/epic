#!/usr/bin/env bats
# Unit tests for scripts/trigger-detect.sh (story 021 — close-the-eval-deferrals).
# Authored by the Test Advisor BEFORE implementation (TDD Red phase).
#
# Contract under test (design.md, Fix Approach 1; R1.1-R1.5):
#   trigger-detect.sh [skill-id]  —  a stream-json transcript on stdin
#     →  ONE JSON object on stdout:
#          {verdict, skill, runs_completed, reason?}
#     verdict ∈ triggered | not-triggered | error
#   - triggered:     a `tool_use` event named "Skill" whose .input.skill equals
#                    the id, inside an `assistant` message, AND the run completed
#   - not-triggered: the run completed and no such event is present
#   - error:         no terminal {"type":"result","is_error":false} event, or one
#                    reporting is_error:true. NEITHER a pass nor a failure.
#   - skill-id defaults to epic:epic; --help on stderr, exit 2 (close-subtask.sh's
#     convention: stdout is JSON or nothing)
#
# WHY THE THIRD VERDICT IS THE POINT. The detector this replaces answered a bare
# boolean, so "the skill did not fire" and "the run never happened" were the same
# `false` — and every should_not_trigger query scored as a pass whenever the API
# errored, having measured nothing. `error` is not a nicety; it is the defect.
#
# WHY THE MUTANT FIXTURE EXISTS. mutant.jsonl is byte-identical to fires.jsonl
# except for the skill id. An assertion that answers `triggered` for both is not
# reading the id at all — it is matching the shape of a transcript and would go
# green against any skill in the world. The pair is the red that proves this
# suite can fail (stories 019/020).
#
# Fixtures are recorded stream-json, trimmed to the events the detector reads.
# They carry `//` comment lines on purpose: a real transcript captured with
# `2>&1` interleaves non-JSON, and a detector that dies on it is unusable.
#
# EPIC_PLUGIN_ROOT overrides root resolution so this draft copy can run before
# materialization into tests/.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="${EPIC_PLUGIN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  SCRIPT="$PLUGIN_ROOT/scripts/trigger-detect.sh"
  FIX="$BATS_TEST_DIRNAME/fixtures/trigger"
}

# Run the detector with stderr DISCARDED, and slurp, so that a script which is
# absent or which dies produces the literal "NO-JSON" rather than leaking its
# error text into $output. Without this the suite reports green for the wrong
# reason: `run` merges stderr into $output, so "is the reason non-empty" was
# satisfied by bash's own "No such file or directory". Found in Red
# verification, which is what Red verification is for.
detect() { # $1 = fixture basename, $2… = args passed to the script
  local fx="$1"; shift
  bash "$SCRIPT" "$@" < "$FIX/$fx" 2>/dev/null
}

field_of() { # $1 = jq path, $2 = fixture, $3… = args
  local path="$1"; shift
  detect "$@" | jq -rs ".[0].$path // \"NO-JSON\""
}

verdict_of() { field_of verdict "$@"; }

@test "1.2: a transcript invoking the skill is triggered" {
  run verdict_of fires.jsonl
  [ "$status" -eq 0 ]
  [ "$output" = "triggered" ]
}

@test "1.2: a completed transcript with no Skill event is not-triggered" {
  run verdict_of no-fire.jsonl
  [ "$status" -eq 0 ]
  [ "$output" = "not-triggered" ]
}

@test "1.2: a transcript with no terminal result event is an error, not a verdict" {
  run verdict_of truncated.jsonl
  [ "$status" -eq 0 ]
  [ "$output" = "error" ]
}

@test "1.2: a run that completed in error is an error, not a scored outcome" {
  run verdict_of errored.jsonl
  [ "$status" -eq 0 ]
  [ "$output" = "error" ]
}

# THE RED THAT PROVES THIS SUITE CAN FAIL. Same transcript, different id.
@test "1.2: the mutant transcript — same events, other skill id — is not-triggered" {
  run verdict_of mutant.jsonl
  [ "$status" -eq 0 ]
  [ "$output" = "not-triggered" ]
}

@test "1.2: the mutant IS triggered when its own id is asked for — the fixture is otherwise intact" {
  run verdict_of mutant.jsonl "epic:NOTTHISONE"
  [ "$status" -eq 0 ]
  [ "$output" = "triggered" ]
}

@test "1.2: empty stdin is an error, never not-triggered" {
  run bash -c "printf '' | bash '$SCRIPT' 2>/dev/null | jq -rs '.[0].verdict // \"NO-JSON\"'"
  [ "$output" = "error" ]
}

@test "1.2: non-JSON lines are skipped, not fatal — a transcript captured with 2>&1 still scores" {
  run bash -c "{ echo 'Warning: something on stderr'; cat '$FIX/fires.jsonl'; } | bash '$SCRIPT' 2>/dev/null | jq -rs '.[0].verdict // \"NO-JSON\"'"
  [ "$output" = "triggered" ]
}

@test "1.2: stdout is one JSON object carrying the skill asked for and whether the run completed" {
  run field_of skill fires.jsonl
  [ "$output" = "epic:epic" ]
  run field_of runs_completed fires.jsonl
  [ "$output" = "true" ]
  run bash -c "detect() { bash '$SCRIPT' < '$FIX/fires.jsonl' 2>/dev/null; }; detect | jq -s 'length'"
  [ "$output" = "1" ]
}

@test "1.2: an error verdict says why, so a failing suite names its cause" {
  run verdict_of truncated.jsonl
  [ "$output" = "error" ]
  run field_of reason truncated.jsonl
  [ "$output" != "NO-JSON" ]
  [ "$output" != "null" ]
  [ -n "$output" ]
}

@test "1.2: --help goes to stderr and exits 2 — stdout is JSON or nothing" {
  run bash -c "bash '$SCRIPT' --help 2>/dev/null"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}
