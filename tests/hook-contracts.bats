#!/usr/bin/env bats
# Output contracts of the SessionStart hooks whose stdout reaches Claude.
#   - compact restore: never past Claude Code's 10,000-character hook cap
#   - orphan drafts after /clear: one removal line per orphan, never a glob

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  mkdir -p "$WORK/.epico/stories/001-old/.draft" "$WORK/.epico/stories/002-live/.draft"
}

teardown() {
  rm -rf "$WORK"
}

@test "compact restore renders progress first and stays under the 10,000-character cap" {
  printf -- '---\nstory: old\n---\n## Task List\n- [x] 1 - Done\n- [ ] 2 - Next\n' > "$WORK/.epico/stories/001-old/tasks.md"
  head -c 15000 /dev/zero | tr '\0' 'x' | fold -w 100 > "$WORK/.epico/stories/001-old/.draft/meta.yaml"
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/hook-session-restore.sh"
  [ "$status" -eq 0 ]
  [ "${#output}" -lt 10000 ]
  [[ "$output" == *"- Tasks: 1/2 completed"*"Truncated"*".epico/stories/001-old"* ]]
}

@test "compact restore prints a small state whole and writes nothing to disk" {
  printf -- '---\nstory: old\n---\n## Task List\n- [ ] 1 - Next\n' > "$WORK/.epico/stories/001-old/tasks.md"
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/hook-session-restore.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- Tasks: 0/1 completed"* ]]
  [[ "$output" != *"Truncated"* ]]
  [ ! -e "$WORK/.epico/stories/001-old/.draft/compact-snapshot.md" ]
}

