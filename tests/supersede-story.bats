#!/usr/bin/env bats
# Unit tests for scripts/supersede-story.sh — the mechanical half of the
# supersede operation.
#
# WHY THIS FILE EXISTS. Supersede writes destructively to artifacts — a banner,
# closed sub-tasks, two frontmatter keys — so its mechanical half lives behind a
# script, for the same reason archive's does, and is unit-tested here.
#
# THE STANDARD THESE CASES ARE HELD TO. Not "a case exists that references the
# rule": every rule here must have a case that FAILS WHEN ITS BEHAVIOUR IS
# REMOVED, demonstrated by removal rather than asserted. The hostile half of
# each rule is written first.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SUPERSEDE="$PLUGIN_ROOT/scripts/supersede-story.sh"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  mkdir -p "$PROJ/.epic/stories"
  cd "$PROJ"
}

teardown() {
  cd /
  rm -rf "$WORK"
}

# mk_story <dir-name> [status]  — a story with three artifacts carrying frontmatter
mk_story() {
  local name="$1" status="${2:-in-progress}" d="$PROJ/.epic/stories/$1"
  mkdir -p "$d"
  local f
  for f in story.md design.md tasks.md; do
    cat > "$d/$f" <<EOF
---
story: ${name#*-}
type: feature
scale: full
version: 1
created: 2026-08-08
status: $status
---

# ${f%.md}
EOF
  done
}

# mk_tasks <dir-name> — replace tasks.md's body with the piped task list,
# keeping its frontmatter.
mk_tasks() {
  local d="$PROJ/.epic/stories/$1" body
  body=$(cat)
  local fm
  fm=$(sed -n '1,/^---$/p' "$d/tasks.md" | head -1)
  awk '/^---$/{n++} n<2 || /^---$/' "$d/tasks.md" > "$d/tasks.md.new"
  printf '\n## Task List\n%s\n\n## Quality Gates\n- Tests pass\n' "$body" >> "$d/tasks.md.new"
  mv "$d/tasks.md.new" "$d/tasks.md"
}

run_supersede() { run bash "$SUPERSEDE" "$@"; }

banner_count() {
  grep -c '⛔ SUPERSEDED' "$PROJ/.epic/stories/$1/story.md" || true
}

# --- The refusal matrix, all four arms ---------------------------------------
# Every arm is a hostile half: the operation must REFUSE and write nothing.
# "Writes nothing" is asserted separately from "refuses", because a refusal
# that has already touched the story is the failure this matrix exists to stop.

@test "refusal matrix row 1: a story cannot supersede itself" {
  mk_story 006-widget-flow
  mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [ ] 1.1 - open
T
  run_supersede 006 --by 006 --rationale "x"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  echo "$output" | jq -e '.reason | test("cannot supersede itself")' > /dev/null
  [ "$(banner_count 006-widget-flow)" -eq 0 ]
}

@test "refusal matrix row 2: the replacement story must already exist" {
  mk_story 006-widget-flow
  mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [ ] 1.1 - open
T
  run_supersede 006 --by 012 --rationale "x"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  echo "$output" | jq -e '.reason | test("does not exist")' > /dev/null
  [ "$(banner_count 006-widget-flow)" -eq 0 ]
}

@test "refusal matrix row 3: an archived story is immutable history" {
  mk_story 006-widget-flow archived
  mk_story 012-successor
  mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [ ] 1.1 - open
T
  run_supersede 006 --by 012 --rationale "x"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  echo "$output" | jq -e '.reason | test("archived")' > /dev/null
  [ "$(banner_count 006-widget-flow)" -eq 0 ]
}

@test "refusal matrix row 4: a COMPLETE prior supersede refuses and does not duplicate the banner" {
  # This arm and the interrupted arm below must give DIFFERENT answers to what is
  # superficially the same finding (a banner is present).
  mk_story 006-widget-flow
  mk_story 012-successor
  mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [ ] 1.1 - open
T
  run_supersede 006 --by 012 --rationale "first run"
  [ "$status" -eq 0 ]
  [ "$(banner_count 006-widget-flow)" -eq 1 ]

  run_supersede 006 --by 012 --rationale "second run"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  echo "$output" | jq -e '.reason | test("already carries the supersede banner")' > /dev/null
  # The unconditional half: written at most once, EVER.
  [ "$(banner_count 006-widget-flow)" -eq 1 ]
}

# --- The interrupted arm, and the state this command cannot produce ---------

@test "recovery: an INTERRUPTED prior run is completed, without a second banner" {
  mk_story 006-widget-flow
  mk_story 012-successor
  mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [ ] 1.1 - open
  - [ ] 1.2 - also open
T
  run_supersede 006 --by 012 --rationale "first run"
  [ "$status" -eq 0 ]

  # Rewind to the *Incomplete* row: banner present, no status written anywhere,
  # closures undone. That is the only shape step 3's close-then-flip order can
  # leave, and it is exactly what recovery is written to finish.
  local d="$PROJ/.epic/stories/006-widget-flow"
  sed -i 's/^status: superseded$/status: in-progress/' "$d"/*.md
  sed -i '/^superseded-by:/d' "$d"/*.md
  sed -i 's/^  - \[~\] 1\.\(.\) - \(.*\) (superseded-by: 012)$/  - [ ] 1.\1 - \2/' "$d/tasks.md"
  [ "$(grep -c '^  - \[ \]' "$d/tasks.md")" -eq 2 ]

  # Completion is AUTHORIZED, not assumed. The unauthorized arm is
  # the case below this one; here the caller has already said yes.
  run_supersede 006 --by 012 --rationale "recovery" --complete-interrupted
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "completed"' > /dev/null
  # The banner is never touched by recovery.
  [ "$(banner_count 006-widget-flow)" -eq 1 ]
  echo "$output" | jq -e '.banner_written == false' > /dev/null
  # And the remaining steps really were done.
  [ "$(grep -c 'superseded-by: 012' "$d/tasks.md")" -ge 2 ]
  grep -q '^status: superseded$' "$d/story.md"
}

@test "recovery hostile: an INTERRUPTED run is OFFERED completion, and writes nothing until authorized" {
  # The hostile half of the case above. Completion is OFFERED, never assumed;
  # an offer that completes anyway is not an offer, so the discriminating
  # assertion is not the exit code — it is that the artifacts are BYTE-IDENTICAL
  # across the unauthorized run. Delete the authorization guard and this reddens
  # while every other case in the file stays green.
  mk_story 006-widget-flow
  mk_story 012-successor
  mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [ ] 1.1 - open
  - [ ] 1.2 - also open
T
  run_supersede 006 --by 012 --rationale "first run"
  [ "$status" -eq 0 ]

  local d="$PROJ/.epic/stories/006-widget-flow"
  sed -i 's/^status: superseded$/status: in-progress/' "$d"/*.md
  sed -i '/^superseded-by:/d' "$d"/*.md
  sed -i 's/^  - \[~\] 1\.\(.\) - \(.*\) (superseded-by: 012)$/  - [ ] 1.\1 - \2/' "$d/tasks.md"

  local before; before=$(cat "$d"/*.md | sha256sum)

  run_supersede 006 --by 012 --rationale "unauthorized"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "recovery-offer"' > /dev/null
  echo "$output" | jq -e '.reason | test("--complete-interrupted")' > /dev/null
  echo "$output" | jq -e '.banner_written == false' > /dev/null
  echo "$output" | jq -e '.closed_subtasks == 0' > /dev/null
  echo "$output" | jq -e '.artifacts_flipped | length == 0' > /dev/null

  # NOTHING was written — the whole content of "offer".
  [ "$(cat "$d"/*.md | sha256sum)" = "$before" ]
  [ "$(banner_count 006-widget-flow)" -eq 1 ]
  [ "$(grep -c '^  - \[ \]' "$d/tasks.md")" -eq 2 ]
}

@test "recovery: the authorization flag can never create a banner or unlock a refusal" {
  # --complete-interrupted is an authorization, and an authorization is only
  # safe if it unlocks exactly one thing. Two ways it could over-reach, both asserted here.
  mk_story 006-widget-flow
  mk_story 012-successor
  mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [ ] 1.1 - open
T
  # (a) On a FRESH story the flag changes nothing: one banner, not two, and the
  #     verdict is still `superseded` rather than `completed`.
  run_supersede 006 --by 012 --rationale "fresh with flag" --complete-interrupted
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "superseded"' > /dev/null
  echo "$output" | jq -e '.banner_written == true' > /dev/null
  [ "$(banner_count 006-widget-flow)" -eq 1 ]

  # (b) On a COMPLETE prior supersede — recovery table row 1 — the flag must NOT
  #     turn a refusal into a completion. Authorization is not a matrix override.
  run_supersede 006 --by 012 --rationale "re-run with flag" --complete-interrupted
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  [ "$(banner_count 006-widget-flow)" -eq 1 ]
}

@test "recovery: a status write over open scope is refused, not offered completion" {
  # The recovery table's third row: a status written over open scope must be
  # refused, never fall through to a SECOND banner, which is never allowed.
  mk_story 006-widget-flow
  mk_story 012-successor
  mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [ ] 1.1 - open
  - [ ] 1.2 - also open
T
  run_supersede 006 --by 012 --rationale "first run"
  [ "$status" -eq 0 ]

  # Hand-edit into the shape this command cannot produce: status written AND a
  # box still open. Only a human or a half-applied sweep gets here.
  local d="$PROJ/.epic/stories/006-widget-flow"
  sed -i 's/^  - \[~\] 1\.2 - \(.*\) (superseded-by: 012)$/  - [ ] 1.2 - \1/' "$d/tasks.md"
  grep -q '^status: superseded$' "$d/story.md"
  [ "$(grep -c '^  - \[ \]' "$d/tasks.md")" -eq 1 ]

  run_supersede 006 --by 012 --rationale "third run"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  echo "$output" | jq -e '.reason | test("cannot produce")' > /dev/null
  [ "$(banner_count 006-widget-flow)" -eq 1 ]
}

@test "recovery: the classification is exhaustive over every banner-bearing state" {
  # Disjointness alone is half a table. Every cell of status x open-box x
  # authorized must reach a VERDICT; none may fall through to a second banner.
  # Driven through the script rather than read off the doc. Adding an input to
  # the table requires re-checking exhaustiveness over it.
  mk_story 012-successor
  local st box d n auth
  local -a authflag
  for auth in unauthorized authorized; do
    case "$auth" in
      unauthorized) authflag=() ;;
      authorized) authflag=(--complete-interrupted) ;;
    esac
  for st in none some all; do
    for box in yes no; do
      rm -rf "$PROJ/.epic/stories/006-widget-flow"
      mk_story 006-widget-flow
      mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [ ] 1.1 - open
  - [ ] 1.2 - also open
T
      run_supersede 006 --by 012 --rationale "seed"
      [ "$status" -eq 0 ]
      d="$PROJ/.epic/stories/006-widget-flow"

      case "$st" in
        none) sed -i 's/^status: superseded$/status: in-progress/' "$d"/*.md
              sed -i '/^superseded-by:/d' "$d"/*.md ;;
        some) sed -i 's/^status: superseded$/status: in-progress/' "$d/design.md" "$d/tasks.md"
              sed -i '/^superseded-by:/d' "$d/design.md" "$d/tasks.md" ;;
        all)  : ;;
      esac
      if [ "$box" = yes ]; then
        sed -i 's/^  - \[~\] 1\.2 - \(.*\) (superseded-by: 012)$/  - [ ] 1.2 - \1/' "$d/tasks.md"
      fi

      run_supersede 006 --by 012 --rationale "probe" "${authflag[@]}"
      # A verdict, whichever it is — and never a second banner.
      echo "$output" | jq -e '.status | test("^(refused|completed|superseded|recovery-offer)$")' > /dev/null
      n=$(banner_count 006-widget-flow)
      [ "$n" -eq 1 ] || { echo "state st=$st box=$box auth=$auth produced $n banners"; false; }
      # An unauthorized run never reaches `completed`: that is the arm the
      # offer replaces, and it is the only cell the axis can move.
      if [ "$auth" = unauthorized ]; then
        echo "$output" | jq -e '.status != "completed"' > /dev/null
      fi
    done
  done
  done
}

# --- What a successful run writes -------------------------------------------

@test "the banner is is prepended and the status set in EVERY artifact" {
  mk_story 006-widget-flow
  mk_story 012-successor
  mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [ ] 1.1 - open
T
  run_supersede 006 --by 012 --rationale "replaced by the v2 flow"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "superseded"' > /dev/null

  local d="$PROJ/.epic/stories/006-widget-flow" f
  # Prepended: the banner is the FIRST line after the frontmatter's closing
  # delimiter, and above everything else. Derived, not hard-coded — the op adds
  # a frontmatter key, so any literal line number here is wrong the moment the
  # write it is testing succeeds.
  local fm_end banner_at
  fm_end=$(grep -n '^---$' "$d/story.md" | sed -n '2p' | cut -d: -f1)
  banner_at=$(grep -n '⛔ SUPERSEDED' "$d/story.md" | cut -d: -f1)
  [ "$banner_at" -eq "$((fm_end + 1))" ]
  grep -q '^# story$' "$d/story.md"
  for f in story.md design.md tasks.md; do
    grep -q '^status: superseded$' "$d/$f"
    grep -q '^superseded-by: 012$' "$d/$f"
  done
  echo "$output" | jq -e '.artifacts_flipped | length == 3' > /dev/null
}

@test "the banner carries the date, the target, the rationale, and one row per OPEN sub-task" {
  mk_story 006-widget-flow
  mk_story 012-successor
  mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [x] 1.1 - already done
  - [ ] 1.2 - still open
  - [~] 1.3 - parked (deferred: waiting on the vendor)
  - [~] 1.4 - dropped (waived: not needed)
T
  run_supersede 006 --by 012 --rationale "replaced by the v2 flow"
  [ "$status" -eq 0 ]

  local d="$PROJ/.epic/stories/006-widget-flow"
  grep -q "⛔ SUPERSEDED ($(date +%Y-%m-%d)) — by story 012" "$d/story.md"
  grep -q 'replaced by the v2 flow' "$d/story.md"

  # Rows for 1.2 (open) and 1.3 (deferred — still owed), and for NOTHING else.
  # The hostile half is the pair that must NOT appear: a closed box and a
  # terminal [~] are settled, and a row for either would claim scope moved
  # that never did.
  #
  # The literal `task ` prefix is the spec's, not a preference: the template's
  # placeholder reads `<task N.N — title>` and supersede-mode.md's walkthrough
  # renders `| task 2.1 — Map legacy fields …`.
  grep -q '^> | task 1.2 ' "$d/story.md"
  grep -q '^> | task 1.3 ' "$d/story.md"
  # `if … then return 1; fi` rather than `! grep`: bash exempts a `!`-inverted
  # command from errexit, so anywhere but an @test's LAST statement the negation
  # is inert — green whatever story.md says.
  # Canonical statement of the rule: the negated-assertion paragraph at the top of tests/reports-by-artifact-policy.bats.
  if grep -q '^> | task 1.1 ' "$d/story.md"; then
    return 1
  fi
  if grep -q '^> | task 1.4 ' "$d/story.md"; then
    return 1
  fi
  echo "$output" | jq -e '.remap_rows == 2' > /dev/null
}

@test "every open sub-task closes as superseded-by, and no closed one is touched" {
  mk_story 006-widget-flow
  mk_story 012-successor
  mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [x] 1.1 - already done
  - [ ] 1.2 - still open
  - [~] 1.3 - parked (deferred: waiting on the vendor)
  - [~] 1.4 - dropped (waived: not needed)
T
  run_supersede 006 --by 012 --rationale "x"
  [ "$status" -eq 0 ]

  local d="$PROJ/.epic/stories/006-widget-flow"
  grep -q '^  - \[x\] 1\.1 - already done$' "$d/tasks.md"
  grep -q '^  - \[~\] 1\.2 - still open (superseded-by: 012)$' "$d/tasks.md"
  # On a deferred box the qualifier is REPLACED, never joined: a line carrying
  # both stays owed, because `deferred:` wins the census.
  grep -q '^  - \[~\] 1\.3 - parked (superseded-by: 012)$' "$d/tasks.md"
  # `if … then return 1; fi` rather than `! grep`, here and at the open-box
  # assertion below: a `!`-inverted command is exempt from errexit, and neither
  # negation is this @test's last statement. Canonical: the negated-assertion paragraph at the top of tests/reports-by-artifact-policy.bats.
  if grep -q 'deferred:' "$d/tasks.md"; then
    return 1
  fi
  grep -q '^  - \[~\] 1\.4 - dropped (waived: not needed)$' "$d/tasks.md"
  # Nothing is left open, so the story is archivable.
  if grep -qE '^  - \[ \]' "$d/tasks.md"; then
    return 1
  fi
  echo "$output" | jq -e '.closed_subtasks == 2' > /dev/null
}

@test "a story with nothing open supersedes with no rows and no closures" {
  # The converse guard. A rule that generates rows unconditionally, or closes
  # boxes unconditionally, passes every case above and fails this one.
  mk_story 006-widget-flow
  mk_story 012-successor
  mk_tasks 006-widget-flow <<'T'
- [x] 1 - Group
  - [x] 1.1 - done
T
  run_supersede 006 --by 012 --rationale "x"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.remap_rows == 0' > /dev/null
  echo "$output" | jq -e '.closed_subtasks == 0' > /dev/null
  local d="$PROJ/.epic/stories/006-widget-flow"
  grep -q '^  - \[x\] 1\.1 - done$' "$d/tasks.md"
  [ "$(banner_count 006-widget-flow)" -eq 1 ]
}

@test "recovery leaves leaves ONE companion key, never two" {
  # `flip_all` runs over every artifact, and on recovery one of them may ALREADY carry
  # `superseded-by:` from the interrupted run. The de-dup guard drops the old
  # key and re-emits it beside `status:`; without it the artifact ends up with
  # two.
  #
  # The damage is silent, which is why it needs a case. `epic-index.sh`'s
  # `front_value` reads the FIRST match, so the index rendering still looks right
  # while the artifact it read is malformed — nothing downstream complains and
  # nothing upstream notices.
  mk_story 006-widget-flow
  mk_story 012-successor
  mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [ ] 1.1 - open
  - [ ] 1.2 - also open
T
  run_supersede 006 --by 012 --rationale "first run"
  [ "$status" -eq 0 ]

  # A PARTIALLY flipped interruption: story.md keeps its companion, the other
  # two lost theirs. This is the only state that exercises the guard, and it is
  # a state the *Incomplete* row explicitly admits ("the writes reached only
  # some artifacts").
  local d="$PROJ/.epic/stories/006-widget-flow"
  sed -i 's/^status: superseded$/status: in-progress/' "$d"/*.md
  sed -i '/^superseded-by:/d' "$d/design.md" "$d/tasks.md"
  [ "$(grep -c '^superseded-by:' "$d/story.md")" -eq 1 ]

  run_supersede 006 --by 012 --rationale "recovery" --complete-interrupted
  [ "$status" -eq 0 ]
  local f
  for f in story.md design.md tasks.md; do
    [ "$(grep -c '^superseded-by: 012$' "$d/$f")" -eq 1 ]
    # And it sits inside the frontmatter, which is the only place
    # epic-index.sh's front_value looks.
    [ "$(grep -n '^superseded-by: 012$' "$d/$f" | cut -d: -f1)" -lt "$(grep -n '^---$' "$d/$f" | sed -n '2p' | cut -d: -f1)" ]
  done
}

# --- Contract: the conventions this script inherits from archive-story.sh ----

@test "contract: exit 2 on invalid input emits NO JSON" {
  mk_story 006-widget-flow
  run_supersede 006 --nonsense
  [ "$status" -eq 2 ]
  if [ -n "$output" ] && echo "$output" | jq -e . > /dev/null 2>&1; then
    return 1
  fi
}

@test "contract: --by is required, and a missing story resolves to exit 2" {
  mk_story 006-widget-flow
  run_supersede 006
  [ "$status" -eq 2 ]
  run_supersede 999 --by 012
  [ "$status" -eq 2 ]
}

@test "contract: every verdict path emits exactly one parseable JSON object on stdout" {
  mk_story 006-widget-flow
  mk_story 012-successor
  mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [ ] 1.1 - open
T
  run_supersede 006 --by 006 --rationale x      # refused
  echo "$output" | jq -e . > /dev/null
  [ "$(echo "$output" | jq -s 'length')" -eq 1 ]

  run_supersede 006 --by 012 --rationale x      # superseded
  echo "$output" | jq -e . > /dev/null
  [ "$(echo "$output" | jq -s 'length')" -eq 1 ]
}

@test "contract: a rationale containing a double quote keeps the JSON parseable" {
  # A user-supplied string reaches an emitted document, so quotes and
  # backslashes in it must not break the JSON.
  mk_story 006-widget-flow
  mk_story 012-successor
  mk_tasks 006-widget-flow <<'T'
- [ ] 1 - Group
  - [ ] 1.1 - open
T
  run_supersede 006 --by 012 --rationale 'he said "no" — and a backslash \ too'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . > /dev/null
  grep -q 'he said "no"' "$PROJ/.epic/stories/006-widget-flow/story.md"
}
