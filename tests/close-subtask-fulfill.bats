#!/usr/bin/env bats
# Unit tests for `close-subtask.sh --fulfill` (story 021 — close-the-eval-deferrals).
# Authored by the Test Advisor BEFORE implementation (TDD Red phase).
#
# Contract under test (design.md, Fix Approach 4; R4.1-R4.4):
#   close-subtask.sh <NNN|dir> <N.N|N|gate:prefix> --fulfill "<evidence>"
#   - a `[~] (deferred: …)` box becomes `[x]`, carrying BOTH the original
#     deferral reason and the evidence that discharged it
#   - a terminal qualifier (waived:, n-a:, superseded-by:) or an already-`[x]`
#     box is a REFUSAL naming the state found — those record a decision taken,
#     not an outstanding debt
#   - a preserved reason that itself carries a qualifier token is a refusal
#     naming the token (the stance the stowaway guard already takes for --tilde)
#   - the census and the `status:` stamp run in the same invocation, as they do
#     for every other close
#
# THE LINE SHAPE IS FORCED BY A MEASUREMENT, NOT BY TASTE. Seven scripts read
# the grammar in code, all through:
#     (^|[^[:alnum:]_-])deferred:
# The obvious spelling `(was deferred: …; fulfilled: …)` MATCHES it, so those
# seven would score a closed box as deferred and the story would never reach
# `done`. The case below asserts the rewritten line does NOT match that regex,
# and it is the case that goes red against the obvious spelling.
#
# EPIC_PLUGIN_ROOT overrides root resolution so this draft copy can run before
# materialization into tests/.

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
Fulfill fixture.

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

## Quality Gates

- [~] All tests written and passing (deferred: the trigger evals could not run)
- [x] Code integrated
EOF
}

fulfill() { # $1 = box id, $2 = evidence
  ( cd "$PROJ" && bash "$SCRIPT" 021 "$1" --fulfill "$2" 2>/dev/null )
}
line_of() { grep -n -- "$1" "$STORY/tasks.md" | head -1; }

# ---------- 4.1: the transition ----------

@test "4.1: a deferred sub-task becomes [x] and keeps both halves of its story" {
  run fulfill 1.1 "trigger eval passed 5/5 after the harness repair"
  [ "$status" -eq 0 ]
  run line_of "1.1 - The owed sub-task"
  [[ "$output" == *"[x]"* ]]
  [[ "$output" == *"fulfilled: trigger eval passed 5/5"* ]]
  [[ "$output" == *"the harness cannot measure this repo"* ]]
}

# THE CASE THE LINE SHAPE EXISTS FOR. Red against `(was deferred: …)`.
@test "4.1: the rewritten line does NOT match the canonical qualifier regex" {
  fulfill 1.1 "measured" || true
  run bash -c "grep -n -- '1.1 - The owed sub-task' '$STORY/tasks.md' | grep -cE '$QUALIFIER_RE' || true"
  [ "$output" = "0" ]
}

@test "4.1: a gate is fulfilled by its text prefix, like every other close" {
  run fulfill "gate:All tests written" "full suite green at 498 cases"
  [ "$status" -eq 0 ]
  run line_of "All tests written"
  [[ "$output" == *"[x]"* ]]
  [[ "$output" == *"full suite green"* ]]
}

# ---------- 4.3: the refusals ----------

@test "4.1: a waived box is refused — it records a decision, not a debt" {
  run fulfill 1.2 "someone did the load test after all"
  [ "$status" -eq 1 ]
  run line_of "1.2 - The waived one"
  [[ "$output" == *"[~]"* ]]
  [[ "$output" == *"waived:"* ]]
}

@test "4.1: an n-a box is refused" {
  run fulfill 1.3 "turns out there was runtime code"
  [ "$status" -eq 1 ]
  run line_of "1.3 - The not-applicable one"
  [[ "$output" == *"[~]"* ]]
}

@test "4.1: an already-[x] box is refused" {
  run fulfill 1.4 "doing it twice"
  [ "$status" -eq 1 ]
}

@test "4.1: the refusal names the state it found, so a caller knows why" {
  run bash -c "cd '$PROJ' && bash '$SCRIPT' 021 1.2 --fulfill 'x' 2>&1 >/dev/null"
  [[ "$output" == *"waived"* ]]
}

@test "4.1: a refusal writes nothing — tasks.md is byte-identical" {
  local before; before=$(md5sum "$STORY/tasks.md" | cut -d' ' -f1)
  # The refusal must be a RECOGNISED one — exit 1, the world is wrong — not an
  # unparsed flag (exit 2). A script that does not know --fulfill also "writes
  # nothing", and this case passed for that reason until the status clause
  # was added.
  run bash -c "cd '$PROJ' && bash '$SCRIPT' 021 1.2 --fulfill 'x' >/dev/null 2>&1"
  [ "$status" -eq 1 ]
  local after; after=$(md5sum "$STORY/tasks.md" | cut -d' ' -f1)
  [ "$before" = "$after" ]
}

@test "4.1: --fulfill with no argument is a usage error naming the argument, exit 2" {
  run bash -c "cd '$PROJ' && bash '$SCRIPT' 021 1.1 --fulfill 2>&1 >/dev/null"
  [ "$status" -eq 2 ]
  # Distinguish "missing argument" from "unknown flag": both are exit 2, and only
  # the first means the flag exists. The message must ask for the evidence.
  [[ "$output" == *"--fulfill"* ]]
  [[ "$output" == *"requires"* || "$output" == *"evidence"* ]]
}

