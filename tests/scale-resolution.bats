#!/usr/bin/env bats
# Story 008 — a leftover artifact must not overrule the declared scale.
# Authored Red-first by the Test Advisor from the EARS requirements plus the
# design contract. Target location after materialization: tests/scale-resolution.bats
#
# WHY A NEW FILE. Run mode materializes the staged tests by COPYING and skips
# any target that already exists, so a case appended to scale-validation.bats or
# to spike-validation.bats could never reach the tree. Those suites stay
# byte-untouched and are re-run as pure regression — the R2.2 legacy golden
# included.
#
# Contract under test:
#   R1.1  tasks.md wins when tasks.md and story.md both declare a valid scale
#   R1.2  a single declaring artifact resolves, whichever file carries it
#   R1.3  an out-of-enum value is an error per artifact and resolves to nothing
#   R2.1  two artifacts declaring different valid values is a WARNING naming
#         each pair and the resolved value
#   R2.2  full agreement is silent
#   R2.3  design.md is enum-checked like the other two
#   R2.4  design.md is compared, never resolved from
#   R3.1  a scale with no requirements chain is not told to add `Requirements:`
#   R3.2  ...and is not compared against one by --cross-ref, orphan and phantom
#         arms included
#   R3.3  no declared scale at all still carries a requirements chain (legacy)
#   R3.4  ...and cross-reference.sh reports the inapplicability and exits 0
#   R4.1  the spike Verdict contract survives a leftover story.md
#   R4.2  ...and so does the archive preflight, at BOTH its call sites
#
# TEST NAMES ARE PREFIXED WITH THE SUB-TASK NUMBER so Red/Green evidence can be
# produced per sub-task with `bats --filter '^1\.1:' tests/scale-resolution.bats`.
#
# ASSERTIONS ARE ON MESSAGE CONTENT, NEVER ON EXIT STATUS, wherever the fixture
# is malformed by construction — which is most of them. Pinning `$status` would
# pin the SUM of everything the validator says about a broken story and would
# redden on any unrelated future check. Where a whole sentence is quoted in
# design.md it is still matched by its stable substrings plus the value that
# matters, never verbatim end to end.
#
# Some cases below are GREEN PINS — behaviour that is already correct and that
# the change must not move (marked `PIN` in their comment). Red for this story
# is judged on the new-contract cases only.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  VALIDATE_SH="$PLUGIN_ROOT/scripts/validate-story.sh"
  ARCHIVE_SH="$PLUGIN_ROOT/scripts/archive-story.sh"
  XREF_SH="$PLUGIN_ROOT/scripts/cross-reference.sh"
  WORK=$(mktemp -d)
  STORY="$WORK/story"           # validator fixtures
  PROJ="$WORK/proj"             # archive fixtures need a .epic/ tree
  MANIFEST="$PROJ/.epic/archive/manifest.yaml"
  mkdir -p "$STORY" "$PROJ/.epic/stories"
  isolate_git_env
  cd "$PROJ"
}

teardown() {
  cd /
  chmod -R u+rwX "$WORK" 2> /dev/null || true
  rm -rf "$WORK"
}

# isolate_git_env — the four environment knobs that stop this machine's own git
# configuration from reaching the fixtures, copied from tests/epic-gitpolicy.bats.
# archive-story.sh asks git whether the story is tracked and picks `git mv` or
# `mv` from the answer; a global config (or an XDG ignore file) that says
# something about `.epic` would make that answer depend on whose laptop runs the
# suite. The directory is never created — git treats an absent HOME as empty.
isolate_git_env() {
  export HOME="$WORK/.fixture-home"
  export XDG_CONFIG_HOME="$WORK/.fixture-home/.config"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_TEMPLATE_DIR=
}

# --- Assertion helpers ------------------------------------------------------
# Every NEGATIVE assertion goes through a refute_* helper. A bare `! grep` is
# exempt from bats' errexit trap and would never fail the test — the whole point
# of most cases here is an absence, so the absence has to be checked by
# something that can actually fail. `// []` keeps the extraction total: a run
# with zero errors has nothing to grep, which is a pass, not a jq crash.

errors_of() { jq -r '.error_details // [] | .[]' <<< "$output"; }
warnings_of() { jq -r '.warning_details // [] | .[]' <<< "$output"; }

