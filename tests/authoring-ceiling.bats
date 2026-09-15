#!/usr/bin/env bats
# Story 014, Task 3.1 — the authoring ceiling in scripts/validate-story.sh.
# Contract (R3.2, R3.3):
#   - A tasks.md over the threshold (32KB or 60 boxes, whichever first) draws
#     a WARNING, never an error (R3.3; making the ceiling an error is
#     explicitly out of scope).
#   - The warning cites the threshold's single home, references/tasks.md, so
#     the value itself lives in exactly one place (R3.2 — every consumer
#     SHALL cite it, and this consumer's citation is the observable half).
#   - A normal-sized tasks.md is silent (PIN).
# The Phase 3 split offer (R3.1) and the batch surfacing rule (R3.4) live in
# SKILL/reference prose, not in this script — out of this suite's reach.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/story"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

@test "3.1: a tasks.md over 32KB warns, citing references/tasks.md as the threshold's home" {
  cat > "$STORY/story.md" <<'EOF'
---
story: ceiling-size
type: feature
version: 1
created: 2026-08-16
---

## Introduction
Oversized-plan fixture.

### R1. First requirement

#### Acceptance Criteria

- R1.1: WHEN x THE SYSTEM SHALL y.
EOF
  {
    cat <<'EOF'
---
version: 1
created: 2026-08-16
---

## Overview

EOF
    # ~36KB of prose padding: over the 32KB arm, far under the 60-box arm.
    for i in $(seq 1 600); do
      printf 'Padding paragraph %04d: prose that inflates the plan without adding a single checkbox to it.\n' "$i"
    done
    cat <<'EOF'

## Task List
- [ ] 1 - Implement
  - Requirements: R1.1
  - Validation: `echo ok`

## Quality Gates
- Done
EOF
  } > "$STORY/tasks.md"
  # Sanity: the fixture really is over 32KB.
  [ "$(wc -c < "$STORY/tasks.md")" -gt 32768 ]
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  echo "$output" | jq -e . > /dev/null
  # A warning, never an error.
  echo "$output" | jq -e '.errors == 0' > /dev/null
  # The warning cites the threshold's one home instead of restating the value.
  echo "$output" | jq -r '.warning_details[]' | grep -q 'references/tasks.md'
}

@test "3.1: a tasks.md over 60 boxes warns even when small in bytes" {
  {
    cat <<'EOF'
---
story: ceiling-boxes
type: feature
scale: fast
version: 1
created: 2026-08-16
---

## Task List
EOF
    # 65 open task boxes, ~3KB total: over the 60-box arm, far under 32KB.
    for i in $(seq 1 65); do
      printf -- '- [ ] %d - Pad step %d\n  - Validation: ok\n' "$i" "$i"
    done
    cat <<'EOF'

## Quality Gates
- Done
EOF
  } > "$STORY/tasks.md"
  [ "$(wc -c < "$STORY/tasks.md")" -lt 32768 ]
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  echo "$output" | jq -e . > /dev/null
  echo "$output" | jq -e '.errors == 0' > /dev/null
  echo "$output" | jq -r '.warning_details[]' | grep -q 'references/tasks.md'
}

@test "3.1: PIN a normal-sized tasks.md draws no ceiling warning" {
  cat > "$STORY/story.md" <<'EOF'
---
story: ceiling-small
type: feature
version: 1
created: 2026-08-16
---

## Introduction
Healthy-sized fixture.

### R1. First requirement

#### Acceptance Criteria

- R1.1: WHEN x THE SYSTEM SHALL y.
EOF
  cat > "$STORY/tasks.md" <<'EOF'
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
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  # No ceiling vocabulary and no citation of the threshold's home.
  if echo "$output" | jq -r '.warning_details[]' | grep -q 'references/tasks.md'; then
    echo "a healthy-sized tasks.md drew a warning citing the threshold's home"
    return 1
  fi
  if echo "$output" | jq -r '.warning_details[]' | grep -qiE 'threshold|ceiling|oversiz'; then
    echo "a healthy-sized tasks.md drew a ceiling-shaped warning"
    return 1
  fi
}
