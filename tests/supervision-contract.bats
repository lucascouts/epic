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

@test "S2: typed page paths with as_of and typed links; _global only for tech gotchas and research; global recall at triage" {
  has references/mcp-integration.md 'epic/<type>/<NNN>-<slug>'
  has references/mcp-integration.md '`causes`, `fixes`, `contradicts`, `supersedes`'
  has references/mcp-integration.md 'only `gotcha` and `research` pages that carry a `tech:`'
  has references/context-discovery.md 'global: true'
  has references/run-mode.md 'epic/deviation/NNN'
  has references/validate-mode.md 'epic/finding/NNN'
}

@test "S3: stories from-memory and sync-docs — routed, verified against code, never code, ADRs superseded" {
  has skills/epic/SKILL.md '"stories from-memory \[<page>\]"'
  has skills/epic/SKILL.md '"sync-docs"'
  has skills/epic/SKILL.md 'not starting with "stories", "init", "archive" or "sync-docs"'
  has references/memory-modes.md 'source: memory:<page path>'
  has references/memory-modes.md "an adr's text is never rewritten"
  has references/memory-modes.md 'same decision, new detail'
  has references/memory-modes.md '## enforcement'
  has references/memory-modes.md '- check:'
  has references/memory-modes.md '- judgment-only:'
  has references/memory-modes.md 'supersedes: adr-<n>'
  has references/memory-modes.md 'headless writes nothing'
  has references/memory-modes.md 'never code'
  # the from-memory arm sits before the bare "stories" arm
  fm=$(command grep -n '^"stories from-memory' "$ROOT/skills/epic/SKILL.md" | cut -d: -f1)
  bare=$(command grep -n '^"stories"$' "$ROOT/skills/epic/SKILL.md" | cut -d: -f1)
  [ "$fm" -lt "$bare" ]
}