@test "orphan drafts: one rm line per old draft, the live draft untouched and unnamed" {
  touch -d '40 days ago' "$WORK/.epico/stories/001-old/.draft"
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/hook-orphan-drafts.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rm -rf .epico/stories/001-old/.draft"* ]]
  [[ "$output" != *"002-live"* ]]
  [[ "$output" != *"*"* ]]
  [ -d "$WORK/.epico/stories/001-old/.draft" ]
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
  run bash -c "$(declare -f guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n '{agent_type:\"epico:executor\",tool_name:\"Bash\",tool_input:{command:\"git add a && git commit -m x\"}}' | guard"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "executor guard denies editing tasks.md inside the Executor" {
  run bash -c "$(declare -f guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n '{agent_type:\"epico:executor\",tool_name:\"Edit\",tool_input:{file_path:\"/w/.epico/stories/001-x/tasks.md\"}}' | guard"
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "executor guard leaves the orchestrator and harmless commands alone" {
  run bash -c "$(declare -f guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n '{tool_name:\"Bash\",tool_input:{command:\"git commit -m x\"}}' | guard"
  [ -z "$output" ]
  run bash -c "$(declare -f guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n '{agent_type:\"epico:executor\",tool_name:\"Bash\",tool_input:{command:\"git log --grep commit\"}}' | guard"
  [ -z "$output" ]
  run bash -c "$(declare -f guard); PLUGIN_ROOT='$PLUGIN_ROOT'; jq -n '{agent_type:\"epico:executor\",tool_name:\"Write\",tool_input:{file_path:\"/w/src/app.js\"}}' | guard"
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
  mkdir -p "$WORK/src/deep" "$WORK/.epico/archive/001-old"
  cd "$WORK/src/deep"
  run bash -c "jq -n --arg f '$WORK/.epico/archive/001-old/story.md' '{tool_name:\"Edit\",tool_input:{file_path:\$f}}' | bash '$PLUGIN_ROOT/scripts/hook-archive-guard.sh'"
  [ "$status" -eq 2 ]
  run bash -c "jq -n --arg f '../../.epico/stories/001-x/tasks.md' '{agent_type:\"epico:executor\",tool_name:\"Write\",tool_input:{file_path:\$f}}' | bash '$PLUGIN_ROOT/scripts/hook-executor-guard.sh'"
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  for c in 'git -C ../.. commit -m x' 'git -c core.hooksPath=/dev/null commit -m x' 'cd ../.. && git commit -m x'; do
    run bash -c "jq -n --arg c '$c' '{agent_type:\"epico:executor\",tool_name:\"Bash\",tool_input:{command:\$c}}' | bash '$PLUGIN_ROOT/scripts/hook-executor-guard.sh'"
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  done
  run bash -c "jq -n '{tool_name:\"Bash\",tool_input:{command:\"cd ../.. && git -c user.email=a@b commit -m x\"}}' | bash '$PLUGIN_ROOT/scripts/hook-commit-identity-guard.sh'"
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

# --- Report guard (SubagentStop) ---

# The transcript carries only the spawn prompt; the verdict comes from disk.
spawn_transcript() {  # <file> <story-dir line> [project-root line]
  jq -cn --arg s "$2" --arg r "${3:-}" '{type:"user",message:{role:"user",content:[{type:"text",text:("> Validate the implementation of these completed tasks.\n>\n> Story directory: " + $s + "\n" + (if $r == "" then "" else "> Project root: " + $r + "\n" end))}]}}' > "$1"
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' >> "$1"
}
report_guard() {  # <transcript> [stop_hook_active]
  jq -n --arg t "$1" --arg c "$WORK" --argjson a "${2:-false}" '{agent_type:"epico:auditor",stop_hook_active:$a,agent_transcript_path:$t,cwd:$c}' \
    | bash "$PLUGIN_ROOT/scripts/hook-report-guard.sh"
}
D() { printf '%s' "$WORK/.epico/stories/001-old/.draft"; }

@test "report guard blocks an Auditor stop when no report is on disk — the validation one first" {
  spawn_transcript "$WORK/t.jsonl" "$WORK/.epico/stories/001-old"
  run report_guard "$WORK/t.jsonl"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block" and (.reason | test("validation-report.yaml"))'
}

@test "report guard reads the disk, not the transcript: a Write the transcript shows proves nothing" {
  spawn_transcript "$WORK/t.jsonl" ".epico/stories/001-old"
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/w/.epico/stories/001-old/.draft/audit-report.yaml"}}]}}' >> "$WORK/t.jsonl"
  run report_guard "$WORK/t.jsonl"
  echo "$output" | jq -e '.decision == "block"'
  printf 'story: "001-old"\nverdict: pass\n' > "$(D)/audit-report.yaml"
  run report_guard "$WORK/t.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "report guard: a validation fail on disk ends the spawn, a validation pass still owes the audit" {
  spawn_transcript "$WORK/t.jsonl" "\`.epico/stories/001-old\`" "$WORK"
  printf 'story: "001-old"\nverdict: fail\n' > "$(D)/validation-report.yaml"
  run report_guard "$WORK/t.jsonl"
  [ -z "$output" ]
  printf 'story: "001-old"\nverdict: pass\n' > "$(D)/validation-report.yaml"
  run report_guard "$WORK/t.jsonl"
  echo "$output" | jq -e '.decision == "block" and (.reason | test("audit-report.yaml"))'
}

@test "report guard fails open: second stop attempt, no story directory, another agent, empty file is not a report" {
  spawn_transcript "$WORK/t.jsonl" "$WORK/.epico/stories/001-old"
  run report_guard "$WORK/t.jsonl" true
  [ -z "$output" ]
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"validate it"}}' > "$WORK/n.jsonl"
  run report_guard "$WORK/n.jsonl"
  [ -z "$output" ]
  run bash -c "jq -n '{agent_type:\"epico:executor\",stop_hook_active:false}' | bash '$PLUGIN_ROOT/scripts/hook-report-guard.sh'"
  [ -z "$output" ]
  : > "$(D)/audit-report.yaml"
  run report_guard "$WORK/t.jsonl"
  echo "$output" | jq -e '.decision == "block"'
}
