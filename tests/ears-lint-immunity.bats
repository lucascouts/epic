#!/usr/bin/env bats
# The immunity set for the EARS form checks, proven by golden diff, plus the
# error/warning split of the checks.
# Contract:
#   - fast (hostile: leftover story.md carrying an UNLABELED criterion), spike,
#     bugfix-behavior and no-scale-declared legacy fixtures keep validator
#     output BYTE-IDENTICAL to the goldens below — no new strings and no new
#     count keys, which byte-identity subsumes.
#   - The unlabeled-criterion check is an ERROR (validator exit 1); the
#     warnings never fail validation (exit 0).
#
# Each golden is the output of `validate-story.sh story` run from the
# fixture's parent, so the "story" field is deterministic. Any drift — an added
# string, a reordered key — is a regression.
#
# Cases whose names carry `PIN` guard behaviour that must stay unchanged.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/story"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

# --- fast, with a hostile leftover story.md ---
# The leftover story.md carries an unlabeled criterion under an Acceptance
# Criteria heading — the exact shape the unlabeled-criterion check errors on at
# standard scale. The resolved scale is fast, so the checks must not run at
# all: the golden's three warnings, zero errors, byte for byte.

@test "PIN fast scale — unlabeled criterion in a leftover story.md changes nothing (golden)" {
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

# --- conforming open spike, tasks-only ---

@test "PIN spike scale — validator output is byte-identical (golden)" {
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

# --- bugfix behavior section, unlabeled SHALL CONTINUE TO items ---

@test "PIN bugfix — unlabeled SHALL CONTINUE TO behavior items change nothing (golden)" {
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

# --- legacy story with no scale declared, conforming EARS ---
# A legacy story keeps its requirements chain (scale "" resolves to
# chain-carrying), so the checks DO run here — and stay silent, because the
# criteria conform. Byte-identity is the proof the silence costs nothing.

@test "PIN no-scale legacy — conforming criteria keep output byte-identical (golden)" {
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

# --- Errors fail validation, warnings never do ---

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

@test "the unlabeled-criterion error fails validation (exit 1)" {
  write_hook_project '- R1.1: WHEN x THE SYSTEM SHALL y.
- WHEN the user saves THE SYSTEM SHALL persist the draft.'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$WORK/proj/.epic/stories/001-hook"
  [ "$status" -eq 1 ]
}

@test "PIN the compound and trigger-less warnings never fail validation (exit 0)" {
  write_hook_project '- R1.1: WHEN the form is submitted THE SYSTEM SHALL validate the fields and SHALL persist the record.
- R1.2: The exporter SHALL write the report to disk.'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$WORK/proj/.epic/stories/001-hook"
  [ "$status" -eq 0 ]
}
