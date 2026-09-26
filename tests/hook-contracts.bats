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

# --- Executor guard (PreToolUse) ---

guard() { bash "$PLUGIN_ROOT/scripts/hook-executor-guard.sh"; }

@test "executor guard denies git commit inside the Executor" {
  run bash -c "$(declare -f guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n '{agent_type:\"epic:executor\",tool_name:\"Bash\",tool_input:{command:\"git add a && git commit -m x\"}}' | guard"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "executor guard denies editing tasks.md inside the Executor" {
  run bash -c "$(declare -f guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n '{agent_type:\"epic:executor\",tool_name:\"Edit\",tool_input:{file_path:\"/w/.epic/stories/001-x/tasks.md\"}}' | guard"
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "executor guard leaves the orchestrator and harmless commands alone" {
  run bash -c "$(declare -f guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n '{tool_name:\"Bash\",tool_input:{command:\"git commit -m x\"}}' | guard"
  [ -z "$output" ]
  run bash -c "$(declare -f guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n '{agent_type:\"epic:executor\",tool_name:\"Bash\",tool_input:{command:\"git log --grep commit\"}}' | guard"
  [ -z "$output" ]
  run bash -c "$(declare -f guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n '{agent_type:\"epic:executor\",tool_name:\"Write\",tool_input:{file_path:\"/w/src/app.js\"}}' | guard"
  [ -z "$output" ]
}

# --- Report guard (SubagentStop) ---

report_guard() { bash "$PLUGIN_ROOT/scripts/hook-report-guard.sh"; }

@test "report guard blocks a Validator stop when its report was never written" {
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' > "$WORK/t.jsonl"
  run bash -c "$(declare -f report_guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n --arg t '$WORK/t.jsonl' '{agent_type:\"epic:validator\",stop_hook_active:false,agent_transcript_path:\$t}' | report_guard"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block" and (.reason | test("validation-report.yaml"))'
}

@test "report guard lets the stop through once the report is written, or on a second attempt" {
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/w/.epic/stories/001-x/.draft/audit-report.yaml"}}]}}' > "$WORK/t.jsonl"
  run bash -c "$(declare -f report_guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n --arg t '$WORK/t.jsonl' '{agent_type:\"epic:auditor\",stop_hook_active:false,agent_transcript_path:\$t}' | report_guard"
  [ -z "$output" ]
  printf '%s\n' '{"type":"assistant","message":{"content":[]}}' > "$WORK/t2.jsonl"
  run bash -c "$(declare -f report_guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n --arg t '$WORK/t2.jsonl' '{agent_type:\"epic:validator\",stop_hook_active:true,agent_transcript_path:\$t}' | report_guard"
  [ -z "$output" ]
}
