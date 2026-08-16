#!/usr/bin/env bats
# Story 010, sub-tasks 3.1 and 3.2 — the commit anchor is checked, not just
# recommended (R4.1, R4.2, R4.3, R4.4).
# Authored by the Test Advisor BEFORE implementation (TDD Red phase).
#
# 3.1 — authoring lint in scripts/validate-story.sh: a Commit field whose
#       subject does not carry `type(NNN):` for this story's number draws a
#       WARNING naming the expected shape and the offending value. Never an
#       error. Zero-padded and unpadded anchors both accepted.
# 3.2 — scripts/story-git-status.sh gains `anchored_commits`: count of
#       subjects reachable from HEAD matching the existing token rules
#       (conventional `type(0*NNN):` or word-bounded `0*NNN-slug`); a bare
#       number never counts. Additive only — existing fields keep their
#       values on an unchanged repo. references/validate-mode.md names the
#       consumption rule.
#
# Cases marked PIN assert behaviour that must NOT change (no false positive
# from the new lint; existing story-git-status fields intact). Red is judged
# on the new-contract cases only.
#
# EPIC_PLUGIN_ROOT overrides root resolution so the draft copy under
# .draft/authored-tests/tests/ can run before materialization into tests/.

setup() {
  PLUGIN_ROOT="${EPIC_PLUGIN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  VALIDATE="$PLUGIN_ROOT/scripts/validate-story.sh"
  GITSTATUS="$PLUGIN_ROOT/scripts/story-git-status.sh"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

refute_grep() {
  if grep -qF "$1" <<< "$output"; then
    echo "did not expect pattern in output: $1"
    return 1
  fi
}

# --- 3.1 fixtures ----------------------------------------------------------
# Calibrated against the pre-change validator: 0 errors, 0 warnings — so any
# warning a case sees is the lint's own. Story number comes from the dir name
# (010-anchored → anchor `type(010):` / `type(10):`).

write_lint_story() { # write_lint_story <commit-message>
  LINT="$WORK/010-anchored"
  mkdir -p "$LINT"
  cat > "$LINT/story.md" <<'EOF'
---
story: anchored
type: feature
scale: standard
status: in-progress
version: 1
created: 2026-08-16
---

## Introduction
Anchor-lint fixture story.

### R1. First requirement
#### Acceptance Criteria
- R1.1: WHEN a THE SYSTEM SHALL b
- R1.2: WHEN c THE SYSTEM SHALL d
- R1.3: WHEN e THE SYSTEM SHALL f
- R1.4: WHEN g THE SYSTEM SHALL h
- R1.5: WHEN i THE SYSTEM SHALL j
EOF
  cat > "$LINT/tasks.md" <<EOF
---
story: anchored
type: feature
scale: standard
status: in-progress
version: 1
created: 2026-08-16
---

## Task List
- [x] 1.1 - First done
  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_
  - Requirements: R1.1
  - Validation: bats green
- [x] 1.2 - Second done
  - Requirements: R1.2
  - Validation: bats green
- [~] 1.3 - Waived gate (waived: tool absent)
  - Requirements: R1.3
  - Validation: waived
- [~] 1.4 - External proof (deferred: real hardware)
  - Requirements: R1.4
  - Validation: deferred
- [ ] 1.5 - Still open
  - Requirements: R1.5
  - Validation: bats green
  - Commit: "$1"

## Quality Gates
- Counts consistent
EOF
}

# =====================================================================
# Sub-task 3.1 — Commit-field anchor lint in validate-story.sh (R4.1)
# =====================================================================

@test "3.1 unanchored Commit field warns, naming the expected shape and the value (R4.1)" {
  write_lint_story "feat: add the scaffold"
  run bash "$VALIDATE" "$LINT"
  [ "$status" -eq 0 ]                       # a warning, never an error
  echo "$output" | grep -q '"errors": 0'
  echo "$output" | jq -e '.warnings >= 1'
  echo "$output" | grep -qF '(010)'         # the expected shape names this story
  echo "$output" | grep -qF 'feat: add the scaffold'   # and the offending value
}

@test "3.1 PIN anchored Commit field stays quiet (R4.1)" {
  write_lint_story "feat(010): add the scaffold"
  run bash "$VALIDATE" "$LINT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"warnings": 0'
}

@test "3.1 PIN unpadded anchor accepted — fix(10): stays quiet (R4.1)" {
  write_lint_story "fix(10): add the scaffold"
  run bash "$VALIDATE" "$LINT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"warnings": 0'
}

@test "3.1 the lint reads the field on a Commit sub-task too — not the checkbox shape (R4.1)" {
  write_lint_story "feat(010): add the scaffold"
  # Append a Commit SUB-TASK carrying an unanchored message: the field is what
  # is matched, whichever shape (015 changes the shape, not the field).
  sed -i 's|^## Quality Gates|- [ ] 1.6 - Commit\n  - Validation: all green\n  - Commit: "chore: tidy the scaffold"\n\n## Quality Gates|' "$LINT/tasks.md"
  run bash "$VALIDATE" "$LINT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.warnings >= 1'
  echo "$output" | grep -qF 'chore: tidy the scaffold'
}

# --- 3.2 fixtures ----------------------------------------------------------
# Real temp git repos, story dir 010-widget-flow (STORY_NUM 10, slug
# widget-flow) — same helpers as tests/story-git-status.bats.

make_repo() { # make_repo <dir> <initial-branch>
  local dir=$1 branch=$2
  mkdir -p "$dir"
  git init -q -b "$branch" "$dir"
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" commit --allow-empty -q -m "chore: initial scaffold"
  mkdir -p "$dir/.epic/stories/010-widget-flow"
  printf -- '---\nstatus: done\n---\n' > "$dir/.epic/stories/010-widget-flow/story.md"
}

commit_msg() {
  git -C "$1" commit --allow-empty -q -m "$2"
}

run_status() {
  cd "$1"
  run bash "$GITSTATUS" .epic/stories/010-widget-flow
}

# =====================================================================
# Sub-task 3.2 — anchored_commits in story-git-status.sh (R4.2-R4.4)
# =====================================================================

@test "3.2 counts conventional and slug anchors reachable from HEAD (R4.3)" {
  make_repo "$WORK/r" main
  commit_msg "$WORK/r" "feat(010): add the closing writer"      # conv, padded
  commit_msg "$WORK/r" "fix(10): tighten the writer"            # conv, unpadded
  commit_msg "$WORK/r" "chore: 010-widget-flow scaffolding"     # slug token
  commit_msg "$WORK/r" "docs: story 10 notes"                   # bare number — never
  commit_msg "$WORK/r" "feat: multiply 1010 by 2"               # substring — never
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.anchored_commits == 3'
}

@test "3.2 a bare story number never counts (R4.3)" {
  make_repo "$WORK/r" main
  commit_msg "$WORK/r" "docs: story 10 notes"
  commit_msg "$WORK/r" "feat: value 1010 handled"
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.anchored_commits == 0'
}

@test "3.2 counts from HEAD, not from main (R4.2)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" checkout -q -b feat/010-widget-flow
  commit_msg "$WORK/r" "feat(010): add the writer"
  commit_msg "$WORK/r" "test(010): cover the writer"
  run_status "$WORK/r"                       # HEAD = the unmerged story branch
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.anchored_commits == 2'
  git -C "$WORK/r" checkout -q main          # main has none of them
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.anchored_commits == 0'
}

