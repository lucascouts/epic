#!/usr/bin/env bats
# Project-side rules — the doc contract of the managed CLAUDE.md block, the
# lookup order, the mandatory constitution, the archive and worktree defaults.
#
# The surface is agent-executed prose, so every case asserts keywords in the
# file that carries the rule, case-insensitively. No case requires a sentence
# verbatim: a correct rewrite must stay green.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

has() {  # <file> <extended regex> — case-insensitive, names the miss
  if ! command grep -Eqi -- "$2" "$ROOT/$1"; then
    echo "$1 does not carry: $2"
    return 1
  fi
}

@test "P1: init writes the managed CLAUDE.md block; repair refreshes it; the doctor flags it" {
  has references/init-mode.md 'epic-claude-md write'
  has references/init-mode.md '## the managed claude.md block'
  has references/init-mode.md '## repair \(`init --repair`\)'
  has scripts/doctor.sh 'claude-md.sh" check'
}

@test "P2: one lookup order, in the reference, the managed block and the Executor" {
  has references/lookup-order.md 'memory, as a pointer'
  has references/lookup-order.md 'issue tracker'
  has references/lookup-order.md 'the web\*\*, last'
  has scripts/claude-md.sh 'Where to look, in order'
  has agents/executor.md 'lookup-order.md'
  has references/mcp-integration.md 'part of the \[lookup order\]'
}
