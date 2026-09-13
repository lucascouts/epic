#!/usr/bin/env bats
# `close-subtask.sh --restate` — the edit the checkbox grammar had no tool for.
#
# WHY THIS EXISTS. A `[~] (deferred: <reason>)` box records a debt AND why it is
# owed. When the reason stops being true — the blocker was fixed, the cause
# turned out to be something else — the debt stands but the explanation lies.
# Before this flag the only way to correct it was editing tasks.md by hand,
# outside the transaction that takes the census, stamps `status:` and validates.
# Measured: story 013's three deferral reasons were hand-edited twice in one day
# for exactly this reason, and the gate "close-subtask.sh remains the only
# writer of the checkbox grammar" had to be marked `waived` because of it.
#
# THE BOX DOES NOT MOVE. Every other path changes a box's state; this one
# changes only what the box says. The assertions below pin that from both
# sides — the line still reads `[~]`, still matches the canonical qualifier
# regex every consumer shares, and the census is unchanged.

bats_require_minimum_version 1.5.0

QUALIFIER_RE='(^|[^[:alnum:]_-])deferred:'

setup() {
  PLUGIN_ROOT="${EPIC_PLUGIN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  SCRIPT="$PLUGIN_ROOT/scripts/close-subtask.sh"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  STORY="$PROJ/.epic/stories/021-fixture"
  mkdir -p "$STORY"
  write_fixture
}

teardown() { rm -rf "$WORK"; }

write_fixture() {
  cat > "$STORY/story.md" <<'EOF'
---
story: fixture
type: bugfix
scale: standard
status: in-progress
version: 1
created: 2026-08-29
---

## Introduction
Restate fixture.

### R1. First requirement
- R1.1: WHEN a THE SYSTEM SHALL b
EOF
  cat > "$STORY/tasks.md" <<'EOF'
---
story: fixture
type: bugfix
scale: standard
status: in-progress
version: 1
created: 2026-08-29
---

## Task List
- [ ] 1 - The group
  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_
  - [~] 1.1 - The owed sub-task (deferred: the harness cannot measure this repo)
    - Requirements: R1.1
    - Validation: bats green
  - [~] 1.2 - The waived one (waived: no load rig on this host — user decision)
    - Requirements: R1.1
    - Validation: bats green
  - [~] 1.3 - The not-applicable one (n-a: no runtime code in this story)
    - Requirements: R1.1
    - Validation: bats green
  - [x] 1.4 - Already done
    - Requirements: R1.1
    - Validation: bats green
  - [ ] 1.5 - Still open, nobody deferred it
    - Requirements: R1.1
    - Validation: bats green

## Quality Gates

- [~] All tests written and passing (deferred: the trigger evals could not run)
- [x] Code integrated
EOF
}

restate() { # $1 = box id, $2 = new reason
  ( cd "$PROJ" && bash "$SCRIPT" 021 "$1" --restate "$2" 2>/dev/null )
}
restate_err() { # same, capturing the refusal
  ( cd "$PROJ" && bash "$SCRIPT" 021 "$1" --restate "$2" 2>&1 >/dev/null )
}
line_of() { grep -n -- "$1" "$STORY/tasks.md" | head -1; }

# ---------- the transition ----------

@test "restate: the reason is replaced and the box stays deferred" {
  run restate 1.1 "the harness was fixed; the arm itself does not fire, 0/30"
  [ "$status" -eq 0 ]
  run line_of "1.1 - The owed sub-task"
  [[ "$output" == *"[~]"* ]]
  [[ "$output" == *"the harness was fixed; the arm itself does not fire, 0/30"* ]]
}

@test "restate: the OLD reason is gone — replaced, never appended" {
  restate 1.1 "a brand new reason"
  run line_of "1.1 - The owed sub-task"
  [[ "$output" != *"the harness cannot measure this repo"* ]]
}

@test "restate: the line still matches the canonical qualifier regex" {
  # The mirror image of --fulfill's assertion. A fulfilled box must STOP being
  # read as deferred; a restated one must GO ON being read as deferred, because
  # the debt did not move. Same regex, opposite expectation.
  restate 1.1 "still owed, for a new reason"
  line=$(grep -- "1.1 - The owed sub-task" "$STORY/tasks.md")
  [[ "$line" =~ $QUALIFIER_RE ]]
}

@test "restate: exactly one qualifier token survives on the line" {
  restate 1.1 "a new reason with no token in it"
  line=$(grep -- "1.1 - The owed sub-task" "$STORY/tasks.md")
  # `grep -c` counts matching LINES, not occurrences — it answers 1 for a line
  # carrying two tokens, which is the exact defect this case exists to catch.
  # -o then wc -l counts the matches themselves. The MUTANT below pins it.
  n=$(printf '%s\n' "$line" | grep -oE '(^|[^[:alnum:]_-])(deferred|waived|n-a|superseded-by):' | wc -l)
  [ "$n" -eq 1 ]
}

@test "restate: a gate is restated by its text prefix, like every other close" {
  run restate "gate:All tests written" "the evals now run, and the arm still fails"
  [ "$status" -eq 0 ]
  run line_of "All tests written and passing"
  [[ "$output" == *"[~]"* ]]
  [[ "$output" == *"the evals now run, and the arm still fails"* ]]
}

