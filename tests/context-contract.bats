#!/usr/bin/env bats
# Orchestrator context — the doc contract of short hand-backs, the band at
# every group gate, the deviation register script and lean tool output.
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

@test "X1: full reports in .draft/reports/, hand-backs of at most 10 lines" {
  has agents/executor.md '\.draft/reports/<sub-task>\.md'
  has agents/executor.md 'at most 10 lines'
  has agents/tech-reviewer.md '\.draft/reports/<sub-task>-tech-review'
  has agents/test-advisor.md '\.draft/reports/test-advisor\.md'
  has references/run-mode.md 'the hand-back is short'
  has agents/auditor.md 'reports in `\.draft/reports/`'
}
