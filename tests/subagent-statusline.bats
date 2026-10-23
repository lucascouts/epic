#!/usr/bin/env bats
# subagentStatusLine contract: JSON rows on stdin, one {"id","content"} line
# per row on stdout. The shipped command is run as written in settings.json —
# Claude Code runs it in a clean environment, so it carries no script path.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CMD=$(jq -r '.subagentStatusLine.command' "$PLUGIN_ROOT/settings.json")
}

@test "settings.json declares a command-type subagentStatusLine" {
  jq -e '.subagentStatusLine.type == "command" and (.subagentStatusLine.command | length > 0)' "$PLUGIN_ROOT/settings.json"
}

@test "one id/content line per Epico row; other plugins' rows are left to the default" {
  stdin='{"columns":120,"tasks":[
    {"id":"t1","agentType":"epico:executor","label":"Write the parser","tokenCount":12345},
    {"id":"t2","agentType":"epico:auditor","description":"Validate 004","tokenCount":0},
    {"id":"t3","agentType":"other:helper","label":"x","tokenCount":5}]}'
  run bash -c "$CMD" <<< "$stdin"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  echo "${lines[0]}" | jq -e '. == {id:"t1",content:"[epico] executor · Write the parser · 12.3k tokens"}'
  echo "${lines[1]}" | jq -e '.id == "t2" and .content == "[epico] auditor · 0k tokens"'
}

@test "no rows, no output, exit 0" {
  run bash -c "$CMD" <<< '{"tasks":[]}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
