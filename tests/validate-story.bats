#!/usr/bin/env bats
# Unit tests for scripts/validate-story.sh. Covers:
#   - Fast mode (tasks.md only) — regression for v1.2.1 TASK_COUNT fix
#   - Standard/Full mode with required sections
#   - Bugfix Unchanged Behavior enforcement
#   - --strict flag promoting warnings to errors
#   - Help and invalid-input exit codes

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/story"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

@test "help flag exits 0" {
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" --help
  [ "$status" -eq 0 ]
}

@test "non-existent directory exits 2" {
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" /definitely/does/not/exist
  [ "$status" -eq 2 ]
}

@test "missing tasks.md fails (exit 1)" {
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'Missing tasks.md'
}

@test "fast mode: tasks.md only does not crash (v1.2.1 regression)" {
  cat > "$STORY/tasks.md" <<'EOF'
---
story: test-fast
type: feature
scale: fast
version: 1
created: 2026-04-19
---

## Overview
Fast mode smoke test.

## Task List
- [ ] 1 - Add field
  - Validation: `npm run lint`

## Quality Gates
- Tests pass
- Validation succeeds
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "pass"'
}

@test "standard mode: tasks.md with R-numbers accepted" {
  cat > "$STORY/story.md" <<'EOF'
---
story: test-standard
type: feature
scale: standard
version: 1
created: 2026-04-19
---

## Introduction
Test story.

### R1
WHEN user clicks X THE SYSTEM SHALL do Y.
EOF
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
created: 2026-04-19
---

## Task List
- [ ] 1 - Implement click handler
  - Requirements: R1
  - Validation: `npm test`

## Quality Gates
- Acceptance criteria met
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
}

@test "bugfix missing Unchanged Behavior: error" {
  cat > "$STORY/story.md" <<'EOF'
---
story: test-bug
type: bugfix
scale: standard
version: 1
created: 2026-04-19
---

## Summary
Login is broken.

### R1
WHEN user submits login THE SYSTEM SHALL redirect to dashboard.
EOF
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
---

## Task List
- [ ] 1 - Fix redirect
  - Requirements: R1
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'Unchanged Behavior'
}

@test "SHOULD instead of SHALL: error" {
  cat > "$STORY/story.md" <<'EOF'
---
story: test-should
type: feature
scale: standard
version: 1
created: 2026-04-19
---

### R1
WHEN user acts THE SYSTEM SHOULD respond.
EOF
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
---

## Task List
- [ ] 1 - Handle action
  - Requirements: R1
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'SHOULD'
}

@test "--strict promotes warnings to errors" {
  # A task list with no Validation or Quality Gates = warnings, not errors
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
created: 2026-04-19
---

## Task List
- [ ] 1 - Sketch
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"warnings": [^0]'

  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY" --strict
  [ "$status" -eq 1 ]
}

@test "--cross-ref reports orphan requirements" {
  cat > "$STORY/story.md" <<'EOF'
---
story: test-xref
type: feature
scale: standard
version: 1
created: 2026-04-19
---

### R1
WHEN x THE SYSTEM SHALL y.

### R2
WHEN a THE SYSTEM SHALL b.
EOF
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
---

## Task List
- [ ] 1 - Only R1
  - Requirements: R1
  - Validation: `echo ok`

## Quality Gates
- Done
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY" --cross-ref
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'R2'
}

@test "--cross-ref: model B group heading is not flagged as orphan" {
  cat > "$STORY/story.md" <<'EOF'
---
story: test-xref-modelb
type: feature
scale: standard
version: 1
created: 2026-05-18
---

### R1. First requirement

#### Acceptance Criteria

- R1.1: WHEN x THE SYSTEM SHALL y.
- R1.2: WHEN a THE SYSTEM SHALL b.
EOF
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
---

## Task List
- [ ] 1 - Implement
  - Requirements: R1.1, R1.2
  - Validation: `echo ok`

## Quality Gates
- Done
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY" --cross-ref
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'Requirement R1 in story.md'
}

