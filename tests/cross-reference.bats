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