assert_error() {
  local errs
  errs=$(errors_of)
  if ! grep -q "$1" <<< "$errs"; then
    echo "expected an error matching: $1"
    echo "errors were:"
    echo "$errs"
    return 1
  fi
}

refute_error() {
  local errs
  errs=$(errors_of)
  if grep -q "$1" <<< "$errs"; then
    echo "did not expect an error matching: $1"
    echo "errors were:"
    echo "$errs"
    return 1
  fi
}

assert_warning() {
  local warns
  warns=$(warnings_of)
  if ! grep -q "$1" <<< "$warns"; then
    echo "expected a warning matching: $1"
    echo "warnings were:"
    echo "$warns"
    return 1
  fi
}

refute_warning() {
  local warns
  warns=$(warnings_of)
  if grep -q "$1" <<< "$warns"; then
    echo "did not expect a warning matching: $1"
    echo "warnings were:"
    echo "$warns"
    return 1
  fi
}

# --- Fixture builders -------------------------------------------------------
# One dialect, borrowed from tests/scale-validation.bats (write_story_md) and
# tests/spike-validation.bats (write_spike). The scale line is a parameter
# rather than a fixed field because "which artifact carries the line" IS the
# subject of this suite; passing "" leaves the artifact with no opinion.

# write_story_md <scale-line> — a minimal standard-shaped story.md carrying one
# requirement, so the R-chain checks have something to look at.
write_story_md() {
  local scale_line="$1"
  {
    echo '---'
    echo 'story: leftover-artifact'
    echo 'type: feature'
    if [ -n "$scale_line" ]; then echo "$scale_line"; fi
    echo 'version: 1'
    echo 'created: 2026-08-10'
    echo '---'
    echo
    echo '## Introduction'
    echo 'Left over from an earlier attempt at a full story.'
    echo
    echo '### R1. First requirement'
    echo
    echo '#### Acceptance Criteria'
    echo
    echo '- R1.1: WHEN x THE SYSTEM SHALL y.'
  } > "$STORY/story.md"
}

# write_design_md <scale-line> — design.md exists only to carry (or not carry) a
# `scale:`; nothing else in it is read.
write_design_md() {
  local scale_line="$1"
  {
    echo '---'
    echo 'story: leftover-artifact'
    if [ -n "$scale_line" ]; then echo "$scale_line"; fi
    echo 'version: 1'
    echo 'created: 2026-08-10'
    echo '---'
    echo
    echo '## Overview'
    echo 'Design fixture.'
  } > "$STORY/design.md"
}

# write_spike_tasks <scale-line> <verdict-block|""> — a spike-shaped tasks.md.
# An empty verdict block means NO `## Verdict` section at all, which is the
# reproduction's shape and the one defect the whole spike contract exists to
# catch.
write_spike_tasks() {
  local scale_line="$1" verdict="${2:-}"
  {
    echo '---'
    echo 'story: leftover-artifact'
    echo 'type: feature'
    if [ -n "$scale_line" ]; then echo "$scale_line"; fi
    echo 'version: 1'
    echo 'created: 2026-08-10'
    echo '---'
    echo
    echo '## Task List'
    echo '- [x] 1 - Run the probe'
    echo '  - Validation: `./probe.sh`'
    echo
    echo '## Quality Gates'
    echo '- Done'
    if [ -n "$verdict" ]; then
      echo
      echo '## Verdict'
      printf '%s\n' "$verdict"
    fi
  } > "$STORY/tasks.md"
}

# write_tasks_md <scale-line> <with-requirements: yes|no> — a lifecycle-shaped
# tasks.md. "no" is the shape the fast contract tells the author to write, and
# the shape the coverage gate currently reports as an error whatever the scale.
write_tasks_md() {
  local scale_line="$1" with_reqs="${2:-yes}"
  {
    echo '---'
    echo 'story: leftover-artifact'
    echo 'type: feature'
    if [ -n "$scale_line" ]; then echo "$scale_line"; fi
    echo 'version: 1'
    echo 'created: 2026-08-10'
    echo '---'
    echo
    echo '## Task List'
    echo '- [ ] 1 - Implement'
    if [ "$with_reqs" = yes ]; then echo '  - Requirements: R1.1'; fi
    echo '  - Validation: `echo ok`'
    echo
    echo '## Quality Gates'
    echo '- Done'
  } > "$STORY/tasks.md"
}

