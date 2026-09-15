#!/usr/bin/env bats
# Cascade↔description coverage for skills/epic/SKILL.md
# (story 021 — close-the-eval-deferrals).
# Authored by the Test Advisor BEFORE the fix (TDD Red phase).
#
# Contract under test (design.md, Fix Approach 3; R3.1-R3.3):
#   Every routing mode present in the cascade is announced by the skill's
#   `description`. The cascade decides where a request goes AFTER the skill is
#   chosen; the description decides WHETHER it is chosen. A mode present only in
#   the cascade is unreachable by the phrasing it introduced.
#
# WHY THIS FILE EXISTS. Stories 013 and 015 added `--batch` and `migrate` to the
# cascade and to argument-hint, and not to the description. Measured on the
# description in isolation: `batch` 0, `migrate` 0, `epic` 1 — and that single
# `epic` sits inside "even without saying 'epic' or 'story' explicitly", a
# negation. Both modes fire 0 out of 3 in the trigger evals. Nothing in the tree
# compared the two lists, so nothing went red for eighteen months of commits.
#
# IT FAILS ON BOTH SIDES, deliberately. A term declared here and missing from
# the description fails; a cascade arm with no entry in the table fails too. A
# table checking only the first half goes stale exactly the way the description
# did — silently, and in the direction nobody is looking.
#
# EPIC_PLUGIN_ROOT overrides root resolution so this draft copy can run before
# materialization into tests/.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="${EPIC_PLUGIN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  SKILL="$PLUGIN_ROOT/skills/epic/SKILL.md"
  WORK=$(mktemp -d)
}

teardown() { rm -rf "$WORK"; }

# THE DECLARED TABLE — the one place a human edits. Each row is
# `<cascade token>|<term(s) the description must carry, comma-separated>`.
# Add a mode to the cascade, add its row here; the roster case below names the
# arm you forgot.
declare_table() {
  # Arms are declared LITERALLY, not by keyword. A keyword table looked tidier
  # and was broken: the token `stories` matched every arm beginning with it, so
  # a newly added `stories teleport NNN` was silently "accounted for" and the
  # roster case could never go red. The mutant below caught that — which is what
  # mutants are for. Literal arms cost one line each and cannot drift.
  cat <<'TABLE'
init|init
stories migrate NNN [--apply]|migrate
stories create --batch <doc>|batch
stories|stories,story
stories full|stories,story
stories NNN|stories,story
stories run NNN [--auto|--batch=N|--gate=commit]|run
stories validate NNN|validate
stories refine NNN|refine
stories archive NNN[-MMM]|--done|archive
stories supersede NNN --by MMM|supersede
stories teams {status|enable|disable}|teams
stories NNN run all [--auto|--batch=N|--gate=commit]|run
stories NNN run N|run
stories NNN run N.N|run
archive|archive
TABLE
}

# The description field of a given SKILL.md, isolated from the rest of the
# frontmatter. Parameterised on the file so the mutant cases below exercise the
# SAME predicate the real assertions do — a mutant checked by a hand-rolled grep
# proves the grep works, not the check.
description_text() { awk '/^description: >/{f=1;next} f&&/^[a-z-]+:/{exit} f' "${1:-$SKILL}"; }

# Every quoted arm inside the routing cascade block of a given SKILL.md.
cascade_arms() { awk '/parsing:/,/^```$/' "${1:-$SKILL}" | grep -E '^"' | tr -d '"'; }

# The two predicates, each printing what it found wrong (empty output = clean).
missing_terms() {
  local desc; desc=$(description_text "${1:-$SKILL}" | tr '[:upper:]' '[:lower:]')
  while read -r row; do
    local terms="${row##*|}"
    local found=0; IFS=',' read -ra list <<< "$terms"
    for t in "${list[@]}"; do [[ "$desc" == *"$t"* ]] && { found=1; break; }; done
    [ "$found" -eq 1 ] || printf '%s ' "$terms"
  done < <(declare_table)
}

undeclared_arms() {
  while read -r arm; do
    [ -n "$arm" ] || continue
    local matched=0
    while read -r row; do
      # the declared arm is everything before the LAST `|`; arms contain `|`
      [ "$arm" = "${row%|*}" ] && { matched=1; break; }
    done < <(declare_table)
    [ "$matched" -eq 1 ] || printf '%s; ' "$arm"
  done < <(cascade_arms "${1:-$SKILL}")
}

# THE CASE THIS FILE EXISTS FOR. Red today.
@test "3.2: every declared mode term appears in the description" {
  run missing_terms
  [ -z "$output" ] || printf 'description is missing the vocabulary of: %s\n' "$output" >&2
  [ -z "$output" ]
}

# The other side of the divergence: a cascade arm nobody declared. Green today,
# and the case below proves it is capable of going red.
@test "3.2: every cascade arm is accounted for by a row in the declared table" {
  run undeclared_arms
  [ -z "$output" ] || printf 'cascade arm with no row in the table: %s\n' "$output" >&2
  [ -z "$output" ]
}

@test "3.2: a mode term is not counted when it appears only inside a negation" {
  # `epic` is present today ONLY as "even without saying 'epic' or 'story'
  # explicitly" — an instruction to fire WITHOUT the word, which is the opposite
  # of announcing the mode. The description must also state it affirmatively.
  run bash -c "awk '/^description: >/{f=1;next} f&&/^[a-z-]+:/{exit} f' '$SKILL' | grep -ci 'create an epic\|an epic for' || true"
  [ "$output" -ge 1 ]
}

# MUTANT 1 — the term side can fail. Same predicate, a description with one
# declared term removed.
@test "3.2: MUTANT — a description missing a declared term is named by the same predicate" {
  local fake="$WORK/skills/epic/SKILL.md"; mkdir -p "$(dirname "$fake")"
  cp "$SKILL" "$fake"
  # strip the word "validate" from the description block only
  awk '/^description: >/{f=1} f&&/^[a-z-]+:/&&!/^description/{f=0} f{gsub(/validate/,"XXXX")} {print}' "$SKILL" > "$fake"
  run missing_terms "$fake"
  [[ "$output" == *"validate"* ]]
}

# MUTANT 2 — the arm side can fail. Same predicate, a cascade with an arm the
# table does not declare.
@test "3.2: MUTANT — an undeclared cascade arm is named by the same predicate" {
  local fake="$WORK/skills/epic/SKILL.md"; mkdir -p "$(dirname "$fake")"
  sed 's|^"init"$|"init"\n"stories teleport NNN"|' "$SKILL" > "$fake"
  run undeclared_arms "$fake"
  [[ "$output" == *"teleport"* ]]
}
