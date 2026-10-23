#!/usr/bin/env bats
# hook-legend-guard.sh: a process word that reached a layperson with no legend
# blocks the end of the turn once; everything else fails open.
#
#   L1  layperson, "Red" in a status line, no legend → block naming Red
#   L2  the same turn with a legend line → allow
#   L3  developer requester → allow
#   L4  stop_hook_active → allow
#   L5  a word from an EARLIER turn does not count; only this turn's text does
#   L6  no transcript, no stories, or no requester field → allow
#   L7  hooks.json registers it on Stop, and the commit guard's reason says commit silently

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$PLUGIN_ROOT/scripts/hook-legend-guard.sh"
  PROJ=$(mktemp -d)
  mkdir -p "$PROJ/.epico/stories/001-demo"
  TR="$PROJ/transcript.jsonl"
}

teardown() { rm -rf "$PROJ"; }

story() { # story <requester line or "">
  {
    echo '---'; echo 'scale: fast'; [[ -z "$1" ]] || echo "$1"; echo '---'
    echo '## Task List'; echo '- [ ] 1 - Do it'
  } > "$PROJ/.epico/stories/001-demo/tasks.md"
}

# transcript <assistant text of this turn...> — one prior turn mentioning Green,
# then the current prompt, a tool round trip, and the given text blocks.
transcript() {
  {
    jq -cn '{type:"user", message:{content:"primeiro pedido"}}'
    jq -cn '{type:"assistant", message:{content:[{type:"text", text:"Green na rodada anterior."}]}}'
    jq -cn '{type:"user", message:{content:"agora o pokedex"}}'
    jq -cn '{type:"assistant", message:{content:[{type:"tool_use", id:"t1", name:"Bash", input:{}}]}}'
    jq -cn '{type:"user", message:{content:[{type:"tool_result", tool_use_id:"t1", content:"ok"}]}}'
    for t in "$@"; do jq -cn --arg t "$t" '{type:"assistant", message:{content:[{type:"text", text:$t}]}}'; done
  } > "$TR"
}

run_hook() { run bash -c "jq -cn --arg tr '$TR' --arg cwd '$PROJ' --argjson a ${1:-false} '{transcript_path:\$tr, cwd:\$cwd, stop_hook_active:\$a}' | bash '$HOOK'"; }

@test "L1 a layperson turn with Red and no legend blocks, naming Red" {
  story 'requester: layperson'
  transcript 'Red confirmado. Agora a implementação.' 'Pronto! Seu programa funciona.'
  run_hook
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -r .reason | grep -qF 'no legend: Red.'
  echo "$output" | jq -r .reason | grep -qF 'Do not mention this check'
}

@test "L2 the same turn with a legend line lets the turn end" {
  story 'requester: layperson'
  transcript 'Red confirmado.' 'Pronto!
*Red* — o teste foi escrito antes e falhou de propósito.'
  run_hook
  [ -z "$output" ]
}

@test "L3 a developer requester is never checked" {
  story 'requester: developer'
  transcript 'Red confirmed, Green next.'
  run_hook
  [ -z "$output" ]
}

@test "L4 the second stop attempt is let through" {
  story 'requester: layperson'
  transcript 'Red confirmado.'
  run_hook true
  [ -z "$output" ]
}

@test "L5 a word said in an earlier turn does not count" {
  story 'requester: layperson'
  transcript 'Pronto, tudo funcionando.'
  run_hook
  [ -z "$output" ]
}

@test "L6 no transcript, no stories, or no requester field fails open" {
  story ''
  transcript 'Red confirmado.'
  run_hook
  [ -z "$output" ]
  story 'requester: layperson'
  rm -f "$TR"
  run_hook
  [ -z "$output" ]
  rm -rf "$PROJ/.epico"
  transcript 'Red confirmado.'
  run_hook
  [ -z "$output" ]
}

@test "L7 registered on Stop; the commit guard tells the model to commit silently" {
  jq -e '.hooks.Stop[].hooks[] | select(.command | contains("hook-legend-guard.sh"))' "$PLUGIN_ROOT/hooks/hooks.json"
  grep -qF 'Commit silently' "$PLUGIN_ROOT/scripts/hook-commit-guard.sh"
}

@test "L8 a story archived in the same turn is still the one checked" {
  story 'requester: layperson'
  mkdir -p "$PROJ/.epico/archive"
  mv "$PROJ/.epico/stories/001-demo" "$PROJ/.epico/archive/001-demo"
  transcript 'Red confirmado.' 'Pronto, arquivei o plano.'
  run_hook
  echo "$output" | jq -e '.decision == "block"'
}
