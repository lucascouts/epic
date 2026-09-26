#!/usr/bin/env bats
# tests/lib/provenance-lint.sh: flags development history in the files the
# model loads, and stays quiet on rules, reasons and fenced examples.
# The runtime-context files (skills/, agents/, references/, assets/) must stay clean:
# a legitimate hit goes into tests/provenance-allowlist.txt, matched by text.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LINT="$ROOT/tests/lib/provenance-lint.sh"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

@test "flags a dated measurement and fails under --strict" {
  printf 'Keep gates short.\nMeasured on 2026-09-17: two runs stalled.\n' > "$WORK/a.md"
  run bash "$LINT" --strict "$WORK/a.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *":2:Measured on 2026-09-17"* ]]
}

@test "flags a requirement ID and a personal setup reference" {
  printf 'Close the header last (R1.7).\nSee the epic-gitignore.sh hook.\n' > "$WORK/b.md"
  run bash "$LINT" --strict "$WORK/b.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *":1:"* && "$output" == *":2:"* ]]
}

@test "ignores dates inside fenced code blocks" {
  printf 'Example:\n```yaml\ncreated: 2026-05-17\n```\n' > "$WORK/c.md"
  run bash "$LINT" --strict "$WORK/c.md"
  [ "$status" -eq 0 ]
}

@test "passes a rule stated without history" {
  printf 'A layperson cannot evaluate a technical document, so the gate is one line.\n' > "$WORK/d.md"
  run bash "$LINT" --strict "$WORK/d.md"
  [ "$status" -eq 0 ]
}

@test "the runtime-context files carry no development history" {
  run bash "$LINT" --strict
  [ "$status" -eq 0 ]
}

@test "scripts, wrappers and tests carry no development-story IDs" {
  # Requirement IDs of the plugin's own stories and sub-task numbers point at
  # documents no reader can open. Fixture content (a user's story.md or
  # tasks.md written by a test) legitimately carries R1.1-style IDs, so the
  # checks target parenthesised ID lists in scripts, sub-task references, and
  # test names.
  cd "$ROOT"
  run git grep -nE '\(R[0-9]+\.[0-9]+([/, ]+R?[0-9]+\.[0-9]+)*\)' -- scripts bin
  [ "$status" -eq 1 ]
  run git grep -niE 'sub-task [0-9]+\.[0-9]' -- scripts bin tests
  [ "$status" -eq 1 ]
  run git grep -nE '@test "[^"]*\bR[0-9]+\.[0-9]+' -- tests
  [ "$status" -eq 1 ]
}
