#!/usr/bin/env bats
# references/run-mode.md, "End of Run" — the next-step question.
#
# A finished run asks ONE AskUserQuestion offering validate, refine and
# archive, and gates the first two on the measured context fill:
#
#   N1  the question is AskUserQuestion, and it names all three options
#   N2  the fill is measured by epic-telemetry --window, never estimated
#   N3  the bands: below 50 recommended here, 50 to 75 allowed, above 75 a new
#       session — a mode that runs out of room mid-way loses what it checked
#   N4  archive is gated on the transition to done, never on the census
#   N5  headless starts nothing and logs the command
#   N6  the old y/n Validator prompt is gone, so two offers never coexist
#   N7  a layperson is asked too: the three-line closing form rule names the
#       question as its exception. A run on 2026-09-26 followed the form rule
#       and skipped the question

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  END=$(awk '/^### End of Run/ {f=1; print; next} f && /^## / {exit} f {print}' "$ROOT/references/run-mode.md")
  [ -n "$END" ]
}

@test "N1: the next step is one AskUserQuestion naming validate, refine and archive" {
  [[ "$END" == *'one `AskUserQuestion`'* ]]
  [[ "$END" == *'**Validate**'* ]]
  [[ "$END" == *'**Refine**'* ]]
  [[ "$END" == *'**Archive**'* ]]
}

@test "N2: the context fill is measured with epic-telemetry --window" {
  [[ "$END" == *'epic-telemetry --window'* ]]
  [[ "$END" == *'used_pct'* ]]
}

@test "N3: below 50 recommended here, 50 to 75 allowed, above 75 a new session" {
  printf '%s\n' "$END" | grep -q '^| below 50 | offered in this session — \*\*strongly recommended here\*\*'
  printf '%s\n' "$END" | grep -q '^| 50 to 75 | offered in this session'
  printf '%s\n' "$END" | grep -q '^| above 75 | \*\*not offered in this session\*\*'
}

@test "N4: archive is offered only on the transition to done" {
  [[ "$END" == *'status_written.to == "done"'* ]]
}

@test "N5: headless starts nothing and logs the command" {
  printf '%s\n' "$END" | grep -q '^\*\*Headless — nobody can answer:\*\* do not call `AskUserQuestion` and do not start any of the three'
}

@test "N6: the y/n Validator prompt is gone from run-mode.md" {
  run grep -n 'Run Validator to verify' "$ROOT/references/run-mode.md"
  [ "$status" -eq 1 ]
}

@test "N7: the layperson closing-form rules keep the next-step question" {
  [[ "$END" == *'**A `layperson` requester is asked too**'* ]]
  n=$(grep -c "closing three lines.*next-step question" "$ROOT/references/run-mode.md")
  [ "$n" -eq 2 ]
}

@test "N8: SKILL.md carries the next-step rule, since run-mode.md is read in slices" {
  # A 2026-09-26 run grepped run-mode.md for "End of Run" and never read the
  # section: a rule that lives only in a reference does not reach the Fast path.
  grep -q 'A run that finishes a story ends with an `AskUserQuestion`' "$ROOT/skills/epic/SKILL.md"
}

@test "N9: a layperson is offered to see the program running, then asked again" {
  # On 2026-09-26 the Bia persona ignored validate/refine/archive and answered
  # in free text: "run it so I can see it working".
  [[ "$END" == *'**See it running** — `layperson` requester only'* ]]
  [[ "$END" == *'drop **Refine** first when five would apply'* ]]
}
