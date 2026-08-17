#!/usr/bin/env bats
# Story 004, sub-tasks 2.3 and 5.3/5.4 — cross-regression harness (R4.1, R5.1,
# R3.3, R3.4); seventh consumer added by story 016, sub-task 1.2; the roster
# moved out to tests/lib/checkbox-consumers.sh in story 017, sub-task 1.3.
# ONE mixed fixture ([x] / [ ] / [~] terminal / [~] deferred) is passed through
# the checkbox consumers, asserting they agree on which boxes exist and which
# work is open. This pins the duplicated regex so one drifted copy cannot
# silently reopen the false-clean/false-orphan class fixed in e890d02.
#
# WHICH SCRIPTS THOSE ARE IS DECLARED AS DATA, NOT LISTED HERE.
# tests/lib/checkbox-consumers.sh carries the roster — CHECKBOX_CONSUMERS — and
# the scan that derives the same set from scripts/; tests/consumer-roster.bats
# reddens and NAMES the script when the two disagree. Each @test title below
# says which consumer that case drives, so this file states what it compares
# without restating who they are: one list, in one place, that can fail.
#
# THE ROSTER HOLDS A WRITER, NOT ONLY READERS. close-subtask.sh WRITES the
# grammar — the one sanctioned writer (story 010) — and every other consumer
# only reads it. That puts it further inside the roster, not outside it: a
# reader that drifts mis-counts a file someone else wrote, while a writer that
# drifts produces the file every reader then mis-counts. It is compared here
# through the `census` object of its stdout JSON, which is its own reading of
# the boxes as they now stand — the same statement the readers make directly in
# their output.
#
# Three enumerations of that list have now been wrong: the design said "6 regex
# places across 4 scripts", sub-task 5.3 raised it to 5 and still missed
# hook-post-tool-failure.sh, which the second validate-mode pass found (task
# 6.4). The lesson is the harness itself — a prose list of consumers cannot
# fail, and this file can. If a seventh appears, it belongs here. One did:
# story 010 copied these regexes into close-subtask.sh and left the roster at
# six, so the count was stale a fourth time — this time in the very file whose
# job is to make it fail. The rule is unchanged; an eighth belongs here too.
#
# THAT HISTORY IS KEPT DELIBERATELY, as the argument for the derivation rather
# than as a claim anyone still has to maintain: story 017 found the enumeration
# wrong a fifth time and moved the roster into the library named above, where
# the set is derived from scripts/ instead of counted by hand.
#
# Mixed fixture totals (the shared truth every consumer must agree on):
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
Shared mixed-grammar fixture for the checkbox consumers.

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
  - Commit: "feat(010): mixed"

## Quality Gates
- Counts consistent
EOF
}

# Byte-stability is a contract about this fixture's OUTPUT, not a freeze on its
# input. Story 006 group 10 made a group header that contradicts its own
# sub-tasks a validation error, and this fixture carried that exact shape:
# `- [x] 1 - Group` over an open `1.2`. The header is now `- [ ]`, which is the
# true statement — the alternative, closing `1.2`, would fabricate completion to
# satisfy the checker, which is the inversion of what the rule is for. Both
# R5.1 goldens below were verified BYTE-IDENTICAL across the change: neither
# validate-story.sh nor cross-reference.sh emits a box-state count, so the
# rendered output never depended on which of the three boxes was open.
#
# STORY 008 EXTENDED THE CROSS-REFERENCE OBJECT, and the golden was updated with
# the new key rather than the key being suppressed to keep the bytes. The report
# now carries `scale`, emitted on BOTH of its paths — the measured report below,
# and the `{story, scale, status: "no-requirements-chain"}` object that a scale
# owing no requirements chain gets instead of a measurement (design.md §5, R3.4).
# It reads `standard` here because this fixture declares `scale: standard` in
# both artifacts; a fixture declaring none anywhere would read a bare `null`.
# THE EXTENSION IS PURELY ADDITIVE, and that is what makes it compatible with
# R5.1's intent instead of a breach of it: every pre-existing key keeps its
# position and its value byte for byte, so nothing reading `coverage`, `mapping`
# or `status` moves. The positive reason the key is on both paths is that after
# story 008 the RESOLVED scale is observable nowhere else in the system — every
# other test of the resolution has to infer it from a downstream error message.
#
# AND THE PART WORTH THE PARAGRAPH. Story 008's design measured "the key set is
# asserted nowhere" against tests/cross-reference.bats alone. That was true of
# that suite and FALSE of the repository: THIS golden pins the whole object by
# equality, it is the fifth pin the survey missed, and it was found only when the
# sub-task's own full-suite run reddened here — one case, in a suite named after
# checkboxes rather than after the script whose output it freezes. The next
# person extending this object should sweep for full-object goldens
# (`[ "$output" = "$expected" ]` over a heredoc) across EVERY suite, not only the
# one named after the script.
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
- [ ] 1 - Group
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

