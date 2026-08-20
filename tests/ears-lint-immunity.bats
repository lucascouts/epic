#!/usr/bin/env bats
# Story 014, Task 1.2 — the immunity set for the EARS form checks, proven
# by golden diff, plus the TaskCompleted hook contract.
# Contract (R1.4, R4.1, R4.2 + R1.6's blocking consequence):
#   - fast (hostile: leftover story.md carrying an UNLABELED criterion), spike,
#     bugfix-behavior and no-scale-declared legacy fixtures keep validator
#     output BYTE-IDENTICAL to the pre-change goldens below (R4.1) — new
#     strings only, no new count keys, is subsumed by byte-identity (R4.2).
#   - The new R1.1 error blocks task completion through hook-task-completed.sh
#     (exit 2); the new warnings never block (exit 0).
#
# Goldens captured from the PRE-CHANGE validator (2026-08-16, story 014
# Phase 3), each run as `validate-story.sh story` from the fixture's parent so
# the "story" field is deterministic. Any drift — an added string, a reordered
# key — is a regression against R4.1.
#
# Cases whose names carry `PIN` pass against the pre-change scripts and must
# stay green; the hook-blocks case is the Red one.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/story"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

# --- R1.4 + R4.1: fast, with a hostile leftover story.md ---
# The leftover story.md carries an unlabeled criterion under an Acceptance
# Criteria heading — the exact shape R1.1 errors on at standard scale. The
# resolved scale is fast, so the checks must not run at all: same three
# warnings as today, zero errors, byte for byte.

@test "1.2: PIN fast scale — unlabeled criterion in a leftover story.md changes nothing (golden)" {
  cat > "$STORY/tasks.md" <<'EOF'
---
story: fast-immunity
type: feature
scale: fast
version: 1
created: 2026-08-16
---

## Task List
- [ ] 1 - Add the config flag
  - Validation: `echo ok`

## Quality Gates
- Done
EOF
  cat > "$STORY/story.md" <<'EOF'
---
story: fast-immunity
type: feature
version: 1
created: 2026-08-16
---

## Introduction
Leftover story.md beside a fast tasks.md.

### R1. Leftover requirement

#### Acceptance Criteria

- WHEN the user saves THE SYSTEM SHALL persist the draft.
EOF
  GOLDEN=$(cat <<'EOF'
{
  "story": "story",
  "errors": 0,
  "warnings": 3,
  "error_details": [],
  "warning_details": [
    "declared scale 'fast' (in tasks.md) contradicts the files present: a 'fast' story is tasks-only, but story.md is present — remove story.md, or declare the scale the files actually describe",
    "No metadata lines found (expected _Complexity: ... | Tests: ... | ..._) on parent tasks",
    "No Commit fields or Commit sub-tasks found — every task group should have a commit point"
  ],
  "strict": false,
  "status": "pass"
}
EOF
)
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" story
  [ "$status" -eq 0 ]
  diff <(printf '%s\n' "$GOLDEN") <(printf '%s\n' "$output")
}

# --- R1.4 + R4.1: conforming open spike, tasks-only ---

@test "1.2: PIN spike scale — validator output is byte-identical (golden)" {
  cat > "$STORY/tasks.md" <<'EOF'
---
story: probe-cache-strategy
type: feature
scale: spike
version: 1
created: 2026-08-16
---

## Overview
Probe: is the cache layer worth it?

## Task List
- [ ] 1 - Benchmark cold vs warm path
  - Validation: `./bench.sh`

## Verdict
- status: open
- conclusion: pending
EOF
  GOLDEN=$(cat <<'EOF'
{
  "story": "story",
  "errors": 0,
  "warnings": 3,
  "error_details": [],
  "warning_details": [
    "tasks.md is missing 'Quality Gates' section",
    "No metadata lines found (expected _Complexity: ... | Tests: ... | ..._) on parent tasks",
    "No Commit fields or Commit sub-tasks found — every task group should have a commit point"
  ],
  "strict": false,
  "status": "pass"
}
EOF
)
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" story
  [ "$status" -eq 0 ]
  diff <(printf '%s\n' "$GOLDEN") <(printf '%s\n' "$output")
}

# --- R1.5 + R4.1: bugfix behavior section, unlabeled SHALL CONTINUE TO items ---

