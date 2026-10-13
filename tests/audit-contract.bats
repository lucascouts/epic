#!/usr/bin/env bats
# Auditor, --auto and honesty — the doc contract of the fail-record verdict,
# the short hand-back with claims, --auto assumptions, loss annotation, the
# bugfix intake and the layperson jargon check.
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

@test "A1: a wrong record is fail-record, fixed by the orchestrator with no fix round" {
  has agents/auditor.md 'pass \| fail \| fail-record'
  has agents/auditor.md 'record_issues'
  has agents/auditor.md 'a wrong record never fails the code'
  has references/validate-mode.md 'on `verdict: fail-record`, fix the record yourself'
  has references/validate-mode.md 'no fix round, no task group, no second auditor'
  has references/validate-mode.md '## record fixes'
}

@test "A2: short hand-back, claims verified with evidence, checks_run beside empty arrays, review budget in the prompt" {
  has agents/auditor.md 'never restate a finding'
  has agents/auditor.md 'confirmed \| partial \| unsupported'
  has agents/auditor.md 'checks_run'
  has agents/auditor.md 'reviewed, no finding" carries what was run'
  has references/validate-mode.md 'review budget: one validation and at most two fix rounds'
  has references/validate-mode.md 'executor-reports.md'
  has references/run-mode.md 'keep every executor report on disk'
}

@test "A3: --auto asks only on failure and logs every assumption, in the run report and in memory" {
  has references/run-mode.md '### assumptions under `--auto`'
  has references/run-mode.md '## assumptions'
  has references/run-mode.md 'epic/decision/<nnn>-auto-assumptions'
  has references/run-mode.md '`--auto` is the one exception'
  has references/mcp-integration.md 'auto-assumptions'
  has skills/epic/SKILL.md '`--auto` takes the recommended step'
}

@test "A4: loss annotation in the audit and in every closing; bugfix intake keeps diagnosis apart from observation" {
  has agents/auditor.md 'not_verified'
  has agents/auditor.md 'never empty by omission'
  has references/validate-mode.md 'always its `not_verified\[\]`'
  has references/run-mode.md 'the loss annotation'
  has references/run-mode.md 'not verified:'
  has references/bugfix.md "reporter's diagnosis"
  has references/bugfix.md 'proposed fix'
  has references/triage.md 'split the report into four'
}

@test "A5: a layperson closing passes epic-jargon before it is sent" {
  has references/plain-register.md 'the closing is checked, not trusted'
  has references/plain-register.md 'epic-jargon'
  has skills/epic/SKILL.md 'checked with `epic-jargon` first'
}
