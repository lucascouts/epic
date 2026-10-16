#!/usr/bin/env bats
# The model is chosen where it is active — the session. Epic suggests, before
# any work, continuing on the recommended model or starting a session already on
# it; it never tries to switch the model itself.

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "triage: Fast and Spike carry a Model line only when the session is not on Sonnet" {
  grep -qF '> - **Model:** (Fast and Spike, only when this session is not on Sonnet)' "$ROOT/references/triage.md"
  grep -qF '`/model sonnet` and continue' "$ROOT/references/triage.md"
  grep -qF '`claude --model sonnet`' "$ROOT/references/triage.md"
}

@test "triage: Epic suggests and never switches; nothing under --auto; Standard/Full go through clarify" {
  f="$ROOT/references/triage.md"
  grep -qF 'So Epic never tries to switch it' "$f"
  grep -qF 'Under `--auto` or headless nothing is suggested' "$f"
  grep -qF 'clarify.md#the-run-model-standard-and-full' "$f"
}

@test "instant: one line before the work, never a question" {
  f="$ROOT/references/instant-mode.md"
  grep -qF '**The model is suggested once, never asked.**' "$f"
  grep -qF 'Then the work starts' "$f"
}

@test "no skill carries a model override" {
  run grep -rlE '^model:' "$ROOT/skills"
  [ "$status" -eq 1 ]
}