@test "1.2: PIN bugfix — unlabeled SHALL CONTINUE TO behavior items change nothing (golden)" {
  cat > "$STORY/story.md" <<'EOF'
---
story: bugfix-immunity
type: bugfix
scale: standard
version: 1
created: 2026-08-16
---

## Introduction
Bugfix immunity fixture: unlabeled, SHALL CONTINUE TO behavior items.

### R1. Wrong total on discounted orders

#### Acceptance Criteria

- R1.1: WHEN an order carries a discount THE SYSTEM SHALL return the discounted total.

## Unchanged Behavior

- WHEN an order has no discount THE SYSTEM SHALL CONTINUE TO return the plain total
- WHEN an order is empty THE SYSTEM SHALL CONTINUE TO return zero
EOF
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
---

## Task List
- [ ] 1 - Fix the total
  - Requirements: R1.1
  - Validation: `echo ok`

## Quality Gates
- Done
EOF
  GOLDEN=$(cat <<'EOF'
{
  "story": "story",
  "errors": 0,
  "warnings": 2,
  "error_details": [],
  "warning_details": [
    "No metadata lines found (expected _Complexity: ... | Tests: ... | ..._) on parent tasks",
    "No Commit fields or Commit sub-tasks found — every task group should have a commit point"
  ],
  "strict": false,
  "status": "pass"
}
EOF
)
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" story
  [ "$status" -eq 0 ]
  diff <(printf '%s\n' "$GOLDEN") <(printf '%s\n' "$output")
}

# --- R4.1: legacy story with no scale declared, conforming EARS ---
# The legacy corpus keeps its requirements chain (scale "" resolves to
# chain-carrying), so the checks DO run here — and stay silent, because the
# criteria conform. Byte-identity is the proof the silence costs nothing.

@test "1.2: PIN no-scale legacy — conforming criteria keep output byte-identical (golden)" {
  cat > "$STORY/story.md" <<'EOF'
---
story: legacy-no-scale
type: feature
version: 1
created: 2026-01-10
---

## Introduction
Legacy story predating the scale field.

### R1. First requirement

#### Acceptance Criteria

- R1.1: WHEN x THE SYSTEM SHALL y.
EOF
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
created: 2026-01-10
---

## Task List
- [ ] 1 - Implement
  - Requirements: R1.1
  - Validation: `echo ok`

## Quality Gates
- Done
EOF
  GOLDEN=$(cat <<'EOF'
{
  "story": "story",
  "errors": 0,
  "warnings": 2,
  "error_details": [],
  "warning_details": [
    "No metadata lines found (expected _Complexity: ... | Tests: ... | ..._) on parent tasks",
    "No Commit fields or Commit sub-tasks found — every task group should have a commit point"
  ],
  "strict": false,
  "status": "pass"
}
EOF
)
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" story
  [ "$status" -eq 0 ]
  diff <(printf '%s\n' "$GOLDEN") <(printf '%s\n' "$output")
}

# --- R1.6's teeth: the TaskCompleted hook ---
# The hook blocks (exit 2) only when the validator reports ERRORS. The new
# R1.1 unlabeled-criterion error must therefore block; the new R1.2/R1.3
# warnings must never block.

write_hook_project() { # $1 = Acceptance Criteria block for the story
  mkdir -p "$WORK/proj/.epic/stories/001-hook"
  cat > "$WORK/proj/.epic/stories/001-hook/story.md" <<EOF
---
story: hook-fixture
type: feature
scale: standard
version: 1
created: 2026-08-16
---

## Introduction
Hook fixture.

### R1. First requirement

#### Acceptance Criteria

$1
EOF
  cat > "$WORK/proj/.epic/stories/001-hook/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
---

## Task List
- [ ] 1 - Implement
  - Requirements: R1.1
  - Validation: `echo ok`

## Quality Gates
- Done
EOF
}

@test "1.2: the unlabeled-criterion error blocks task completion (hook exit 2)" {
  write_hook_project '- R1.1: WHEN x THE SYSTEM SHALL y.
- WHEN the user saves THE SYSTEM SHALL persist the draft.'
  cd "$WORK/proj"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/scripts/hook-task-completed.sh"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'failed validation'
}

@test "1.2: PIN the compound and trigger-less warnings never block (hook exit 0)" {
  write_hook_project '- R1.1: WHEN the form is submitted THE SYSTEM SHALL validate the fields and SHALL persist the record.
- R1.2: The exporter SHALL write the report to disk.'
  cd "$WORK/proj"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/scripts/hook-task-completed.sh"
  [ "$status" -eq 0 ]
}
