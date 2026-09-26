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

@test "compact restore stays under the 10,000-character hook cap and names the file" {
  head -c 15000 /dev/zero | tr '\0' 'x' | fold -w 100 > "$WORK/.epic/stories/001-old/.draft/compact-snapshot.md"
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/hook-session-restore.sh"
  [ "$status" -eq 0 ]
  [ "${#output}" -lt 10000 ]
  [[ "$output" == *"truncated"*"001-old/.draft/compact-snapshot.md"* ]]
}

@test "compact restore prints a small snapshot whole" {
  printf 'Story: 001-old\n- Tasks: 1/3\n' > "$WORK/.epic/stories/001-old/.draft/compact-snapshot.md"
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/hook-session-restore.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- Tasks: 1/3"* ]]
  [[ "$output" != *"truncated"* ]]
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
