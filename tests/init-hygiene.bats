#!/usr/bin/env bats
# Init hygiene and the evidence-stays-in-.draft decision — the doc contract.
#
# Blocks by structural anchor, keywords inside, case-insensitive; no sentence
# verbatim. Note on awk patterns: strings, no backslash escapes.
#
#   I1  init's verbatim .epic/.gitignore block carries node_modules/ beside
#       .draft/ and *.wip
#   I2  no agent-memory step: since 0.12.0 no agent declares `memory:`, so
#       nothing writes .claude/agent-memory/ and there is nothing to ignore
#   I4  the versioning-policy text names the evidence files as scratch by
#       decision, and points at the memory page as the durable form
#   I5  run-mode.md states a proven parallel group instead of asking [y/n],
#       and documents --serial

ROOT="$BATS_TEST_DIRNAME/.."

section() {
  awk -v s="$2" -v e="$3" '$0 ~ s {f=1; print; next} f && $0 ~ e {exit} f {print}' "$1"
}

has() {
  if ! printf '%s' "$2" | grep -qi -- "$3"; then
    echo "$1: expected the block to mention '$3'" >&2
    printf '%s\n' "$2" | head -20 >&2
    return 1
  fi
}

@test "I1: init's .epic/.gitignore block carries node_modules/ beside .draft/ and *.wip" {
  block=$(section "$ROOT/references/init-mode.md" '^```gitignore' '^```$')
  has "I1" "$block" "node_modules/"
  has "I1" "$block" "[.]draft/"
  has "I1" "$block" "[*][.]wip"
}

@test "I2: init has no agent-memory step — no agent writes one any more" {
  run grep -n 'agent-memory' "$ROOT/references/init-mode.md"
  [ "$status" -eq 1 ]
}

@test "I4: the policy text names the evidence files as scratch by decision, with the page as durable form" {
  block=$(section "$ROOT/references/init-mode.md" '^## Versioning Policy' '^### Step 5[.]1')
  has "I4 deviations" "$block" "deviations.yaml"
  has "I4 red" "$block" "red-evidence.yaml"
  has "I4 decision" "$block" "by decision"
  has "I4 page" "$block" "memory-mcp"
}

@test "I5: run-mode.md states a proven parallel group instead of asking, and documents --serial" {
  # Parallel Execution lives in its own appendix (references/run-parallel.md),
  # loaded only when a run has a group to prove; run-mode.md keeps the pointer.
  det=$(section "$ROOT/references/run-parallel.md" '^### Detection' '^### ')
  if printf '%s' "$det" | grep -q 'Execute in parallel? \[y/n\]'; then
    echo 'detection still asks [y/n] to parallelize' >&2
    return 1
  fi
  has "I5 serial" "$det" "--serial"
  flags=$(section "$ROOT/references/run-mode.md" '^## Execution Flags' '^## ')
  has "I5 flag row" "$flags" "--serial"
  rules=$(section "$ROOT/references/run-mode.md" '^## Run Mode Rules' '^### ')
  has "I5 rule" "$rules" "proven"
}
