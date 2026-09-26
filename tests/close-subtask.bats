#!/usr/bin/env bats
# scripts/close-subtask.sh: skeleton, marking, refusals.
#
# Contract under test:
#   close-subtask.sh <NNN|story-dir> <N.N|N|gate:<text-prefix>> \
#                    [--tilde "<qualifier>: <reason>"]
#   stdout: one JSON object; diagnostics on stderr.
#   Exit 0 done · 1 refused (nothing written) · 2 usage.
#   Refusals: box not found; box already [x]/[~]; qualifier outside the
#   four-form grammar (deferred: / waived: / n-a: / superseded-by: NNN);
#   story under .epic/archive/.
#
# EPIC_PLUGIN_ROOT overrides root resolution so a copy of this file outside
# tests/ can run against the plugin.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="${EPIC_PLUGIN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  SCRIPT="$PLUGIN_ROOT/scripts/close-subtask.sh"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  STORY="$PROJ/.epic/stories/012-widget"
  mkdir -p "$STORY"
  write_story_fixture
}

teardown() {
  rm -rf "$WORK"
}

write_story_fixture() {
  cat > "$STORY/story.md" <<'EOF'
---
story: widget
type: feature
scale: standard
status: in-progress
version: 1
created: 2026-08-16
---

## Introduction
Close-subtask marking fixture.

### R1. First requirement
#### Acceptance Criteria
- R1.1: WHEN a THE SYSTEM SHALL b
- R1.2: WHEN c THE SYSTEM SHALL d
- R1.3: WHEN e THE SYSTEM SHALL f
- R1.4: WHEN g THE SYSTEM SHALL h
EOF
  cat > "$STORY/tasks.md" <<'EOF'
---
story: widget
type: feature
scale: standard
status: in-progress
version: 1
created: 2026-08-16
---

## Task List
- [ ] 1 - Build the widget
  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_
  - [ ] 1.1 - Implement the parser
    - Requirements: R1.1
    - Validation: bats green
  - [ ] 1.2 - Implement the emitter
    - Requirements: R1.2
    - Validation: bats green
- [x] 2 - Landed group
  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_
  - [x] 2.1 - Already closed
    - Requirements: R1.3
    - Validation: bats green
- [~] 3 - Skipped group (waived: tool absent)
  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_
- [ ] 4 - Wrap-up
  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_
  - [x] 4.1 - Final polish
    - Requirements: R1.4
    - Validation: bats green
  - Commit: "feat(012): build the widget"

## Quality Gates
- [ ] All task validations pass
- [x] All tests written and passing
EOF
}

# make_archived: the same story shape parked under .epic/archive/.
make_archived() {
  mkdir -p "$PROJ/.epic/archive/007-old"
  cp "$STORY/tasks.md" "$PROJ/.epic/archive/007-old/tasks.md"
}

# snapshot <file>: keep a pristine copy for unchanged-on-refusal assertions.
snapshot() {
  cp "$1" "$WORK/snapshot.md"
}

assert_unchanged() {
  cmp -s "$1" "$WORK/snapshot.md"
}

# run_close <args...>: invoke from the project root, stdout captured alone so
# $output is exactly the JSON the contract promises.
run_close() {
  cd "$PROJ"
  run --separate-stderr bash "$SCRIPT" "$@"
}

# =====================================================================
# Skeleton: args, story resolution, refusal arms
# =====================================================================

@test "no arguments: exit 2 with the synopsis on stderr" {
  run_close
  [ "$status" -eq 2 ]
  grep -qi 'usage' <<< "$stderr"
}

@test "missing task argument: exit 2 (usage)" {
  run_close .epic/stories/012-widget
  [ "$status" -eq 2 ]
}

@test "--help: exit 2 (usage synopsis, not a close)" {
  run_close --help
  [ "$status" -eq 2 ]
}

@test "missing story: exit 1 (refusal, not usage)" {
  run_close 999 1.1
  [ "$status" -eq 1 ]
}

@test "archived story: exit 1 and tasks.md byte-identical" {
  make_archived
  snapshot "$PROJ/.epic/archive/007-old/tasks.md"
  run_close .epic/archive/007-old 1.1
  [ "$status" -eq 1 ]
  assert_unchanged "$PROJ/.epic/archive/007-old/tasks.md"
}

@test "refusal leaves no file behind — not even a tmp" {
  make_archived
  find "$PROJ" -type f | sort > "$WORK/before.txt"
  run_close .epic/archive/007-old 1.1
  [ "$status" -eq 1 ]
  find "$PROJ" -type f | sort > "$WORK/after.txt"
  cmp -s "$WORK/before.txt" "$WORK/after.txt"
}

# =====================================================================
# Locate-and-mark with the shared grammar, atomically
# =====================================================================

@test "marks [x] on an open sub-task and reports it" {
  run_close .epic/stories/012-widget 1.1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.task == "1.1" and .box == "x"'
  grep -qE '^[[:space:]]*- \[x\] 1\.1 - Implement the parser' "$STORY/tasks.md"
  # The sibling box is untouched.
  grep -qE '^[[:space:]]*- \[ \] 1\.2 - Implement the emitter' "$STORY/tasks.md"
}

@test "resolves a bare story number from the project root" {
  run_close 012 1.2
  [ "$status" -eq 0 ]
  grep -qE '^[[:space:]]*- \[x\] 1\.2 - Implement the emitter' "$STORY/tasks.md"
}

