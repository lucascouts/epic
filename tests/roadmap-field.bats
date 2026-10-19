#!/usr/bin/env bats
# `roadmap:` in tasks.md: the ROADMAP task IDs a story works on, so a stage
# checkpoint can reconcile stories against the plan. Checked — never enforced:
# a malformed list or an unknown ID is a warning, never an error.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/proj/.epic/stories/001-x"
  mkdir -p "$STORY"
}

teardown() { rm -rf "$WORK"; }

write_tasks() { # write_tasks <roadmap line or "">
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-10-19'
    echo 'scale: fast'
    [[ -z "$1" ]] || echo "$1"
    echo '---'
    echo
    echo '## Task List'
    echo '- [ ] 1 - Implement'
    echo '  - Commit: "feat(001): implement"'
    echo '  - [ ] 1.1 - Write it'
    echo '    - Validation: `echo ok`'
  } > "$STORY/tasks.md"
}

roadmap_with() { # roadmap_with <path under proj> — a ROADMAP holding 2.4.1 (task line) and 2.4.2 (table row)
  mkdir -p "$(dirname "$WORK/proj/$1")"
  {
    echo '| 2.4.2 | Store tables | Medium | done |'
    echo
    echo '- [x] **2.4.1 Add whatsmeow under a boundary rule** · Simple · `done`'
  } > "$WORK/proj/$1"
}

validate() { bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"; }
roadmap_warnings() { printf '%s' "$1" | jq -r '.warnings[]?' | grep -i "'roadmap'" || true; }
roadmap_errors() { printf '%s' "$1" | jq -r '.error_details[]?' | grep -i 'roadmap' || true; }

@test "a well-formed list of known IDs is silent" {
  roadmap_with docs/ROADMAP.md
  write_tasks 'roadmap: [2.4.1, 2.4.2]'
  run validate
  [ -z "$(roadmap_warnings "$output")" ]
  [ -z "$(roadmap_errors "$output")" ]
}

@test "no roadmap field is fail-open" {
  write_tasks ''
  run validate
  [ -z "$(roadmap_warnings "$output")" ]
}

@test "a malformed list is a warning naming the form, never an error" {
  write_tasks 'roadmap: 2.4.1 and 2.4.2'
  run validate
  roadmap_warnings "$output" | grep -qF 'roadmap: [2.4.1, 2.4.2]'
  [ -z "$(roadmap_errors "$output")" ]
}

@test "an ID no ROADMAP or stage file holds is a warning naming it" {
  roadmap_with ROADMAP.md
  write_tasks 'roadmap: [2.4.1, 9.9.9]'
  run validate
  msg=$(roadmap_warnings "$output")
  echo "$msg" | grep -qF 'task 9.9.9'
  ! echo "$msg" | grep -qF 'task 2.4.1'
  [ -z "$(roadmap_errors "$output")" ]
}

@test "stage files are read too" {
  roadmap_with docs/stages/02-spike.md
  write_tasks 'roadmap: [2.4.2]'
  run validate
  [ -z "$(roadmap_warnings "$output")" ]
}

@test "without any ROADMAP an ID cannot be checked and nothing is said" {
  write_tasks 'roadmap: [7.1.1]'
  run validate
  [ -z "$(roadmap_warnings "$output")" ]
}

@test "clarify asks it only where the project numbers its tasks, never at Fast, instant, --auto or headless; batch adds a Roadmap column" {
  f="$PLUGIN_ROOT/references/clarify.md"
  grep -qF '### The ROADMAP tasks (only when the project numbers them)' "$f"
  grep -qF 'A project without one never sees the question' "$f"
  grep -qF 'Not asked at Fast scale, in instant mode, under `--auto` or headless' "$f"
  grep -qF 'roadmap: [2.4.1, 2.4.2]' "$PLUGIN_ROOT/references/tasks.md"
  grep -qF 'the table gains a `Roadmap` column' "$PLUGIN_ROOT/references/batch-create.md"
}