@test "--cross-ref: model B flags an uncovered leaf criterion" {
  cat > "$STORY/story.md" <<'EOF'
---
story: test-xref-leaf
type: feature
scale: standard
version: 1
created: 2026-05-18
---

### R1. First requirement

#### Acceptance Criteria

- R1.1: WHEN x THE SYSTEM SHALL y.
- R1.2: WHEN a THE SYSTEM SHALL b.
EOF
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
---

## Task List
- [ ] 1 - Implement
  - Requirements: R1.1
  - Validation: `echo ok`

## Quality Gates
- Done
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY" --cross-ref
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Requirement R1.2 in story.md has no matching'
}

# --- Wave-0 regressions: structural silence and JSON validity ---

@test "tasks.md with zero parseable tasks is an error, not a silent pass" {
  cat > "$STORY/tasks.md" <<'TASKS'
---
version: 1
created: 2026-07-23
---
## T1. Heading-style task
### T1.1 Do the thing [x]
- **Covers:** R1.1
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'no parseable checkbox tasks'
}

@test "JSON output stays valid when a message embeds a double quote" {
  cat > "$STORY/tasks.md" <<'TASKS'
---
version: v1"quoted
created: 2026-07-23
---
- [ ] 1 - One
  - Requirements: R1
  - Validation: ok
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e . > /dev/null
}

# --- 10.3: group-header consistency ------------------------------------------
# A group header is a claim about its own sub-tasks, and until story 006 nothing
# checked it — group 8 of 006 shipped `- [ ] 8` over seven closed sub-tasks and
# every validator returned pass. The rule is an IDENTITY, so it is enforced in
# BOTH directions; shipping one half of one is exactly what this story did four
# consecutive times. And it must leave the THIRD box state alone: `[~]` is a
# header closed without doing the work, which 004's grammar allows and which
# neither direction may touch.
#
# `write_group` builds a fast-mode tasks.md (no story.md, so no Requirements
# check) whose only interesting property is the group box and its children.
# Args: <group-box> <sub-task-box>...   e.g. write_group ' ' x x
write_group() {
  local group_box="$1"; shift
  local n=0 body="" box
  for box in "$@"; do
    n=$((n + 1))
    body+="  - [$box] 1.$n - Sub-task $n"$'\n'"    - Validation: \`true\`"$'\n'
  done
  cat > "$STORY/tasks.md" <<EOF
---
story: header-consistency
type: feature
scale: fast
version: 1
created: 2026-08-07
---

## Overview
Group-header consistency fixture.

## Task List

- [$group_box] 1 - The group
  - _Complexity: Trivial | Tests: None_
$body
## Quality Gates
- Tests pass
EOF
}

@test "10.3 an open group header over all-closed sub-tasks is an error (the shape group 8 shipped)" {
  write_group ' ' x x x
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "fail"' > /dev/null
  echo "$output" | grep -q 'group 1 is open'
}

@test "10.3 a closed group header over an open sub-task is an error (the other direction)" {
  write_group x x ' ' x
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "fail"' > /dev/null
  echo "$output" | grep -q 'group 1 is closed'
}

@test "10.3 both honest shapes stay green" {
  write_group ' ' x ' ' x
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "pass"' > /dev/null

  write_group x x x x
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "pass"' > /dev/null
}

@test "10.3 a [~] group header is untouched by either direction (the third element)" {
  # 8.1's derived-value question asked of this rule: a check written over two
  # states forgets the third. Both sub-task shapes that make a `[ ]` or `[x]`
  # header an error must leave a qualified `[~]` header alone.
  write_group '~' x x x
  sed -i 's|^- \[~\] 1 - The group$|- [~] 1 - The group (waived: superseded by group 2)|' "$STORY/tasks.md"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "pass"' > /dev/null

  write_group '~' x ' ' x
  sed -i 's|^- \[~\] 1 - The group$|- [~] 1 - The group (waived: superseded by group 2)|' "$STORY/tasks.md"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "pass"' > /dev/null
}

