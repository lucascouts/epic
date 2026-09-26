#!/usr/bin/env bats
# The commit anchor is checked, not just recommended.
#
# Authoring lint in scripts/validate-story.sh: a Commit field whose subject
#   does not carry `type(NNN):` for this story's number draws a WARNING naming
#   the expected shape and the offending value. Never an error. Zero-padded
#   and unpadded anchors both accepted.
# scripts/story-git-status.sh reports `anchored_commits`: count of subjects
#   reachable from HEAD matching the existing token rules (conventional
#   `type(0*NNN):` or word-bounded `0*NNN-slug`); a bare number never counts.
#   Additive only — existing fields keep their values on an unchanged repo.
#   references/validate-mode.md names the consumption rule.
#
# Cases marked PIN assert behaviour that must not change: no false positive
# from the lint, and the existing story-git-status fields intact.
#
# EPIC_PLUGIN_ROOT overrides root resolution so the suite can run against a
# plugin tree other than its parent directory.

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

# md_section <file> <start regex> <end regex> — the lines strictly between the
# heading that matches <start> and the next heading that matches <end>. The
# doc-contract case below reads a rule whose wording recurs elsewhere in the
# same file for unrelated reasons, and a whole-file grep cannot tell the rule
# from its homonyms. Same helper, same three arguments and same idiom as
# tests/reports-by-artifact-policy.bats' — copied rather than shared because a
# .bats file cannot source another without becoming its runner.
md_section() { # $1 = file, $2 = start regex, $3 = end regex
  awk -v start="$2" -v end="$3" '
    !inb && $0 ~ start {inb=1; next}
    inb && $0 ~ end {exit}
    inb {print}' "$1"
}

# --- Commit-field lint fixtures ---------------------------------------------
# The fixture validates with 0 errors and 0 warnings on its own, so any warning
# a case sees is the lint's own. The story number comes from the dir name
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
# Commit-field anchor lint in validate-story.sh
# =====================================================================

@test "unanchored Commit field warns, naming the expected shape and the value" {
  write_lint_story "feat: add the scaffold"
  run bash "$VALIDATE" "$LINT"
  [ "$status" -eq 0 ]                       # a warning, never an error
  echo "$output" | grep -q '"errors": 0'
  echo "$output" | jq -e '.warnings >= 1'
  echo "$output" | grep -qF '(010)'         # the expected shape names this story
  echo "$output" | grep -qF 'feat: add the scaffold'   # and the offending value
}

@test "PIN anchored Commit field stays quiet" {
  write_lint_story "feat(010): add the scaffold"
  run bash "$VALIDATE" "$LINT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"warnings": 0'
}

@test "PIN unpadded anchor accepted — fix(10): stays quiet" {
  write_lint_story "fix(10): add the scaffold"
  run bash "$VALIDATE" "$LINT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"warnings": 0'
}

@test "the lint reads the field on a Commit sub-task too — not the checkbox shape" {
  write_lint_story "feat(010): add the scaffold"
  # Append a Commit SUB-TASK carrying an unanchored message: the field is what
  # is matched, whichever shape carries it.
  sed -i 's|^## Quality Gates|- [ ] 1.6 - Commit\n  - Validation: all green\n  - Commit: "chore: tidy the scaffold"\n\n## Quality Gates|' "$LINT/tasks.md"
  run bash "$VALIDATE" "$LINT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.warnings >= 1'
  echo "$output" | grep -qF 'chore: tidy the scaffold'
}

# --- anchored_commits fixtures ------------------------------------------------------
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
# anchored_commits in story-git-status.sh
# =====================================================================

