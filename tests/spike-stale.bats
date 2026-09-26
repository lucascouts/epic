#!/usr/bin/env bats
# Spike staleness threshold.
# Contract: monitor-stale.sh applies a spike threshold (14 days on tasks.md
# mtime) alongside the story threshold. An OPEN spike untouched for >14 days emits a spike-specific
# staleness notice ("promote or close" pressure); 13 days does not; a
# terminal Verdict never does.
#
# Note on surface: the LIST-row rendering of the flag lives in
# references/list-mode.md (agent-executed doc, not script-testable). This
# file pins the computable half — the 13d/15d threshold flip — on the
# script surface.
#
# Every run of monitor-stale.sh is one synchronous pass. The no-argument cases
# assert stdout only; the argument-driven cases (below the `--once` divider)
# also assert the status, 0 or 2. `timeout` is only a hang guard.

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
  run timeout 5 bash "$PLUGIN_ROOT/scripts/monitor-stale.sh"
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
  # NOTHING is emitted here, and the assertion below is the reachable half of
  # that. The spike rule REPLACES the generic 7-day pending-tasks nag rather
  # than adding to it — monitor-stale.sh's spike branch ends in `continue`, so
  # this story never reaches the pending-work rule at all — and 13 days is under
  # the 14-day spike threshold, so the spike branch itself prints nothing
  # either. The case still asserts only the absence of the spike line, because
  # the threshold flip is what it exists to pin.
  if echo "$output" | grep -qi 'spike'; then
    return 1
  fi
}

@test "wont-do spike untouched for 15 days is NOT spike-flagged" {
  write_spike_aged "wont-do" "15 days ago"
  run_monitor_once
  if echo "$output" | grep -qi 'spike'; then
    return 1
  fi
}

# --- The `--once` entry point and the other arguments --------------------
# Everything above runs without arguments and asserts stdout only. The cases
# below pass arguments, the way the story list does (references/list-mode.md),
# and also assert the exit status.
#
# These characterize existing behaviour, so each case's ability to fail is
# shown by mutating scripts/monitor-stale.sh and watching that case redden.

# Argument-driven invocations; `timeout` is only a hang guard.
run_monitor_arg() {
  cd "$WORK"
  run timeout 3 bash "$PLUGIN_ROOT/scripts/monitor-stale.sh" "$@"
}

@test "--once emits the spike notice and exits 0" {
  # `--once` is accepted, and every run is one pass that exits 0.
  write_spike_aged "open" "15 days ago"
  run_monitor_arg --once
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'spike'
}

@test "--spike-days moves the spike deadline; a non-numeric value falls back to 14" {
  # The list passes the user's spikeStaleThresholdDays by argument, because a
  # command run through the Bash tool receives no plugin options. An unsaved
  # option reaches the list as its literal placeholder, which must not break it.
  write_spike_aged "open" "15 days ago"
  run_monitor_arg --spike-days 20
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run_monitor_arg --spike-days '${user_config.spikeStaleThresholdDays}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'spike'
}

@test "an unknown argument exits 2 and prints the usage text" {
  # The third arm of the argument contract, and the one that keeps a typo
  # loud. Delete it and that arm can quietly become an `exit 0`: with a stale
  # spike sitting right there in the fixture, `--onse` would then produce
  # exactly what a repo with nothing to report produces — an empty listing and
  # a success status — so the list would render no flag and no one would learn
  # why. Status 2 is what makes the difference legible to the caller.
  write_spike_aged "open" "15 days ago"
  run_monitor_arg --onse
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'Usage: monitor-stale.sh'
}
