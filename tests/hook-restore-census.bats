#!/usr/bin/env bats
# Census regression pin for hook-session-restore.sh.
#
# hook-session-restore.sh holds its own copy of the checkbox regex, and it is
# the only script that actually *renders* progress: its snapshot is injected
# into the model's context after a compaction. A drifted copy here does not
# fail a build — it quietly feeds the model a wrong progress number.
#
# These tests are regression PINS: they fail if a future maintainer widens,
# narrows or re-derives the census.

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
  run bash -c "bash '$PLUGIN_ROOT/scripts/hook-session-restore.sh' > '$WORK/snapshot.md'"
  [ "$status" -eq 0 ]
  run grep '^- Tasks:' "$WORK/snapshot.md"
  [ "$status" -eq 0 ]
}

@test "mixed fixture — closed is [x] plus terminal [~], deferred counted apart" {
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

@test "the (+N deferred) suffix appears only when a deferred box exists" {
  run_census <<'EOF'
## Task List
- [x] 1.1 - Done
- [ ] 1.2 - Open
- [~] 1.3 - Waived gate (waived: tool absent)
EOF
  [ "$output" = "- Tasks: 2/3 completed" ]
}

@test "a story whose only open boxes are terminal [~] reads fully closed" {
  # A waived gate must not keep the census short of fully closed.
  run_census <<'EOF'
## Task List
- [x] 1.1 - Done
- [x] 1.2 - Done
- [x] 1.3 - Done
- [~] 1.4 - Waived gate (waived: user decision)
EOF
  [ "$output" = "- Tasks: 4/4 completed" ]
}

@test "done-except-external — no [ ] remains, deferred still reported apart" {
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
  # Must match validate-story.sh's census: deferred
  # wins, because deferred work is not actually finished.
  run_census <<'EOF'
## Task List
- [x] 1.1 - Done
- [~] 1.2 - Ambiguous (deferred: hardware) (waived: also this)
EOF
  [ "$output" = "- Tasks: 1/2 completed (+1 deferred)" ]
}

@test "a qualifier with no space after the box still closes" {
  # `- [~]waived: …`. validate-story.sh reads this as a closed box: its box
  # regex does not require the space, and the qualifier is token-anchored, so
  # `]waived:` qualifies. The hook must count it the same way — one rule, one
  # answer.
  run_census <<'EOF'
## Task List
- [x] 1.1 - Done
- [~]waived: no rig on this host
- [ ] 1.3 - Open
EOF
  [ "$output" = "- Tasks: 2/3 completed" ]
}

@test "a legacy story with no [~] counts only its [x] boxes as closed" {
  run_census <<'EOF'
## Task List
- [ ] 1 - Group
  - [x] 1.1 - implement first
  - [ ] 1.2 - implement second
EOF
  # Three boxes, one closed, and no suffix because no deferred box can exist.
  # The group header stays open because a header that contradicts its own
  # sub-tasks is a validation error. The census is a pure function of the
  # boxes on disk.
  [ "$output" = "- Tasks: 1/3 completed" ]
}

@test "no .epic directory: the hook exits 0 and writes nothing" {
  mkdir -p "$WORK/bare"
  cd "$WORK/bare"
  run bash "$PLUGIN_ROOT/scripts/hook-session-restore.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
