#!/usr/bin/env bats
# Story 010, sub-tasks 2.1 and 2.2 — marking and status as ONE transaction
# inside scripts/close-subtask.sh (R2.1, R2.2, R2.3, R2.4, R1.5).
# Authored by the Test Advisor BEFORE implementation (TDD Red phase).
#
# Contract under test (design.md, component 1, status transaction):
#   after the box write the script runs the census, applies run-mode's 4
#   transition rules, stamps `status:` in every artifact carrying frontmatter,
#   self-invokes validate-story.sh, and emits ONE JSON object:
#   {story, task, box, qualifier, census: {total, open, closed, deferred},
#    status_written: {from, to} | null, validate: {errors, warnings, status}}
# A validation failure never rolls the marking back (R2.4).
#
# Census fixtures avoid terminal [~] where counts are asserted, so the
# assertions pin the completion definition (tasks.md#completion), not one
# consumer's private aggregation of terminal tildes.
#
# EPIC_PLUGIN_ROOT overrides root resolution so the draft copy under
# .draft/authored-tests/tests/ can run before materialization into tests/.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="${EPIC_PLUGIN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  SCRIPT="$PLUGIN_ROOT/scripts/close-subtask.sh"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  STORY="$PROJ/.epic/stories/013-txn"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

# frontmatter <status-or-empty>: prints the shared frontmatter block.
frontmatter() {
  printf -- '---\nstory: txn\ntype: feature\nscale: standard\n'
  [ -n "$1" ] && printf 'status: %s\n' "$1"
  printf -- 'version: 1\ncreated: 2026-08-16\n---\n'
}

# write_artifacts <status-or-empty>: story.md + design.md with frontmatter;
# tasks.md gets the same frontmatter plus the body read from stdin.
write_artifacts() {
  local st="$1"
  { frontmatter "$st"
    cat <<'EOF'

## Introduction
Transaction fixture story.

### R1. First requirement
#### Acceptance Criteria
- R1.1: WHEN a THE SYSTEM SHALL b
- R1.2: WHEN c THE SYSTEM SHALL d
- R1.3: WHEN e THE SYSTEM SHALL f
EOF
  } > "$STORY/story.md"
  { frontmatter "$st"
    printf '\n## Overview\nTransaction fixture design.\n'
  } > "$STORY/design.md"
  { frontmatter "$st"; printf '\n'; cat; } > "$STORY/tasks.md"
}

# Body A: two closed, one open — closing 1.3 completes the story.
body_last_open() {
  cat <<'EOF'
## Task List
- [x] 1.1 - First slice
  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_
  - Requirements: R1.1
  - Validation: bats green
- [x] 1.2 - Second slice
  - Requirements: R1.2
  - Validation: bats green
- [ ] 1.3 - Third slice
  - Requirements: R1.3
  - Validation: bats green
  - Commit: "feat(013): all three slices"

## Quality Gates
- Counts consistent
EOF
}

# Body B: all three open.
body_all_open() {
  cat <<'EOF'
## Task List
- [ ] 1.1 - First slice
  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_
  - Requirements: R1.1
  - Validation: bats green
- [ ] 1.2 - Second slice
  - Requirements: R1.2
  - Validation: bats green
- [ ] 1.3 - Third slice
  - Requirements: R1.3
  - Validation: bats green
  - Commit: "feat(013): all three slices"

## Quality Gates
- Counts consistent
EOF
}

status_line_of() { # status_line_of <file> → the status: value
  sed -n '2,/^---$/p' "$1" | sed -n 's/^status:[[:space:]]*//p' | head -1
}

run_close() {
  cd "$PROJ"
  run --separate-stderr bash "$SCRIPT" .epic/stories/013-txn "$@"
}

# =====================================================================
# Sub-task 2.1 — census + status transition + frontmatter stamping
# =====================================================================

@test "2.1 closing the last open box flips in-progress→done in every artifact (R2.1, R2.2)" {
  body_last_open | write_artifacts in-progress
  run_close 1.3
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status_written.from == "in-progress" and .status_written.to == "done"'
  [ "$(status_line_of "$STORY/tasks.md")" = done ]
  [ "$(status_line_of "$STORY/story.md")" = done ]
  [ "$(status_line_of "$STORY/design.md")" = done ]
}

@test "2.1 a deferred-only close never writes done (R2.1)" {
  body_last_open | write_artifacts in-progress
  run_close 1.3 --tilde "deferred: awaiting the live account"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status_written == null'
  [ "$(status_line_of "$STORY/tasks.md")" = in-progress ]
  [ "$(status_line_of "$STORY/story.md")" = in-progress ]
  [ "$(status_line_of "$STORY/design.md")" = in-progress ]
}

