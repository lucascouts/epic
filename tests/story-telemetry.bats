#!/usr/bin/env bats
# scripts/story-telemetry.sh — token and wall-clock telemetry from a session
# transcript.
#
# The contract these cases pin, and why each one exists:
#
#   T1  --help prints usage on stdout and exits 0 (the one documented stdout
#       exception, same as archive-story.sh)
#   T2  invalid input exits 2 with NOTHING on stdout — a consumer piping into
#       jq must never receive half a document
#   T3  usage is summed per DISTINCT message.id. This is the whole reason the
#       script exists as a script instead of a one-line jq: the transcript
#       repeats the same usage on every content block, measured at 2.4x
#   T4  `events` and `unique_messages` are BOTH emitted, so the deduplication
#       is visible rather than promised
#   T5  isSidechain splits orchestrator from sub-agent
#   T6  subagent_split_verified is false when no sidechain event was seen, so a
#       zeroed subagent block never reads as "confirmed none"
#   T7  --since / --until bound the window, inclusively
#   T8  an empty window is zeros at exit 0, not an error
#   T9  a malformed line is skipped, not fatal — a live session's transcript
#       can be truncated mid-write
#   T10 fractional-second timestamps produce a real wall clock (fromdateiso8601
#       refuses them raw; a normalisation bug would silently report 0)
#   T11 events that are not assistant, or carry no usage, are ignored
#
# Fixtures are written per case: a transcript is just JSONL, so a case that
# builds its own is readable without a fixtures directory to cross-reference.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../scripts/story-telemetry.sh"

setup() {
  TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/telemetry.XXXXXX")"
  T="$TMP/transcript.jsonl"
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
  return 0
}

# msg <id> <sidechain> <timestamp> <input> <cache_creation> <cache_read> <output>
msg() {
  printf '{"type":"assistant","uuid":"u-%s-%s","isSidechain":%s,"timestamp":"%s","message":{"id":"%s","model":"claude-opus-5","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' \
    "$1" "$RANDOM" "$2" "$3" "$1" "$4" "$5" "$6" "$7" >> "$T"
}

@test "T1: --help prints usage on stdout and exits 0" {
  run --separate-stderr bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == Usage:* ]]
}

@test "T2: an unknown flag exits 2 with nothing on stdout" {
  run --separate-stderr bash "$SCRIPT" --frobnicate
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"unknown argument"* ]]
}

