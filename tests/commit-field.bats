#!/usr/bin/env bats
# Commit-field tests for story 015 — variant 5 of migrate-story.sh (2.3) and
# the consumer sweep's executable surface (3.2: validate-story nudge, run-mode
# ordering prose). Authored Red-first by the Test Advisor from the EARS
# requirements (R2.5, R3.2, R4.1, R4.3) and the design.md contract — never
# from any ToDo.
# Target location after materialization: tests/commit-field.bats
#
# Contract under test:
#   R2.5 — a Commit checkbox sub-task (open OR closed) converts to the
#     group-level `- Commit: "..."` field, message verbatim; the numbering gap
#     stays — numbers are provenance and are never reassigned; a closed box's
#     state is dropped (the field has no box).
#   R3.2 — validation accepts the field form as the commit point and warns
#     that a checkbox Commit sub-task is the legacy shape migrate converts.
#   R4.1 — run-mode orders the group tail: close boxes -> status census (may
#     write done) -> execute the group's Commit: field -> archive offer; the
#     `--gate=commit` row gates at field execution, not at sub-tasks.
#   R4.3 — the reference states that dependency satisfaction reads the boxes
#     that exist (no Commit box, no commit wait).
#
# The 3.2 doc-contract cases match FLATTENED text where the claim may span
# source lines. One case is a PIN: it passes today and must stay green.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MIGRATE_SH="$PLUGIN_ROOT/scripts/migrate-story.sh"
  VALIDATE_SH="$PLUGIN_ROOT/scripts/validate-story.sh"
  REFS="$PLUGIN_ROOT/references"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  mkdir -p "$PROJ/.epic/stories" "$PROJ/.epic/archive"
  cd "$PROJ"
}

teardown() {
  cd /
  rm -rf "$WORK"
}

write_story_md() {
  cat > "$1/story.md" <<'EOF'
---
story: fixture
type: feature
scale: standard
version: 1
created: 2026-08-16
status: in-progress
---

# Story - fixture

## Requirements

### R1. Fixture requirement

#### Acceptance Criteria

- R1.1: WHEN invoked THE SYSTEM SHALL do the thing
EOF
}

# Variant-5 fixture: a group whose commit point is a CLOSED checkbox
# sub-task, a sibling group depending on `Task 1.2` (a provenance pointer the
# rewrite must not strand).
make_commit_subtask_story() {
  local dir="$PROJ/.epic/stories/$1"
  mkdir -p "$dir"
  write_story_md "$dir"
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
scale: standard
status: in-progress
---

# Implementation Plan - legacy commit shape

## Task List

- [ ] 1 - Build the thing
  - _Complexity: Simple | Tests: Unit | Risks: None | Dependencies: None_
  - Objective: Build it

  - [ ] 1.1 - Make part one
    - Validation: ok
    - Requirements: R1.1

  - [ ] 1.2 - Make part two
    - Validation: ok
    - Requirements: R1.1

  - [x] 1.3 - Commit
    - Validation: All tests from 1.1 and 1.2 pass
    - Commit: "feat(090): the exact message, verbatim — punctuation and all"

- [ ] 2 - Follow-up
  - _Complexity: Simple | Tests: None | Risks: None | Dependencies: Task 1.2_
  - Objective: Use it

  - [ ] 2.1 - Use part two
    - Validation: ok
    - Requirements: R1.1

## Quality Gates

- [ ] All task validations pass
EOF
}

# Field-form fixture: the canonical post-template shape — commit point as a
# group-level field, no Commit checkbox anywhere.
make_field_form_story() {
  local dir="$PROJ/.epic/stories/$1"
  mkdir -p "$dir"
  write_story_md "$dir"
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
scale: standard
status: in-progress
---

# Implementation Plan - field form

## Task List

- [ ] 1 - Build the thing
  - _Complexity: Simple | Tests: Unit | Risks: None | Dependencies: None_
  - Objective: Build it
  - Commit: "feat(091): build the thing"

  - [ ] 1.1 - Make part one
    - Validation: ok
    - Requirements: R1.1

## Quality Gates

- [ ] All task validations pass
EOF
}

# --- 2.3 Variant 5: Commit sub-task -> group field, gap preserved (R2.5) ---

@test "2.3: a Commit sub-task becomes one group-level Commit field with the message verbatim" {
  make_commit_subtask_story 090-legacy
  bash "$MIGRATE_SH" .epic/stories/090-legacy --apply > /dev/null 2>&1
  local f="$PROJ/.epic/stories/090-legacy/tasks.md"
  [ "$(grep -cF -- '- Commit: "feat(090): the exact message, verbatim — punctuation and all"' "$f")" -eq 1 ]
  # the field landed inside group 1, before group 2 opens
  local fieldline group2
  fieldline=$(grep -nF 'feat(090): the exact message' "$f" | head -1 | cut -d: -f1)
  group2=$(grep -nE '^- \[ \] 2 - Follow-up' "$f" | head -1 | cut -d: -f1)
  [ -n "$fieldline" ] && [ -n "$group2" ] && [ "$fieldline" -lt "$group2" ]
}