@test "10.3 a group owns its sub-tasks by number, so 1 never owns 10.1" {
  # 8.1's derived-value question asked of the OTHER derived value in this rule.
  # The group number is a computed key, and `1` is a string prefix of `10` —
  # the third-element collision that a rule written over one group forgets.
  #
  # Red is established by MUTATION rather than by precedence: the behaviour was
  # already correct when this case was written, so it is a regression guard, and
  # the gate's own reading is "a case that fails when its behaviour is removed".
  # Removed (owning by first digit instead of by number), this fixture still
  # reports exactly ONE error — it merely blames group 1 for group 10's open
  # box. A case asserting only the error COUNT would stay green through that,
  # which is why the assertion below is on the attribution.
  cat > "$STORY/tasks.md" <<'TASKS'
---
story: prefix-ownership
type: feature
scale: fast
version: 1
created: 2026-08-07
---

## Overview
Group 1 and group 10 in one file.

## Task List

- [x] 1 - group one, honestly closed
  - _Complexity: Trivial | Tests: None_
  - [x] 1.1 - closed
    - Validation: `true`
- [x] 10 - group ten, dishonestly closed
  - [ ] 10.1 - still open
    - Validation: `true`

## Quality Gates
- Tests pass
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.errors == 1' > /dev/null
  echo "$output" | jq -e '.error_details[0] | contains("group 10 is closed")' > /dev/null
  # Group 1 is clean, which is only possible if it does not own 10.1.
  echo "$output" | jq -e '[.error_details[] | select(contains("group 1 is"))] | length == 0' > /dev/null
}

# --- 10.3 fix cycle 1: what the tech review found, each with its own case -----
# `write_doc` takes a whole tasks.md body so a fixture can carry its own
# `## Quality Gates` section — the section `write_group` hard-codes and which
# turned out to be where the rule's worst defect lived.
write_doc() {
  { printf -- '---\nstory: header-consistency\ntype: feature\nscale: fast\nversion: 1\ncreated: 2026-08-07\n---\n\n## Overview\nGroup-header consistency fixture.\n\n'
    cat
  } > "$STORY/tasks.md"
}

@test "10.3 a numbered Quality Gate line cannot mask a group's violation" {
  # The rule read the WHOLE file, so any `- [box] N - ...` line outside the task
  # list overwrote that group's header state. Quality Gates share the checkbox
  # grammar by design (references/tasks.md), so a numbered gate is a legal
  # shape — and this one silenced the exact violation group 8 of story 006
  # shipped, which is the shape the whole rule exists to catch.
  write_doc <<'TASKS'
## Task List

- [x] 1 - Real group
  - _Complexity: Trivial | Tests: None_
  - [ ] 1.1 - still open
    - Validation: `true`

## Quality Gates
- [ ] 1 - All tests pass
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '[.error_details[] | select(contains("group 1 is closed"))] | length == 1' > /dev/null
}

@test "10.3 a numbered Quality Gate line cannot invent a violation" {
  # The converse guard. The same whole-file read also FLAGGED an honest file,
  # and pointed the line number at the gate rather than at any group header.
  write_doc <<'TASKS'
## Task List

- [x] 3 - Group three
  - _Complexity: Trivial | Tests: None_
  - [x] 3.1 - done
    - Validation: `true`

## Quality Gates
- [ ] 3 - Coverage >= 80%
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "pass"' > /dev/null
}

@test "10.3 a duplicate group number is an error, not a silent overwrite" {
  # Last-write-wins is the mechanism behind both cases above, and it bites
  # inside the task list too: the `[ ]` header over an all-closed 1.1 vanished
  # because a second `1` header overwrote it. A repeated group number is an
  # identity violation in its own right, and the consistency verdict for that
  # number is not computable while it stands.
  write_doc <<'TASKS'
## Task List

- [ ] 1 - First half
  - _Complexity: Trivial | Tests: None_
  - [x] 1.1 - done
    - Validation: `true`
- [x] 1 - Second half
  - [x] 1.2 - done
    - Validation: `true`

## Quality Gates
- Tests pass
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '[.error_details[] | select(contains("group 1 has more than one header"))] | length == 1' > /dev/null
}