# =============================================================================
# 1.1 — resolution: tasks.md wins, every artifact is enum-checked, design.md is
#       compared but never resolved from (R1.1, R1.2, R1.3, R2.3, R2.4)
# =============================================================================

# The resolved scale is not printed anywhere, so every case below reads it
# through an OBSERVABLE: `scale: spike` is the one value with a contract
# attached, so "the Verdict error fired" means "spike was resolved" and nothing
# else — the guard on that block is satisfiable only by a declared spike.

@test "1.1: tasks.md wins over story.md when both declare a valid scale" {
  write_spike_tasks 'scale: spike' ''
  write_story_md 'scale: standard'
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  # Resolved spike => the spike contract was evaluated => its one defect (no
  # `## Verdict`) is reported. Under story.md-first the block is never entered.
  assert_error 'Verdict'
}

@test "1.1: the scale-vs-files warning attributes the declaration to tasks.md" {
  # DECLARED_SCALE_FILE is user-visible in the R2.3 mismatch sentence, and for a
  # story declaring in BOTH files the winner is the only honest thing to name
  # there. Two substrings, not the sentence: the wording around them is free.
  write_spike_tasks 'scale: spike' ''
  write_story_md 'scale: standard'
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  assert_warning "declared scale 'spike'"
  assert_warning 'in tasks.md'
}

@test "1.1: PIN a scale declared only in story.md still resolves" {
  # R1.2, the half that already works. tasks.md carries no opinion at all.
  write_spike_tasks '' ''
  write_story_md 'scale: spike'
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  assert_error 'Verdict'
}

@test "1.1: PIN a scale declared only in tasks.md still resolves" {
  write_spike_tasks 'scale: spike' ''
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  assert_error 'Verdict'
}

@test "1.1: PIN an invalid value in the losing artifact still errors and never occupies the slot" {
  # R1.3, and the property a rewrite that returns early on the first match
  # silently loses: `medium` must be REPORTED and must not become the resolved
  # scale, while tasks.md's `spike` still resolves. Both halves in one case
  # because either alone is satisfied by the wrong implementation.
  write_spike_tasks 'scale: spike' ''
  write_story_md 'scale: medium'
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  assert_error 'medium'
  assert_error 'Verdict'
}

@test "1.1: an invalid scale in design.md is an error naming the artifact, the value and the valid set" {
  # R2.3. design.md is the third artifact that may carry the field and the one
  # no script reads today, so `scale: medium` there is reported by nobody.
  write_tasks_md '' yes
  write_story_md 'scale: full'
  write_design_md 'scale: medium'
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  assert_error 'design.md'
  DETAIL=$(errors_of | grep 'design.md')
  echo "$DETAIL" | grep -q 'medium'
  # The full enum, so the author can self-correct without opening a reference.
  echo "$DETAIL" | grep -q 'fast'
  echo "$DETAIL" | grep -q 'standard'
  echo "$DETAIL" | grep -q 'full'
  echo "$DETAIL" | grep -q 'spike'
}

@test "1.1: PIN a valid scale in design.md does not resolve the declared scale" {
  # R2.4. design.md describes the SOLUTION; it does not declare the work's
  # shape. A rewrite that simply adds design.md to the resolution list resolves
  # `full` here and the spike contract disappears again — which is exactly the
  # defect this story is closing, re-entered through the other door.
  write_spike_tasks 'scale: spike' ''
  write_design_md 'scale: full'
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  assert_error 'Verdict'
}

# =============================================================================
# 1.2 — the divergence warning (R2.1, R2.2)
# =============================================================================

@test "1.2: two artifacts declaring different scales warn naming both pairs and the resolved value" {
  write_spike_tasks 'scale: spike' ''
  write_story_md 'scale: standard'
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  # The pairs, in the `file=value` shape the `status:` sibling already uses.
  assert_warning 'story.md=standard'
  assert_warning 'tasks.md=spike'
  # And the winner, which the `status:` sibling has no need to disclose and this
  # one does — naming the disagreement without naming the resolution tells the
  # author there is a problem and not which value is in force. Matched as
  # "some line says `resolved` and quotes `'spike'`" rather than as the whole
  # sentence, so the wording stays the implementer's.
  DIVERGENCE=$(warnings_of | grep 'tasks.md=spike')
  echo "$DIVERGENCE" | grep -qi 'resolved'
  echo "$DIVERGENCE" | grep -q "'spike'"
}

