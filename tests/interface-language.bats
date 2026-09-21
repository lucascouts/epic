#!/usr/bin/env bats
# The interface language — the boundary the English rule never drew.
#
# Measured 2026-09-21: given the same Portuguese request, `instant` shipped an
# English menu "on the repository's standing rule that written artifacts are
# English", and the requester spent a turn undoing it. The rule was about
# artifacts; nothing said where it stopped.
#
#   L1  the Language section names what the requester's own users read, and
#       puts it outside the English rule
#   L2  the interface language is asked in the requester's language, with the
#       three options, and skipped when the request is already English
#   L3  a run with no question round defaults to the request's language
#   L4  instant states the default on its line instead of inheriting English
#   L5  the artifacts stay English — the boundary moved, the rule did not

ROOT="$BATS_TEST_DIRNAME/.."
SKILL="$ROOT/skills/epic/SKILL.md"

section() {
  awk -v s="$2" -v e="$3" '$0 ~ s {f=1; print; next} f && $0 ~ e {exit} f {print}' "$1"
}

has() {
  if ! printf '%s' "$2" | grep -qi -- "$3"; then
    echo "$1: expected the block to mention '$3'" >&2
    printf '%s\n' "$2" | head -25 >&2
    return 1
  fi
}

@test "L1: the Language section puts what the requester's users read outside the English rule" {
  lang=$(section "$SKILL" '^## Language' '^## ')
  has "L1 interface" "$lang" "interface"
  has "L1 readme" "$lang" "README"
  has "L1 boundary" "$lang" "does not cover"
}

@test "L2: the interface language is asked in the requester's own language, three options" {
  lang=$(section "$SKILL" '^## Language' '^## ')
  has "L2 asked" "$lang" "asked, not assumed"
  has "L2 own language" "$lang" "requester's own language"
  has "L2 english option" "$lang" "English"
  has "L2 skip" "$lang" "not asked when the request is already in English"
}

@test "L3: with no question round the default is the language the request was written in" {
  lang=$(section "$SKILL" '^## Language' '^## ')
  has "L3 default" "$lang" "the language the request was written in"
  has "L3 stated" "$lang" "stated on its line"
}

@test "L4: instant states the interface language instead of inheriting the artifacts' English" {
  inst=$(section "$SKILL" '^## Instant' '^## ')
  has "L4 rule" "$inst" "language the request was written in"
  has "L4 not artifacts" "$inst" "about artifacts"
}

@test "L5: the artifacts, EARS keywords and identifiers stay English" {
  lang=$(section "$SKILL" '^## Language' '^## ')
  has "L5 artifacts" "$lang" "always English"
  has "L5 ears" "$lang" "EARS keywords"
  has "L5 identifiers" "$lang" "Code identifiers"
}

@test "L6: the clarify protocol carries the question, not just the Language section" {
  clar=$(section "$SKILL" '^## Clarify Protocol' '^## ')
  has "L6 question" "$clar" "interface language"
  has "L6 skip" "$clar" "already in English"
}
