#!/usr/bin/env bats
# Tests under TDD — the doc contract of the Red, setup-repair, test-diff,
# scratch, unit-ownership, regression and breaker rules.
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

@test "T1: Red is a failed assertion against a stub; setup failures are not Red" {
  has agents/test-advisor.md 'stub the api under test'
  has agents/test-advisor.md 'red is a failed assertion'
  has agents/test-advisor.md 'red_at: assertion'
  has agents/test-advisor.md 'red_at.*setup'
  has agents/auditor.md 'red_at: setup'
  has references/run-mode.md 'against a stub'
  has references/run-mode.md 'red_at: assertion'
}
