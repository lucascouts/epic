#!/usr/bin/env bats
# Story 004, sub-task 5.3 — census regression pin for hook-precompact.sh (R3.5).
#
# hook-precompact.sh holds the FIFTH copy of the checkbox regex, and it is the
# only script that actually *renders* progress: its snapshot is injected into
# the model's context after a compaction. A drifted copy here does not fail a
# build — it quietly feeds the model a wrong progress number, which is exactly
# the lying-progress class story 004 exists to kill. Before this suite it was
# the one consumer with no automated coverage.
#
# These tests are regression PINS, not TDD: the implementation already carries
# the correct census (commit edbb8e5). They fail if a future maintainer widens,
# narrows or re-derives it.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY_DIR="$WORK/proj/.epic/stories/010-census"
  mkdir -p "$STORY_DIR"
}

teardown() {
  rm -rf "$WORK"
}

# Write tasks.md from stdin, run the hook, leave the Progress line in $output.
run_census() {
  cat > "$STORY_DIR/tasks.md"
  cd "$WORK/proj"
  run bash "$PLUGIN_ROOT/scripts/hook-precompact.sh"
  [ "$status" -eq 0 ]
  run grep '^- Tasks:' "$STORY_DIR/.draft/compact-snapshot.md"
  [ "$status" -eq 0 ]
}

@test "R3.5: mixed fixture — closed is [x] plus terminal [~], deferred counted apart" {
  run_census <<'EOF'
## Task List
- [x] 1.1 - Done
- [ ] 1.2 - Open
- [~] 1.3 - Waived gate (waived: tool absent)
- [~] 1.4 - External proof (deferred: real hardware)
- [~] 1.5 - Not applicable (n-a: by construction)
EOF
  # total = 5 · closed = [x] 1.1 + terminal [~] 1.3, 1.5 = 3 · deferred = 1
  [ "$output" = "- Tasks: 3/5 completed (+1 deferred)" ]
}

@test "R3.5: the (+N deferred) suffix appears only when a deferred box exists" {
  run_census <<'EOF'
## Task List
- [x] 1.1 - Done
- [ ] 1.2 - Open
- [~] 1.3 - Waived gate (waived: tool absent)
EOF
  [ "$output" = "- Tasks: 2/3 completed" ]
}

@test "R3.5: a story whose only open boxes are terminal [~] reads fully closed" {
  # The corpus's #1 false signal: a waived gate used to render 3/4 forever.
  run_census <<'EOF'
## Task List
- [x] 1.1 - Done
- [x] 1.2 - Done
- [x] 1.3 - Done
- [~] 1.4 - Waived gate (waived: user decision)
EOF
  [ "$output" = "- Tasks: 4/4 completed" ]
}

@test "R3.5: done-except-external — no [ ] remains, deferred still reported apart" {
  run_census <<'EOF'
## Task List
- [x] 1.1 - Done
- [x] 1.2 - Done
- [~] 1.3 - Waived gate (waived: tool absent)
- [~] 1.4 - External proof (deferred: real hardware)
EOF
  [ "$output" = "- Tasks: 3/4 completed (+1 deferred)" ]
}

@test "precedence: a line carrying both deferred: and a terminal qualifier counts as deferred" {
  # Must match validate-story.sh's census (deviations.yaml, task 1.1): deferred
  # wins, because deferred work is not actually finished.
  run_census <<'EOF'
## Task List
- [x] 1.1 - Done
- [~] 1.2 - Ambiguous (deferred: hardware) (waived: also this)
EOF
  [ "$output" = "- Tasks: 1/2 completed (+1 deferred)" ]
}

@test "R5.1: a legacy story with no [~] renders exactly as it did pre-change" {
  run_census <<'EOF'
## Task List
- [x] 1 - Group
  - [x] 1.1 - implement first
  - [ ] 1.2 - implement second
EOF
  # Pre-change: TOTAL counted `[ x]`, DONE counted `[x]` — same three boxes,
  # same two closed, and no suffix because no deferred box can exist.
  [ "$output" = "- Tasks: 2/3 completed" ]
}

@test "no .epic directory: the hook exits 0 and writes nothing" {
  mkdir -p "$WORK/bare"
  cd "$WORK/bare"
  run bash "$PLUGIN_ROOT/scripts/hook-precompact.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