@test "1.2: PIN three artifacts declaring the same scale produce no divergence warning" {
  # R2.2. The shipped examples carry the same `scale:` in all three artifacts,
  # so a "warn whenever two artifacts declare" variant would fire on
  # assets/examples/full-feature.md — silence on agreement is the contract.
  write_tasks_md 'scale: full' yes
  write_story_md 'scale: full'
  write_design_md 'scale: full'
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  refute_warning "different 'scale' values"
}

@test "1.2: an invalid value produces its enum error and no divergence warning" {
  # The one deliberate divergence from the `status:` collector, which DOES pair
  # a value that failed its enum. An invalid scale already has its own error;
  # pairing it too would report one defect twice in two vocabularies, which is
  # the failure mode this story exists to stop.
  write_spike_tasks 'scale: spike' ''
  write_story_md 'scale: medium'
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  assert_error 'medium'
  refute_warning "different 'scale' values"
  refute_warning 'story.md=medium'
}

# =============================================================================
# 1.3 — the reproduction, end to end (R4.1)
# =============================================================================

@test "1.3: the reproduction reports the missing Verdict and not the coverage demand" {
  # story.md Reproduction Step 3, measured: `errors: 1`, the sole error being
  # `tasks.md has 1 tasks but no 'Requirements:' fields`, and no spike check run
  # at all. The movement must show in BOTH directions — the Verdict error now
  # present, the coverage demand now absent — because either one alone is
  # satisfied by the wrong implementation (suppressing the gate without fixing
  # resolution, or fixing resolution while the gate keeps firing).
  write_spike_tasks 'scale: spike' ''
  write_story_md 'scale: standard'
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  assert_error 'Verdict'
  refute_error "no 'Requirements:' fields"
}

@test "1.3: deleting the leftover scale line does not change what the spike is told" {
  # Reproduction Step 4: one line in an unrelated artifact decided whether the
  # contract existed. After the fix the two runs must agree, and the assertion
  # is the AGREEMENT — the same two facts before and after the line is removed.
  write_spike_tasks 'scale: spike' ''
  write_story_md 'scale: standard'
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  assert_error 'Verdict'
  refute_error "no 'Requirements:' fields"
  # The same leftover artifact, minus the single `scale:` line.
  write_story_md ''
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  assert_error 'Verdict'
  refute_error "no 'Requirements:' fields"
}

# =============================================================================
# 2.1 — the requirements-coverage gate reads the scale (R3.1, R3.3)
# =============================================================================

@test "2.1: a fast story with a leftover story.md is not told to add 'Requirements:' fields" {
  # R3.1. references/tasks.md tells a fast author to omit the field; the gate
  # reports its absence as an error the moment any story.md is on disk. The
  # story is still malformed (fast is tasks-only) and the R2.3 mismatch warning
  # still says so — what goes away is the second, contradictory instruction.
  write_tasks_md 'scale: fast' no
  write_story_md ''
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  refute_error "no 'Requirements:' fields"
  # The honest report survives: the declaration and the file that contradicts it.
  assert_warning "declared scale 'fast'"
}

@test "2.1: PIN a standard story omitting 'Requirements:' fields is still an error" {
  # The gate's real job, and the case a predicate written as a positive list
  # would keep by accident rather than by design.
  write_tasks_md 'scale: standard' no
  write_story_md 'scale: standard'
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  assert_error "no 'Requirements:' fields"
}

@test "2.1: PIN a story with no declared scale is still told to add them" {
  # R3.3, the legacy corpus: 340+ stories predate the field and must keep
  # carrying a requirements chain. A predicate written as `standard|full|"")`
  # makes this pass by accident and opts every future enum member into the
  # chain; written as the false set `fast|spike)` it passes on purpose.
  write_tasks_md '' no
  write_story_md ''
  run bash "$VALIDATE_SH" "$STORY"
  echo "$output" | jq -e . > /dev/null
  assert_error "no 'Requirements:' fields"
}

# =============================================================================
# 2.2 — the whole --cross-ref block, not one arm of it (R3.2)
# =============================================================================

