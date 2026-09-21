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

@test "0.8.0: many boxes in few bytes are silent — the count arm was removed" {
  # Until 0.7.0 this fixture warned: 65 boxes was over the 60-box arm. The arm
  # is gone (references/tasks.md § Authoring Ceiling): how many tasks a story
  # has follows from the work, and a checkbox is not a unit of work.
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
  if echo "$output" | jq -r '.warning_details[]' | grep -q 'references/tasks.md'; then
    echo "65 boxes in 3KB drew a size warning: $(echo "$output" | jq -r '.warning_details[]')"
    return 1
  fi
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

# --- 0.8.0: the level no longer caps the number of tasks ---
# Contract (references/tasks.md § Authoring Ceiling, references/engineering-level.md):
#   - the plan has ONE threshold, on bytes; no count of Task List boxes warns,
#     at any engineering level;
#   - an invented level is still an ERROR naming the four values, and tasks.md
#     is still authoritative over story.md for reading it.

# level_fixture <engineering line or ""> <task boxes> <gate boxes> [with-story]
# A Fast-shaped tasks.md with a fenced example (two boxes that must not count),
# N Task List boxes, M Quality Gates boxes. With a 4th argument, every task
# also carries `Requirements: R1.1` so it pairs with a story.md written by
# level_story.
level_fixture() {
  local eng="$1" tasks="$2" gates="$3" req="${4:-}" i
  {
    printf -- '---\nstory: ceiling-level\ntype: feature\n'
    if [ -n "$eng" ]; then printf '%s\n' "$eng"; fi
    printf 'version: 1\ncreated: 2026-09-17\n---\n\n## Overview\n\n'
    printf '```markdown\n- [ ] a box inside a fence is documentation\n- [ ] and so is this one\n```\n\n## Task List\n'
    for i in $(seq 1 "$tasks"); do
      printf -- '- [ ] %d - Pad step %d\n  - Validation: ok\n' "$i" "$i"
      if [ -n "$req" ]; then printf '  - Requirements: R1.1\n'; fi
    done
    printf '\n## Quality Gates\n'
    # The security floor rides in every fixture that declares a level, because
    # a story that declares one owes these four gates whatever else it drops
    # (references/quality-catalog.md; tests/security-floor-gates.bats). Without
    # them the `.errors == 0` assertions below would be measuring the floor
    # lint instead of the ceiling this file is about. Four extra boxes are
    # inert here: since 0.8.0 the ceiling is bytes only.
    printf -- '- [ ] Q1 — Supported and declared runtime: `node --version`\n'
    printf -- '- [ ] Q2 — Secrets: `gitleaks detect`\n'
    printf -- '- [ ] Q3 — README: the commands it names run\n'
    printf -- '- [ ] Q4 — Dependency vulnerabilities (SCA): `trivy fs .`\n'
    for i in $(seq 1 "$gates"); do printf -- '- [ ] gate %d\n' "$i"; done
  } > "$STORY/tasks.md"
}

level_story() { # level_story <engineering line or "">
  {
    printf -- '---\nstory: ceiling-level\ntype: feature\n'
    if [ -n "$1" ]; then printf '%s\n' "$1"; fi
    printf 'version: 1\ncreated: 2026-09-17\n---\n\n## Introduction\nLevel fixture.\n\n### R1. First requirement\n\n#### Acceptance Criteria\n\n- R1.1: WHEN x THE SYSTEM SHALL y.\n'
  } > "$STORY/story.md"
}

no_ceiling_warning() { # the negative shared by every silent case
  if echo "$output" | jq -r '.warning_details[]' | grep -q 'references/tasks.md'; then
    echo "$1: drew a ceiling warning: $(echo "$output" | jq -r '.warning_details[]' | grep 'references/tasks.md')"
    return 1
  fi
  if echo "$output" | jq -r '.warning_details[]' | grep -qiE 'threshold|ceiling|oversiz'; then
    echo "$1: drew a ceiling-shaped warning"
    return 1
  fi
}

@test "0.8.0: no number of Task List boxes warns, at any level" {
  # 0.7.0 warned one box over 5 / 12 / 24 / 40. Those counts are now ordinary.
  local pair level n
  for pair in "experiment 6" "tool 13" "project 25" "product 41" "product 80"; do
    level=${pair% *}; n=${pair#* }
    level_fixture "engineering: $level" "$n" 5
    run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
    echo "$output" | jq -e . > /dev/null
    echo "$output" | jq -e '.errors == 0' > /dev/null
    no_ceiling_warning "$level at $n"
  done
}

@test "0.7.0: an invented engineering level is an error naming the four values" {
  level_fixture "engineering: throwaway" 3 0
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  echo "$output" | jq -e . > /dev/null
  echo "$output" | jq -e '.errors >= 1' > /dev/null
  echo "$output" | grep -q "engineering"
  echo "$output" | grep -q "experiment, tool, project, product"
}

@test "0.8.0: a story with no engineering field is silent whatever its size in boxes" {
  level_fixture "" 60 5
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  echo "$output" | jq -e . > /dev/null
  echo "$output" | jq -e '.errors == 0' > /dev/null
  no_ceiling_warning "no level at 60"
}

@test "0.8.0: tasks.md is still authoritative for the level — its invented value errors over a valid story.md" {
  level_story "engineering: product"
  level_fixture "engineering: throwaway" 6 0 with-story
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  echo "$output" | jq -e . > /dev/null
  echo "$output" | jq -e '.errors >= 1' > /dev/null
  echo "$output" | grep -q "experiment, tool, project, product"
}
