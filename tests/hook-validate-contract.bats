#!/usr/bin/env bats
# Output contract of scripts/hook-validate.sh (PostToolUse on Write).
#
# On exit 0, Claude Code shows a PostToolUse hook's stdout to Claude only when
# it is a JSON object carrying hookSpecificOutput.additionalContext; anything
# else goes to the debug log. So:
#   - a story that fails validation prints exactly that object, naming the errors;
#   - a story that passes prints nothing;
#   - a write outside .epic/stories/ prints nothing;
#   - the hook always exits 0, so it never blocks the write.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  WORK=$(mktemp -d)
  STORY="$WORK/.epic/stories/001-sample"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

payload() {
  jq -n --arg p "$1" '{hook_event_name: "PostToolUse", tool_name: "Write", tool_input: {file_path: $p}}'
}

write_valid_fast() {
  cat > "$STORY/tasks.md" <<'EOF'
---
story: sample
type: feature
scale: fast
version: 1
created: 2026-01-01
---

## Overview
Contract fixture.

## Task List
- [ ] 1 - Add field
  - Validation: `true`

## Quality Gates
- Tests pass
EOF
}

@test "invalid story: prints one additionalContext object and exits 0" {
  printf -- '---\nstory: sample\n---\n\nno sections\n' > "$STORY/tasks.md"
  run bash -c "$(declare -f payload); payload '$STORY/tasks.md' | bash '$PLUGIN_ROOT/scripts/hook-validate.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("validate-story found [0-9]+ error")'
  [ "$(echo "$output" | jq -c 'keys')" = '["hookSpecificOutput"]' ]
}

@test "valid story: prints nothing and exits 0" {
  write_valid_fast
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 0 ]
  run bash -c "$(declare -f payload); payload '$STORY/tasks.md' | bash '$PLUGIN_ROOT/scripts/hook-validate.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "write outside .epic/stories: prints nothing and exits 0" {
  run bash -c "$(declare -f payload); payload '$WORK/README.md' | bash '$PLUGIN_ROOT/scripts/hook-validate.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