@test "10.3 the open-header message states the tested condition, not an inference" {
  # `[~] (deferred: ...)` is the case where nothing is pending and the work did
  # NOT happen — references/tasks.md is emphatic about it. The predicate is
  # right (the honest header is `[~] deferred:`), but the message told the
  # author the opposite of what their own file says.
  write_doc <<'TASKS'
## Task List

- [ ] 5 - Provider integration
  - _Complexity: Trivial | Tests: None_
  - [~] 5.1 - Register the callback URL (deferred: needs the provider live account)
    - Validation: `true`

## Quality Gates
- Tests pass
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '[.error_details[] | select(contains("group 5 is open"))] | length == 1' > /dev/null
  echo "$output" | jq -e '[.error_details[] | select(contains("no sub-task is still open"))] | length == 1' > /dev/null
  # The false clause must be gone, not merely joined by a true one.
  echo "$output" | jq -e '[.error_details[] | select(contains("already done"))] | length == 0' > /dev/null
}

@test "10.3 an unqualified [~] sub-task makes the group's state uncomputable" {
  # The census calls an unqualified `[~]` a grammar error of unknown state; the
  # group tally called it closed. One typo produced two errors, the second
  # accusing a header that is correct — and it evaporates the moment the author
  # fixes the first the honest way, by writing `- [ ] 1.1`. validate-mode.md:
  # not computable must never dress up as a finding.
  write_doc <<'TASKS'
## Task List

- [ ] 1 - The group
  - _Complexity: Trivial | Tests: None_
  - [~] 1.1 - Something
    - Validation: `true`

## Quality Gates
- Tests pass
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.errors == 1' > /dev/null
  echo "$output" | jq -e '.error_details[0] | contains("no qualifier")' > /dev/null
  echo "$output" | jq -e '[.error_details[] | select(contains("group 1 is"))] | length == 0' > /dev/null
}

@test "10.3 the message names the group as it is spelled, not as it is keyed" {
  # `10#` normalises `08` to 8 so it can be an array subscript. That is right
  # for keying and wrong for the message: grepping the file for the reported
  # number would not find the line it names.
  write_doc <<'TASKS'
## Task List

- [ ] 08 - Padded eight
  - _Complexity: Trivial | Tests: None_
  - [x] 08.1 - done
    - Validation: `true`

## Quality Gates
- Tests pass
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '[.error_details[] | select(contains("group 08 is open"))] | length == 1' > /dev/null
}

@test "10.3 an absurd group number cannot kill the emitter" {
  # A number past 2^63 wraps to a negative array subscript, which bash treats as
  # fatal. Under `set -euo pipefail` the script died emitting NOTHING — no JSON,
  # no message, exit 1 — and every consumer of this script parses that JSON.
  # Unrealistic input; total failure is the point.
  write_doc <<'TASKS'
## Task List

- [ ] 9223372036854775808 - Huge
  - _Complexity: Trivial | Tests: None_
  - [x] 9223372036854775808.1 - done
    - Validation: `true`

## Quality Gates
- Tests pass
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  # Whatever the verdict, the contract is that a parseable document is emitted.
  echo "$output" | jq -e . > /dev/null
  echo "$output" | jq -e 'has("status") and has("errors")' > /dev/null
}

# --- 10.3 fix cycle 2: the exclusion must not be section arithmetic ----------
# Cycle 1 stopped the Quality Gates section from overwriting group headers by
# scoping the gathering to `## Task List`. That traded one defect for three,
# all of the same kind: deciding where a markdown section ENDS is genuinely
# hard, and every way of getting it wrong is silent. A decorated or
# differently-cased heading fell back to whole-document scope; a `###` Quality
# Gates never terminated the scope; and any column-0 `#` line — a shell comment
# in a fenced block, say — truncated it for the rest of the file.
#
# The cases below pin the inverted criterion: gather group state EVERYWHERE
# EXCEPT from the `Quality Gates` heading onward (any level, any case) and
# except inside fenced code blocks. Two rules, no section arithmetic, and no
# dependence on how `## Task List` happens to be spelled.

