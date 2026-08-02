#!/usr/bin/env bats
# Regression tests for scripts/hook-task-completed.sh. Covers the wave-0
# fail-open fix: under set -e, the OUTPUT=$(validate-story.sh ...) assignment
# used to abort the hook with exit 1 on validation failure, so the blocking
# exit 2 never ran and TaskCompleted (which only blocks on 2) sailed through.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  mkdir -p "$WORK/proj/.epic/stories/001-teste"
}

teardown() {
  rm -rf "$WORK"
}

write_story() { # $1 = SHALL|SHOULD keyword to plant a pass/fail story
  cat > "$WORK/proj/.epic/stories/001-teste/story.md" <<STORY
---
version: 1
created: 2026-07-23
---
# Story
### R1. X
- R1.1 WHEN a THE SYSTEM $1 b
STORY
}

@test "no .epic/stories directory: exit 0 (no-op)" {
  cd "$WORK"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/scripts/hook-task-completed.sh"
  [ "$status" -eq 0 ]
}

@test "failing story blocks with exit 2 and surfaces the errors (fail-open regression)" {
  write_story "SHOULD"
  cat > "$WORK/proj/.epic/stories/001-teste/tasks.md" <<'TASKS'
---
version: 1
created: 2026-07-23
---
- [ ] 1 - One
TASKS
  cd "$WORK/proj"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/scripts/hook-task-completed.sh"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'failed validation'
  echo "$output" | grep -q 'Fix the reported issues'
}

@test "passing story allows completion with exit 0" {
  write_story "SHALL"
  cat > "$WORK/proj/.epic/stories/001-teste/tasks.md" <<'TASKS'
---
version: 1
created: 2026-07-23
---
## Quality Gates
- [ ] 1 - One
  - _Complexity: Trivial_
  - Requirements: R1.1
  - Validation: ok
  - Commit: feat: one
TASKS
  cd "$WORK/proj"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/scripts/hook-task-completed.sh"
  [ "$status" -eq 0 ]
}

@test "unset CLAUDE_PLUGIN_ROOT falls back to the script's own root (set -u regression)" {
  write_story "SHOULD"
  cat > "$WORK/proj/.epic/stories/001-teste/tasks.md" <<'TASKS'
---
version: 1
created: 2026-07-23
---
- [ ] 1 - One
TASKS
  cd "$WORK/proj"
  run env -u CLAUDE_PLUGIN_ROOT bash "$PLUGIN_ROOT/scripts/hook-task-completed.sh"
  [ "$status" -eq 2 ]
}
