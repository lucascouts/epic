#!/usr/bin/env bats
# references/run-mode.md, "End of Run" — the next-step question.
#
# A finished run asks ONE AskUserQuestion offering validate, refine and
# archive, and gates the first two on the measured context fill:
#
#   N1  the question is AskUserQuestion, and it names all three options
#   N2  the fill is measured by epic-telemetry's `band`, never estimated and
#       never from a guessed --window: a 200k guess on a 1M model read 107%
#   N3  the bands: high recommended here, efficient allowed, degraded a new
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

@test "N2: the context fill is read from epic-telemetry's band, never a guessed window" {
  [[ "$END" == *"epic-telemetry | jq '.context'"* ]]
  [[ "$END" == *'Read `band`'* ]]
  run grep -q 'epic-telemetry --window' "$ROOT/references/run-mode.md"
  [ "$status" -eq 1 ]
}

@test "N3: high recommended here, efficient allowed, degraded a new session" {
  printf '%s\n' "$END" | grep -q '^| `high` | ≤ 100k | ≤ 200k | offered in this session — \*\*strongly recommended here\*\*'
  printf '%s\n' "$END" | grep -q '^| `efficient` | ≤ 150k | ≤ 500k | offered in this session'
  printf '%s\n' "$END" | grep -q '^| `degraded` | above | above | \*\*not offered in this session\*\*'
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

@test "N10: the recommended marker is written in the user's language" {
  # 2026-09-27 battery: a Portuguese run labelled its option "(Recommended)".
  [[ "$END" == *"recommended marker **in the user's language**"* ]]
  grep -q 'never the English marker in another language' "$ROOT/references/clarify.md"
}

@test "N11: the validate-fix loop is bounded — asked after round 1, stopped after round 2" {
  # 2026-09-27 battery: a validate-fix-revalidate loop ran with no ceiling.
  VM="$ROOT/references/validate-mode.md"
  grep -q '^### Fix loop bound' "$VM"
  grep -q 'Validation fixes — round N' "$VM"
  grep -q '\*\*Round 2 is the last one offered.\*\*' "$VM"
  grep -q '\*\*Every offer states what a round costs\*\*' "$VM"
  [[ "$END" == *'**A fix round is asked, never chained.**'* ]]
}