@test "2.3: a closed Commit box's state is dropped — no Commit-titled box of any state remains" {
  make_commit_subtask_story 090-legacy
  bash "$MIGRATE_SH" .epic/stories/090-legacy --apply > /dev/null 2>&1
  local f="$PROJ/.epic/stories/090-legacy/tasks.md"
  run ! grep -qE '^[[:space:]]*- \[[x~ ]\][[:space:]]+[0-9]+\.[0-9]+[[:space:]]+-[[:space:]]+Commit' "$f"
}

@test "2.3: the numbering gap is preserved and nothing is renumbered" {
  make_commit_subtask_story 090-legacy
  bash "$MIGRATE_SH" .epic/stories/090-legacy --apply > /dev/null 2>&1
  local f="$PROJ/.epic/stories/090-legacy/tasks.md"
  grep -qF -- '- [ ] 1.1 - Make part one' "$f"
  grep -qF -- '- [ ] 1.2 - Make part two' "$f"
  # 1.3 is a gap now: no box of any state carries that number
  run ! grep -qE '\[[x~ ]\][[:space:]]+1\.3' "$f"
  grep -qE '^- \[ \] 2 - Follow-up' "$f"
  grep -qF -- '- [ ] 2.1 - Use part two' "$f"
}

@test "2.3: the 'Task 1.2' dependency pointer still resolves after conversion" {
  make_commit_subtask_story 090-legacy
  bash "$MIGRATE_SH" .epic/stories/090-legacy --apply > /dev/null 2>&1
  local f="$PROJ/.epic/stories/090-legacy/tasks.md"
  grep -qF 'Dependencies: Task 1.2' "$f"
  grep -qF -- '- [ ] 1.2 - Make part two' "$f"
}

# --- 3.2 validate-story nudge + run-mode ordering (R3.2, R4.1, R4.3) ---

@test "3.2: PIN a field-only tasks.md raises no commit warning and no legacy nudge" {
  make_field_form_story 091-field
  run --separate-stderr bash "$VALIDATE_SH" .epic/stories/091-field
  echo "$output" | jq -e '[.warning_details[] | select(test("No Commit"))] | length == 0' > /dev/null
  echo "$output" | jq -e '[.warning_details[] | select(test("legacy"; "i"))] | length == 0' > /dev/null
}

@test "3.2: a checkbox Commit sub-task raises the warning-level nudge naming the legacy shape and migrate" {
  make_commit_subtask_story 090-legacy
  run --separate-stderr bash "$VALIDATE_SH" .epic/stories/090-legacy
  echo "$output" | jq -e '[.warning_details[] | select(test("legacy"; "i") and test("migrate"; "i"))] | length > 0' > /dev/null
}

@test "3.2: a sub-task that merely mentions a commit does not raise the legacy nudge" {
  # The nudge names migrate-story.sh and tells the reader to run it, so it may
  # only count what that tool actually converts: a box titled exactly
  # `N.M - Commit`. A sub-task whose TITLE mentions the word is ordinary work —
  # story 015's own `2.3 - Variant 5: Commit sub-task -> group field` is one —
  # and counting it produced a warning that survived doing what it asked:
  # migrate reported `commit_subtasks: 0` and the identical nudge came back.
  make_field_form_story 092-mentions
  cat >> "$PROJ/.epic/stories/092-mentions/tasks.md" <<'EOF'

- [ ] 9 - Later work
  - _Complexity: Simple | Tests: None | Risks: None | Dependencies: None_
  - Objective: Convert the legacy shape
  - Commit: "feat(092): later"

  - [x] 9.1 - Variant 5: Commit sub-task to group field, gap preserved
    - Validation: ok
    - Requirements: R1.1
EOF
  run --separate-stderr bash "$VALIDATE_SH" .epic/stories/092-mentions
  # The nudge must be silent...
  echo "$output" | jq -e '[.warning_details[] | select(test("Commit sub-task checkbox"))] | length == 0' > /dev/null
  # ...and migrate must agree there is nothing to convert.
  run --separate-stderr bash "$MIGRATE_SH" .epic/stories/092-mentions
  echo "$output" | jq -e '.rewrites.commit_subtasks == 0' > /dev/null
}

@test "3.2: run-mode states the group-tail ordering — close boxes, census, Commit field, archive offer" {
  run bash -c "tr '\n' ' ' < '$REFS/run-mode.md' | grep -Eq 'close (the )?boxes.*(status )?census.*Commit:.*archive'"
  [ "$status" -eq 0 ]
}

@test "3.2: the --gate=commit row no longer gates at Commit sub-tasks" {
  # backtick-free pattern: the bats preprocessor mangles \` inside test bodies
  run grep -E -- '--gate=commit.*Gate' "$REFS/run-mode.md"
  [ "$status" -eq 0 ]
  [[ "$output" != *sub-task* ]]
}

@test "3.2: the references state that dependency satisfaction reads the boxes that exist" {
  grep -qiE 'boxes that exist' "$REFS/tasks.md" "$REFS/run-mode.md"
}
