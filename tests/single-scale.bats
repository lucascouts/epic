#!/usr/bin/env bats
# One scale at triage: the four modes, read from risk and uncertainty.
# The story-level Trivial/Simple/Moderate/High labels are gone from triage; the
# sub-task Complexity field stays, because it routes the Executor model and the
# tech review.

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "triage carries no story-level complexity table or proposal line" {
  run grep -nE 'Trivial / Simple|\*\*Complexity:\*\*|### Complexity' "$ROOT/references/triage.md"
  [ "$status" -eq 1 ]
}

@test "the mode is read from risk and uncertainty; file counts are examples" {
  grep -qF 'The mode is read from risk and uncertainty, not from a file count.' "$ROOT/references/triage.md"
  grep -qF 'There is one scale' "$ROOT/references/triage.md"
}

@test "exploratory signals live on the Spike row, not on a separate label" {
  row=$(grep -F '| **Spike** |' "$ROOT/references/triage.md" | head -1)
  printf '%s' "$row" | grep -qF 'find out whether'
}

@test "the sub-task Complexity field survives in tasks.md" {
  grep -qF '| Complexity | Trivial / Simple / Moderate / High | Always on parent |' "$ROOT/references/tasks.md"
}