@test "counts conventional and slug anchors reachable from HEAD" {
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

@test "a bare story number never counts" {
  make_repo "$WORK/r" main
  commit_msg "$WORK/r" "docs: story 10 notes"
  commit_msg "$WORK/r" "feat: value 1010 handled"
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.anchored_commits == 0'
}

@test "counts from HEAD, not from main" {
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

@test "additive only — existing fields keep their values beside anchored_commits" {
  make_repo "$WORK/r" main
  commit_msg "$WORK/r" "feat(010): add the writer"
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.story == "010-widget-flow" and .main_branch == "main"
    and .integrated == true and (.evidence | type) == "array"
    and (.checked_at | type) == "string" and (.anchored_commits | type) == "number"'
}

@test "validate-mode.md names the anchored_commits consumption rule (doc contract)" {
  command grep -q 'anchored_commits' "$PLUGIN_ROOT/references/validate-mode.md"
}

# =====================================================================
# Group-level Commit shape and the no-double-fire precedence doc contract
# =====================================================================

# write_group_lint_story <commit-message>: the group-level Commit field —
# `- Commit: "..."` on the parent task body, no checkbox, no Commit sub-task.
# The fixture validates with 0 errors and 0 warnings on its own, so any
# warning a case sees is the lint's own.
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

@test "group-level unanchored Commit field on a parent draws the warning" {
  write_group_lint_story "feat: add the grouped scaffold"
  run bash "$VALIDATE" "$GROUPED"
  [ "$status" -eq 0 ]                       # still a warning, never an error
  echo "$output" | grep -q '"errors": 0'
  echo "$output" | jq -e '.warnings >= 1'
  echo "$output" | grep -qF '(010)'
  echo "$output" | grep -qF 'feat: add the grouped scaffold'
}

@test "PIN group-level anchored Commit field stays quiet" {
  write_group_lint_story "feat(010): add the grouped scaffold"
  run bash "$VALIDATE" "$GROUPED"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"warnings": 0'
}

@test "validate-mode.md settles the no-double-fire precedence (doc contract)" {
  # At most ONE integration-flavored warning: `anchored_commits == 0` wins;
  # the integrated=false warning fires only when anchored commits exist but
  # none reached main; `integrated: null` silences both. Matched on the
  # flattened text so wrapping never decides the verdict.
  FLAT=$(tr -s '[:space:]' ' ' < "$PLUGIN_ROOT/references/validate-mode.md")
  grep -qF 'anchored_commits == 0' <<< "$FLAT"
  # WHICH SIDE WINS, not that the word `wins` is somewhere in the file: the
  # specific finding must PRECEDE `wins` inside one sentence, so a reversed
  # precedence (`Rule 3 **wins** over `anchored_commits == 0``) reds, while a
  # rewording that keeps the same side winning, or a reflow, stays green.
  # Residual: a rewording that keeps the same side winning while replacing the
  # verb (`rule 3 yields to `anchored_commits == 0``) false-reds. The order of
  # the two sides IS the direction, and pinning it is what direction costs.
  grep -qE 'anchored_commits == 0[^.]{0,40}wins' <<< "$FLAT"
  # WHICH CONDITION THE `only when` GOVERNS, and in which section it is stated.
  # The bare literal `only when` recurs in this file for unrelated rules (a
  # status transition, a shell comment inside a code block), so a whole-file
  # match cannot tell this rule from its homonyms and would stay green with the
  # rule deleted.
  #
  # SCOPED to `## Integration Warning` — the section that owns both warnings
  # and the precedence between them, its `###` subsection included. The `##`
  # boundary is used rather than the `###` one because the rule may
  # legitimately move between the section and its own subsection.
  #
  # THE TRAILING SPACE IN `^## ` IS LOAD-BEARING HERE: without it the end
  # pattern matches the `### The anchor warning` heading, the capture holds no
  # `only when` at all, and this assertion would red on unmutated prose.
  # Whether a boundary wants the space depends on the section, never on style.
  #
  # THEN THE PIN, because a scope alone still admits the code-block comment.
  # Three anchors: `integration warning` … `fires` reds a swap to `The anchor
  # warning therefore fires only when …`, the other warning and the opposite
  # rule; `only when` reds `except when`; and `ha(s|ve) anchored commits` reds
  # the condition negated to `has no anchored commits`, which no count and no
  # scope would reach. Rewordings and reflows stay green — the flatten below
  # carries the reflow.
  #
  # Known residuals: a pronoun subject (`It therefore fires only when …`)
  # false-reds, and the SECOND conjunct reversed (`and at least one of them
  # reached the main branch`) stays green. Reaching that one costs a fourth
  # anchor over a `none|no|not one|never` alternation whose false-red surface
  # is wider than the inversion it catches.
  SEC=$(md_section "$PLUGIN_ROOT/references/validate-mode.md" '^## Integration Warning' '^## ')
  # md_section yields lines, so the section is flattened here exactly as $FLAT
  # is above — otherwise a wrap decides the verdict.
  FLATSEC=$(printf '%s\n' "$SEC" | tr -s '[:space:]' ' ')
  grep -qiE 'integration warning[^.]{0,40}fires[^.]{0,20}only when[^.]{0,40}ha(s|ve) anchored commits' <<< "$FLATSEC"
  grep -qF 'integrated: null' <<< "$FLAT"
}

# =====================================================================
# The SECOND copy of the key set
# =====================================================================
# The detector's key set is written in two reference files, validate-mode.md
# and list-mode.md. This case pins the list-mode.md copy so it fails when it
# drifts from the script, because a fact stated only in prose cannot fail, so
# it is never corrected.
#
# CITED BY NAME, NOT BY LINE: a line number goes stale with the next edit
# above it.

@test "list-mode.md enumerates anchored_commits in the detector's key set (doc contract)" {
  # Asserted as the WHOLE key set rather than the bare field name, so the
  # position is pinned too: `anchored_commits` sits between `evidence` and
  # `checked_at`, which is the order story-git-status.sh emits and the order
  # validate-mode.md already names. A field present but reordered
  # would still be a doc that disagrees with the script.
  #
  # Matched on the flattened text so wrapping never decides the verdict — the
  # shape the two validate-mode.md doc-contract cases above use.
  FLAT=$(tr -s '[:space:]' ' ' < "$PLUGIN_ROOT/references/list-mode.md")
  grep -qF '{story, main_branch, integrated, evidence, anchored_commits, checked_at}' <<< "$FLAT"
}
