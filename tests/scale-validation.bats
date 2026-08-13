#!/usr/bin/env bats
# Story 007, Task 1.1 — scale-aware validation in scripts/validate-story.sh.
# Contract (R2.1–R2.3):
#   - A declared `scale:` outside fast|standard|full|spike is an ERROR naming
#     both the invalid value and the valid set.
#   - An ABSENT `scale:` field keeps today's file-presence inference with
#     byte-identical output (golden captured from the pre-change validator).
#   - A declared scale contradicting the files present is a WARNING naming both.
# Spike enum acceptance (a conforming `scale: spike` fixture passing) is
# asserted in tests/spike-validation.bats (Task 2.2) — not duplicated here.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/story"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

# Minimal valid standard-shaped story.md (model B) used by several fixtures.
write_story_md() {
  local scale_line="$1"
  cat > "$STORY/story.md" <<EOF
---
story: test-scale
type: feature
${scale_line}
version: 1
created: 2026-08-02
---

## Introduction
Scale validation fixture.

### R1. First requirement

#### Acceptance Criteria

- R1.1: WHEN x THE SYSTEM SHALL y.
EOF
}

write_tasks_md() {
  cat > "$STORY/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-02
---

## Task List
- [ ] 1 - Implement
  - Requirements: R1.1
  - Validation: `echo ok`

## Quality Gates
- Done
EOF
}

# --- R2.1: enum enforcement ---

@test "scale: medium is an error naming the value and the valid set" {
  write_story_md "scale: medium"
  write_tasks_md
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e . > /dev/null
  # The error must name the offending value...
  echo "$output" | jq -r '.error_details[]' | grep -q 'medium'
  # ...and the valid set (all four members, so the user can self-correct).
  DETAIL=$(echo "$output" | jq -r '.error_details[]' | grep 'medium')
  echo "$DETAIL" | grep -q 'fast'
  echo "$DETAIL" | grep -q 'standard'
  echo "$DETAIL" | grep -q 'full'
  echo "$DETAIL" | grep -q 'spike'
}

@test "scale: standard on a conforming story passes" {
  write_story_md "scale: standard"
  write_tasks_md
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "pass"'
}

@test "scale: fast on a tasks-only story passes" {
  cat > "$STORY/tasks.md" <<'EOF'
---
story: test-fast
type: feature
scale: fast
version: 1
created: 2026-08-02
---

## Task List
- [ ] 1 - Add field
  - Validation: `npm run lint`

## Quality Gates
- Done
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "pass"'
}

@test "scale: full with story.md, design.md and tasks.md passes" {
  write_story_md "scale: full"
  write_tasks_md
  cat > "$STORY/design.md" <<'EOF'
---
version: 1
created: 2026-08-02
---

## Overview
Design fixture.
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "pass"'
}

# --- R2.2: absent scale field = legacy behavior, byte-identical ---

@test "absent scale field keeps legacy output byte-identical (golden)" {
  # Fixture is identical to the one the golden below was captured from,
  # against the PRE-CHANGE validator (2026-08-02). Any drift — even an added
  # field or reordered key — is a regression against R2.2.
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
  # Run with a fixed relative path so the "story" field is deterministic.
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" story
  [ "$status" -eq 0 ]
  diff <(printf '%s\n' "$GOLDEN") <(printf '%s\n' "$output")
}

# --- R2.3: declared scale vs files present ---

@test "scale: spike with a story.md present warns naming both sides" {
  write_story_md "scale: spike"
  write_tasks_md
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  echo "$output" | jq -e . > /dev/null
  MISMATCH=$(echo "$output" | jq -r '.warning_details[]' | grep -i 'spike')
  # The warning names the declared scale AND the contradicting file.
  echo "$MISMATCH" | grep -q 'story.md'
}

@test "scale: fast with a story.md present warns naming both sides" {
  write_story_md "scale: fast"
  write_tasks_md
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . > /dev/null
  MISMATCH=$(echo "$output" | jq -r '.warning_details[]' | grep -i 'fast')
  echo "$MISMATCH" | grep -q 'story.md'
}
