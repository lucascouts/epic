#!/usr/bin/env bats
# Story 007, Task 2.2 — spike Verdict contract in scripts/validate-story.sh.
# Contract (R1.1 shape, R1.2–R1.4):
#   - A spike is tasks-only and MUST carry a `## Verdict` section with a valid
#     `status:` line (open | promote | wont-do); missing Verdict is an ERROR.
#   - `status: promote` without a `promoted-to:` reference is an ERROR.
#   - Any `Requirements:` field or R-number token in a spike tasks.md is an
#     ERROR — spikes have no requirements chain.
# The conforming-fixture test also asserts the spike template shape from
# references/tasks.md (Task 2.1) validates clean, and that `spike` is an
# accepted member of the scale enum (complementing tests/scale-validation.bats).

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/story"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

# A spike tasks.md per the sanctioned template: tasks-only, Verdict section.
# $1 = Verdict block content (lines after "## Verdict").
write_spike() {
  cat > "$STORY/tasks.md" <<EOF
---
story: probe-cache-strategy
type: feature
scale: spike
version: 1
created: 2026-08-02
---

## Overview
Probe: is the cache layer worth it?

## Task List
- [ ] 1 - Benchmark cold vs warm path
  - Validation: \`./bench.sh\`

## Verdict
$1
EOF
}

@test "conforming open spike passes validation" {
  write_spike '- status: open
- conclusion: pending'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "pass"'
}

@test "spike without a Verdict section is an error (R1.2)" {
  cat > "$STORY/tasks.md" <<'EOF'
---
story: probe-cache-strategy
type: feature
scale: spike
version: 1
created: 2026-08-02
---

## Task List
- [ ] 1 - Benchmark cold vs warm path
  - Validation: `./bench.sh`
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e . > /dev/null
  echo "$output" | jq -r '.error_details[]' | grep -qi 'verdict'
}

@test "spike promote without promoted-to is an error (R1.3)" {
  write_spike '- status: promote
- conclusion: cache pays off, build the real story'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -r '.error_details[]' | grep -qi 'promoted-to'
}

@test "spike promote with promoted-to recorded passes" {
  write_spike '- status: promote
- conclusion: cache pays off, build the real story
- promoted-to: 012'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "pass"'
}

@test "spike wont-do verdict passes" {
  write_spike '- status: wont-do
- conclusion: latency win too small to justify the layer'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "pass"'
}

@test "Requirements field in a spike tasks.md is an error (R1.4)" {
  cat > "$STORY/tasks.md" <<'EOF'
---
story: probe-cache-strategy
type: feature
scale: spike
version: 1
created: 2026-08-02
---

## Task List
- [ ] 1 - Benchmark cold vs warm path
  - Requirements: R1.1
  - Validation: `./bench.sh`

## Verdict
- status: open
- conclusion: pending
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -r '.error_details[]' | grep -qi 'no requirements chain'
}

@test "bare R-number token in a spike tasks.md is an error (R1.4)" {
  write_spike '- status: open
- conclusion: pending, see R2.1 upstream'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  echo "$output" | jq -r '.error_details[]' | grep -qi 'no requirements chain'
}