@test "tilde-marks with each of the four qualifiers, same line" {
  local q
  for q in "deferred: needs the live account" \
           "waived: tool absent" \
           "n-a: covered by construction" \
           "superseded-by: 011"; do
    write_story_fixture
    run_close .epic/stories/012-widget 1.1 --tilde "$q"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.box == "~"'
    echo "$output" | jq -e --arg q "${q%%:*}" '.qualifier == $q'
    grep -qF -- "- [~] 1.1 - Implement the parser (${q%%:*}:" "$STORY/tasks.md"
  done
}

@test "refuses an unknown box and writes nothing" {
  snapshot "$STORY/tasks.md"
  run_close .epic/stories/012-widget 9.9
  [ "$status" -eq 1 ]
  assert_unchanged "$STORY/tasks.md"
}

@test "refuses a box already [x], naming it" {
  snapshot "$STORY/tasks.md"
  run_close .epic/stories/012-widget 2.1
  [ "$status" -eq 1 ]
  grep -qF '2.1' <<< "$stderr"
  assert_unchanged "$STORY/tasks.md"
}

@test "refuses a box already [~]" {
  snapshot "$STORY/tasks.md"
  run_close .epic/stories/012-widget 3
  [ "$status" -eq 1 ]
  assert_unchanged "$STORY/tasks.md"
}

@test "refuses a qualifier outside the four-form grammar" {
  snapshot "$STORY/tasks.md"
  run_close .epic/stories/012-widget 1.1 --tilde "blocked: waiting on review"
  [ "$status" -eq 1 ]
  assert_unchanged "$STORY/tasks.md"
}

@test "marks a group box by bare N without touching N.N" {
  run_close .epic/stories/012-widget 4
  [ "$status" -eq 0 ]
  grep -qE '^- \[x\] 4 - Wrap-up' "$STORY/tasks.md"
  # 4.1 keeps exactly its one pre-existing [x]; group 1 stays open.
  [ "$(grep -cE '^[[:space:]]*- \[x\] 4\.1 ' "$STORY/tasks.md")" -eq 1 ]
  grep -qE '^- \[ \] 1 - Build the widget' "$STORY/tasks.md"
}

@test "marks a Quality Gate box by gate: text-prefix" {
  run_close .epic/stories/012-widget "gate:All task validations"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.box == "x"'
  grep -qE '^- \[x\] All task validations pass' "$STORY/tasks.md"
}

@test "CRLF fixture round-trips byte-identical outside the marked line" {
  sed -i 's/$/\r/' "$STORY/tasks.md"
  TOTAL_LINES=$(wc -l < "$STORY/tasks.md")
  snapshot "$STORY/tasks.md"
  run_close .epic/stories/012-widget 1.1
  [ "$status" -eq 0 ]
  # Every line still ends CRLF — the marked one included.
  [ "$(grep -c $'\r$' "$STORY/tasks.md")" -eq "$TOTAL_LINES" ]
  grep -qE $'^[[:space:]]*- \[x\] 1\.1 - Implement the parser\r$' "$STORY/tasks.md"
  # Exactly one line changed against the pristine copy.
  [ "$(diff "$WORK/snapshot.md" "$STORY/tasks.md" | grep -c '^<')" -eq 1 ]
}

# =====================================================================
# Group-header auto-close
# =====================================================================
# A close that leaves a task group with no open children closes the parent
# group header in the SAME atomic write — validate-story.sh errors on both
# inconsistent pairs ([x] header over an open child, [ ] header over zero
# open children), and this script is the single writer, so it owns the pair.

# The base fixture deliberately carries one pre-existing inconsistent pair
# (group 4: [ ] header over zero open children) for the bare-N marking case.
# Repair it first so the diff-count assertion below measures ONLY the pair
# this close writes.
close_group4_header() {
  sed -i 's/^- \[ \] 4 - Wrap-up/- [x] 4 - Wrap-up/' "$STORY/tasks.md"
}

@test "closing the last open child closes the group header in the same write" {
  close_group4_header
  sed -i 's/^  - \[ \] 1\.1 - Implement the parser/  - [x] 1.1 - Implement the parser/' "$STORY/tasks.md"
  snapshot "$STORY/tasks.md"
  run_close .epic/stories/012-widget 1.2
  [ "$status" -eq 0 ]
  grep -qE '^[[:space:]]*- \[x\] 1\.2 - Implement the emitter' "$STORY/tasks.md"
  grep -qE '^- \[x\] 1 - Build the widget' "$STORY/tasks.md"
  # One invocation wrote the pair: exactly two lines differ from the snapshot.
  [ "$(diff "$WORK/snapshot.md" "$STORY/tasks.md" | grep -c '^<')" -eq 2 ]
}

@test "a close leaving an open sibling leaves the group header open" {
  run_close .epic/stories/012-widget 1.1
  [ "$status" -eq 0 ]
  grep -qE '^[[:space:]]*- \[x\] 1\.1 - Implement the parser' "$STORY/tasks.md"
  grep -qE '^[[:space:]]*- \[ \] 1\.2 - Implement the emitter' "$STORY/tasks.md"
  grep -qE '^- \[ \] 1 - Build the widget' "$STORY/tasks.md"
}

@test "children closed via terminal [~] close their group header too" {
  close_group4_header
  sed -i 's/^  - \[ \] 1\.1 - Implement the parser/  - [~] 1.1 - Implement the parser (waived: tool absent)/' "$STORY/tasks.md"
  run_close .epic/stories/012-widget 1.2 --tilde "n-a: covered by construction"
  [ "$status" -eq 0 ]
  # No open child remains: the header must not stay [ ]. Whichever closed
  # mark the writer chooses, the pair is consistent after one invocation.
  grep -qE '^- \[[x~]\] 1 - Build the widget' "$STORY/tasks.md"
}
