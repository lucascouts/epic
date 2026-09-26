#!/usr/bin/env bats
# `[~]` awareness in scripts/monitor-stale.sh: staleness treats ONLY `[ ]` as
# pending work. A story whose only non-[x] boxes are `[~]` is never reported
# stale; a story with a real `[ ]` box still is.

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

# One pass of the stale check with a 7-day story threshold.
run_monitor_once() {
  run timeout 5 bash "$PLUGIN_ROOT/scripts/monitor-stale.sh" --story-days 7
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
  [ "$status" -eq 0 ]
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
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '001-teste'
  echo "$output" | grep -q 'pending tasks'
}