@test "10.3 a decorated Task List heading does not change the verdict" {
  # `## Task List (1 group)` used to fall back to whole-document scope, where
  # the numbered gate below was read as a second header for group 3.
  write_doc <<'TASKS'
## Task List (1 group)

- [x] 3 - Group three
  - _Complexity: Trivial | Tests: None_
  - [x] 3.1 - done
    - Validation: `true`

## Quality Gates
- [ ] 3 - Coverage >= 80%
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "pass"' > /dev/null
}

@test "10.3 a differently-cased Task List heading does not change the verdict" {
  write_doc <<'TASKS'
## Task list

- [x] 3 - Group three
  - _Complexity: Trivial | Tests: None_
  - [x] 3.1 - done
    - Validation: `true`

## Quality Gates
- [ ] 3 - Coverage >= 80%
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "pass"' > /dev/null
}

@test "10.3 Quality Gates is excluded at any heading level" {
  # `### Quality Gates` passes the validator's own presence check, which is
  # case-insensitive and level-agnostic. The exclusion must be too, or the two
  # disagree about where the gates are.
  write_doc <<'TASKS'
## Task List

- [x] 3 - Group three
  - _Complexity: Trivial | Tests: None_
  - [x] 3.1 - done
    - Validation: `true`

### Quality Gates
- [ ] 3 - Coverage >= 80%
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "pass"' > /dev/null
}

@test "10.3 a fenced code block does not truncate the gathering" {
  # The false-NEGATIVE direction, and the dangerous one: group 2 is the exact
  # shape the rule exists to catch, and a `#` comment inside a fence made it
  # vanish with no error, no warning and no trace in the JSON.
  write_doc <<'TASKS'
## Task List

- [x] 1 - Group one
  - _Complexity: Trivial | Tests: None_
  - [x] 1.1 - done
    - Validation: `true`

```bash
# regenerate the fixtures
make fixtures
```

- [x] 2 - Group two
  - [ ] 2.1 - still open
    - Validation: `true`

## Quality Gates
- Tests pass
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '[.error_details[] | select(contains("group 2 is closed"))] | length == 1' > /dev/null
}

@test "10.3 a checkbox inside a fenced block is not a group header" {
  # The converse of the case above. Fences are excluded in BOTH directions: an
  # illustrative task list inside a code block is documentation, not a claim.
  write_doc <<'TASKS'
## Task List

- [x] 1 - Group one
  - _Complexity: Trivial | Tests: None_
  - [x] 1.1 - done
    - Validation: `true`

```markdown
- [ ] 1 - how a group header is written
```

## Quality Gates
- Tests pass
TASKS
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "pass"' > /dev/null
}

@test "10.3 three headers for one number name all three lines" {
  # The duplicate message renders a list, and a list rendered from a
  # space-joined string is the kind of thing that works for two and breaks for
  # three. Pinned rather than believed.
  #
  # This one is a GUARD, not a hostile half: three-header rendering was already
  # correct when the case was written, so its Red is by removal, not by
  # precedence — same standing as the number-prefix case above.
  #
  # The expected line numbers are derived from the fixture rather than written
  # in, because a hard-coded pointer into a file the test itself generates is
  # exactly the drift this story has spent four groups repairing.
  write_doc <<'TASKS'
## Task List

- [ ] 1 - First
  - [x] 1.1 - done
    - Validation: `true`
- [x] 1 - Second
  - [x] 1.2 - done
    - Validation: `true`
- [x] 1 - Third
  - [x] 1.3 - done
    - Validation: `true`

## Quality Gates
- Tests pass
TASKS
  expected=$(grep -n -- '- \[.\] 1 - ' "$STORY/tasks.md" | cut -d: -f1 | paste -sd, - | sed 's/,/, /g')
  [ "$(echo "$expected" | tr -cd ',' | wc -c)" -eq 2 ]   # the fixture really has three
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '[.error_details[] | select(contains("more than one header"))] | length == 1' > /dev/null
  echo "$output" | jq --arg e "lines $expected" -e '.error_details[0] | contains($e)' > /dev/null
}
