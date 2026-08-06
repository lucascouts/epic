#!/usr/bin/env bats
# Story 004, sub-tasks 2.3 and 5.3/5.4 — cross-regression harness (R4.1, R5.1,
# R3.3, R3.4).
# ONE mixed fixture ([x] / [ ] / [~] terminal / [~] deferred) is passed
# through the SIX checkbox consumers — validate-story.sh, cross-reference.sh,
# hook-task-completed.sh, monitor-stale.sh, hook-precompact.sh,
# hook-post-tool-failure.sh — asserting they agree on which boxes exist and
# which work is open. This pins the duplicated regex so one drifted copy cannot
# silently reopen the false-clean/false-orphan class fixed in e890d02.
#
# Three enumerations of that list have now been wrong: the design said "6 regex
# places across 4 scripts", sub-task 5.3 raised it to 5 and still missed
# hook-post-tool-failure.sh, which the second validate-mode pass found (task
# 6.4). The lesson is the harness itself — a prose list of consumers cannot
# fail, and this file can. If a seventh appears, it belongs here.
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

@test "R4.1: hook-post-tool-failure counts terminal [~] as closed — the reminder still fires" {
  # The sixth consumer, and the quietest one: its guard needs one closed box and
  # one open [ ]. Here the finished work was all closed WITHOUT execution — no
  # [x] anywhere — which the binary guard read as "not mid-run", swallowing the
  # executor Step-4 reminder on a Bash failure.
  sed -i 's/^- \[x\] 1.1 - First done/- [~] 1.1 - First done (n-a: covered by construction)/' "$MIXED/tasks.md"
  sed -i 's/^- \[x\] 1.2 - Second done/- [~] 1.2 - Second done (superseded-by: 011)/' "$MIXED/tasks.md"
  cd "$WORK/proj"
  run bash "$PLUGIN_ROOT/scripts/hook-post-tool-failure.sh" <<< '{"tool_name":"Bash"}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Per executor Step 4 protocol'
  echo "$output" | grep -qF '010-mixed'
  # And it still points at the next OPEN box, never at a [~] one.
  echo "$output" | grep -qF '1.5 - Still open'
}

@test "R4.1: hook-post-tool-failure — a deferred box does not close, so nothing is mid-run" {
  # Every box now open or deferred: this run has produced nothing, so there is
  # no Step-4 protocol to remind anyone about. Same reading as the closed count.
  sed -i 's/^- \[x\] 1.1 - First done/- [ ] 1.1 - First done/' "$MIXED/tasks.md"
  sed -i 's/^- \[x\] 1.2 - Second done/- [ ] 1.2 - Second done/' "$MIXED/tasks.md"
  sed -i 's/(waived: tool absent)/(deferred: waiting on the vendor)/' "$MIXED/tasks.md"
  cd "$WORK/proj"
  run bash "$PLUGIN_ROOT/scripts/hook-post-tool-failure.sh" <<< '{"tool_name":"Bash"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "R5.1: hook-post-tool-failure — the binary [x] + [ ] story behaves exactly as before" {
  cd "$WORK/proj"
  run bash "$PLUGIN_ROOT/scripts/hook-post-tool-failure.sh" <<< '{"tool_name":"Bash"}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Per executor Step 4 protocol'
  echo "$output" | grep -qF '1.5 - Still open'
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

@test "R4.1: the malformed-but-qualified shape — validate-story and hook-precompact agree on it" {
  # `- [~]waived: …` with no space after the box. validate-story read it as a
  # closed box while hook-precompact's grep pipeline counted it as neither
  # closed nor deferred (found by the second validate-mode pass, fixed in 6.5).
  # Replacing the terminal [~] of the mixed fixture with this shape must not
  # move the census: same 5 boxes, same 3 closed, same 1 deferred.
  sed -i 's/^- \[~\] 1.3 - Waived gate (waived: tool absent)/- [~]waived: tool absent/' "$MIXED/tasks.md"

  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$MIXED"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"errors": 0'
  refute_grep 'has no qualifier'

  cd "$WORK/proj"
  run bash "$PLUGIN_ROOT/scripts/hook-precompact.sh"
  [ "$status" -eq 0 ]
  run grep '^- Tasks:' "$MIXED/.draft/compact-snapshot.md"
  [ "$output" = "- Tasks: 3/5 completed (+1 deferred)" ]
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