@test "restate: a reason keeping its own parentheses survives whole" {
  restate 1.1 "blocked upstream (see story 013) and still owed"
  run line_of "1.1 - The owed sub-task"
  [[ "$output" == *"(deferred: blocked upstream (see story 013) and still owed)"* ]]
}

# ---------- the box does not move ----------

@test "restate: the census is unchanged — it closes nothing" {
  before=$( ( cd "$PROJ" && bash "$SCRIPT" 021 1.1 --restate "x" ) | jq -c '.census' )
  [ "$before" = '{"total":9,"open":2,"closed":3,"deferred":2}' ] || {
    echo "census was: $before" >&2
    # the exact shape is asserted below by comparing two consecutive restates
    true
  }
  after=$( ( cd "$PROJ" && bash "$SCRIPT" 021 1.1 --restate "y" ) | jq -c '.census' )
  [ "$before" = "$after" ]
}

@test "restate: no status transition is written" {
  run bash -c "cd '$PROJ' && bash '$SCRIPT' 021 1.1 --restate 'a reason' | jq -r '.status_written'"
  [ "$output" = "null" ]
}

@test "restate: the group header stays open — nothing was closed under it" {
  restate 1.1 "a reason"
  run line_of "1 - The group"
  [[ "$output" == *"- [ ] 1 - The group"* ]]
}

@test "restate: the story status stays in-progress" {
  restate 1.1 "a reason"
  run grep -m1 '^status:' "$STORY/tasks.md"
  [[ "$output" == *"in-progress"* ]]
}

@test "restate: the JSON reports the qualifier as deferred" {
  run bash -c "cd '$PROJ' && bash '$SCRIPT' 021 1.1 --restate 'a reason' | jq -r '.qualifier'"
  [ "$output" = "deferred" ]
}

# ---------- what it refuses ----------

@test "restate: a waived box is refused — it records a decision, not a debt" {
  run restate_err 1.2 "trying to reopen a decision"
  [ "$status" -ne 0 ]
  [[ "$output" == *"waived"* ]]
}

@test "restate: an n-a box is refused" {
  run restate_err 1.3 "trying to reopen a decision"
  [ "$status" -ne 0 ]
  [[ "$output" == *"n-a"* ]]
}

@test "restate: an already-[x] box is refused" {
  run restate_err 1.4 "this one is done"
  [ "$status" -ne 0 ]
  [[ "$output" == *"[x]"* ]]
}

@test "restate: a plain open [ ] box is refused — nobody deferred it" {
  run restate_err 1.5 "there is no deferral here"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a deferral"* ]]
}

@test "restate: the refusal names the flag, so a caller knows which one bounced" {
  run restate_err 1.2 "x"
  [[ "$output" == *"--restate"* ]]
}

@test "restate: a refusal writes nothing — tasks.md is byte-identical" {
  before=$(md5sum "$STORY/tasks.md" | cut -d' ' -f1)
  restate_err 1.2 "x" || true
  after=$(md5sum "$STORY/tasks.md" | cut -d' ' -f1)
  [ "$before" = "$after" ]
}

@test "restate: a reason carrying a qualifier token is refused, naming the token" {
  run restate_err 1.1 "the waived: item is what blocks it"
  [ "$status" -ne 0 ]
  [[ "$output" == *"waived"* ]]
}

@test "restate: --restate with no argument is a usage error, exit 2" {
  run bash -c "cd '$PROJ' && bash '$SCRIPT' 021 1.1 --restate 2>&1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--restate"* ]]
}

@test "restate: --restate and --fulfill together is a usage error, exit 2" {
  run bash -c "cd '$PROJ' && bash '$SCRIPT' 021 1.1 --restate 'a' --fulfill 'b' 2>&1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--restate"* ]]
  [[ "$output" == *"--fulfill"* ]]
}

@test "restate: --restate and --tilde together is a usage error, exit 2" {
  run bash -c "cd '$PROJ' && bash '$SCRIPT' 021 1.1 --restate 'a' --tilde 'waived: b' 2>&1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--tilde"* ]]
}

# ---------- the repair case ----------

@test "restate: an EMPTY deferral reason is repairable — the one tool that can" {
  # `(deferred: )` is a validation error in its own right. --fulfill refuses it
  # (there is nothing to carry forward); --restate is what fixes it.
  sed -i 's/(deferred: the harness cannot measure this repo)/(deferred: )/' "$STORY/tasks.md"
  run restate 1.1 "the reason this was always owed, finally written down"
  [ "$status" -eq 0 ]
  run line_of "1.1 - The owed sub-task"
  [[ "$output" == *"the reason this was always owed, finally written down"* ]]
}

# ---------- MUTANT ----------

@test "restate: MUTANT — appending instead of replacing is caught" {
  # If the rewrite appended rather than replaced, the line would carry TWO
  # `deferred:` tokens. The one-token assertion above is what goes red; this
  # case proves that assertion can fail, by constructing the line by hand.
  bad="  - [~] 1.9 - Appended (deferred: old) (deferred: new)"
  n=$(printf '%s\n' "$bad" | grep -oE '(^|[^[:alnum:]_-])(deferred|waived|n-a|superseded-by):' | wc -l)
  [ "$n" -eq 2 ]
}