@test "4.1: a preserved reason carrying a qualifier token is refused, naming the token" {
  sed -i 's|(deferred: the harness cannot measure this repo)|(deferred: blocked until waived: someone signs off)|' "$STORY/tasks.md"
  run bash -c "cd '$PROJ' && bash '$SCRIPT' 021 1.1 --fulfill 'done' 2>&1 >/dev/null"
  [ "$status" -eq 1 ]
  [[ "$output" == *"waived"* ]]
}

# ---------- 4.4: the census ----------

@test "4.1: fulfilling the last deferral lets the census write status: done" {
  # close the two open-ish states the fixture still has, then fulfil both
  # deferrals; nothing is left open and nothing is left owed.
  ( cd "$PROJ" && bash "$SCRIPT" 021 1.2 --tilde "waived: keep" >/dev/null 2>&1 ) || true
  fulfill 1.1 "measured" >/dev/null 2>&1 || true
  fulfill "gate:All tests written" "measured" >/dev/null 2>&1 || true
  run grep -c '^status: done' "$STORY/tasks.md"
  [ "$output" = "1" ]
}

@test "4.1: the JSON on stdout reports the transition, as every other path does" {
  run bash -c "cd '$PROJ' && bash '$SCRIPT' 021 1.1 --fulfill 'measured' 2>/dev/null | jq -r '.box'"
  [ "$status" -eq 0 ]
  [ "$output" = "x" ]
}

# ---------- 5.1: against a real deferred story ----------

@test "5.1: a real deferred story reaches done only when no deferral remains" {
  # Two deferrals, one gate and one sub-task. Fulfilling ONE must not produce
  # `done` — the census reads every box, not the one just written.
  run bash -c "cd '$PROJ' && bash '$SCRIPT' 021 1.1 --fulfill 'measured' >/dev/null 2>&1"
  [ "$status" -eq 0 ]
  # Prove the write LANDED before asserting what the census did with it: a
  # script that did nothing at all also leaves status un-done, and this case
  # passed for that reason until these two clauses were added.
  run bash -c "grep -c -- '- \[x\] 1.1' '$STORY/tasks.md'"
  [ "$output" = "1" ]
  run bash -c "grep -c '^status: done' '$STORY/tasks.md' || true"
  [ "$output" = "0" ]
}

# ---------- 4.1: added during execution — guards nothing above could fail ----
# Each of these was proven capable of failing by MUTATING scripts/close-subtask.sh
# and observing the red, never by argument. The mutation is named in the comment
# over each case.

# The story's Tests field lists four refusal states — waived:, n-a:,
# superseded-by: and [x] — and the suite above pins three of them. This is the
# fourth. Failability: dropping `superseded-by` from TILDE_TERMINAL_RE makes the
# box read as an unqualified [~]; the refusal then never says the word.
@test "4.1: a superseded-by box is refused, naming the token" {
  sed -i 's|(n-a: no runtime code in this story)|(superseded-by: 022)|' "$STORY/tasks.md"
  run bash -c "cd '$PROJ' && bash '$SCRIPT' 021 1.3 --fulfill 'the scope came back' 2>&1 >/dev/null"
  [ "$status" -eq 1 ]
  [[ "$output" == *"superseded-by"* ]]
  run line_of "1.3 - The not-applicable one"
  [[ "$output" == *"[~]"* ]]
}

# THE OTHER HALF OF THE LINE. The suite pins the carried-forward reason; the
# EVIDENCE lands on the same line and can smuggle the same token — and a
# `deferred:` in it would have every reader score this CLOSED box as an
# outstanding debt, which is the one failure the line shape exists to prevent.
# Failability: deleting the evidence stowaway guard makes this exit 0 and writes
# `- [x] 1.1 - … (fulfilled: the deferred: rig arrived; …)`, which the canonical
# regex matches.
@test "4.1: evidence carrying a qualifier token is refused, naming the token" {
  run bash -c "cd '$PROJ' && bash '$SCRIPT' 021 1.1 --fulfill 'the deferred: rig arrived' 2>&1 >/dev/null"
  [ "$status" -eq 1 ]
  [[ "$output" == *"deferred"* ]]
  run line_of "1.1 - The owed sub-task"
  [[ "$output" == *"[~]"* ]]
}

# Two contradictory writes for one box: --tilde closes it WITHOUT the work,
# --fulfill BECAUSE of it. Exit 2 and not 1, because no state of the world could
# make the pair coherent — the header's rule, 2 = fix the call, 1 = fix the
# world. Failability: removing the mutual-exclusion arm makes this exit 0.
@test "4.1: --tilde and --fulfill together is a usage error, exit 2" {
  run bash -c "cd '$PROJ' && bash '$SCRIPT' 021 1.1 --tilde 'waived: x' --fulfill 'y' 2>&1 >/dev/null"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--tilde"* ]]
  [[ "$output" == *"--fulfill"* ]]
}

# A REASON WITH PARENTHESES OF ITS OWN COMES BACK WHOLE. Two of the five real
# deferrals this story has to close (013's 3.2, 015's 4.1) carry a parenthesised
# aside and then keep going, so a cut at the first `)` would destroy the tail of
# a reason that `.epic/` — untracked here — does not hold anywhere else (R4.2).
# Failability: making the reason capture non-greedy (`[^)]*`) fails to match at
# all and the close is refused; cutting at the first `)` drops "and it is owed".
@test "4.1: a preserved reason keeps its own parentheses and everything after them" {
  sed -i 's|(deferred: the harness cannot measure this repo)|(deferred: blocked (see 013) and it is owed)|' "$STORY/tasks.md"
  run fulfill 1.1 "the rig landed"
  [ "$status" -eq 0 ]
  run line_of "1.1 - The owed sub-task"
  [[ "$output" == *"original deferral — blocked (see 013) and it is owed)"* ]]
  [[ "$output" == *"[x]"* ]]
}
