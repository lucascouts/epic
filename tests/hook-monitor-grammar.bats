#!/usr/bin/env bats
# Story 004, sub-task 2.2 — `[~]` awareness in scripts/hook-task-completed.sh
# and scripts/monitor-stale.sh.
# Contract under test (R4.3 + hook phase-3 detection):
#   - The TaskCompleted hook recognizes a story whose task headings use `[~]`
#     as past Phase 3, so it still validates it (and blocks with exit 2 when
#     validation fails). Today the phase-3 regex only sees [ ]/[x], so a
#     [~]-marked story silently escapes validation.
#   - Staleness treats ONLY `[ ]` as pending work (R4.3): a story whose only
#     non-[x] boxes are `[~]` is never reported stale; a story with a real
#     `[ ]` box still is. These two scenarios pin the current (correct)
#     monitor-stale behavior against regression while its regex neighborhood
#     is edited.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  mkdir -p "$WORK/proj/.epic/stories/001-teste"
  STORY="$WORK/proj/.epic/stories/001-teste"
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

# One invocation of the monitor loop: enabled, 7-day threshold, killed by
# timeout after the first find_stale pass (exit 124 expected).
run_monitor_once() {
  run timeout 2 env \
    CLAUDE_PLUGIN_OPTION_ENABLESTALEMONITOR=true \
    CLAUDE_PLUGIN_OPTION_STALETHRESHOLDDAYS=7 \
    CLAUDE_PLUGIN_OPTION_STALECHECKINTERVALSECONDS=10 \
    bash "$PLUGIN_ROOT/scripts/monitor-stale.sh"
}

@test "hook validates a story whose task headings are [~] (phase-3 detection includes ~)" {
  # Failing story (SHOULD instead of SHALL) so a validated story blocks.
  cat > "$STORY/story.md" <<'EOF'
---
version: 1
created: 2026-08-02
---
# Story
### R1. X
- R1.1 WHEN a THE SYSTEM SHOULD b
EOF
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-02
---
- [~] 1 - One (waived: gate dispensed)
  - Requirements: R1.1
EOF
  cd "$WORK/proj"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/scripts/hook-task-completed.sh"
  # A [~]-marked story is past Phase 3: the hook must validate it and block
  # on the SHOULD error. Exit 0 here means the story escaped validation.
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'failed validation'
}

@test "R4.3: a story whose only open boxes are [~] is not reported stale" {
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-02
---
- [x] 1 - Done
- [~] 2 - Deferred proof (deferred: hardware)
EOF
  touch -d '30 days ago' "$STORY/tasks.md"
  cd "$WORK/proj"
  run_monitor_once
  [ "$status" -eq 124 ]
  refute_grep '001-teste'
}

@test "R4.3: a story with a real [ ] box untouched past the threshold is reported stale" {
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-02
---
- [x] 1 - Done
- [ ] 2 - Open work
EOF
  touch -d '30 days ago' "$STORY/tasks.md"
  cd "$WORK/proj"
  run_monitor_once
  [ "$status" -eq 124 ]
  echo "$output" | grep -q '001-teste'
  echo "$output" | grep -q 'pending tasks'
}
