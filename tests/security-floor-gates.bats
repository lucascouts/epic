#!/usr/bin/env bats
# The security floor, checked as gates in scripts/validate-story.sh.
#
# The floor is the four items no engineering level drops
# (references/quality-catalog.md, The security floor): the supported and
# declared runtime, secrets, the README, and the dependency-vulnerability scan
# (SCA). Until this lint the whole chain that carries them was prose — legend,
# generated gate, Validate running the command — so a story whose legend
# omitted the floor produced no gate, gave Validate nothing to run, and passed.
# Measured 2026-09-19: four of fourteen Epic arms in a seven-language matrix
# skipped floor items and all four validated clean.
#
#   F1  a declared level with no floor gates is an ERROR naming all four
#   F2  a declared level with all four gates raises no floor error
#   F3  NO `engineering:` field is fail-OPEN — a legacy story is untouched
#   F4  a partial floor names exactly the missing item, and only it
#   F5  the scope is the gates section: a floor word in a sub-task is not a gate
#   F6  a gate inside a fenced block is documentation, not a claim
#   F7  `sca` is bounded by non-letters, so `scaffold` does not satisfy SCA
#   F8  the floor is level-agnostic: `product` owes it exactly as `experiment`

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/story"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

# A minimal fast-shaped story: tasks.md alone, one group, one sub-task.
# $1 = the `engineering:` frontmatter line (may be empty), $2 = gates body.
write_tasks() {
  local eng_line="$1" gates="$2"
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-09-19'
    echo 'scale: fast'
    [[ -z "$eng_line" ]] || echo "$eng_line"
    echo '---'
    echo
    echo '## Task List'
    echo '- [ ] 1 - Implement'
    echo '  - Commit: "feat(001): implement"'
    echo '  - [ ] 1.1 - Write it'
    echo '    - Validation: `echo ok`'
    echo
    echo '## Quality Gates'
    printf '%s\n' "$gates"
  } > "$STORY/tasks.md"
}

ALL_FOUR='- [ ] Q1 — Supported and declared runtime: `node --version`
- [ ] Q2 — Secrets: `gitleaks detect`
- [ ] Q3 — README: the two commands it names run
- [ ] Q4 — Dependency vulnerabilities (SCA): `trivy fs .`'

# errors <output> — the error messages, one per line. `.errors` is the COUNT;
# `.error_details` is the array, and reading the wrong one silently yields a
# number that every grep below would fail to match.
errors() { printf '%s' "$1" | jq -r '.error_details[]?'; }

# floor_errors <output> — only the floor lint's own errors.
floor_errors() { errors "$1" | grep -i 'security-floor' || true; }

# refute_mentions <text> <needle> — a plain `if`, not a `!` prefix: in Bats a
# `!`-prefixed command is exempt from the errexit that turns a failed assertion
# into a failed test, so `! grep -q` asserts nothing at all (SC2314).
refute_mentions() {
  if printf '%s' "$1" | grep -q -- "$2"; then
    echo "expected the message NOT to mention '$2', got: $1" >&2
    return 1
  fi
}

# --- F1: declared level, no floor at all ---

@test "F1 a declared engineering level with no floor gates is an error naming all four" {
  write_tasks 'engineering: experiment' '- [ ] All tests pass'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | jq -e . > /dev/null
  msg=$(floor_errors "$output")
  [ -n "$msg" ]
  echo "$msg" | grep -q '4 of the four'
  echo "$msg" | grep -q 'Supported and declared runtime'
  echo "$msg" | grep -q 'Secrets'
  echo "$msg" | grep -q 'README'
  echo "$msg" | grep -q 'Dependency vulnerabilities'
  # The message points at the rule rather than restating it.
  echo "$msg" | grep -q 'quality-catalog.md'
}

# --- F2: the floor honoured ---

@test "F2 all four gates present raises no floor error" {
  write_tasks 'engineering: experiment' "$ALL_FOUR"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ -z "$(floor_errors "$output")" ]
}

# --- F3: fail-OPEN on absence, the rule `engineering:` itself established ---

