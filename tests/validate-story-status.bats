#!/usr/bin/env bats
# Story 004, sub-task 1.2 — `status:` enum validation in scripts/validate-story.sh.
# Contract under test (R2.1–R2.4):
#   - status outside the enum (draft|in-progress|done|validated|superseded|
#     archived) is an ERROR naming the invalid value and the enum (R2.1).
#   - ABSENT status produces zero status-related errors or warnings — the
#     legacy hard contract (R2.2).
#   - status done|validated while a `[ ]` box remains warns "ahead of the
#     checkboxes" (R2.3).
#   - divergent status values across the story's artifacts warn, naming the
#     divergent files (R2.4).

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/story"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

# Assert $output does NOT match a pattern. (Bare `! grep` is exempt from
# bats' errexit trap and would never fail the test.)
refute_grep() {
  if grep -q "$1" <<< "$output"; then
    echo "did not expect pattern in output: $1"
    return 1
  fi
}

# Minimal warning-free standard fixture; $1 = extra frontmatter line for
# story.md (e.g. "status: draft") or empty, $2 = extra frontmatter line for
# tasks.md or empty, $3 = checkbox state of the single task ("x" or " ").
write_story_pair() {
  local fm_story="$1" fm_tasks="$2" box="${3:-x}"
  {
    echo '---'
    echo 'story: status-fixture'
    echo 'type: feature'
    echo 'scale: standard'
    echo 'version: 1'
    echo 'created: 2026-08-02'
    if [ -n "$fm_story" ]; then echo "$fm_story"; fi
    echo '---'
    echo
    echo '## Introduction'
    echo 'Status enum fixture.'
    echo
    echo '### R1. First requirement'
    echo '#### Acceptance Criteria'
    echo '- R1.1: WHEN x THE SYSTEM SHALL y'
  } > "$STORY/story.md"
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-08-02'
    if [ -n "$fm_tasks" ]; then echo "$fm_tasks"; fi
    echo '---'
    echo
    echo '## Task List'
    echo "- [$box] 1 - Implement"
    echo '  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_'
    echo '  - Requirements: R1.1'
    echo '  - Validation: bats green'
    echo '  - Commit: "feat: x"'
    echo
    echo '## Quality Gates'
    echo '- Done'
  } > "$STORY/tasks.md"
}

@test "R2.1: status outside the enum is an error naming the value and the enum" {
  write_story_pair "status: medium" "status: medium" "x"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  # Error names the offending value...
  echo "$output" | grep -q 'medium'
  # ...and the sanctioned enum (spot-check distinctive members).
  echo "$output" | grep -q 'in-progress'
  echo "$output" | grep -q 'superseded'
}

@test "R2.1: every enum value is accepted without a status error" {
  local v
  for v in draft in-progress done validated superseded archived; do
    write_story_pair "status: $v" "status: $v" "x"
    run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
    [ "$status" -eq 0 ] || { echo "enum value rejected: $v"; echo "$output"; return 1; }
    echo "$output" | grep -q '"errors": 0'
  done
}

@test "R2.2: absent status field produces zero errors and zero warnings (legacy hard contract)" {
  write_story_pair "" "" "x"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"errors": 0'
  echo "$output" | grep -q '"warnings": 0'
}

@test "R2.3: status done with an open [ ] box warns that status is ahead of the checkboxes" {
  write_story_pair "status: done" "status: done" " "
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  # Warning, not error: exit stays 0 without --strict.
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'ahead'
  refute_grep '"warnings": 0'
}

@test "R2.3: status validated with an open [ ] box also warns" {
  write_story_pair "status: validated" "status: validated" " "
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'ahead'
}

@test "R2.4: divergent status across artifacts warns naming the divergent files" {
  write_story_pair "status: done" "status: draft" "x"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  refute_grep '"warnings": 0'
  echo "$output" | grep -q 'story\.md'
  echo "$output" | grep -q 'tasks\.md'
}