# snapshot_fixture / assert_fixture_untouched — R2.4. The shared fixture is read
# by every case in this file; a comparison that writes to it would make the
# suite order-dependent, which is the one failure a cross-regression harness
# cannot afford. Snapshot before the run, diff after.
snapshot_fixture() {
  rm -rf "$WORK/fixture-before"
  cp -r "$MIXED" "$WORK/fixture-before"
}

assert_fixture_untouched() {
  if ! diff -r "$WORK/fixture-before" "$MIXED"; then
    echo "the consumer under comparison wrote to the SHARED fixture"
    return 1
  fi
}

# load_roster — the declared roster (story 017 sub-task 1.1), used by the
# closing case. MERGE NOTE: if tests/checkbox-grammar.bats ends up defining
# this helper elsewhere, keep one copy.
load_roster() {
  local lib="$PLUGIN_ROOT/tests/lib/checkbox-consumers.sh"
  if [ ! -f "$lib" ]; then
    echo "the declared consumer roster does not exist yet: $lib"
    return 1
  fi
  # shellcheck disable=SC1090
  source "$lib"
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

@test "R4.1: hook-precompact renders the census the other consumers parse" {
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

@test "R4.1: close-subtask — the seventh consumer, and the only one that WRITES" {
  # A WRITER IS COMPARED THROUGH ITS `census` OBJECT. That object is the
  # script's own reading of the grammar — it re-reads tasks.md after marking it
  # — so it is the comparable surface every reader above hands over directly in
  # its output. Drift then shows up here as a disagreement about the same five
  # boxes, in the same terms, rather than as a diff of the file it wrote.
  #
  # The close lands on a COPY: $MIXED is the shared fixture the cases above
  # read, and this is the one consumer that would write to it. The copy keeps
  # the proj/.epic/stories/010-mixed shape so the script resolves the story
  # exactly as a real caller's does.
  COPY=$(mktemp -d "$WORK/seventh.XXXXXX")
  mkdir -p "$COPY/proj/.epic/stories"
  cp -r "$MIXED" "$COPY/proj/.epic/stories/010-mixed"
  cd "$COPY/proj"

  # Diagnostics go to stderr and a clean close emits none, so $output is the
  # JSON object. (bats merges the two streams by default, so a stray diagnostic
  # would redden this case as a parse failure rather than pass unnoticed.)
  run bash "$PLUGIN_ROOT/scripts/close-subtask.sh" .epic/stories/010-mixed 1.5
  [ "$status" -eq 0 ]

  # The header's shared truth, advanced by that one close: 1.5 stops being the
  # open box, the terminal [~] 1.3 still counts as closed, and the deferred
  # [~] 1.4 still counts apart from both. The report also carries a validate
  # verdict; it is not this harness's subject, and this script never rolls a
  # landed marking back on it.
  echo "$output" | jq -e '.census.total == 5 and .census.open == 0 and .census.closed == 4 and .census.deferred == 1'
}

@test "R2.1/R2.4: archive-story.sh — the same five boxes, partitioned for the manifest" {
  # THE MAPPING THIS CASE ASSERTS, MEASURED RATHER THAN ASSUMED. archive-story
  # reports three DISJOINT numbers a manifest reader must be able to add up, so
  # `closed` is [x] AND ONLY [x], and EVERY [~] — terminal or deferred — is
  # `deferred`. Against the shared truth that is:
  #   total 5   == 5   (identical)
  #   open  1   == 1   (identical)
  #   closed 2  = shared closed 3 MINUS the terminal [~] 1.3
  #   deferred 2 = shared deferred 1 PLUS that same terminal [~] 1.3
  # so the two readings differ by exactly one box, in one direction, and their
  # sum is the same 4 settled boxes. Asserting `closed == 3` here would not
  # detect drift — it would demand archive-story change an aggregation it
  # documents on purpose, which this story puts out of scope.
  #
  # The verdict path used is the REFUSAL: one box is still open, so the story
  # is incomplete and nothing is moved — and the census is reported anyway,
  # because a refusal reports what it measured. That keeps the comparison on
  # the reading, not on the move.
  snapshot_fixture
  COPY=$(mktemp -d "$WORK/archive.XXXXXX")
  mkdir -p "$COPY/proj/.epic/stories"
  cp -r "$MIXED" "$COPY/proj/.epic/stories/010-mixed"
  cd "$COPY/proj"

  # archive-story TALKS on stderr, and bats merges the streams — dropping
  # stderr is what keeps $output one parseable JSON object.
  run bash -c "bash '$PLUGIN_ROOT/scripts/archive-story.sh' .epic/stories/010-mixed 2>/dev/null"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused" and .moved == false'

  # Identical on the two totals that are not a matter of aggregation.
  echo "$output" | jq -e '.tasks.total == 5 and .tasks.open == 1'
  # The partition itself, and the fact that it partitions: the three numbers
  # are disjoint and exhaust the total.
  echo "$output" | jq -e '.tasks.closed == 2 and .tasks.deferred == 2'
  echo "$output" | jq -e '.tasks.closed + .tasks.deferred + .tasks.open == .tasks.total'
  # The mapping onto the shared truth: 4 settled boxes, one open, however the
  # settled four are split.
  echo "$output" | jq -e '.tasks.closed + .tasks.deferred == 4'

  assert_fixture_untouched
}

@test "R2.2/R2.4: epic-index.sh — the census the index renders folds the terminal [~] into done" {
  # epic-index RENDERS FOR A HUMAN and reuses hook-precompact's split verbatim:
  # a terminal [~] closes the box, `deferred:` is reported apart. It emits no
  # `open` field at all, so the shared open count is recovered as
  # total − done − deferred — that arithmetic is the agreement, and it is
  # asserted on the numbers PARSED OUT OF THE RENDERED CELL, never on literals.
  snapshot_fixture
  COPY=$(mktemp -d "$WORK/index.XXXXXX")
  cp -r "$WORK/proj" "$COPY/proj"
  printf '# Epic\n\n<!-- epic:index:start -->\n<!-- epic:index:end -->\n' \
    > "$COPY/proj/.epic/EPIC.md"
  cd "$COPY/proj"

  run bash -c "bash '$PLUGIN_ROOT/scripts/epic-index.sh' 2>/dev/null"
  [ "$status" -eq 0 ]

  # Column 5 of the story's row is the progress cell: `done/total (+N deferred)`.
  prog=$(awk -F'|' '$2 ~ /010/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $5); print $5 }' \
    "$COPY/proj/.epic/EPIC.md")
  if [[ ! "$prog" =~ ^([0-9]+)/([0-9]+)\ \(\+([0-9]+)\ deferred\)$ ]]; then
    echo "the index rendered no parseable census for the mixed fixture: '$prog'"
    return 1
  fi
  idx_done="${BASH_REMATCH[1]}"
  idx_total="${BASH_REMATCH[2]}"
  idx_deferred="${BASH_REMATCH[3]}"

  [ "$idx_total" -eq 5 ]
  [ "$idx_done" -eq 3 ]
  [ "$idx_deferred" -eq 1 ]
  # The shared open count, recovered from a report that never states it.
  [ "$((idx_total - idx_done - idx_deferred))" -eq 1 ]

  assert_fixture_untouched
}

@test "R2.3/R2.4: supersede-story.sh — the scope it carries is the open-or-deferred SET" {
  # supersede's reading of the grammar decides WHAT MOVES: every `[ ]` and every
  # `[~] (deferred: …)` is scope still owed and must land in the successor;
  # `[x]` and a TERMINAL `[~]` are settled, and a row for either would claim
  # work moved that never did. Against the shared truth that set is exactly
  # {1.4, 1.5} — the deferred box and the open one.
  #
  # THE SET IS ASSERTED, NOT THE COUNT. `remap_rows == 2` is true of a script
  # that carried 1.1 and 1.3 instead; the numbers themselves are what pins the
  # grammar, so they are read off both surfaces the operation produces — the
  # banner table, and the boxes it closed in tasks.md.
  snapshot_fixture
  COPY=$(mktemp -d "$WORK/supersede.XXXXXX")
  cp -r "$WORK/proj" "$COPY/proj"
  SUCCESSOR="$COPY/proj/.epic/stories/011-successor"
  mkdir -p "$SUCCESSOR"
  for f in story.md tasks.md; do
    printf -- '---\nstory: successor\ntype: feature\nscale: standard\nversion: 1\ncreated: 2026-08-16\n---\n\n# %s\n' \
      "$f" > "$SUCCESSOR/$f"
  done
  cd "$COPY/proj"

  run bash -c "bash '$PLUGIN_ROOT/scripts/supersede-story.sh' .epic/stories/010-mixed --by 011 2>/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "superseded" and .remap_rows == 2 and .closed_subtasks == 2'

  SUPERSEDED="$COPY/proj/.epic/stories/010-mixed"

  # Surface 1 — the remap table written into the superseded story: which scope
  # was declared to have moved.
  carried=$(grep -oE '^> \| task [0-9]+\.[0-9]+' "$SUPERSEDED/story.md" \
    | grep -oE '[0-9]+\.[0-9]+' | sort | tr '\n' ' ')
  [ "$carried" = "1.4 1.5 " ]

  # Surface 2 — the boxes it closed: the same set, or the two surfaces
  # disagree with each other about the same five boxes.
  closed=$(grep -oE '^- \[~\] [0-9]+\.[0-9]+ .*\(superseded-by: 011\)' "$SUPERSEDED/tasks.md" \
    | grep -oE '^- \[~\] [0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+' | sort | tr '\n' ' ')
  [ "$closed" = "1.4 1.5 " ]

  # And the settled boxes were left alone — the terminal [~] keeps its own
  # qualifier rather than being re-closed as superseded.
  # `--` because the pattern opens with a dash, which grep would read as a flag.
  grep -qF -- '- [~] 1.3 - Waived gate (waived: tool absent)' "$SUPERSEDED/tasks.md"
  grep -qE '^- \[x\] 1\.1 ' "$SUPERSEDED/tasks.md"
  grep -qE '^- \[x\] 1\.2 ' "$SUPERSEDED/tasks.md"

  assert_fixture_untouched
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
  "scale": "standard",
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

@test "R1.5/R2.5: every declared consumer is compared by a case in this harness" {
  # THE LOOP CLOSER. Story 017's derivation reddens when a script under
  # scripts/ reads the grammar and is not on the roster. This is the other
  # direction: a name ON the roster that no case here compares. Without it,
  # registering a script — one line of data — turns the derivation green while
  # its copy of the regex stays unmeasured, which is exactly the state the
  # three consumers pinned above were in.
  #
  # The check is on @test TITLES, so the convention it enforces is that a
  # comparison case names the consumer it compares. That convention is what
  # makes this harness readable at all, and it is already true of every case
  # here.
  load_roster
  HARNESS="$PLUGIN_ROOT/tests/checkbox-grammar.bats"
  [ -f "$HARNESS" ]

  missing=()
  for s in "${CHECKBOX_CONSUMERS[@]}"; do
    stem="${s%.sh}"
    if ! grep -E '^@test ' "$HARNESS" | grep -qF "$stem"; then
      missing+=("$s")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "declared consumers with no comparison case in ${HARNESS##*/}: ${missing[*]}"
    return 1
  fi
}