# write_spike_tasks_with_r_tokens — the RICHER fixture the measured
# reproduction (Step 7) never reached. Step 7 produced the "no R-number
# references" warning, which is the block's `elif` arm; a spike whose tasks.md
# DOES carry R-tokens takes the other branch instead and gets one warning per
# orphan and one per phantom, each advising exactly what the spike's
# no-requirements-chain rule makes an error. Gating only the arm that was
# measured leaves the larger half of the defect in place.
write_spike_tasks_with_r_tokens() {
  {
    echo '---'
    echo 'story: leftover-artifact'
    echo 'type: feature'
    echo 'scale: spike'
    echo 'version: 1'
    echo 'created: 2026-08-10'
    echo '---'
    echo
    echo '## Task List'
    echo '- [ ] 1 - Probe the cache path (R1.1)'
    echo '  - Validation: `./probe.sh`'
    echo '- [ ] 2 - Probe the cold path (R9.9)'
    echo '  - Validation: `./probe.sh`'
    echo
    echo '## Verdict'
    echo '- status: open'
    echo '- conclusion: pending'
    echo
    echo '## Quality Gates'
    echo '- Done'
  } > "$STORY/tasks.md"
}

# write_story_md_two_reqs — story.md defining R1.1 and R1.2, so a tasks.md
# referencing only R1.1 leaves exactly one orphan.
write_story_md_two_reqs() {
  local scale_line="$1"
  {
    echo '---'
    echo 'story: leftover-artifact'
    echo 'type: feature'
    if [ -n "$scale_line" ]; then echo "$scale_line"; fi
    echo 'version: 1'
    echo 'created: 2026-08-10'
    echo '---'
    echo
    echo '## Introduction'
    echo 'Left over from an earlier attempt at a full story.'
    echo
    echo '### R1. First requirement'
    echo
    echo '#### Acceptance Criteria'
    echo
    echo '- R1.1: WHEN x THE SYSTEM SHALL y.'
    echo '- R1.2: WHEN a THE SYSTEM SHALL b.'
  } > "$STORY/story.md"
}

@test "2.2: --cross-ref on a spike reports no orphan and no phantom" {
  write_spike_tasks_with_r_tokens
  write_story_md_two_reqs ''
  run bash "$VALIDATE_SH" "$STORY" --cross-ref
  echo "$output" | jq -e . > /dev/null
  # R1.2 is defined in story.md and referenced nowhere in tasks.md — an orphan.
  refute_warning 'has no matching reference in tasks.md'
  # R9.9 is referenced in tasks.md and defined nowhere — a phantom.
  refute_warning 'does not exist in story.md'
}

@test "2.2: --cross-ref on a spike does not report the missing R-number references" {
  # The measured arm of Step 7: a conforming spike (no R-token anywhere, exactly
  # as its contract demands) beside a story.md carrying R-numbers is told to add
  # references that R1.4 of story 007 makes an error to write.
  write_spike_tasks 'scale: spike' '- status: open
- conclusion: pending'
  write_story_md_two_reqs ''
  run bash "$VALIDATE_SH" "$STORY" --cross-ref
  echo "$output" | jq -e . > /dev/null
  refute_warning 'no R-number references'
}

@test "2.2: PIN --cross-ref on a standard story still reports orphans and phantoms" {
  # The block's real job. Identical fixture shape to the spike case above, one
  # frontmatter line apart, so the suppression is attributable to the scale and
  # to nothing else.
  write_story_md_two_reqs 'scale: standard'
  {
    echo '---'
    echo 'story: leftover-artifact'
    echo 'type: feature'
    echo 'version: 1'
    echo 'created: 2026-08-10'
    echo '---'
    echo
    echo '## Task List'
    echo '- [ ] 1 - Implement the cache path'
    echo '  - Requirements: R1.1'
    echo '  - Validation: `echo ok`'
    echo '- [ ] 2 - Implement the cold path'
    echo '  - Requirements: R9.9'
    echo '  - Validation: `echo ok`'
    echo
    echo '## Quality Gates'
    echo '- Done'
  } > "$STORY/tasks.md"
  run bash "$VALIDATE_SH" "$STORY" --cross-ref
  echo "$output" | jq -e . > /dev/null
  assert_warning 'R1.2 in story.md has no matching reference in tasks.md'
  assert_warning 'R9.9 referenced in tasks.md does not exist in story.md'
}

