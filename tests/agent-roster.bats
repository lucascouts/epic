#!/usr/bin/env bats
# Which work is a sub-agent's and which is the main agent's — decided by A/B
# (n=5 per arm, 2026-09-27), and pinned so a spawn does not come back unseen.
#
#   A1  validation and audit are one Auditor spawn: no Validator agent, and
#       validate mode spawns once
#   A2  integration points and gotchas are the main agent's, inline: no
#       Architect agent
#   A3  the completeness checklist is the main agent's

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

section() {
  awk -v s="$2" -v e="$3" '$0 ~ s {f=1; print; next} f && $0 ~ e {exit} f {print}' "$1"
}

@test "A1: no Validator agent — the Auditor runs the validation protocol, in one spawn" {
  [ ! -e "$ROOT/agents/validator.md" ]
  [ -f "$ROOT/references/validation-protocol.md" ]
  proc=$(section "$ROOT/references/validate-mode.md" '^## Validate Mode Procedure' '^### ')
  [[ "$proc" == *'spawn **one** Auditor sub-agent'* ]]
  run grep -n 'spawn the Validator' "$ROOT/references/validate-mode.md"
  [ "$status" -eq 1 ]
}

@test "A2: no Architect agent — Full adds integration points and gotchas inline" {
  [ ! -e "$ROOT/agents/architect.md" ]
  step=$(section "$ROOT/references/phase-gates.md" '^## Integration points and gotchas' '^## ')
  [[ "$step" == *'**No sub-agent**'* ]]
  grep -q '^## Implementation Gotchas' "$ROOT/references/design-guide.md"
}

@test "A3: the completeness checklist is written by the main agent" {
  cl=$(section "$ROOT/references/context-discovery.md" '^## Completeness Checklist' '^[*][*]Rules:[*][*]')
  [[ "$cl" == *'**main agent writes the checklist itself**'* ]]
}
