#!/usr/bin/env bats
# Integration tests for the helper ↔ reference ↔ router contract
# (story 013 — quick-create, task 4.1).
# Authored by the Test Advisor BEFORE implementation (TDD Red phase).
#
# Three-way contract under test (design.md components 1 and 3):
#   - references/batch-create.md documents the allocator's JSON keys
#     (`next`, `reserved`, `collisions`) and they round-trip EXACTLY against
#     a live run of scripts/next-story-number.sh on a fixture tree — every
#     documented contract key is emitted, every emitted key is documented
#   - the SKILL Mode Dispatch batch row and references/batch-create.md
#     cross-resolve, and the reference names the real allocator script
#   - batch-create.md cites list-mode.md's batch-verdict grammar by anchor
#     and that anchor exists (single-definition rule, story Constraints)
#
# Fidelity: every scenario reads the real files and executes the real
# allocator — no stubs, no inline copies of the reference prose.
#
# EPIC_PLUGIN_ROOT overrides root resolution so the draft copy under
# .draft/authored-tests/tests/ can run before materialization into tests/.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="${EPIC_PLUGIN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  SCRIPT="$PLUGIN_ROOT/scripts/next-story-number.sh"
  REF="$PLUGIN_ROOT/references/batch-create.md"
  SKILL="$PLUGIN_ROOT/skills/epic/SKILL.md"
  LIST="$PLUGIN_ROOT/references/list-mode.md"
  WORK=$(mktemp -d)
  mkdir -p "$WORK/.epic/stories" "$WORK/.epic/archive"
}

teardown() {
  rm -rf "$WORK"
}

# GitHub-style slug for a markdown heading: lowercase, strip everything but
# alphanumerics, spaces and hyphens, then spaces -> hyphens.
slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9 -]//g' -e 's/ /-/g'
}

@test "4.1: documented JSON keys round-trip against a live allocator run" {
  [ -f "$REF" ]
  mkdir "$WORK/.epic/stories/003-fixture"
  out=$( cd "$WORK" && bash "$SCRIPT" --reserve 1 )
  echo "$out" | jq -e 'type == "object"'
  # every contract key the reference documents is emitted by the script
  for key in next reserved collisions; do
    command grep -q "\`$key\`" "$REF"
    echo "$out" | jq -e --arg k "$key" 'has($k)'
  done
  # and the script emits no top-level key the reference does not document
  while IFS= read -r k; do
    command grep -q "\`$k\`" "$REF"
  done < <(echo "$out" | jq -r 'keys_unsorted[]')
}

@test "4.1: SKILL dispatch row, reference and allocator cross-resolve" {
  # router -> reference: a Mode Dispatch table row for batch names the file
  command grep -Eq '\|.*[Bb]atch.*\|.*batch-create\.md' "$SKILL"
  [ -f "$REF" ]
  # reference -> helper: batch-create.md names the allocator, which exists
  # and parses
  command grep -q 'next-story-number\.sh' "$REF"
  [ -f "$SCRIPT" ]
  bash -n "$SCRIPT"
}

@test "4.1: the list-mode grammar anchor cited by batch-create.md exists" {
  [ -f "$REF" ]
  anchor=$(command grep -o 'list-mode\.md#[a-z0-9-]*' "$REF" | head -1)
  [ -n "$anchor" ]
  anchor="${anchor#list-mode.md#}"
  found=0
  while IFS= read -r line; do
    text=$(printf '%s' "$line" | sed -e 's/^#\{1,6\} //')
    if [ "$(slug "$text")" = "$anchor" ]; then
      found=1
      break
    fi
  done < <(command grep -E '^#{1,6} ' "$LIST")
  # tolerate an explicit HTML anchor as the citation target
  if [ "$found" -ne 1 ]; then
    command grep -Eq "(id|name)=\"$anchor\"" "$LIST"
  fi
}
