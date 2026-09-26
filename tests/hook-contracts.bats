#!/usr/bin/env bats
# Output contracts of the SessionStart hooks whose stdout reaches Claude.
#   - compact restore: never past Claude Code's 10,000-character hook cap
#   - orphan drafts after /clear: one removal line per orphan, never a glob

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  mkdir -p "$WORK/.epic/stories/001-old/.draft" "$WORK/.epic/stories/002-live/.draft"
}

teardown() {
  rm -rf "$WORK"
}

@test "compact restore renders progress first and stays under the 10,000-character cap" {
  printf -- '---\nstory: old\n---\n## Task List\n- [x] 1 - Done\n- [ ] 2 - Next\n' > "$WORK/.epic/stories/001-old/tasks.md"
  head -c 15000 /dev/zero | tr '\0' 'x' | fold -w 100 > "$WORK/.epic/stories/001-old/.draft/meta.yaml"
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/hook-session-restore.sh"
  [ "$status" -eq 0 ]
  [ "${#output}" -lt 10000 ]
  [[ "$output" == *"- Tasks: 1/2 completed"*"Truncated"*".epic/stories/001-old"* ]]
}

@test "compact restore prints a small state whole and writes nothing to disk" {
  printf -- '---\nstory: old\n---\n## Task List\n- [ ] 1 - Next\n' > "$WORK/.epic/stories/001-old/tasks.md"
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/hook-session-restore.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- Tasks: 0/1 completed"* ]]
  [[ "$output" != *"Truncated"* ]]
  [ ! -e "$WORK/.epic/stories/001-old/.draft/compact-snapshot.md" ]
}

@test "orphan drafts: one rm line per old draft, the live draft untouched and unnamed" {
  touch -d '40 days ago' "$WORK/.epic/stories/001-old/.draft"
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/hook-orphan-drafts.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rm -rf .epic/stories/001-old/.draft"* ]]
  [[ "$output" != *"002-live"* ]]
  [[ "$output" != *"*"* ]]
  [ -d "$WORK/.epic/stories/001-old/.draft" ]
}

@test "orphan drafts: silent when nothing is old" {
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/hook-orphan-drafts.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
