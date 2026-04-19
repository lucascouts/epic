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
