#!/usr/bin/env bats
# Story 007, Task 2.3 — spike staleness threshold (R1.5).
# Contract (design Integration Points): monitor-stale.sh gains a spike
# threshold (14 days on tasks.md mtime) alongside the existing story
# threshold. An OPEN spike untouched for >14 days emits a spike-specific
# staleness notice ("promote or close" pressure); 13 days does not; a
# terminal Verdict never does.
#
# Note on surface: the LIST-row rendering of the flag lives in
# references/list-mode.md (agent-executed doc, not script-testable). This
# file pins the computable half of R1.5 — the 13d/15d threshold flip —
# on the script surface design assigns it to.
#
# monitor-stale.sh is a long-running monitor (find + sleep loop, opt-in via
# env). Tests run one iteration by killing it with `timeout` after the first
# pass; only stdout is asserted, never the (timeout-induced 124) exit code.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  SPIKE_DIR="$WORK/.epic/stories/031-probe-cache"
  mkdir -p "$SPIKE_DIR"
}

teardown() {
  rm -rf "$WORK"
}

# $1 = Verdict status line content; $2 = age for touch -d.
write_spike_aged() {
  cat > "$SPIKE_DIR/tasks.md" <<EOF
---
story: probe-cache
type: feature
scale: spike
version: 1
created: 2026-07-01
---

## Task List
- [ ] 1 - Benchmark cold vs warm path
  - Validation: \`./bench.sh\`

## Verdict
- status: $1
- conclusion: pending
EOF
  touch -d "$2" "$SPIKE_DIR/tasks.md"
}

run_monitor_once() {
  cd "$WORK"
  export CLAUDE_PLUGIN_OPTION_ENABLESTALEMONITOR=true
  run timeout 3 bash "$PLUGIN_ROOT/scripts/monitor-stale.sh"
}

@test "open spike untouched for 15 days emits a spike staleness notice" {
  write_spike_aged "open" "15 days ago"
  run_monitor_once
  # Spike-specific line: names the spike shape, not just the generic
  # pending-tasks message (story dir name deliberately avoids 'spike').
  echo "$output" | grep -qi 'spike'
}

@test "open spike untouched for 13 days is NOT spike-flagged" {
  write_spike_aged "open" "13 days ago"
  run_monitor_once
  # The generic 7-day pending-tasks notice may appear; the spike-specific
  # 14-day notice must not.
  ! echo "$output" | grep -qi 'spike'
}

@test "wont-do spike untouched for 15 days is NOT spike-flagged" {
  write_spike_aged "wont-do" "15 days ago"
  run_monitor_once
  ! echo "$output" | grep -qi 'spike'
}
