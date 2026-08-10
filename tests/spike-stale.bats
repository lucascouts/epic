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
# monitor-stale.sh has TWO invocation shapes, and this file covers both with
# opposite rules about the exit code:
#   - NO ARGUMENT is the long-running monitor (find + sleep loop, opt-in via
#     env). Those cases run one iteration by killing it with `timeout` after the
#     first pass and assert stdout only — 124 there is the killer's verdict, not
#     the script's, so asserting it would prove nothing about the script.
#   - `--once` is one synchronous pass that returns on its own. Those cases
#     (below the sub-task 5.2 divider) DO assert the status, 0 or 2, and that
#     assertion is the load-bearing half of their "one pass, never the loop"
#     claim. `timeout` survives there only as a hang guard.
# This note claimed the exit code was never asserted until sub-task 5.4
# corrected it; the `--once` cases that made it false arrived two sub-tasks
# earlier.

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
  # NOTHING is emitted here, and the assertion below is the reachable half of
  # that. The spike rule REPLACES the generic 7-day pending-tasks nag rather
  # than adding to it — monitor-stale.sh's spike branch ends in `continue`, so
  # this story never reaches the pending-work rule at all — and 13 days is under
  # the 14-day spike threshold, so the spike branch itself prints nothing
  # either. The case still asserts only the absence of the spike line, because
  # the threshold flip is what it exists to pin.
  ! echo "$output" | grep -qi 'spike'
}

@test "wont-do spike untouched for 15 days is NOT spike-flagged" {
  write_spike_aged "wont-do" "15 days ago"
  run_monitor_once
  ! echo "$output" | grep -qi 'spike'
}

# --- Sub-task 5.2 — the `--once` entry point ----------------------------
# Everything above drives the LOOP: no argument, killed by `timeout`, exit code
# deliberately unasserted because 124 is the killer's verdict, not the script's.
# The cases below are the OTHER mode and invert that. `--once` is the only
# invocation the docs hand an agent (references/list-mode.md, README's
# "Background Monitors" section), it returns on its own, and until now nothing
# in this repo passed the script any argument at all.
#
# These characterize behaviour that already shipped, so Red could not come from
# absent behaviour. Each case was instead proved able to fail by mutating
# scripts/monitor-stale.sh, watching that one case redden, and reverting —
# recorded in the story 007 red evidence as `red_via: mutation`.

# Second invocation shape. Deliberately NOT a tweak of run_monitor_once():
# that helper forces enableStaleMonitor on and is load-bearing for the three
# assertions above, whereas these cases need the option set both ways and need
# the script's own exit status. `timeout` survives here only as a HANG GUARD —
# a `--once` that fell through into `while true` would hang the suite forever
# instead of failing, and the guard turns that hang into a visible status 124.
# It is never the expected outcome: every case below asserts a real status.
run_monitor_arg() {
  cd "$WORK"
  run timeout 3 bash "$PLUGIN_ROOT/scripts/monitor-stale.sh" "$@"
}

@test "--once emits the spike notice and exits 0 without entering the loop" {
  # Delete this and the entry point references/list-mode.md and README tell
  # callers to run is covered by nothing. The STATUS assertion is the
  # load-bearing half: the hang guard kills a looping script only AFTER its
  # first pass has printed, so a stdout-only check would still pass even if the
  # script never returned. `0` rather than the guard's `124` IS the "one pass,
  # then exit — never the loop" half of the contract.
  # enableStaleMonitor is true here on purpose: it isolates this case to the
  # mode contract and leaves the gate-bypass claim to the next case.
  write_spike_aged "open" "15 days ago"
  export CLAUDE_PLUGIN_OPTION_ENABLESTALEMONITOR=true
  run_monitor_arg --once
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'spike'
}

@test "--once ignores enableStaleMonitor=false on purpose" {
  # This is the task 2.3 deviation's own claim, and nothing asserted it before:
  # `--once` answers whether or not the watcher was ever enabled, because that
  # option governs the thing that polls unasked while R1.5 asks for the spike
  # flag in the story list unconditionally. false is the DEFAULT-INSTALL value,
  # so this is the shape every real caller hits.
  # Delete this and the opt-in gate can be "simplified" back above the Mode
  # block — the move monitor-stale.sh's own comment warns against — with the
  # suite still green, silently leaving R1.5 unmet for everyone who never
  # opted into being notified in their sleep.
  write_spike_aged "open" "15 days ago"
  export CLAUDE_PLUGIN_OPTION_ENABLESTALEMONITOR=false
  run_monitor_arg --once
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