@test "T2: a missing transcript exits 2 with nothing on stdout" {
  run --separate-stderr bash "$SCRIPT" --transcript "$TMP/absent.jsonl"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "T3: usage is summed once per message.id, however many events repeat it" {
  # Three events, one message: the shape the real transcript emits.
  msg m1 false 2026-09-16T10:00:00.100Z 10 20 30 40
  msg m1 false 2026-09-16T10:00:00.200Z 10 20 30 40
  msg m1 false 2026-09-16T10:00:00.300Z 10 20 30 40
  run --separate-stderr bash "$SCRIPT" --transcript "$T"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.unique_messages == 1' > /dev/null
  echo "$output" | jq -e '.main.output == 40' > /dev/null
  echo "$output" | jq -e '.main.cache_read == 30' > /dev/null
}

@test "T4: events and unique_messages are both emitted, so the dedup is visible" {
  msg m1 false 2026-09-16T10:00:00.000Z 1 1 1 1
  msg m1 false 2026-09-16T10:00:01.000Z 1 1 1 1
  msg m2 false 2026-09-16T10:00:02.000Z 1 1 1 1
  run --separate-stderr bash "$SCRIPT" --transcript "$T"
  echo "$output" | jq -e '.events == 3' > /dev/null
  echo "$output" | jq -e '.unique_messages == 2' > /dev/null
}

@test "T5: isSidechain splits the orchestrator from the sub-agent" {
  msg m1 false 2026-09-16T10:00:00.000Z 0 0 0 100
  msg m2 true  2026-09-16T10:00:01.000Z 0 0 0 7
  run --separate-stderr bash "$SCRIPT" --transcript "$T"
  echo "$output" | jq -e '.main.output == 100' > /dev/null
  echo "$output" | jq -e '.subagent.output == 7' > /dev/null
  echo "$output" | jq -e '.main.messages == 1 and .subagent.messages == 1' > /dev/null
  echo "$output" | jq -e '.subagent_split_verified == true' > /dev/null
}

@test "T6: with no sidechain event, the split is reported unverified" {
  msg m1 false 2026-09-16T10:00:00.000Z 1 1 1 1
  run --separate-stderr bash "$SCRIPT" --transcript "$T"
  echo "$output" | jq -e '.subagent_split_verified == false' > /dev/null
  echo "$output" | jq -e '.subagent.messages == 0' > /dev/null
}

@test "T7: --since and --until bound the window inclusively" {
  msg m1 false 2026-09-16T10:00:00.000Z 0 0 0 1
  msg m2 false 2026-09-16T11:00:00.000Z 0 0 0 2
  msg m3 false 2026-09-16T12:00:00.000Z 0 0 0 4
  run --separate-stderr bash "$SCRIPT" --transcript "$T" --since 2026-09-16T11:00:00.000Z
  echo "$output" | jq -e '.main.output == 6' > /dev/null
  run --separate-stderr bash "$SCRIPT" --transcript "$T" --until 2026-09-16T11:00:00.000Z
  echo "$output" | jq -e '.main.output == 3' > /dev/null
  run --separate-stderr bash "$SCRIPT" --transcript "$T" --since 2026-09-16T11:00:00.000Z --until 2026-09-16T11:00:00.000Z
  echo "$output" | jq -e '.main.output == 2' > /dev/null
  echo "$output" | jq -e '.window.since == "2026-09-16T11:00:00.000Z"' > /dev/null
}

@test "T8: an empty window reports zeros at exit 0, never an error" {
  msg m1 false 2026-09-16T10:00:00.000Z 5 5 5 5
  run --separate-stderr bash "$SCRIPT" --transcript "$T" --since 2030-01-01T00:00:00Z
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.events == 0 and .unique_messages == 0' > /dev/null
  echo "$output" | jq -e '.main.output == 0 and .wall_clock_seconds == 0' > /dev/null
  echo "$output" | jq -e '.models == []' > /dev/null
}

@test "T9: a malformed line is skipped, not fatal — a live transcript is written as you read it" {
  msg m1 false 2026-09-16T10:00:00.000Z 0 0 0 11
  printf '{"type":"assistant","message":{"id":"half-w\n' >> "$T"
  msg m2 false 2026-09-16T10:00:05.000Z 0 0 0 22
  run --separate-stderr bash "$SCRIPT" --transcript "$T"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.main.output == 33' > /dev/null
}

@test "T10: fractional-second timestamps produce a real wall clock" {
  # fromdateiso8601 refuses ".296Z" raw; a normalisation bug reports 0 here.
  msg m1 false 2026-09-16T10:00:00.296Z 0 0 0 1
  msg m2 false 2026-09-16T10:01:30.742Z 0 0 0 1
  run --separate-stderr bash "$SCRIPT" --transcript "$T"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.wall_clock_seconds == 90' > /dev/null
  echo "$output" | jq -e '.started == "2026-09-16T10:00:00.296Z"' > /dev/null
}

@test "T11: non-assistant events and assistant events without usage are ignored" {
  printf '{"type":"user","timestamp":"2026-09-16T10:00:00.000Z","message":{"content":"hi"}}\n' >> "$T"
  printf '{"type":"attachment","timestamp":"2026-09-16T10:00:01.000Z"}\n' >> "$T"
  printf '{"type":"assistant","timestamp":"2026-09-16T10:00:02.000Z","message":{"id":"no-usage"}}\n' >> "$T"
  msg m1 false 2026-09-16T10:00:03.000Z 0 0 0 9
  run --separate-stderr bash "$SCRIPT" --transcript "$T"
  echo "$output" | jq -e '.events == 1 and .unique_messages == 1' > /dev/null
  echo "$output" | jq -e '.main.output == 9' > /dev/null
}

@test "T11: a transcript with no usable event at all is zeros, not a crash" {
  printf '{"type":"user","message":{"content":"only me"}}\n' >> "$T"
  run --separate-stderr bash "$SCRIPT" --transcript "$T"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.unique_messages == 0 and .started == null' > /dev/null
}
