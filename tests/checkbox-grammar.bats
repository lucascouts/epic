#!/usr/bin/env bats
# Story 004, sub-tasks 2.3 and 5.3/5.4 — cross-regression harness (R4.1, R5.1,
# R3.3, R3.4).
# ONE mixed fixture ([x] / [ ] / [~] terminal / [~] deferred) is passed
# through the FIVE checkbox consumers — validate-story.sh, cross-reference.sh,
# hook-task-completed.sh, monitor-stale.sh, hook-precompact.sh — asserting they
# agree on which boxes exist and which work is open. This pins the duplicated
# regex so one drifted copy cannot silently reopen the false-clean/false-orphan
# class fixed in e890d02.
#
# The design originally claimed "6 regex places across 4 scripts"; a fifth
# script (hook-precompact.sh) was found during Run and is covered here plus in
# tests/hook-precompact-grammar.bats. If a sixth appears, it belongs here too —
# that is the whole point of a harness over a per-script suite.
#
# Mixed fixture totals (the shared truth all four must agree on):
#   total = 5 boxes · closed = 3 ([x] 1.1, 1.2 + terminal [~] 1.3)
#   deferred = 1 ([~] 1.4) · open = 1 ([ ] 1.5)
#
# Plus the legacy compat contract (R5.1): a story with no status: and no [~]
# produces BYTE-IDENTICAL validate-story and cross-reference JSON vs the
# golden output recorded from the pre-change scripts (2026-08-02, branch
# fix/epic-traceability).

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  mkdir -p "$WORK/proj/.epic/stories/010-mixed"
  MIXED="$WORK/proj/.epic/stories/010-mixed"
  write_mixed_fixture
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

write_mixed_fixture() {
  cat > "$MIXED/story.md" <<'EOF'
---
story: mixed-fixture
type: feature
scale: standard
version: 1
created: 2026-08-02
---

## Introduction
Shared mixed-grammar fixture for the four checkbox consumers.

### R1. First requirement
#### Acceptance Criteria
- R1.1: WHEN a THE SYSTEM SHALL b
- R1.2: WHEN c THE SYSTEM SHALL d
- R1.3: WHEN e THE SYSTEM SHALL f
- R1.4: WHEN g THE SYSTEM SHALL h
- R1.5: WHEN i THE SYSTEM SHALL j
EOF
  cat > "$MIXED/tasks.md" <<'EOF'
---
story: mixed-fixture
type: feature
scale: standard
version: 1
created: 2026-08-02
---

## Task List
- [x] 1.1 - First done
  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_
  - Requirements: R1.1
  - Validation: bats green
- [x] 1.2 - Second done
  - Requirements: R1.2
  - Validation: bats green
- [~] 1.3 - Waived gate (waived: tool absent)
  - Requirements: R1.3
  - Validation: waived
- [~] 1.4 - External proof (deferred: real hardware)
  - Requirements: R1.4
  - Validation: deferred
- [ ] 1.5 - Still open
  - Requirements: R1.5
  - Validation: bats green
  - Commit: "feat: mixed"

## Quality Gates
- Counts consistent
EOF
}

write_legacy_fixture() { # writes $WORK/legacy/story — MUST stay byte-stable
  mkdir -p "$WORK/legacy/story"
  cat > "$WORK/legacy/story/story.md" <<'EOF'
---
story: legacy-fixture
type: feature
scale: standard
version: 1
created: 2026-01-10
---

## Introduction
Legacy story with no status field and no tilde boxes.

### R1. First requirement
#### Acceptance Criteria
- R1.1: WHEN x THE SYSTEM SHALL y
- R1.2: WHEN a THE SYSTEM SHALL b
EOF
  cat > "$WORK/legacy/story/tasks.md" <<'EOF'
---
story: legacy-fixture
type: feature
scale: standard
version: 1
created: 2026-01-10
---

## Task List
- [x] 1 - Group
  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_
  - [x] 1.1 - implement first
    - Requirements: R1.1
    - Validation: bats green
  - [ ] 1.2 - implement second
    - Requirements: R1.2
    - Validation: bats green
  - Commit: "feat: legacy"

## Quality Gates
- [ ] All acceptance criteria validated
EOF
}

@test "R4.1: validate-story accepts the mixed fixture with zero errors" {
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$MIXED"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"errors": 0'
  refute_grep 'no parseable checkbox tasks'
}

@test "R4.1: cross-reference sees all 5 boxes and traces all 5 requirements" {
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$MIXED"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "clean"'
  echo "$output" | grep -qF '"parseable_tasks": 5'
  echo "$output" | grep -qF '"coverage": "5/5"'
  echo "$output" | grep -qF '"orphan_requirements": []'
  # The [~] headings (terminal AND deferred) keep attributing:
  echo "$output" | grep -qF '"R1.3": ["1.3"]'
  echo "$output" | grep -qF '"R1.4": ["1.4"]'
}