@test "3.2 additive only — existing fields keep their values beside the new one (R4.4)" {
  make_repo "$WORK/r" main
  commit_msg "$WORK/r" "feat(010): add the writer"
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.story == "010-widget-flow" and .main_branch == "main"
    and .integrated == true and (.evidence | type) == "array"
    and (.checked_at | type) == "string" and (.anchored_commits | type) == "number"'
}

@test "3.2 validate-mode.md names the anchored_commits consumption rule (R4.2, doc contract)" {
  command grep -q 'anchored_commits' "$PLUGIN_ROOT/references/validate-mode.md"
}

# =====================================================================
# Refine delta 2 (cross-artifact review) — group-level Commit shape (3.1)
# and the no-double-fire precedence doc contract (3.2, design §4)
# =====================================================================

# write_group_lint_story <commit-message>: story 015's group-level Commit
# field — `- Commit: "..."` on the parent task body, no checkbox, no Commit
# sub-task. Calibrated against the pre-change validator: 0 errors, 0 warnings,
# so any warning a case sees is the lint's own.
write_group_lint_story() {
  GROUPED="$WORK/010-grouped"
  mkdir -p "$GROUPED"
  cat > "$GROUPED/story.md" <<'STORYEOF'
---
story: grouped
type: feature
scale: standard
status: in-progress
version: 1
created: 2026-08-16
---

## Introduction
Group-level Commit field fixture story.

### R1. First requirement
#### Acceptance Criteria
- R1.1: WHEN a THE SYSTEM SHALL b
- R1.2: WHEN c THE SYSTEM SHALL d
- R1.3: WHEN e THE SYSTEM SHALL f
STORYEOF
  cat > "$GROUPED/tasks.md" <<TASKSEOF
---
story: grouped
type: feature
scale: standard
status: in-progress
version: 1
created: 2026-08-16
---

## Task List
- [ ] 1 - Grouped work
  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_
  - [x] 1.1 - First done
    - Requirements: R1.1
    - Validation: bats green
  - [x] 1.2 - Second done
    - Requirements: R1.2
    - Validation: bats green
  - [ ] 1.3 - Still open
    - Requirements: R1.3
    - Validation: bats green
  - Commit: "$1"

## Quality Gates
- Counts consistent
TASKSEOF
}

@test "3.1 group-level unanchored Commit field on a parent draws the warning (R4.1)" {
  write_group_lint_story "feat: add the grouped scaffold"
  run bash "$VALIDATE" "$GROUPED"
  [ "$status" -eq 0 ]                       # still a warning, never an error
  echo "$output" | grep -q '"errors": 0'
  echo "$output" | jq -e '.warnings >= 1'
  echo "$output" | grep -qF '(010)'
  echo "$output" | grep -qF 'feat: add the grouped scaffold'
}

@test "3.1 PIN group-level anchored Commit field stays quiet (R4.1)" {
  write_group_lint_story "feat(010): add the grouped scaffold"
  run bash "$VALIDATE" "$GROUPED"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"warnings": 0'
}

@test "3.2 validate-mode.md settles the no-double-fire precedence (design §4, doc contract)" {
  # At most ONE integration-flavored warning: `anchored_commits == 0` wins;
  # 006's integrated=false warning fires only when anchored commits exist but
  # none reached main; `integrated: null` silences both. Matched on the
  # flattened text so wrapping never decides the verdict.
  FLAT=$(tr -s '[:space:]' ' ' < "$PLUGIN_ROOT/references/validate-mode.md")
  grep -qF 'anchored_commits == 0' <<< "$FLAT"
  grep -q 'wins' <<< "$FLAT"
  grep -q 'only when' <<< "$FLAT"
  grep -qF 'integrated: null' <<< "$FLAT"
}
