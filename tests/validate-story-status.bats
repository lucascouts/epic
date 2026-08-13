#!/usr/bin/env bats
# Story 004, sub-task 1.2 — `status:` enum validation in scripts/validate-story.sh.
# Contract under test (R2.1–R2.4):
#   - status outside the enum (draft|in-progress|done|validated|superseded|
#     archived) is an ERROR naming the invalid value and the enum (R2.1).
#   - ABSENT status produces zero status-related errors or warnings — the
#     legacy hard contract (R2.2).
#   - status done|validated while a `[ ]` box remains warns "ahead of the
#     checkboxes" (R2.3).
#   - divergent status values across the story's artifacts warn, naming the
#     divergent files (R2.4).
#
# Story 006, sub-task 12.3 — the CONVERSE of the R2.3 warning (finding F2):
#   - status draft|in-progress while the census shows no open `[ ]` AND no
#     deferred `[~]` warns "behind the checkboxes" — rule 1 of
#     references/run-mode.md writes `done` at exactly that point, and until this
#     check existed the condition was PREVENTED rather than DETECTED, so a
#     prevention that silently failed to fire was reported by nothing.
#   - The hostile half is the DEFERRED arm, and it is the reason the census
#     carries BOX_DEFERRED at all: a deferred box blocks `done` deliberately, so
#     a story resting at `in-progress` with deferred work owed is CORRECT.
#     Folding deferred into closed makes that story warn falsely — the case
#     `12.3 hostile:` below is what reddens on the fold.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/story"
  mkdir -p "$STORY"
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

# Minimal warning-free standard fixture; $1 = extra frontmatter line for
# story.md (e.g. "status: draft") or empty, $2 = extra frontmatter line for
# tasks.md or empty, $3 = checkbox state of the single task ("x" or " ").
write_story_pair() {
  local fm_story="$1" fm_tasks="$2" box="${3:-x}"
  {
    echo '---'
    echo 'story: status-fixture'
    echo 'type: feature'
    echo 'scale: standard'
    echo 'version: 1'
    echo 'created: 2026-08-02'
    if [ -n "$fm_story" ]; then echo "$fm_story"; fi
    echo '---'
    echo
    echo '## Introduction'
    echo 'Status enum fixture.'
    echo
    echo '### R1. First requirement'
    echo '#### Acceptance Criteria'
    echo '- R1.1: WHEN x THE SYSTEM SHALL y'
  } > "$STORY/story.md"
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-08-02'
    if [ -n "$fm_tasks" ]; then echo "$fm_tasks"; fi
    echo '---'
    echo
    echo '## Task List'
    echo "- [$box] 1 - Implement"
    echo '  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_'
    echo '  - Requirements: R1.1'
    echo '  - Validation: bats green'
    echo '  - Commit: "feat: x"'
    echo
    echo '## Quality Gates'
    echo '- Done'
  } > "$STORY/tasks.md"
}

@test "R2.1: status outside the enum is an error naming the value and the enum" {
  write_story_pair "status: medium" "status: medium" "x"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  # Error names the offending value...
  echo "$output" | grep -q 'medium'
  # ...and the sanctioned enum (spot-check distinctive members).
  echo "$output" | grep -q 'in-progress'
  echo "$output" | grep -q 'superseded'
}

@test "R2.1: every enum value is accepted without a status error" {
  local v
  for v in draft in-progress done validated superseded archived; do
    write_story_pair "status: $v" "status: $v" "x"
    run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
    [ "$status" -eq 0 ] || { echo "enum value rejected: $v"; echo "$output"; return 1; }
    echo "$output" | grep -q '"errors": 0'
  done
}

@test "R2.2: absent status field produces zero errors and zero warnings (legacy hard contract)" {
  write_story_pair "" "" "x"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"errors": 0'
  echo "$output" | grep -q '"warnings": 0'
}

@test "R2.3: status done with an open [ ] box warns that status is ahead of the checkboxes" {
  write_story_pair "status: done" "status: done" " "
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  # Warning, not error: exit stays 0 without --strict.
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'ahead'
  refute_grep '"warnings": 0'
}

