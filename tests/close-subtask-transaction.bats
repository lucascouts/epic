#!/usr/bin/env bats
# Marking and status as ONE transaction inside scripts/close-subtask.sh.
#
# Contract under test (status transaction):
#   after the box write the script runs the census, applies run-mode's 4
#   transition rules, stamps `status:` in every artifact carrying frontmatter,
#   self-invokes validate-story.sh, and emits ONE JSON object:
#   {story, task, box, qualifier, census: {total, open, closed, deferred},
#    status_written: {from, to} | null, validate: {errors, warnings, status}}
# A validation failure never rolls the marking back.
#
# Census fixtures avoid terminal [~] where counts are asserted, so the
# assertions pin the completion definition (tasks.md#completion), not one
# consumer's private aggregation of terminal tildes.
#
# EPIC_PLUGIN_ROOT overrides root resolution so a copy of this file outside
# tests/ can run against the plugin.

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
# Census + status transition + frontmatter stamping
# =====================================================================

@test "closing the last open box flips in-progress→done in every artifact" {
  body_last_open | write_artifacts in-progress
  run_close 1.3
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status_written.from == "in-progress" and .status_written.to == "done"'
  [ "$(status_line_of "$STORY/tasks.md")" = done ]
  [ "$(status_line_of "$STORY/story.md")" = done ]
  [ "$(status_line_of "$STORY/design.md")" = done ]
}

@test "a deferred-only close never writes done" {
  body_last_open | write_artifacts in-progress
  run_close 1.3 --tilde "deferred: awaiting the live account"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status_written == null'
  [ "$(status_line_of "$STORY/tasks.md")" = in-progress ]
  [ "$(status_line_of "$STORY/story.md")" = in-progress ]
  [ "$(status_line_of "$STORY/design.md")" = in-progress ]
}

@test "a terminal tilde close of the last box does write done" {
  body_last_open | write_artifacts in-progress
  run_close 1.3 --tilde "waived: tool absent"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status_written.to == "done"'
  [ "$(status_line_of "$STORY/tasks.md")" = done ]
}

@test "first marking of a draft story writes in-progress everywhere" {
  body_all_open | write_artifacts draft
  run_close 1.1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status_written.from == "draft" and .status_written.to == "in-progress"'
  [ "$(status_line_of "$STORY/tasks.md")" = in-progress ]
  [ "$(status_line_of "$STORY/story.md")" = in-progress ]
  [ "$(status_line_of "$STORY/design.md")" = in-progress ]
}

@test "legacy story with no status field gains status: in-progress" {
  body_all_open | write_artifacts ""
  run_close 1.1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status_written.to == "in-progress"'
  [ "$(status_line_of "$STORY/tasks.md")" = in-progress ]
  [ "$(status_line_of "$STORY/story.md")" = in-progress ]
}

@test "a close that leaves open boxes on an in-progress story writes no transition" {
  body_all_open | write_artifacts in-progress
  run_close 1.1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status_written == null'
  [ "$(status_line_of "$STORY/tasks.md")" = in-progress ]
}

@test "an open Quality-Gate box blocks done — the census spans the gates" {
  { body_last_open; printf -- '- [ ] Schema diff reviewed by the data owner\n'; } |
    write_artifacts in-progress
  run_close 1.3
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status_written == null'
  [ "$(status_line_of "$STORY/tasks.md")" = in-progress ]
}

@test "the census in the JSON matches the boxes as they now stand" {
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
# Self-validation + the one JSON report
# =====================================================================

@test "one JSON object with the full key set, hostile reason escaped" {
  body_all_open | write_artifacts in-progress
  run_close 1.1 --tilde 'deferred: needs "quotes" and a \ tail'
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  echo "$output" | jq -e 'has("story") and has("task") and has("box") and
    has("qualifier") and has("census") and has("status_written") and has("validate")'
  echo "$output" | jq -e '.qualifier == "deferred"'
}

@test "a reason carrying a newline still yields parseable JSON" {
  body_all_open | write_artifacts in-progress
  run_close 1.1 --tilde $'deferred: first line\nsecond line'
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}

@test "the embedded validate verdict is present and clean on a clean story" {
  body_last_open | write_artifacts in-progress
  run_close 1.3
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.validate.errors == 0 and (.validate | has("warnings") and has("status"))'
}

@test "a validation error is surfaced and does NOT roll back the marking" {
  # Standard scale with checkbox tasks but zero Requirements: fields — a
  # validate-story.sh ERROR ("has N tasks but no 'Requirements:'
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

# =====================================================================
# Rule 2 (reopen) and rule 1's guard for statuses outside the enum
#
# Both arms live in close-subtask.sh's "3c. The four transition rules"
# block, and a plain close never exercises either. Prose cannot fail, so
# each arm gets a case that fails if it regresses.
# =====================================================================

@test "rule 2 — a done story with work still owed reopens to in-progress" {
  # WHY: a story with an open box still owes work, and a story that owes
  # work is not done. So the marking that finds `done` sitting over a
  # leftover `[ ]` does not merely decline to write — it REOPENS, walking
  # the status back to in-progress in every artifact. Rule 2 is the only
  # arm of the table that moves a status BACKWARDS.
  #
  # 1.1 is closed and 1.2/1.3 stay open on purpose: rule 1 is tested
  # first and would swallow this case if the census reached zero open.
  body_all_open | write_artifacts done
  run_close 1.1
  [ "$status" -eq 0 ]
  # The census still shows work owed — the precondition rule 2 fires on.
  echo "$output" | jq -e '.census.open == 2'
  echo "$output" | jq -e '.status_written.from == "done" and .status_written.to == "in-progress"'
  # Stamped in the FILES, not merely announced in the JSON: the report is
  # a claim about the artifacts, and only the artifacts can confirm it.
  [ "$(status_line_of "$STORY/tasks.md")" = in-progress ]
  [ "$(status_line_of "$STORY/story.md")" = in-progress ]
  [ "$(status_line_of "$STORY/design.md")" = in-progress ]
}

@test "rule 1 leaves a status outside the enum alone — superseded survives" {
  # WHY: `superseded` and `archived` are terminal, and both legitimately
  # sit over a fully-closed census — validate-story.sh says so in those
  # words ("neither is a state rule 1 would overwrite with `done`") while
  # choosing which statuses its behind-the-checkboxes warning may fire
  # on. Reading rule 1 as unconditional would make this script erase a
  # supersede the first time a Quality Gate was settled on a superseded
  # story. Anything else outside the six-value enum is left alone for the
  # same reason: it is not a state this table describes.
  body_last_open | write_artifacts superseded
  run_close 1.3
  [ "$status" -eq 0 ]
  # THE CONDITION REALLY WAS MET: zero open and zero deferred is exactly
  # what rule 1 fires on. Without this assertion the case could pass by
  # never reaching the `case` at all, and would then prove nothing about
  # the guard.
  echo "$output" | jq -e '.census.open == 0 and .census.deferred == 0'
  echo "$output" | jq -e '.status_written == null'
  # And the guard held where it counts — in the artifacts on disk.
  [ "$(status_line_of "$STORY/tasks.md")" = superseded ]
  [ "$(status_line_of "$STORY/story.md")" = superseded ]
  [ "$(status_line_of "$STORY/design.md")" = superseded ]
}
