#!/usr/bin/env bats
# How the plugin uses epic-supervisor when it is installed: the claims check at
# validate, the sensors and the findings store at the checkpoint, urgent
# proposals acknowledged on their own, and the mailbox kept for live runs only.

setup() { ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"; }

has() {  # <file> <extended regex>
  if ! command grep -Eqi -- "$2" "$ROOT/$1"; then echo "$1 does not carry: $2"; return 1; fi
}

@test "validate runs the claims check only when epic-supervise is on PATH, and never blocks on it" {
  has references/validate-mode.md 'when `epic-supervise` is on PATH and `EPICO_SUPERVISION` is not `off`'
  has references/validate-mode.md 'epic-supervise claims --root <project> --story <NNN>'
  has references/validate-mode.md 'it never blocks the verdict'
  has references/validate-mode.md 'without the command, say so in one line and go on'
}

@test "the checkpoint offers the sensors and triages the findings store" {
  has references/checkpoint-mode.md 'epic-supervise sense --root <project> --stage <N>'
  has references/checkpoint-mode.md 'epic-finding list --root <project> --status open'
  has references/checkpoint-mode.md 'record a store finding.s decision with `epic-finding decide`'
}

@test "an urgent proposal is acknowledged on its own and never drafted headless" {
  has references/memory-modes.md 'marked `priority: urgent` is listed first and drafted only after the user acknowledges it'
  has references/memory-modes.md 'headless never drafts it'
}

@test "the mailbox carries live-run claims only; everything after the run goes to the findings store" {
  has references/supervision.md 'only for a claim about a run still in progress'
  has references/supervision.md 'everything after the run goes to the findings store'
}
