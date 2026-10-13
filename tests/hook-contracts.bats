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

# --- hooks.json shape and guards from a subdirectory (cwd-relative `if`) ---

@test "hooks.json: every if pattern is rooted with **/, guards fail closed, the Bash guards have no if" {
  H="$PLUGIN_ROOT/hooks/hooks.json"
  jq -e '.description | type == "string" and length > 0' "$H"
  jq -e '[.. | objects | .if? // empty] | length > 0 and all(test("^[A-Za-z]+\\(\\*\\*/"))' "$H"
  jq -e '[.hooks.PreToolUse[].hooks[]] | all(.onFailure == "block")' "$H"
  jq -e '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | has("if")] | all(. == false)' "$H"
  if command grep -q MultiEdit "$PLUGIN_ROOT/scripts/hook-executor-guard.sh"; then echo "dead MultiEdit branch is back"; return 1; fi
}

@test "guards hold when the session cwd is a subdirectory of the project" {
  mkdir -p "$WORK/src/deep" "$WORK/.epic/archive/001-old"
  cd "$WORK/src/deep"
  run bash -c "jq -n --arg f '$WORK/.epic/archive/001-old/story.md' '{tool_name:\"Edit\",tool_input:{file_path:\$f}}' | bash '$PLUGIN_ROOT/scripts/hook-archive-guard.sh'"
  [ "$status" -eq 2 ]
  run bash -c "jq -n --arg f '../../.epic/stories/001-x/tasks.md' '{agent_type:\"epic:executor\",tool_name:\"Write\",tool_input:{file_path:\$f}}' | bash '$PLUGIN_ROOT/scripts/hook-executor-guard.sh'"
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  for c in 'git -C ../.. commit -m x' 'git -c core.hooksPath=/dev/null commit -m x' 'cd ../.. && git commit -m x'; do
    run bash -c "jq -n --arg c '$c' '{agent_type:\"epic:executor\",tool_name:\"Bash\",tool_input:{command:\$c}}' | bash '$PLUGIN_ROOT/scripts/hook-executor-guard.sh'"
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  done
  run bash -c "jq -n '{tool_name:\"Bash\",tool_input:{command:\"cd ../.. && git -c user.email=a@b commit -m x\"}}' | bash '$PLUGIN_ROOT/scripts/hook-commit-identity-guard.sh'"
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

# --- Report guard (SubagentStop) ---

report_guard() { bash "$PLUGIN_ROOT/scripts/hook-report-guard.sh"; }

@test "report guard blocks an Auditor stop when no report was written — the validation one first" {
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' > "$WORK/t.jsonl"
  run bash -c "$(declare -f report_guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n --arg t '$WORK/t.jsonl' '{agent_type:\"epic:auditor\",stop_hook_active:false,agent_transcript_path:\$t}' | report_guard"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block" and (.reason | test("validation-report.yaml"))'
}

@test "report guard lets the stop through once the report is written, or on a second attempt" {
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/w/.epic/stories/001-x/.draft/audit-report.yaml"}}]}}' > "$WORK/t.jsonl"
  run bash -c "$(declare -f report_guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n --arg t '$WORK/t.jsonl' '{agent_type:\"epic:auditor\",stop_hook_active:false,agent_transcript_path:\$t}' | report_guard"
  [ -z "$output" ]
  printf '%s\n' '{"type":"assistant","message":{"content":[]}}' > "$WORK/t2.jsonl"
  run bash -c "$(declare -f report_guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n --arg t '$WORK/t2.jsonl' '{agent_type:\"epic:auditor\",stop_hook_active:true,agent_transcript_path:\$t}' | report_guard"
  [ -z "$output" ]
}

@test "report guard: a validation fail ends the spawn, a validation pass still owes the audit" {
  # One Auditor spawn validates, then audits only on a pass.
  w() { jq -cn --arg c "$1" '{type:"assistant",message:{content:[{type:"tool_use",name:"Write",input:{file_path:"/w/.epic/stories/001-x/.draft/validation-report.yaml",content:$c}}]}}'; }
  w $'story: "001-x"\nverdict: fail' > "$WORK/f.jsonl"
  run bash -c "$(declare -f report_guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n --arg t '$WORK/f.jsonl' '{agent_type:\"epic:auditor\",stop_hook_active:false,agent_transcript_path:\$t}' | report_guard"
  [ -z "$output" ]
  w $'story: "001-x"\nverdict: pass' > "$WORK/p.jsonl"
  run bash -c "$(declare -f report_guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n --arg t '$WORK/p.jsonl' '{agent_type:\"epic:auditor\",stop_hook_active:false,agent_transcript_path:\$t}' | report_guard"
  echo "$output" | jq -e '.decision == "block" and (.reason | test("audit-report.yaml"))'
}
