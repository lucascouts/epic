#!/usr/bin/env bats
# Story 007, Task 2.2 — spike Verdict contract in scripts/validate-story.sh.
# Contract (R1.1 shape, R1.2–R1.4):
#   - A spike is tasks-only and MUST carry a `## Verdict` section with a valid
#     `status:` line (open | promote | wont-do); missing Verdict is an ERROR.
#   - `status: promote` without a `promoted-to:` reference is an ERROR.
#   - Any `Requirements:` field or R-number token in a spike tasks.md is an
#     ERROR — spikes have no requirements chain.
# The conforming-fixture test also asserts the spike template shape from
# references/tasks.md (Task 2.1) validates clean, and that `spike` is an
# accepted member of the scale enum (complementing tests/scale-validation.bats).

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/story"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

# A spike tasks.md per the sanctioned template: tasks-only, Verdict section.
# $1 = Verdict block content (lines after "## Verdict").
write_spike() {
  cat > "$STORY/tasks.md" <<EOF
---
story: probe-cache-strategy
type: feature
scale: spike
version: 1
created: 2026-08-02
---

## Overview
Probe: is the cache layer worth it?

## Task List
- [ ] 1 - Benchmark cold vs warm path
  - Validation: \`./bench.sh\`

## Verdict
$1
EOF
}

@test "conforming open spike passes validation" {
  write_spike '- status: open
- conclusion: pending'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "pass"'
}

@test "spike without a Verdict section is an error (R1.2)" {
  cat > "$STORY/tasks.md" <<'EOF'
---
story: probe-cache-strategy
type: feature
scale: spike
version: 1
created: 2026-08-02
---

## Task List
- [ ] 1 - Benchmark cold vs warm path
  - Validation: `./bench.sh`
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e . > /dev/null
  echo "$output" | jq -r '.error_details[]' | grep -qi 'verdict'
}

@test "spike promote without promoted-to is an error (R1.3)" {
  write_spike '- status: promote
- conclusion: cache pays off, build the real story'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -r '.error_details[]' | grep -qi 'promoted-to'
}

@test "spike promote with promoted-to recorded passes" {
  write_spike '- status: promote
- conclusion: cache pays off, build the real story
- promoted-to: 012'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "pass"'
}

@test "spike wont-do verdict passes" {
  write_spike '- status: wont-do
- conclusion: latency win too small to justify the layer'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "pass"'
}

@test "Requirements field in a spike tasks.md is an error (R1.4)" {
  cat > "$STORY/tasks.md" <<'EOF'
---
story: probe-cache-strategy
type: feature
scale: spike
version: 1
created: 2026-08-02
---

## Task List
- [ ] 1 - Benchmark cold vs warm path
  - Requirements: R1.1
  - Validation: `./bench.sh`

## Verdict
- status: open
- conclusion: pending
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -r '.error_details[]' | grep -qi 'no requirements chain'
}

@test "bare R-number token in a spike tasks.md is an error (R1.4)" {
  write_spike '- status: open
- conclusion: pending, see R2.1 upstream'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -r '.error_details[]' | grep -qi 'no requirements chain'
}

# --- Appended at story 007, sub-task 5.3 -------------------------------------
# THE SECOND HALF OF R1.2 HAD NEVER BEEN EXECUTED. Task 2.2 registered a
# deviation: "a spike concludes through its Verdict" is enforced by TWO errors,
# not one — an absent or unreadable Verdict, and a Verdict whose `status:` is
# present but is not a member of the enum — and the deviation record states
# "R1.2 is satisfied by both arms". Every case above exercises the first arm
# (the fixture with no `## Verdict` section at all) and none exercises the
# second, so deleting the second arm outright left the whole suite green while
# R1.2 was only half met.
#
# The two arms are ALSO the pair most easily confused, because they are the two
# that talk about the same section: the absent-Verdict case above asserts
# `grep -qi verdict`, and that pattern matches BOTH messages. So a case for the
# second arm has to assert its own sentence and the absence of the other's, or
# it proves nothing the first case did not already prove.
#
# Characterization of behaviour that already shipped, so Red came from a
# mutation of scripts/validate-story.sh rather than from absent behaviour —
# recorded in the story 007 red evidence as `red_via: mutation`.

@test "spike Verdict with a status outside the enum errors, naming the value and the enum (R1.2)" {
  # `promoted` rather than an obviously foreign word, ON PURPOSE: it is a
  # near-miss of a real member, so this case pins the ANCHORS on the membership
  # test and not merely "an unknown word errors". Drop the ^…$ from
  # `=~ ^(open|promote|wont-do)$` — the kind of edit a refactor makes without
  # thinking — and `promoted` starts matching `promote`, the error vanishes, and
  # every case above stays green because each of them uses an exact member.
  # It is also the realistic typo: past tense of the verdict the author just
  # reached.
  # Delete this case and the arm is unexecuted again — a spike could then
  # conclude with any word at all and validation would pass it, and because the
  # `promoted-to:` requirement keys on the exact string `promote`, the promote
  # flow would silently never ask for its target either.
  write_spike '- status: promoted
- conclusion: cache pays off, build the real story'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e . > /dev/null
  # THE MESSAGE, NOT MERELY THE FAILURE. Both arms name the Verdict and both end
  # in the same enum text, so the `grep -qi verdict` used by the absent-Verdict
  # case cannot tell them apart. These three can: the arm's own sentence, the
  # offending value quoted back to the author, and the enum they must choose
  # from — the two things an author needs to fix it in one edit.
  echo "$output" | jq -r '.error_details[]' | grep -q "is not a spike verdict"
  echo "$output" | jq -r '.error_details[]' | grep -q "found 'promoted'"
  echo "$output" | jq -r '.error_details[]' | grep -q "open, promote, wont-do"
  # And it is NOT the other arm. This fixture HAS a `## Verdict` carrying a
  # `status:` line; reporting it as missing would send the author off to write a
  # section that is already sitting in the file.
  ! echo "$output" | jq -r '.error_details[]' | grep -q "has no readable"
  # Exactly one error, which is the if/elif made observable: the two arms are
  # mutually exclusive by construction and must never both fire on one file.
  # Safe to assert as a count because the conforming case at the top of this file
  # proves the same fixture validates with zero errors when the status is valid.
  [ "$(echo "$output" | jq -r '.errors')" -eq 1 ]
}

# --- Appended at story 007, sub-task 5.4 -------------------------------------
# THE CONTRADICTION TASK 2.2 REGISTERED AND LEFT UNOWNED. The requirements-
# coverage check is gated on `HAS_STORY`, not on the declared scale
# (scripts/validate-story.sh, "Check Requirements field"). So a malformed spike
# that ALSO carries a story.md reaches that check and is told to add
# `Requirements:` fields — while the spike R-chain check three sections below
# makes a `Requirements:` field an ERROR (R1.4), and references/tasks.md tells a
# spike author to write no R-number anywhere in the file. Obeying either
# instruction breaks the other, and the author has no way to tell which one is
# the bug.
#
# The fix is a SUPPRESSION, not a rescue: the fixture below IS malformed, and
# must go on being reported as such. The R2.3 scale-mismatch warning is the
# honest report — it names both sides and lets the author decide which is wrong
# (drop story.md, or declare the scale the files describe). What must stop is
# the second, contradictory instruction stacked on top of it.
#
# WHY THE FIXTURE IS THE CONFORMING SPIKE PLUS ONE FILE: the tasks.md is
# byte-identical to the one the first case in this file validates with zero
# errors. So the coverage error here is attributable to the presence of
# story.md and to nothing else in the spike — no second explanation is available.
#
# WHY NO EXIT-STATUS ASSERTION: this fixture is malformed by construction and
# will legitimately keep collecting diagnostics as the validator grows. Pinning
# `$status` would pin the SUM of everything the validator says about a broken
# story, and would redden on any unrelated future check. The contract is about
# two specific messages, so exactly those two are asserted.

# Assert the errors do NOT contain a pattern. (Bare `! grep` is exempt from
# bats' errexit trap and would never fail the test.) `// []` keeps the
# extraction total: a run with zero errors has nothing to grep, which is a pass
# here, not a jq failure.
refute_error() {
  local errs
  errs=$(jq -r '.error_details // [] | .[]' <<< "$output")
  if grep -q "$1" <<< "$errs"; then
    echo "did not expect error matching: $1"
    echo "errors were:"
    echo "$errs"
    return 1
  fi
}

@test "a spike carrying a story.md warns about the scale mismatch and is not told to add 'Requirements:' fields (R1.4)" {
  write_spike '- status: open
- conclusion: pending'
  # The leftover artifact — an earlier attempt at a full story, never removed.
  # Deliberately carries no requirement numbering of its own: the defect under
  # test is the mere PRESENCE of story.md, and a story.md with R-numbers would
  # drag the cross-reference checks into the picture and give the coverage
  # error a second possible explanation.
  cat > "$STORY/story.md" <<'STORY_MD'
---
story: probe-cache-strategy
type: feature
version: 1
created: 2026-08-02
---

## Overview
Left over from an earlier attempt at a full story.
STORY_MD
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  echo "$output" | jq -e . > /dev/null
  # The real defect stays reported, and keeps naming BOTH sides — the
  # declaration on one side, the file that contradicts it on the other. Two
  # substrings rather than the whole sentence: the wording around them is free
  # to change, the two facts an author needs are not.
  echo "$output" | jq -r '.warning_details[]' | grep -q "declared scale 'spike'"
  echo "$output" | jq -r '.warning_details[]' | grep -q "story.md is present"
  # And the contradictory advice is gone. Matched on the demand itself rather
  # than on the task count, so the case does not re-redden if the fixture ever
  # grows a second task.
  refute_error "no 'Requirements:' fields"
}
