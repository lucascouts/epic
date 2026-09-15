#!/usr/bin/env bats
# Story 014, Task 1.1 — EARS form checks in scripts/validate-story.sh.
# Contract (R1.1-R1.3, R1.5):
#   - A criterion bullet under an Acceptance Criteria heading with no `Rn.m`
#     label is an ERROR naming the line (R1.1).
#   - A labeled criterion carrying more than one SHALL is a WARNING naming the
#     line (R1.2).
#   - A labeled criterion with no EARS trigger (WHEN/WHILE/WHERE/IF) that does
#     not open with the ubiquitous form is a WARNING whose text names
#     `THE SYSTEM SHALL` as the accepted exception (R1.3).
#   - The ubiquitous form itself is silent (R1.3), and a fenced example is
#     never scanned (R1.5).
# Scale gating (R1.4) and the wider immunity set are asserted in
# tests/ears-lint-immunity.bats — not duplicated here.
#
# Assertions are behavior-level on message content, never on exact wording
# beyond what the requirements themselves promise (the line number, the
# warning/error split, the named ubiquitous form). Cases whose names carry
# `PIN` pass against the pre-change validator and must stay green.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/story"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

# Standard-scale story.md whose Acceptance Criteria block is the argument.
write_story_criteria() {
  cat > "$STORY/story.md" <<EOF
---
story: ears-lint-fixture
type: feature
scale: standard
version: 1
created: 2026-08-16
---

## Introduction
EARS form lint fixture.

### R1. First requirement

#### Acceptance Criteria

$1
EOF
}

write_tasks_md() {
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
---

## Task List
- [ ] 1 - Implement
  - Requirements: R1.1
  - Validation: `echo ok`

## Quality Gates
- Done
EOF
}

@test "1.1: unlabeled criterion under Acceptance Criteria is an error naming the line" {
  write_story_criteria '- R1.1: WHEN x THE SYSTEM SHALL y.
- WHEN the user saves THE SYSTEM SHALL persist the draft.'
  write_tasks_md
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  echo "$output" | jq -e . > /dev/null
  # The offending bullet's line number, computed from the fixture itself so the
  # assertion survives fixture edits.
  LINE_NO=$(grep -n 'persist the draft' "$STORY/story.md" | cut -d: -f1)
  # An ERROR (not a warning): the unlabeled criterion is invisible to the whole
  # traceability chain, and the finding must name the line.
  DETAIL=$(echo "$output" | jq -r '.error_details[]' | grep -iE 'label|criterion')
  echo "$DETAIL" | grep -q "line $LINE_NO"
}

@test "1.1: a criterion carrying four SHALLs draws exactly one warning naming the line" {
  write_story_criteria '- R1.1: WHEN the form is submitted THE SYSTEM SHALL validate the fields, SHALL persist the record, SHALL emit the event, and SHALL redirect home.'
  write_tasks_md
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  echo "$output" | jq -e . > /dev/null
  # A compound criterion is untestable as one unit — but it is a WARNING, not
  # an error (the constraint limits error severity to R1.1).
  echo "$output" | jq -e '.errors == 0' > /dev/null
  LINE_NO=$(grep -n 'redirect home' "$STORY/story.md" | cut -d: -f1)
  MATCHES=$(echo "$output" | jq -r '.warning_details[]' | grep -c "line $LINE_NO")
  [ "$MATCHES" -eq 1 ]
  # The warning is about the SHALL count, not something else on that line.
  echo "$output" | jq -r '.warning_details[]' | grep "line $LINE_NO" | grep -qi 'SHALL'
}

@test "1.1: a trigger-less criterion warns, and the warning names the ubiquitous form" {
  write_story_criteria '- R1.1: The exporter SHALL write the report to disk.'
  write_tasks_md
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  echo "$output" | jq -e . > /dev/null
  echo "$output" | jq -e '.errors == 0' > /dev/null
  LINE_NO=$(grep -n 'write the report' "$STORY/story.md" | cut -d: -f1)
  # R1.3's own text: the ubiquitous form is legal EARS and the warning says so —
  # the accepted exception is named verbatim, so an author can self-correct.
  DETAIL=$(echo "$output" | jq -r '.warning_details[]' | grep "line $LINE_NO")
  echo "$DETAIL" | grep -q 'THE SYSTEM SHALL'
}

@test "1.1: PIN the ubiquitous form (THE SYSTEM SHALL ...) is silent" {
  write_story_criteria '- R1.1: THE SYSTEM SHALL reject a payload larger than the configured maximum.'
  write_tasks_md
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.errors == 0' > /dev/null
  # No finding lands on the criterion's line: the ubiquitous form is legal
  # EARS, not a trigger-less shape to be warned about.
  LINE_NO=$(grep -n 'reject a payload' "$STORY/story.md" | cut -d: -f1)
  if echo "$output" | jq -r '.warning_details[]' | grep -q "line $LINE_NO"; then
    echo "the ubiquitous form drew a finding on line $LINE_NO — it is legal EARS and must be silent"
    return 1
  fi
}

@test "1.1: PIN an unlabeled bullet inside a fenced example is never scanned" {
  write_story_criteria '- R1.1: WHEN x THE SYSTEM SHALL y.

An illustrative shape, fenced and therefore documentation (R1.5):

```markdown
#### Acceptance Criteria

- WHEN pasted from a doc THE SYSTEM SHALL not be linted.
```'
  write_tasks_md
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  # The fenced unlabeled bullet must not draw the R1.1 error — errors stay 0.
  echo "$output" | jq -e '.errors == 0' > /dev/null
}