@test "R2.3: status validated with an open [ ] box also warns" {
  write_story_pair "status: validated" "status: validated" " "
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'ahead'
}

@test "R2.4: divergent status across artifacts warns naming the divergent files" {
  write_story_pair "status: done" "status: draft" "x"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  refute_grep '"warnings": 0'
  echo "$output" | grep -q 'story\.md'
  echo "$output" | grep -q 'tasks\.md'
}

# --- 12.3: the converse — status BEHIND the checkboxes -----------------------

# Same shape as write_story_pair, but the single task's checkbox line is given
# verbatim so a `[~]` can carry its qualifier. $3 is the whole line after the
# leading `- `.
write_story_pair_box() {
  local fm="$1" box_line="$2"
  write_story_pair "$fm" "$fm" "x"
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-08-02'
    if [ -n "$fm" ]; then echo "$fm"; fi
    echo '---'
    echo
    echo '## Task List'
    echo "- $box_line"
    echo '  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_'
    echo '  - Requirements: R1.1'
    echo '  - Validation: bats green'
    echo '  - Commit: "feat: x"'
    echo
    echo '## Quality Gates'
    echo '- Done'
  } > "$STORY/tasks.md"
}

@test "12.3: status in-progress with every box closed warns that status is behind" {
  write_story_pair "status: in-progress" "status: in-progress" "x"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  # Warning, not error: exit stays 0 without --strict.
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"errors": 0'
  echo "$output" | grep -qi 'behind'
  # It must name the rule that owed the write, or the reader cannot act on it.
  echo "$output" | grep -q 'rule 1'
}

@test "12.3: status draft with every box closed warns too — draft is behind, not exempt" {
  write_story_pair "status: draft" "status: draft" "x"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'behind'
}

@test "12.3 hostile: a deferred [~] blocks 'done', so in-progress over it is CORRECT and must not warn" {
  # The fold-detector. references/run-mode.md: "A deferred box blocks `done` —
  # deliberately." Count this box as plain-closed and the warning fires falsely.
  write_story_pair_box "status: in-progress" '[~] 1 - Implement (deferred: vendor credentials pending)'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"errors": 0'
  refute_grep 'behind'
}

@test "12.3 hostile: superseded sits over a fully-closed census legitimately and must not warn" {
  # `superseded` and `archived` are terminal: rule 1 would never overwrite them
  # with `done`, so they belong to NEITHER status set.
  write_story_pair_box "status: superseded" '[~] 1 - Implement (superseded-by: 012)'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  refute_grep 'behind'
}

@test "12.3 third element: a box carrying BOTH qualifiers is deferred — deferred wins" {
  # 8.1's derived-value question asked of the census: `deferred:` and a terminal
  # qualifier on one line is neither cleanly deferred nor cleanly terminal.
  # references/supersede-mode.md fixes the precedence — a line carrying both
  # stays owed — so this box must suppress the warning exactly like a plain
  # deferred one.
  write_story_pair_box "status: in-progress" \
    '[~] 1 - Implement (deferred: vendor credentials pending) (superseded-by: 012)'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  refute_grep 'behind'
}

@test "12.3 third element: no boxes at all is not 'finished' — a plan not yet written must not warn" {
  # Neither open nor closed but ABSENT: the census reads zero of everything, and
  # `0 open, 0 deferred` would satisfy the warning's arithmetic without the
  # TASK_COUNT guard. A freshly created story sitting at `draft` is the state
  # this protects.
  write_story_pair "status: draft" "status: draft" "x"
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-08-02'
    echo 'status: draft'
    echo '---'
    echo
    echo '## Task List'
    echo
    echo '## Quality Gates'
    echo '- Done'
  } > "$STORY/tasks.md"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  refute_grep 'behind'
}

@test "12.3: ahead and behind are mutually exclusive — an open box silences the converse" {
  write_story_pair "status: in-progress" "status: in-progress" " "
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  refute_grep 'behind'
  refute_grep 'ahead'   # in-progress is not a completion claim either
}
