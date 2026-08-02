#!/usr/bin/env bats
# Unit tests for scripts/cross-reference.sh. Covers:
#   - Help and invalid-input exit codes
#   - Model B (group header `### Rn.` + leaf criteria `Rn.m`): a heading must
#     NOT be reported as an orphan requirement (the traceability fix)
#   - Model A (flat one-level `### Rn` requirements): backward compatibility
#   - Orphan and phantom detection at the requirement-leaf level

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
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" --help
  [ "$status" -eq 0 ]
}

@test "non-existent directory exits 2" {
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" /definitely/does/not/exist
  [ "$status" -eq 2 ]
}

@test "missing story.md exits 2" {
  echo '- [ ] 1.1 - do' > "$STORY/tasks.md"
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 2 ]
}

@test "missing tasks.md exits 2" {
  echo '### R1. First' > "$STORY/story.md"
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 2 ]
}

@test "model B: group heading is not counted as an orphan" {
  cat > "$STORY/story.md" <<'EOF'
### R1. First requirement
#### Acceptance Criteria
- R1.1: WHEN x THE SYSTEM SHALL y
- R1.2: WHEN a THE SYSTEM SHALL b
EOF
  cat > "$STORY/tasks.md" <<'EOF'
- [ ] 1.1 - implement
  - Requirements: R1.1, R1.2
EOF
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "clean"'
  echo "$output" | grep -qF '"orphan_requirements": []'
}

@test "model B: an uncovered leaf criterion is an orphan" {
  cat > "$STORY/story.md" <<'EOF'
### R1. First requirement
#### Acceptance Criteria
- R1.1: WHEN x THE SYSTEM SHALL y
- R1.2: WHEN a THE SYSTEM SHALL b
EOF
  cat > "$STORY/tasks.md" <<'EOF'
- [ ] 1.1 - implement
  - Requirements: R1.1
EOF
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qF '"orphan_requirements": ["R1.2"]'
}

@test "model B: a task reference with no story criterion is a phantom" {
  cat > "$STORY/story.md" <<'EOF'
### R1. First requirement
#### Acceptance Criteria
- R1.1: WHEN x THE SYSTEM SHALL y
EOF
  cat > "$STORY/tasks.md" <<'EOF'
- [ ] 1.1 - implement
  - Requirements: R1.1, R9.9
EOF
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qF '"phantom_references": ["R9.9"]'
}

@test "model A: a flat one-level requirement is traced clean" {
  cat > "$STORY/story.md" <<'EOF'
### R1
WHEN x THE SYSTEM SHALL y.
EOF
  cat > "$STORY/tasks.md" <<'EOF'
- [ ] 1 - implement
  - Requirements: R1
EOF
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "clean"'
}

@test "model A: an uncovered one-level requirement is an orphan" {
  cat > "$STORY/story.md" <<'EOF'
### R1
WHEN x THE SYSTEM SHALL y.
### R2
WHEN a THE SYSTEM SHALL b.
EOF
  cat > "$STORY/tasks.md" <<'EOF'
- [ ] 1 - implement
  - Requirements: R1
EOF
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qF '"orphan_requirements": ["R2"]'
}

@test "mapping: lists the sub-task that declares each requirement" {
  cat > "$STORY/story.md" <<'EOF'
### R1. First
#### Acceptance Criteria
- R1.1: WHEN x THE SYSTEM SHALL y
- R1.2: WHEN a THE SYSTEM SHALL b
EOF
  cat > "$STORY/tasks.md" <<'EOF'
- [ ] 1 - Group
  - [ ] 1.1 - implement A
    - Requirements: R1.1
  - [ ] 1.2 - implement B
    - Requirements: R1.2
EOF
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '"R1.1": ["1.1"]'
  echo "$output" | grep -qF '"R1.2": ["1.2"]'
}

@test "mapping: an orphan requirement maps to an empty array" {
  cat > "$STORY/story.md" <<'EOF'
### R1. First
#### Acceptance Criteria
- R1.1: WHEN x THE SYSTEM SHALL y
- R1.2: WHEN a THE SYSTEM SHALL b
EOF
  cat > "$STORY/tasks.md" <<'EOF'
- [ ] 1.1 - implement A
  - Requirements: R1.1
EOF
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qF '"R1.2": []'
}

@test "mapping: a requirement shared by two sub-tasks lists both" {
  cat > "$STORY/story.md" <<'EOF'
### R1. First
#### Acceptance Criteria
- R1.1: WHEN x THE SYSTEM SHALL y
EOF
  cat > "$STORY/tasks.md" <<'EOF'
- [ ] 1.1 - implement
  - Requirements: R1.1
- [ ] 2.1 - integrate
  - Requirements: R1.1
EOF
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '"R1.1": ["1.1","2.1"]'
}

# --- Wave-0 regressions: coverage must derive from the structural parse ---

@test "prose-only reference is NOT traced (false-clean regression)" {
  cat > "$STORY/story.md" <<'STORY'
### R1. First requirement
- R1.1: WHEN x THE SYSTEM SHALL y
- R1.2: WHEN a THE SYSTEM SHALL b
STORY
  cat > "$STORY/tasks.md" <<'TASKS'
## Overview
This plan covers R1.2 in prose only.
- [ ] 1.1 - implement
  - Requirements: R1.1
  - ToDo: also touches R1.2 (mentioned outside any Requirements field)
TASKS
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q '"status": "issues"'
  echo "$output" | grep -q '"R1.2"'
  echo "$output" | grep -q '"coverage": "1/2"'
}

@test "unrecognized tasks.md dialect reports untraceable-format, never clean" {
  cat > "$STORY/story.md" <<'STORY'
### R1. First requirement
- R1.1: WHEN x THE SYSTEM SHALL y
STORY
  cat > "$STORY/tasks.md" <<'TASKS'
## T1. Heading-style task
### T1.1 Do the thing [x]
- **Covers:** R1.1
TASKS
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q '"status": "untraceable-format"'
  echo "$output" | grep -q '"parseable_tasks": 0'
}

@test "report includes parseable_tasks count" {
  cat > "$STORY/story.md" <<'STORY'
### R1. First requirement
- R1.1: WHEN x THE SYSTEM SHALL y
STORY
  cat > "$STORY/tasks.md" <<'TASKS'
- [ ] 1.1 - implement
  - Requirements: R1.1
TASKS
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"parseable_tasks": 1'
}
