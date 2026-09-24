#!/usr/bin/env bats
# Fast runs auto by default, the orchestrator's effort is the session's, and
# the memory recommendation names a permitted provider — the doc contract
# (story 025).
#
# The surface is agent-executed prose, so every case pins a BLOCK found by a
# structural anchor and asserts a keyword inside it, case-insensitively. No
# case requires a sentence verbatim: a correct rewrite must stay green.
#
#   D1  run-mode.md's flags table says Fast runs as --auto and names --step
#   D2  run-mode.md's Run Mode Rules promise a stop per group only under
#       --step, and keep run-and-show
#   D3  the skill frontmatter carries no effort: line — the session decides
#   D4  mcp-integration.md's Memory section names a permitted provider and
#       rules the subscription OAuth token out
#   D5  README's run table names --step and says Fast is auto
#   D6  every sub-agent runs in the foreground: the Personas section says so
#       with run_in_background: false, and the Analyst and Test Advisor spawn
#       sites repeat it (story 026)
#
# Note on awk patterns: passed as strings, so no backslash escapes; literal
# punctuation goes in a bracket class.

ROOT="$BATS_TEST_DIRNAME/.."

section() {
  awk -v s="$2" -v e="$3" '$0 ~ s {f=1; print; next} f && $0 ~ e {exit} f {print}' "$1"
}

has() { # has <label> <block> <keyword>
  if ! printf '%s' "$2" | grep -qi -- "$3"; then
    echo "$1: expected the block to mention '$3'" >&2
    printf '%s\n' "$2" | head -20 >&2
    return 1
  fi
}

@test "D1: the flags table says Fast runs as --auto by default and names --step" {
  block=$(section "$ROOT/references/run-mode.md" '^Parse flags from' '^## ')
  [ -n "$block" ]
  default_row=$(printf '%s' "$block" | grep -E '^\| \(default\)')
  [ -n "$default_row" ]
  has "D1 fast auto" "$default_row" "Fast"
  has "D1 fast auto" "$default_row" "auto"
  step_row=$(printf '%s' "$block" | grep -E '^\| `--step`')
  [ -n "$step_row" ]
  has "D1 step" "$step_row" "group"
}

@test "D2: Run Mode Rules promise a stop per group only under --step, and keep run-and-show" {
  block=$(section "$ROOT/references/run-mode.md" '^## Run Mode Rules' '^### ')
  [ -n "$block" ]
  has "D2 step" "$block" "--step"
  has "D2 doubt" "$block" "doubt"
  has "D2 show" "$block" "run and show"
}

@test "D3: the skill frontmatter carries no effort: line — the session's effort applies to the orchestrator" {
  front=$(awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f' "$ROOT/skills/epic/SKILL.md")
  [ -n "$front" ]
  if printf '%s\n' "$front" | grep -qE '^effort:'; then
    echo "D3: the skill frontmatter pins the orchestrator's effort again (story 025 removed effort: max)" >&2
    return 1
  fi
}

@test "D4: the Memory section names a permitted provider and rules the subscription OAuth token out" {
  block=$(section "$ROOT/references/mcp-integration.md" 'separate from research: [*][*]memory[*][*]' '^### Detection')
  [ -n "$block" ]
  has "D4 api key" "$block" "API key"
  has "D4 local" "$block" "local model"
  has "D4 oauth" "$block" "OAuth"
  has "D4 never" "$block" "never"
}

@test "D5: the README run table names --step and says Fast is auto" {
  grep -qE -- '--step' "$ROOT/README.md"
  row=$(grep -E -- 'stories run NNN --auto' "$ROOT/README.md")
  [ -n "$row" ]
  has "D5" "$row" "Fast"
}

@test "D6: every sub-agent runs in the foreground — Personas says run_in_background: false, and the Analyst and Test Advisor spawn sites repeat it" {
  personas=$(section "$ROOT/references/personas.md" '^## Personas' '^## Command Routing')
  [ -n "$personas" ]
  has "D6 rule" "$personas" "run_in_background: false"
  has "D6 foreground" "$personas" "foreground"
  has "D6 measured" "$personas" "12 of 12"
  ta=$(section "$ROOT/references/phase-gates.md" '^## Test Advisor Sub-agent' '^### ')
  has "D6 test advisor" "$ta" "run_in_background: false"
  an=$(section "$ROOT/references/context-discovery.md" '^## Codebase Analysis' '^## ')
  has "D6 analyst" "$an" "run_in_background: false"
  if grep -qE 'run_in_background: true' "$ROOT/skills/epic/SKILL.md" "$ROOT/references/personas.md" "$ROOT/references/triage.md" "$ROOT/references/clarify.md" "$ROOT/references/phase-execution.md" "$ROOT/references/phase-gates.md" "$ROOT/references/context-discovery.md" "$ROOT/references/run-mode.md" "$ROOT/references/validate-mode.md"; then
    echo "D6: a spawn site asks for a background sub-agent" >&2
    return 1
  fi
}
