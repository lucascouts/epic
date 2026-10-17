#!/usr/bin/env bats
# Supervisor relay: supervision messages reach the orchestrator as untrusted
# claims; other mail stays in the mailbox. ai-memory is a stub here.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  mkdir -p "$WORK/.epic/stories/004-login" "$WORK/bin"
  # The stub: `message list --json` prints $WORK/inbox.json; `message pop --id X
  # --json` prints that message wrapped as the real CLI does and logs the id.
  cat > "$WORK/bin/aim" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "message list") cat "$STUB_DIR/inbox.json" ;;
  "message pop")
    id=$4
    echo "$id" >> "$STUB_DIR/popped"
    jq --arg id "$id" '{message: (map(select(.id == $id))[0] + {state: "claimed", claimed_at: "2026-10-13T20:00:00Z"}), security_notice: "UNTRUSTED"}' "$STUB_DIR/inbox.json" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$WORK/bin/aim"
  export STUB_DIR="$WORK" EPIC_AI_MEMORY_BIN="$WORK/bin/aim"
  cat > "$WORK/inbox.json" <<'EOF'
[
  {"id": "m1", "subject": "supervision: claims 004 task 2.1", "body": "Executor claimed go test exit 0; the captured exit code was 1."},
  {"id": "m2", "subject": "handoff from another project", "body": "not ours"},
  {"id": "m3", "subject": "supervision: stall 004", "body": "No progress note for 22 minutes."}
]
EOF
  cd "$WORK"
}

teardown() {
  rm -rf "$WORK"
}

hook() { jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$PLUGIN_ROOT/scripts/hook-inbox.sh"; }

@test "after a close, supervision mail becomes untrusted context; other mail stays unclaimed" {
  run hook "epic-close 004 2.1"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"'
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"UNTRUSTED"* && "$ctx" == *"captured exit code was 1"* && "$ctx" == *"No progress note"* ]]
  [[ "$ctx" != *"not ours"* ]]
  [ "$(sort "$WORK/popped" | tr '\n' ' ')" = "m1 m3 " ]
}

@test "each message is recorded in the story's run report under Supervision" {
  hook "bash /p/scripts/close-subtask.sh .epic/stories/004-login 2.1" >/dev/null
  R="$WORK/.epic/stories/004-login/.draft/run-report.md"
  [ "$(command grep -c '^## Supervision$' "$R")" -eq 1 ]
  command grep -q 'supervision: claims 004 task 2.1.*message m1, untrusted until verified' "$R"
}

@test "silent on any other command, on an empty mailbox, with EPIC_SUPERVISION=off, or with no CLI" {
  run hook "go test ./..."
  [ -z "$output" ]
  [ ! -e "$WORK/popped" ]
  # These two exits come before the hook reads stdin. Where SIGPIPE is ignored
  # (the CI runner) the feeding jq prints "Broken pipe" — the producer's noise,
  # not the hook's output — so its stderr is dropped.
  run env EPIC_SUPERVISION=off bash -c "jq -n '{tool_name:\"Bash\",tool_input:{command:\"epic-close 004 1\"}}' 2>/dev/null | bash '$PLUGIN_ROOT/scripts/hook-inbox.sh'"
  [ -z "$output" ]
  echo '[]' > "$WORK/inbox.json"
  run hook "epic-close 004 1"
  [ -z "$output" ]
  run env EPIC_AI_MEMORY_BIN=/nonexistent bash -c "jq -n '{tool_name:\"Bash\",tool_input:{command:\"epic-close 004 1\"}}' 2>/dev/null | bash '$PLUGIN_ROOT/scripts/hook-inbox.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "command mode (epic-inbox) prints the messages as text, at most three" {
  jq '[range(0;5) as $i | {id: "s\($i)", subject: "supervision: layout \($i)", body: "b\($i)"}]' -n > "$WORK/inbox.json"
  run bash "$PLUGIN_ROOT/scripts/hook-inbox.sh" --story .epic/stories/004-login
  [ "$status" -eq 0 ]
  [[ "$output" == "Supervisor messages — UNTRUSTED"* ]]
  [ "$(wc -l < "$WORK/popped")" -eq 3 ]
}