@test "2.1 a terminal tilde close of the last box does write done (R2.1)" {
  body_last_open | write_artifacts in-progress
  run_close 1.3 --tilde "waived: tool absent"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status_written.to == "done"'
  [ "$(status_line_of "$STORY/tasks.md")" = done ]
}

@test "2.1 first marking of a draft story writes in-progress everywhere (R2.1)" {
  body_all_open | write_artifacts draft
  run_close 1.1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status_written.from == "draft" and .status_written.to == "in-progress"'
  [ "$(status_line_of "$STORY/tasks.md")" = in-progress ]
  [ "$(status_line_of "$STORY/story.md")" = in-progress ]
  [ "$(status_line_of "$STORY/design.md")" = in-progress ]
}

@test "2.1 legacy story with no status field gains status: in-progress (R2.1)" {
  body_all_open | write_artifacts ""
  run_close 1.1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status_written.to == "in-progress"'
  [ "$(status_line_of "$STORY/tasks.md")" = in-progress ]
  [ "$(status_line_of "$STORY/story.md")" = in-progress ]
}

@test "2.1 a close that leaves open boxes on an in-progress story writes no transition (R2.1)" {
  body_all_open | write_artifacts in-progress
  run_close 1.1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status_written == null'
  [ "$(status_line_of "$STORY/tasks.md")" = in-progress ]
}

@test "2.1 an open Quality-Gate box blocks done — the census spans the gates (R2.1)" {
  { body_last_open; printf -- '- [ ] Schema diff reviewed by the data owner\n'; } |
    write_artifacts in-progress
  run_close 1.3
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status_written == null'
  [ "$(status_line_of "$STORY/tasks.md")" = in-progress ]
}

@test "2.1 the census in the JSON matches the boxes as they now stand (R2.1)" {
  # 1.1 [x] · 1.2 [ ] (about to close) · 1.3 [~] deferred — no terminal [~],
  # so the counts are consumer-independent: total 3, open 0, closed 2, deferred 1.
  { cat <<'EOF'
## Task List
- [x] 1.1 - First slice
  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_
  - Requirements: R1.1
  - Validation: bats green
- [ ] 1.2 - Second slice
  - Requirements: R1.2
  - Validation: bats green
- [~] 1.3 - Third slice (deferred: real hardware)
  - Requirements: R1.3
  - Validation: deferred
  - Commit: "feat(013): all three slices"

## Quality Gates
- Counts consistent
EOF
  } | write_artifacts in-progress
  run_close 1.2
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.census.total == 3 and .census.open == 0 and .census.closed == 2 and .census.deferred == 1'
}

# =====================================================================
# Sub-task 2.2 — self-validation + the one JSON report
# =====================================================================

@test "2.2 one JSON object with the full key set, hostile reason escaped (R1.5)" {
  body_all_open | write_artifacts in-progress
  run_close 1.1 --tilde 'deferred: needs "quotes" and a \ tail'
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  echo "$output" | jq -e 'has("story") and has("task") and has("box") and
    has("qualifier") and has("census") and has("status_written") and has("validate")'
  echo "$output" | jq -e '.qualifier == "deferred"'
}

@test "2.2 a reason carrying a newline still yields parseable JSON (R1.5)" {
  body_all_open | write_artifacts in-progress
  run_close 1.1 --tilde $'deferred: first line\nsecond line'
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}

@test "2.2 the embedded validate verdict is present and clean on a clean story (R2.3)" {
  body_last_open | write_artifacts in-progress
  run_close 1.3
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.validate.errors == 0 and (.validate | has("warnings") and has("status"))'
}

@test "2.2 a validation error is surfaced and does NOT roll back the marking (R2.4)" {
  # Standard scale with checkbox tasks but zero Requirements: fields — a
  # calibrated validate-story.sh ERROR ("has N tasks but no 'Requirements:'
  # fields"). The close still lands and still exits 0.
  { cat <<'EOF'
## Task List
- [ ] 1.1 - Unmapped slice
  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_
  - Validation: bats green
  - Commit: "feat(013): unmapped"

## Quality Gates
- Counts consistent
EOF
  } | write_artifacts in-progress
  run_close 1.1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.validate.errors >= 1'
  grep -qE '^[[:space:]]*- \[x\] 1\.1 - Unmapped slice' "$STORY/tasks.md"
}