# =============================================================================
# 2.3 — scripts/cross-reference.sh reports the inapplicability, never zero
#       (R3.4)
# =============================================================================
#
# THE THIRD GATE, and the one no earlier survey named. It is the gate the
# story's own first Quality Gate runs, and on the leftover-artifact shape it
# reports `orphan_requirements: ["R1.1","R1.2"]`, `status:
# "untraceable-format"`, exit 1 — measured. Its `:37-40` guard exits 2 when
# story.md is absent, so a CONFORMING tasks-only spike never reaches the report
# at all: the contradictory output is reachable only through the leftover
# artifact, which is why nothing caught it before.
#
# WHY EXIT STATUS IS ASSERTED HERE AND NOWHERE ELSE IN THIS SUITE. Everywhere
# above, the exit code is the sum of every diagnostic a malformed fixture
# collects, so pinning it pins the whole validator. Here the exit code IS the
# contract: R3.4 says exit 0, cross-reference.sh has exactly three exit codes,
# and a consumer (the Quality Gate, ci-mode) reads nothing else.
#
# "REPORT THE INAPPLICABILITY, NEVER MEASURE ZERO." `traced: 0` with `coverage:
# "0/0"` says a measurement was made and came back empty; the truth is that
# there was nothing to measure, and those are different statements to a human
# reading a gate report. The shape follows epic-gitpolicy.sh's non-git object:
# the keys that would report a measurement are ABSENT, not zeroed.

@test "2.3: cross-reference.sh on a spike reports no orphan and exits 0" {
  # The leftover-artifact shape, deliberately: story.md declares `standard` and
  # tasks.md declares `spike`, so the reported `scale` doubles as the only
  # place in any output where the RESOLVED scale is directly visible. A fix
  # that resolves story.md-first here still reports orphans and still fails.
  write_story_md_two_reqs 'scale: standard'
  write_spike_tasks_with_r_tokens
  run --separate-stderr bash "$XREF_SH" "$STORY"
  # Reported through an `if` rather than a bare `[` so the failure log carries
  # the report itself: the exit code alone cannot say WHICH of the two defects
  # produced it (an orphan, or the untraceable-format verdict).
  if [ "$status" -ne 0 ]; then
    echo "expected exit 0 — a spike has no requirements chain to compare against"
    echo "got exit $status and this report:"
    echo "$output"
    return 1
  fi
  echo "$output" | jq -e . > /dev/null
  echo "$output" | jq -e '.status == "no-requirements-chain"' > /dev/null
  # The resolution itself, named in the report rather than inferred from it.
  echo "$output" | jq -e '.scale == "spike"' > /dev/null
  # No orphan and no phantom. Written total (`// []`) so it holds whether the
  # key is absent or empty — R3.4 says "reports no orphan", and which of the
  # two spellings satisfies that is the implementer's call.
  echo "$output" | jq -e '(.orphan_requirements // []) | length == 0' > /dev/null
  echo "$output" | jq -e '(.phantom_references // []) | length == 0' > /dev/null
  # The two keys that must NOT be spelled zero: they claim a measurement.
  echo "$output" | jq -e 'has("traced") | not' > /dev/null
  echo "$output" | jq -e 'has("coverage") | not' > /dev/null
}

@test "2.3: PIN cross-reference.sh on a standard story still reports its orphan and exits 1" {
  # The gate's real job, on the same fixture shape one frontmatter line apart:
  # R1.2 is defined and declared by no sub-task. If this ever goes quiet, the
  # suppression above stopped being a suppression and became a hole.
  write_story_md_two_reqs 'scale: standard'
  {
    echo '---'
    echo 'story: leftover-artifact'
    echo 'type: feature'
    echo 'scale: standard'
    echo 'version: 1'
    echo 'created: 2026-08-10'
    echo '---'
    echo
    echo '## Task List'
    echo '- [ ] 1 - Implement the cache path'
    echo '  - Requirements: R1.1'
    echo '  - Validation: `echo ok`'
    echo
    echo '## Quality Gates'
    echo '- Done'
  } > "$STORY/tasks.md"
  run --separate-stderr bash "$XREF_SH" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e . > /dev/null
  echo "$output" | jq -e '.orphan_requirements == ["R1.2"]' > /dev/null
  echo "$output" | jq -e '.status == "issues"' > /dev/null
  # The measurement keys are still there, because here a measurement was made.
  echo "$output" | jq -e '.coverage == "1/2"' > /dev/null
}

