#!/usr/bin/env bats
# Requester profile, plain register, question budget, adaptive rounds and
# constitution defaults — the doc contract (Onda A + T1).
#
# The surface is agent-executed prose, so every case pins a BLOCK found by a
# structural anchor and asserts a keyword inside it, case-insensitively. No
# case requires a sentence verbatim: a correct rewrite must stay green.
#
#   Q1  SKILL.md triage reads the requester from the request as a four-field
#       block (level, persona, always, never), names both registers, defaults
#       to developer, and says the level never changes the scale — the 0.6.0
#       Fast lock for a layperson is retired by story 022 and must not return
#   Q2  the triage proposal block carries a Requester line
#   Q3  SKILL.md Clarify names a budget, both registers, the three counted
#       sources (gates, run), and the calibration question
#   Q4  plain-register.md exists and names the measured process words as
#       words that stay out of the chat, the per-turn ceiling, run-and-show
#   Q5  plain-register.md says what does NOT change: artifacts, sub-agents
#   Q6  phase-gates.md gives a layperson a one-line gate that counts
#   Q7  run-mode.md rules count run-time questions and name run-and-show
#   Q8  preferred-tooling.md never pauses for a layperson
#   Q9  init-mode.md writes a Defaults block, and its Rules say it is read,
#       never re-asked
#   Q10 developer-register.md exists: direct, context and example on every
#       option, never the basics, and nothing measured yet
#   Q11 plain-register.md explains by example — one analogy per concept
#   Q12 the Draft Saving example carries the requester block, not a bare value
#   Q13 Clarify appends a revealed working rule to always/never
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

@test "Q1: triage reads the requester as a four-field block, both registers, developer when unsure, and the level never changes the scale" {
  block=$(section "$ROOT/skills/epic/SKILL.md" '^## Triage Protocol' '^### Complexity')
  [ -n "$block" ]
  has "Q1" "$block" "developer"
  has "Q1" "$block" "layperson"
  has "Q1" "$block" "never from a question"
  has "Q1" "$block" "plain-register"
  has "Q1 developer register" "$block" "developer-register"
  for f in level persona always never; do
    has "Q1 field" "$block" "$f:"
  done
  has "Q1 decoupled" "$block" "never changes the scale"
  # The 0.6.0 rule held a layperson at Fast "unless they ask". Story 022
  # retired it: the level governs the register, the budget, the defaults and
  # the gate shape, never the mode. Its text returning is a regression.
  if printf '%s' "$block" | grep -qi "unless they ask"; then
    echo "Q1: the Fast lock for a layperson is back — retired by story 022" >&2
    return 1
  fi
}

@test "Q2: the triage proposal block carries a Requester line" {
  grep -q '^> - \*\*Requester:\*\*' "$ROOT/skills/epic/SKILL.md"
}

@test "Q3: Clarify names a story-wide budget, counts gates and run questions, and opens with a calibration question when unsure" {
  block=$(section "$ROOT/skills/epic/SKILL.md" '^## Clarify Protocol' '^### Question shape')
  [ -n "$block" ]
  has "Q3 budget" "$block" "budget"
  has "Q3 gates" "$block" "gate"
  has "Q3 run" "$block" "Run"
  has "Q3 registers" "$block" "layperson"
  has "Q3 calibration" "$block" "calibration question"
  has "Q3 adaptive" "$block" "left open"
}

@test "Q4: plain-register.md keeps the measured process words out of the chat, caps the turn, runs and shows" {
  f="$ROOT/references/plain-register.md"
  [ -f "$f" ]
  words=$(section "$f" '^## Words that stay' '^## ')
  for w in executor framework box Red commit story "Quality Gate" EARS SHALL; do
    has "Q4 word" "$words" "$w"
  done
  ceiling=$(section "$f" '^## Ceiling' '^## ')
  has "Q4 ceiling" "$ceiling" "1,500"
  has "Q4 by form" "$ceiling" "between them"
  show=$(section "$f" '^## Run and show' '^## ')
  has "Q4 show" "$show" "never"
}