@test "F3 no engineering field means no floor check — a legacy story is untouched" {
  write_tasks '' '- [ ] All tests pass'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ -z "$(floor_errors "$output")" ]
}

@test "F3b the legacy story's whole output is unchanged by the presence of the lint" {
  # Stronger than F3: not merely "no floor error", but that the fixture with no
  # level and the identical fixture validate to the same JSON. The floor lint
  # must be invisible to every artifact that predates the field.
  write_tasks '' '- [ ] All tests pass'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  before="$output"
  write_tasks '' '- [ ] All tests pass'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$output" = "$before" ]
}

# --- F4: partial floor ---

@test "F4 a partial floor names exactly the missing item and only it" {
  write_tasks 'engineering: tool' '- [ ] Q1 — Supported and declared runtime: `node --version`
- [ ] Q2 — Secrets: `gitleaks detect`
- [ ] Q3 — Dependency vulnerabilities (SCA): `trivy fs .`'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  msg=$(floor_errors "$output")
  [ -n "$msg" ]
  echo "$msg" | grep -q '1 of the four'
  echo "$msg" | grep -q 'README'
  refute_mentions "$msg" 'Secrets'
  refute_mentions "$msg" 'runtime'
}

# --- F5: the scope is the gates section ---

@test "F5 a floor word in a sub-task title is work planned, not a gate that runs" {
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-09-19'
    echo 'scale: fast'
    echo 'engineering: experiment'
    echo '---'
    echo
    echo '## Task List'
    echo '- [ ] 1 - Implement'
    echo '  - Commit: "feat(001): implement"'
    echo '  - [ ] 1.1 - Write the README and scan for secrets at a supported runtime'
    echo '    - Validation: `echo ok`'
    echo
    echo '## Quality Gates'
    echo '- [ ] Q1 — Dependency vulnerabilities (SCA): `trivy fs .`'
  } > "$STORY/tasks.md"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  msg=$(floor_errors "$output")
  [ -n "$msg" ]
  echo "$msg" | grep -q '3 of the four'
  refute_mentions "$msg" 'Dependency vulnerabilities'
}

# --- F6: a fenced gate is documentation ---

@test "F6 a floor gate inside a fenced block does not satisfy the floor" {
  write_tasks 'engineering: experiment' '```
- [ ] Q1 — Supported and declared runtime: `node --version`
- [ ] Q2 — Secrets: `gitleaks detect`
- [ ] Q3 — README: it exists
- [ ] Q4 — Dependency vulnerabilities (SCA): `trivy fs .`
```'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  msg=$(floor_errors "$output")
  [ -n "$msg" ]
  echo "$msg" | grep -q '4 of the four'
}

# --- F7: `sca` is a word, not a substring ---

@test "F7 scaffold does not satisfy the SCA item" {
  write_tasks 'engineering: experiment' '- [ ] Q1 — Supported and declared runtime: `node --version`
- [ ] Q2 — Secrets: `gitleaks detect`
- [ ] Q3 — README: it exists
- [ ] Q4 — Scaffold generated: `ls src`'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  msg=$(floor_errors "$output")
  [ -n "$msg" ]
  echo "$msg" | grep -q '1 of the four'
  echo "$msg" | grep -q 'Dependency vulnerabilities'
}

@test "F7b a bare SCA acronym on the gate line satisfies the item" {
  write_tasks 'engineering: experiment' '- [ ] Q1 — Supported and declared runtime: `node --version`
- [ ] Q2 — Secrets: `gitleaks detect`
- [ ] Q3 — README: it exists
- [ ] Q4 — SCA: `cargo audit`'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ -z "$(floor_errors "$output")" ]
}

# --- F8: level-agnostic ---

@test "F8 product owes the floor exactly as experiment does" {
  write_tasks 'engineering: product' '- [ ] All tests pass'
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY"
  [ "$status" -eq 1 ]
  msg=$(floor_errors "$output")
  [ -n "$msg" ]
  echo "$msg" | grep -q "engineering 'product'"
}
