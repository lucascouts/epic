#!/usr/bin/env bats
# Story 004, sub-task 1.1 — `[~]` checkbox grammar in scripts/validate-story.sh.
# Contract under test (R3.1, R3.2, R3.5):
#   - A `[~]` line with a same-line qualifier among deferred:/waived:/n-a:/
#     superseded-by: is a VALID closed-state checkbox (R3.1).
#   - A `[~]` line without a recognized qualifier is an ERROR listing the four
#     valid qualifier forms (R3.2).
#   - `[~]` boxes participate in the box totals: a tasks.md whose only boxes
#     are qualified `[~]` has parseable tasks, not "no parseable checkbox
#     tasks" (R3.5 — closed counts include terminal `[~]`).
#   - Legacy fixtures (no `[~]`) keep passing unchanged.

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

# Fast-mode fixture (tasks.md only) whose ONLY checkboxes are `[~]` with the
# given qualifier. Under the new grammar these are valid closed boxes, so the
# story must validate clean — not "no parseable checkbox tasks".
write_tilde_only_tasks() { # $1 = qualifier text, e.g. "waived: tool absent"
  cat > "$STORY/tasks.md" <<EOF
---
story: tilde-fixture
type: feature
scale: fast
version: 1
created: 2026-08-02
---

## Task List
- [~] 1 - Optional gate ($1)
  - Validation: not executed by design

## Quality Gates
- Grammar accepted
EOF
}

@test "R3.1: [~] with waived: qualifier is a valid closed checkbox (story passes)" {
  write_tilde_only_tasks "waived: tool absent"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "pass"'
  refute_grep 'no parseable checkbox tasks'
}

@test "R3.1: all four qualifier forms are accepted" {
  local q
  for q in "deferred: waiting on hardware" "waived: user decision" "n-a: not applicable here" "superseded-by: 006"; do
    write_tilde_only_tasks "$q"
    run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
    [ "$status" -eq 0 ] || { echo "qualifier rejected: $q"; echo "$output"; return 1; }
    echo "$output" | grep -q '"errors": 0'
  done
}

@test "R3.2: [~] without a qualifier is an error listing the four valid forms" {
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-02
---

## Task List
- [x] 1 - Done work
  - Validation: ok
- [~] 2 - Closed without saying why

## Quality Gates
- Grammar accepted
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  # The error must teach the grammar: all four valid qualifier forms named.
  echo "$output" | grep -q 'deferred:'
  echo "$output" | grep -q 'waived:'
  echo "$output" | grep -q 'n-a:'
  echo "$output" | grep -q 'superseded-by:'
}

@test "R3.2: [~] with an unrecognized qualifier is an error (fail-closed grammar)" {
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-02
---

## Task List
- [x] 1 - Done work
  - Validation: ok
- [~] 2 - Closed oddly (skipped: felt like it)

## Quality Gates
- Grammar accepted
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'deferred:'
  echo "$output" | grep -q 'superseded-by:'
}

@test "R3.5: mixed [x]/[ ]/[~] story is accepted with no grammar errors" {
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-02
---

## Task List
- [x] 1 - Done work
  - Validation: ok
- [~] 2 - Waived gate (waived: tool absent)
  - Validation: waived
- [~] 3 - Deferred proof (deferred: needs real hardware)
  - Validation: deferred
- [ ] 4 - Still open
  - Validation: pending

## Quality Gates
- Counts consistent
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"errors": 0'
}

@test "legacy: story with no [~] still passes unchanged" {
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-02
---

## Task List
- [x] 1 - Done
  - Validation: ok
- [ ] 2 - Open
  - Validation: pending

## Quality Gates
- Legacy tolerance
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "pass"'
}