@test "Q5: plain-register.md says what does not change — artifacts in English, sub-agents run whole protocols" {
  block=$(section "$ROOT/references/plain-register.md" '^## What does not change' '^## ')
  [ -n "$block" ]
  has "Q5 artifacts" "$block" "English"
  has "Q5 protocol" "$block" "protocol"
}

@test "Q6: phase-gates.md gives a layperson a one-line gate that counts against the budget" {
  block=$(section "$ROOT/references/phase-gates.md" '^## Gate Protocol' '^## ')
  has "Q6" "$block" "layperson"
  has "Q6 one line" "$block" "one line"
  has "Q6 budget" "$block" "budget"
}

@test "Q7: run-mode.md rules count run-time questions and run-and-show for a layperson" {
  block=$(section "$ROOT/references/run-mode.md" '^## Run Mode Rules' '^### ')
  has "Q7 budget" "$block" "budget"
  has "Q7 layperson" "$block" "layperson"
  has "Q7 show" "$block" "run and show"
  has "Q7 report file" "$block" "run-report.md"
  has "Q7 between tools" "$block" "between tool calls"
  tf=$(section "$ROOT/references/run-mode.md" '^### Run-time test-first ordering' '^### ')
  has "Q7 red stays in the file" "$tf" "layperson"
}

@test "Q8: preferred-tooling.md never pauses for a layperson" {
  if ! grep -qi 'layperson' "$ROOT/references/preferred-tooling.md"; then
    echo 'preferred-tooling.md does not name the layperson branch' >&2
    return 1
  fi
  block=$(grep -i -A2 'layperson' "$ROOT/references/preferred-tooling.md")
  has "Q8 no pause" "$block" "no pause"
}

@test "Q9: init-mode.md writes a Defaults block and its Rules say it is read, never re-asked" {
  proc=$(section "$ROOT/references/init-mode.md" '^## Procedure' '^## ')
  has "Q9 block" "$proc" "Defaults"
  has "Q9 gitignored" "$proc" "gitignored"
  rules=$(section "$ROOT/references/init-mode.md" '^## Rules' '^## ')
  has "Q9 rules" "$rules" "Defaults"
  has "Q9 never re-asked" "$rules" "silently"
}

@test "Q10: developer-register.md is direct, keeps context and an example, never teaches the basics, and admits nothing is measured" {
  f="$ROOT/references/developer-register.md"
  [ -f "$f" ]
  always=$(section "$f" '^## Always' '^## ')
  has "Q10 direct" "$always" "direct"
  has "Q10 example" "$always" "example"
  has "Q10 recommend" "$always" "recommend"
  never=$(section "$f" '^## Never' '^## ')
  has "Q10 basics" "$never" "basics"
  has "Q10 no analogy for the term" "$never" "analogy"
  unchanged=$(section "$f" '^## What does not change' '^## ')
  has "Q10 scale" "$unchanged" "never changes the scale"
  measured=$(section "$f" '^## Measured' '^## ')
  has "Q10 honest" "$measured" "Nothing yet"
}

@test "Q11: plain-register.md explains by example — one analogy per new concept, inside the ceiling" {
  block=$(section "$ROOT/references/plain-register.md" '^## Explain by example' '^## ')
  [ -n "$block" ]
  has "Q11 analogy" "$block" "analogy"
  has "Q11 one per" "$block" "one per concept"
  has "Q11 ceiling" "$block" "ceiling"
}

@test "Q12: the Draft Saving example carries the requester block with its four fields" {
  block=$(section "$ROOT/skills/epic/SKILL.md" '^### Draft Saving' '^### Resume')
  [ -n "$block" ]
  has "Q12 block" "$block" "requester:"
  for f in level persona always never; do
    has "Q12 field" "$block" "$f:"
  done
  if printf '%s' "$block" | grep -qE '^requester: (developer|layperson)'; then
    echo "Q12: meta.yaml still shows the bare 0.6.0 value" >&2
    return 1
  fi
}

@test "Q13: Clarify appends a revealed working rule to requester.always or requester.never" {
  block=$(section "$ROOT/skills/epic/SKILL.md" '^## Clarify Protocol' '^### Question shape')
  has "Q13 level" "$block" "requester.level"
  has "Q13 never" "$block" "requester.never"
  has "Q13 always" "$block" "requester.always"
}
