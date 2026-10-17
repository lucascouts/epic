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

@test "X2: the band is read after every group; degraded stops with run all; 400k on 1M; 1M opt-out honoured" {
  has references/run-mode.md 'context band is read after every task group'
  has references/run-mode.md 'stories NNN run all'
  has references/run-mode.md '≤ 400k'
  has scripts/story-telemetry.sh 'CLAUDE_CODE_DISABLE_1M_CONTEXT'
  has scripts/story-telemetry.sh 'e: 400000'
}

@test "X3: the deviation register is written only through epic-deviation" {
  has references/run-mode.md 'written only through `epic-deviation`'
  has references/run-mode.md 'epic-deviation discharge'
  has references/validate-mode.md 'epic-deviation'
  has references/refine-mode.md 'epic-deviation add deviation'
}

@test "X4: the orchestrator greps and reads through epic-* scripts, never cats a whole report" {
  has references/output-rules.md '## reading files back'
  has references/output-rules.md 'never `cat` the file'
  has references/output-rules.md 'epic-report --story'
  has references/validate-mode.md 'epic-report --story <dir>'
}

@test "X5: per-spawn effort for the Executor by complexity; model only in a declared A/B" {
  has references/run-mode.md 'executor `effort`'
  has references/run-mode.md 'this skill asks for the `effort` column'
  has references/run-mode.md 'never pass `model` on an executor spawn outside a declared a/b'
}

@test "X6: headless takes the mode's gates but never starts the step after it (prompt-audit finding)" {
  has skills/epic/SKILL.md 'the step after the mode is never started'
}
