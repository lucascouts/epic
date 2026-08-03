#!/usr/bin/env bats
# Story 004, sub-task 2.1 — `[~]` sub-task headings in scripts/cross-reference.sh.
# Contract under test (R4.2):
#   - A `[~]` sub-task heading with a `Requirements:` field keeps attributing
#     its R-numbers in the traceability mapping — deferring a sub-task must
#     never turn its requirements into orphans.
#   - `[~]` headings count as parseable tasks.
#   - Legacy fixtures (no `[~]`) behave exactly as before.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/story"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

@test "R4.2: a deferred [~] sub-task still attributes its Requirements in the mapping" {
  cat > "$STORY/story.md" <<'EOF'
### R1. First requirement
#### Acceptance Criteria
- R1.1: WHEN x THE SYSTEM SHALL y
- R1.2: WHEN a THE SYSTEM SHALL b
EOF
  cat > "$STORY/tasks.md" <<'EOF'
- [x] 1.1 - implement
  - Requirements: R1.1
- [~] 1.2 - hardware proof (deferred: hw)
  - Requirements: R1.2
EOF
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "clean"'
  echo "$output" | grep -qF '"orphan_requirements": []'
  echo "$output" | grep -qF '"R1.2": ["1.2"]'
}

@test "R4.2: [~] headings count as parseable tasks" {
  cat > "$STORY/story.md" <<'EOF'
### R1. First requirement
#### Acceptance Criteria
- R1.1: WHEN x THE SYSTEM SHALL y
- R1.2: WHEN a THE SYSTEM SHALL b
EOF
  cat > "$STORY/tasks.md" <<'EOF'
- [x] 1.1 - implement
  - Requirements: R1.1
- [~] 1.2 - waived gate (waived: tool absent)
  - Requirements: R1.2
EOF
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '"parseable_tasks": 2'
}

@test "legacy: story with no [~] keeps its pre-change traceability behavior" {
  cat > "$STORY/story.md" <<'EOF'
### R1. First requirement
#### Acceptance Criteria
- R1.1: WHEN x THE SYSTEM SHALL y
EOF
  cat > "$STORY/tasks.md" <<'EOF'
- [ ] 1.1 - implement
  - Requirements: R1.1
EOF
  run bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "clean"'
  echo "$output" | grep -qF '"parseable_tasks": 1'
}
