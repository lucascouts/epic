#!/usr/bin/env bats
# Story 014, Task 2.1 — the `(satisfied-by: <artifact>)` suffix, honored by
# BOTH orphan sites.
# Contract (R2.1-R2.3):
#   - A criterion leaf ending `(satisfied-by: <artifact>)` is satisfied, not
#     orphaned, in scripts/cross-reference.sh AND in validate-story.sh's
#     --cross-ref gate (R2.1, R2.2).
#   - cross-reference.sh reports such leaves under a new list key, with the
#     `status` enum unchanged — a story whose only untraced leaf is
#     satisfied-by is `clean` (R2.2).
#   - An EMPTY artifact is a warning: the class legalizes a deliverable, not a
#     blank (R2.3).
#   - Phantom detection is untouched: a task reference matching no story leaf
#     stays a phantom regardless of satisfied-by grammar in the story (PIN).
#
# The new-list-key assertion matches `satisfied` with a flexible separator so
# it pins the behavior (the leaf is REPORTED, not dropped), not one spelling.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/story"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

# Story with one code-satisfied leaf (R1.1) and one leaf whose deliverable is
# the artifact named by the suffix (R1.2, referenced by no task on purpose).
write_satisfied_by_story() { # $1 = the satisfied-by leaf line
  cat > "$STORY/story.md" <<EOF
---
story: satisfied-by-fixture
type: feature
scale: standard
version: 1
created: 2026-08-16
---

## Introduction
satisfied-by fixture.

### R1. First requirement

#### Acceptance Criteria

- R1.1: WHEN x THE SYSTEM SHALL y
$1
EOF
}

write_tasks_md() { # $1 = Requirements list
  cat > "$STORY/tasks.md" <<EOF
---
version: 1
created: 2026-08-16
---

## Task List
- [ ] 1.1 - implement
  - Requirements: $1
  - Validation: \`echo ok\`

## Quality Gates
- Done
EOF
}

@test "2.1: cross-reference.sh — a satisfied-by leaf is not an orphan and the report stays clean" {
  write_satisfied_by_story '- R1.2: THE SYSTEM SHALL keep the regression guarded (satisfied-by: tests/regression.bats)'
  write_tasks_md "R1.1"
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  # The leaf is satisfied, so the story is clean and exits 0 — the status enum
  # is unchanged, `clean` covers it (R2.2).
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "clean"'
  echo "$output" | grep -qF '"orphan_requirements": []'
  # The leaf is reported, not dropped: a new list key names it (R2.2).
  echo "$output" | grep -qiE '"satisfied[_-]?by"'
  SATLINE=$(echo "$output" | grep -iE '"satisfied[_-]?by"')
  echo "$SATLINE" | grep -q 'R1.2'
}

@test "2.1: validate --cross-ref — a satisfied-by leaf draws no orphan warning" {
  write_satisfied_by_story '- R1.2: THE SYSTEM SHALL keep the regression guarded (satisfied-by: tests/regression.bats)'
  write_tasks_md "R1.1"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY" --cross-ref
  echo "$output" | jq -e . > /dev/null
  # Pre-change this emits "Requirement R1.2 in story.md has no matching
  # reference in tasks.md" — the satisfied leaf must not be advised about.
  if echo "$output" | jq -r '.warning_details[]' | grep -E 'R1\.2' | grep -q 'no matching reference'; then
    echo "R1.2 carries a satisfied-by suffix and still drew the orphan advisory"
    return 1
  fi
}

@test "2.1: an empty satisfied-by artifact is a warning" {
  write_satisfied_by_story '- R1.2: THE SYSTEM SHALL keep the regression guarded (satisfied-by: )'
  write_tasks_md "R1.1"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY" --cross-ref
  echo "$output" | jq -e . > /dev/null
  # The class legalizes a deliverable, not a blank (R2.3): a warning names the
  # suffix so the author can fill it in.
  echo "$output" | jq -r '.warning_details[]' | grep -qi 'satisfied-by'
}

@test "2.1: PIN a task reference matching no story leaf is still a phantom beside satisfied-by grammar" {
  write_satisfied_by_story '- R1.2: THE SYSTEM SHALL keep the regression guarded (satisfied-by: tests/regression.bats)'
  write_tasks_md "R1.1, R9.9"
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  # The suffix legalizes a STORY leaf with a non-code deliverable; it must not
  # make the task side lax — R9.9 names nothing and stays a phantom.
  [ "$status" -eq 1 ]
  echo "$output" | grep -qF '"phantom_references": ["R9.9"]'
}
