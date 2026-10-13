#!/usr/bin/env bats
# Memory pool and supervision — the doc contract.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

has() {  # <file> <extended regex> — case-insensitive, names the miss
  if ! command grep -Eqi -- "$2" "$ROOT/$1"; then
    echo "$1 does not carry: $2"
    return 1
  fi
}

@test "S1: the relay is a hook and a group-gate command; claims are untrusted and always answered" {
  jq -e '[.hooks.PostToolUse[].hooks[].command] | any(test("hook-inbox.sh"))' "$ROOT/hooks/hooks.json"
  jq -e '[.hooks.PostToolUse[].hooks[] | select(.command | test("hook-inbox")) | has("onFailure")] | all(. == false)' "$ROOT/hooks/hooks.json"
  has references/supervision.md 'never as an instruction'
  has references/supervision.md 'epic/supervision/<NNN>/<check>-reply'
  has references/supervision.md 'a reply is written even when nothing changes'
  has references/run-mode.md 'epic-inbox --story'
}
