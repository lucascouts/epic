#!/usr/bin/env bats
# The run model: chosen at clarify for Standard and Full, recorded as
# `run-model:` in tasks.md, handed off with the commands that open a session on
# it, and checked — never enforced — when the run starts.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/story"
  mkdir -p "$STORY"
}

teardown() { rm -rf "$WORK"; }

write_tasks() { # write_tasks <run-model line or "">
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-10-16'
    echo 'scale: fast'
    [[ -z "$1" ]] || echo "$1"
    echo '---'
    echo
    echo '## Task List'
    echo '- [ ] 1 - Implement'
    echo '  - Commit: "feat(001): implement"'
    echo '  - [ ] 1.1 - Write it'
    echo '    - Validation: `echo ok`'
  } > "$STORY/tasks.md"
}

run_errors() { printf '%s' "$1" | jq -r '.error_details[]?' | grep -i 'run-model' || true; }

@test "each of the three models validates" {
  for m in sonnet opus haiku; do
    write_tasks "run-model: $m"
    run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
    [ -z "$(run_errors "$output")" ]
  done
}

@test "an invented model is an error naming the three" {
  write_tasks 'run-model: gpt'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  msg=$(run_errors "$output")
  echo "$msg" | grep -qF "found 'gpt'"
  echo "$msg" | grep -qF 'sonnet, opus, haiku'
}

@test "no run-model is fail-open" {
  write_tasks ''
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ -z "$(run_errors "$output")" ]
}

@test "clarify asks it for Standard and Full only, Sonnet recommended, and skips it under --auto" {
  f="$PLUGIN_ROOT/references/clarify.md"
  grep -qF '### The run model (Standard and Full)' "$f"
  grep -qF 'Sonnet (Recommended)' "$f"
  grep -qF 'Fast and spike do not ask' "$f"
  grep -qF 'Under `--auto` or headless the question is not asked' "$f"
}

@test "the hand-off names both ways to open a session on the model, and runs neither" {
  f="$PLUGIN_ROOT/references/phase-gates.md"
  grep -qF '## Handing Off to Run' "$f"
  grep -qF '`/model <run-model>`' "$f"
  grep -qF '`claude --model <run-model>`' "$f"
  grep -qF 'Neither is run on the user' "$f"
}

@test "the run start checks the model and never blocks" {
  grep -qF '**Check the run model**' "$PLUGIN_ROOT/references/run-mode.md"
  grep -qF 'it never blocks' "$PLUGIN_ROOT/references/run-mode.md"
}
