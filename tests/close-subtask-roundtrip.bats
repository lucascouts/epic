#!/usr/bin/env bats
# Interface verification: executor closing block → close-subtask.sh args →
# JSON verdict, driven as ONE flow the way run-mode's closing step drives it.
#
# The executor report's closing block is simulated as the JSON the executor.md
# contract defines (sub-task id, outcome done | close-tilde + qualifier +
# reason), the test lifts the script arguments from it exactly as the
# orchestrator does, and the assertions read ONLY what run-mode reads:
# the returned census, status_written, and embedded validate verdict — no
# re-read of tasks.md for the census, the file is checked only for the final
# box states and status stamp.
#
# EPIC_PLUGIN_ROOT overrides root resolution so a copy of this file outside
# tests/ can run against the plugin.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="${EPIC_PLUGIN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  SCRIPT="$PLUGIN_ROOT/scripts/close-subtask.sh"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  STORY="$PROJ/.epic/stories/011-roundtrip"
  mkdir -p "$STORY"
  write_fixture_story
}

teardown() {
  rm -rf "$WORK"
}

# The fixture validates with 0 errors and 0 warnings, so the embedded verdict
# asserted below is the fixture's own truth.
write_fixture_story() {
  cat > "$STORY/story.md" <<'EOF'
---
story: roundtrip
type: feature
scale: standard
status: in-progress
version: 1
created: 2026-08-16
---

## Introduction
Round-trip fixture story.

### R1. First requirement
#### Acceptance Criteria
- R1.1: WHEN a THE SYSTEM SHALL b
- R1.2: WHEN c THE SYSTEM SHALL d
EOF
  cat > "$STORY/tasks.md" <<'EOF'
---
story: roundtrip
type: feature
scale: standard
status: in-progress
version: 1
created: 2026-08-16
---

## Task List
- [ ] 1.1 - Ship the first slice
  - _Complexity: Simple | Tests: none | Risks: none | Dependencies: None_
  - Requirements: R1.1
  - Validation: bats green
- [ ] 1.2 - Ship the second slice
  - Requirements: R1.2
  - Validation: bats green
  - Commit: "feat(011): ship both slices"

## Quality Gates
- Counts consistent
EOF
}

status_line_of() {
  sed -n '2,/^---$/p' "$1" | sed -n 's/^status:[[:space:]]*//p' | head -1
}

# close_from_block <closing-block-json>: lift the script arguments from the
# executor closing block the way run-mode does, then invoke the script.
close_from_block() {
  local block="$1" task outcome qualifier reason
  task=$(jq -r '.task' <<< "$block")
  outcome=$(jq -r '.outcome' <<< "$block")
  cd "$PROJ"
  if [ "$outcome" = "close-tilde" ]; then
    qualifier=$(jq -r '.qualifier' <<< "$block")
    reason=$(jq -r '.reason' <<< "$block")
    run --separate-stderr bash "$SCRIPT" .epic/stories/011-roundtrip "$task" \
      --tilde "$qualifier: $reason"
  else
    run --separate-stderr bash "$SCRIPT" .epic/stories/011-roundtrip "$task"
  fi
}

@test "round-trip: one done block + one close-tilde deferred block" {
  # --- closing block 1: the executor finished 1.1 ---
  close_from_block '{"task":"1.1","outcome":"done","commit":"feat(011): ship both slices"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  echo "$output" | jq -e '.task == "1.1" and .box == "x"'
  # run-mode reads the census from the JSON instead of re-reading tasks.md:
  echo "$output" | jq -e '.census.open == 1'
  echo "$output" | jq -e '.status_written == null'   # work still open

  # --- closing block 2: 1.2 closed without the work being done ---
  close_from_block '{"task":"1.2","outcome":"close-tilde","qualifier":"deferred","reason":"needs the live account"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  echo "$output" | jq -e '.task == "1.2" and .box == "~" and .qualifier == "deferred"'
  echo "$output" | jq -e '.census.total == 2 and .census.open == 0 and .census.closed == 1 and .census.deferred == 1'
  # A deferred box blocks done — no transition, so no archive offer:
  echo "$output" | jq -e '.status_written == null'
  [ "$(echo "$output" | jq -r '.status_written.to // "none"')" != done ]
  # The embedded verdict is the validation:
  echo "$output" | jq -e '.validate.errors == 0 and (.validate | has("status"))'

  # --- the artifacts agree with everything the JSON claimed ---
  grep -qE '^[[:space:]]*- \[x\] 1\.1 - Ship the first slice' "$STORY/tasks.md"
  grep -qE '^[[:space:]]*- \[~\] 1\.2 - Ship the second slice \(deferred: needs the live account\)' "$STORY/tasks.md"
  [ "$(status_line_of "$STORY/tasks.md")" = in-progress ]
  [ "$(status_line_of "$STORY/story.md")" = in-progress ]
}

@test "round-trip: both blocks done — the run flips done and the archive-offer trigger fires" {
  close_from_block '{"task":"1.1","outcome":"done"}'
  [ "$status" -eq 0 ]
  close_from_block '{"task":"1.2","outcome":"done"}'
  [ "$status" -eq 0 ]
  # The archive offer keys on status_written.to == "done". Cited by name, not
  # by line — run-mode.md's "End of Run — Validator, archive, index" trigger —
  # because line numbers go stale.
  echo "$output" | jq -e '.status_written.from == "in-progress" and .status_written.to == "done"'
  [ "$(echo "$output" | jq -r '.status_written.to')" = done ]
  grep -qE '^[[:space:]]*- \[x\] 1\.2 - Ship the second slice' "$STORY/tasks.md"
  [ "$(status_line_of "$STORY/tasks.md")" = done ]
  [ "$(status_line_of "$STORY/story.md")" = done ]
}