@test "2.3: PIN a conforming tasks-only spike still exits 2 with no report" {
  # The guard at cross-reference.sh:37-40, unchanged and pinned on purpose. The
  # tempting "fix" is to make a missing story.md exit 0 now that a spike is
  # allowed to have none — that would swallow a genuinely malformed lifecycle
  # story (one whose story.md was deleted by mistake) under the same silence.
  # A spike simply must not be routed through this script; being TOLD so, on
  # stderr with exit 2, is the correct answer and not a defect.
  write_spike_tasks 'scale: spike' '- status: open
- conclusion: pending'
  run --separate-stderr bash "$XREF_SH" "$STORY"
  [ "$status" -eq 2 ]
  # No JSON at all — a consumer must not be able to read a verdict out of this.
  [ -z "$output" ]
  echo "$stderr" | grep -q 'story.md'
}

# =============================================================================
# 3.1 — archive-story.sh resolves the scale from tasks.md, at BOTH call sites
#       (R4.2)
# =============================================================================

# make_archive_spike <dir> <verdict-status|""> <story.md scale line>
# The archive shape of the reproduction: a spike whose probe boxes are all
# closed — which is what makes the generic closed-boxes rule fire when the scale
# is mis-resolved — beside a story.md left over from an earlier attempt.
# `status: in-progress` on both artifacts so the status branch can never be the
# thing that decides.
make_archive_spike() {
  local dir="$PROJ/.epic/stories/$1" verdict="$2" story_scale_line="$3"
  mkdir -p "$dir"
  {
    echo '---'
    echo 'story: probe'
    echo 'type: feature'
    echo 'scale: spike'
    echo 'status: in-progress'
    echo 'version: 1'
    echo 'created: 2026-08-10'
    echo '---'
    echo
    echo '## Task List'
    echo '- [x] 1 - Run the probe'
    echo '  - Validation: `./probe.sh`'
    if [ -n "$verdict" ]; then
      echo
      echo '## Verdict'
      echo "- status: $verdict"
      echo '- conclusion: what the probe showed'
    fi
  } > "$dir/tasks.md"
  {
    echo '---'
    echo 'story: probe'
    echo 'type: feature'
    echo "$story_scale_line"
    echo 'status: in-progress'
    echo 'version: 1'
    echo 'created: 2026-08-10'
    echo '---'
    echo
    echo '# Story - left over from an earlier attempt'
  } > "$dir/story.md"
}

@test "3.1: a spike with no Verdict beside a leftover story.md is refused and nothing is moved" {
  # story.md Reproduction Step 5, the only IRREVERSIBLE consequence in this
  # story: measured `status: "archived"`, `moved: true` — a spike filed away
  # without the conclusion that is its only deliverable. With the story.md scale
  # line absent the same fixture is already refused.
  make_archive_spike 031-probe '' 'scale: full'
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/031-probe
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  echo "$output" | jq -e '.moved == false' > /dev/null
  # ...and refused means nothing happened on disk, not "refused after moving".
  [ -d "$PROJ/.epic/stories/031-probe" ]
  [ ! -d "$PROJ/.epic/archive/031-probe" ]
  [ ! -e "$MANIFEST" ]
}

@test "3.1: an archivable spike records 'spike' in its manifest entry" {
  # THE SECOND CALL SITE. A fix applied only to the completion gate refuses the
  # case above correctly and then files this one under `scale: full` — the
  # manifest is the archive's permanent record and its scale is derived, never
  # declared, so a wrong value there is a lie that outlives the story directory.
  make_archive_spike 032-probe wont-do 'scale: full'
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/032-probe
  echo "$output" | jq -e '.status == "archived"' > /dev/null
  echo "$output" | jq -e '.moved == true' > /dev/null
  echo "$output" | jq -e '.manifest_entry.scale == "spike"' > /dev/null
  # The report and the file on disk are two renderings of one entry; the file is
  # the one a future reader has.
  [ -f "$MANIFEST" ]
  grep -Eq 'scale:[[:space:]]*"?spike"?' "$MANIFEST"
}

# =============================================================================
# 3.2 — the documentation contract: no sentence left describing the old rule
#       (R1.1)
# =============================================================================