@test "R4.1: hook-task-completed recognizes the mixed story and passes it" {
  cd "$WORK/proj"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/scripts/hook-task-completed.sh"
  [ "$status" -eq 0 ]
}

@test "R4.1: monitor-stale agrees — open [ ] pending, deferred/terminal [~] not pending" {
  # Mixed fixture has one [ ] box: an old story IS stale.
  touch -d '30 days ago' "$MIXED/tasks.md"
  cd "$WORK/proj"
  run timeout 2 env \
    CLAUDE_PLUGIN_OPTION_ENABLESTALEMONITOR=true \
    CLAUDE_PLUGIN_OPTION_STALETHRESHOLDDAYS=7 \
    CLAUDE_PLUGIN_OPTION_STALECHECKINTERVALSECONDS=10 \
    bash "$PLUGIN_ROOT/scripts/monitor-stale.sh"
  [ "$status" -eq 124 ]
  echo "$output" | grep -q '010-mixed'

  # Close the last [ ]: only [x] + [~] remain — no pending work, not stale.
  sed -i 's/^- \[ \] 1.5/- [x] 1.5/' "$MIXED/tasks.md"
  touch -d '30 days ago' "$MIXED/tasks.md"
  run timeout 2 env \
    CLAUDE_PLUGIN_OPTION_ENABLESTALEMONITOR=true \
    CLAUDE_PLUGIN_OPTION_STALETHRESHOLDDAYS=7 \
    CLAUDE_PLUGIN_OPTION_STALECHECKINTERVALSECONDS=10 \
    bash "$PLUGIN_ROOT/scripts/monitor-stale.sh"
  [ "$status" -eq 124 ]
  refute_grep '010-mixed'
}

@test "R4.1: hook-precompact renders the census the other four parse" {
  cd "$WORK/proj"
  run bash "$PLUGIN_ROOT/scripts/hook-precompact.sh"
  [ "$status" -eq 0 ]
  run grep '^- Tasks:' "$MIXED/.draft/compact-snapshot.md"
  # Same shared truth as the header: total 5, closed 3, deferred 1.
  [ "$output" = "- Tasks: 3/5 completed (+1 deferred)" ]
}

@test "R3.3/R3.4: only-deferred fixture — no work is open, and the deferred box is not hidden" {
  # The scenario task 3.2 claimed was covered and was not. Close the last [ ]:
  # what remains is [x] + terminal [~] + one deferred [~]. By the single
  # completion definition nothing is pending, and the story's computed
  # condition is done-except-external (1 deferred).
  sed -i 's/^- \[ \] 1.5/- [x] 1.5/' "$MIXED/tasks.md"

  # A persisted `validated` here must NOT trip the ahead-of-checkboxes warning
  # (R2.3 counts `[ ]` only) — this is what lets a done-except-external story
  # go in-progress -> validated, skipping done.
  sed -i 's/^created: 2026-08-02$/created: 2026-08-02\nstatus: validated/' \
    "$MIXED/tasks.md" "$MIXED/story.md"

  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$MIXED"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"errors": 0'
  echo "$output" | grep -q '"warnings": 0'
  refute_grep 'ahead of the checkboxes'

  # cross-reference still traces every requirement, deferred box included.
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$MIXED"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '"parseable_tasks": 5'
  echo "$output" | grep -qF '"coverage": "5/5"'

  # The renderer reports 4 closed of 5, with the one deferred box counted apart
  # rather than folded into either number.
  cd "$WORK/proj"
  run bash "$PLUGIN_ROOT/scripts/hook-precompact.sh"
  [ "$status" -eq 0 ]
  run grep '^- Tasks:' "$MIXED/.draft/compact-snapshot.md"
  [ "$output" = "- Tasks: 4/5 completed (+1 deferred)" ]

  # And nothing is pending: no "Next pending" line is emitted.
  run grep -c '^- Next pending:' "$MIXED/.draft/compact-snapshot.md"
  [ "$output" = "0" ]
}

@test "R5.1: legacy story — validate-story output is byte-identical to the pre-change golden" {
  write_legacy_fixture
  cd "$WORK/legacy"
  expected=$(cat <<'GOLDEN'
{
  "story": "story",
  "errors": 0,
  "warnings": 0,
  "error_details": [],
  "warning_details": [],
  "strict": false,
  "status": "pass"
}
GOLDEN
)
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" story
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "R5.1: legacy story — cross-reference output is byte-identical to the pre-change golden" {
  write_legacy_fixture
  cd "$WORK/legacy"
  expected=$(cat <<'GOLDEN'
{
  "story": "story",
  "story_requirements": 2,
  "task_references": 2,
  "parseable_tasks": 3,
  "traced": 2,
  "orphan_requirements": [],
  "phantom_references": [],
  "coverage": "2/2",
  "mapping": {"R1.1": ["1.1"], "R1.2": ["1.2"]},
  "status": "clean"
}
GOLDEN
)
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" story
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}