# comment_blocks <file> — every run of consecutive `#` comment lines, flattened
# to one line per run. Wrapping is an editing artifact: the claim under test is
# split across two source lines ("...story.md FIRST — it is the" / "story's own
# frontmatter and therefore wins..."), so a line-by-line grep for
# `story.md.*wins` finds nothing and the check would pass while the sentence is
# still there. Flattening makes the assertion about the PROSE, not the layout.
comment_blocks() {
  awk '
    /^[[:space:]]*#/ {
      line = $0
      sub(/^[[:space:]]*#[[:space:]]?/, "", line)
      buf = buf " " line
      next
    }
    { if (buf != "") { print buf; buf = "" } }
    END { if (buf != "") print buf }
  ' "$1"
}

@test "3.2: references/tasks.md states that tasks.md is authoritative for the declared scale" {
  # The contract sentence today (references/tasks.md, Spike Scale Adaptations)
  # only IMPLIES precedence — "the only place a spike can declare it, and
  # validation reads it from there" — which is why two documents could point
  # opposite ways for this long without either being wrong on its face. The fix
  # retracts one of them, so the surviving one has to say the rule out loud.
  DOC="$PLUGIN_ROOT/references/tasks.md"
  [ -f "$DOC" ]
  # Flattened to one line: the statement may wrap, and `[^.]` keeps a match from
  # spanning a sentence boundary.
  FLAT=$(tr '\n' ' ' < "$DOC")
  grep -qiE "tasks\.md[^.]{0,160}authoritative|authoritative[^.]{0,160}tasks\.md" <<< "$FLAT"
  # Half a rule is not the rule: the reader also has to be told what happens to
  # the artifact that disagrees — it is REPORTED, not honoured, and not silently
  # ignored either.
  grep -qiE "story\.md[^.]{0,200}(reported|not honoured|not honored)" <<< "$FLAT"
}

@test "3.2: no comment in validate-story.sh still claims story.md wins for scale" {
  # scripts/validate-story.sh:131-137 does not merely implement the defect, it
  # ARGUES for it in prose. Shipping the fix beside the rationale for the bug is
  # the defect class story 007 spent its last sub-task removing.
  BLOCKS=$(comment_blocks "$PLUGIN_ROOT/scripts/validate-story.sh")
  SCALE_BLOCKS=$(grep -i 'scale' <<< "$BLOCKS" || true)
  [ -n "$SCALE_BLOCKS" ]
  # The retraction, stated: some comment about scale says tasks.md owns it.
  if ! grep -qiE "tasks\.md[^.]{0,120}(owns|authoritative|wins)|(authoritative)[^.]{0,120}tasks\.md" <<< "$SCALE_BLOCKS"; then
    echo "expected a comment stating that tasks.md owns/is authoritative for 'scale'"
    # Truncated: these blocks are paragraphs, and dumping them whole buries the
    # one line of diagnosis under a page of prose.
    echo "the scale-mentioning comment blocks (first 120 chars each) were:"
    cut -c1-120 <<< "$SCALE_BLOCKS"
    return 1
  fi
  # And the claim it replaces is gone. Phrase the retraction as what the rule IS
  # ("tasks.md owns scale:") rather than as a restatement of what it was, or
  # this assertion will read the quotation as the claim — it cannot tell them
  # apart, and neither can a reader skimming the comment.
  if grep -qiE "story\.md[^.]{0,120}(first|wins)" <<< "$SCALE_BLOCKS"; then
    echo "a comment still claims story.md is read first / wins for 'scale':"
    grep -iE "story\.md[^.]{0,120}(first|wins)" <<< "$SCALE_BLOCKS" | cut -c1-200
    return 1
  fi
}

@test "3.2: epic-index.sh no longer attributes the scale lookup to archive-story.sh's story_field" {
  # scripts/epic-index.sh:751-754 states that scale "is looked up the way
  # archive-story.sh's story_field looks it up — story.md first, then tasks.md".
  # `story_field` stops resolving scale the moment 3.1 lands, so the sentence
  # becomes false about a function it names by hand. Its CODE is out of scope
  # and may keep its own precedence; what it may not keep is an appeal to a
  # reader that no longer works that way.
  BLOCKS=$(comment_blocks "$PLUGIN_ROOT/scripts/epic-index.sh")
  if grep -q 'story_field' <<< "$BLOCKS"; then
    echo "a comment in epic-index.sh still explains 'scale' through archive-story.sh's story_field:"
    grep 'story_field' <<< "$BLOCKS" | cut -c1-200
    return 1
  fi
}
