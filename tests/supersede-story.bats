#!/usr/bin/env bats
# Unit tests for scripts/supersede-story.sh — the mechanical half of the
# supersede operation (story 006, design.md component 3, amended at v8).
#
# WHY THIS FILE EXISTS. Through design v7 supersede was specified as an
# orchestrator flow with no script, and `.draft/deviations.yaml` entry 5 waived
# this very test level for exactly that reason: there was no entry point a case
# could drive. That waiver was sound given the design and is retired at v8,
# because the design changed. The discriminator 9.1 established is not
# "orchestrator flow versus script" but **does the step write destructively to
# artifacts** — supersede writes a banner, closes sub-tasks and flips two
# frontmatter keys, so its mechanical half belongs behind a script for the same
# reason archive's does.
#
# THE STANDARD THESE CASES ARE HELD TO. Not "a case exists that references the
# criterion" — this story passed four consecutive validates on that reading
# while the code violated a criterion. Every R3 criterion here must have a case
# that FAILS WHEN ITS BEHAVIOUR IS REMOVED, demonstrated by removal rather than
# asserted. The hostile half of each rule is written first.

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

# --- R3.4: the refusal matrix, all four arms --------------------------------
# Every arm is a hostile half: the operation must REFUSE and write nothing.
# "Writes nothing" is asserted separately from "refuses", because a refusal
# that has already touched the story is the failure this matrix exists to stop.

@test "R3.4 row 1: a story cannot supersede itself" {
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

@test "R3.4 row 2: the replacement story must already exist" {
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

@test "R3.4 row 3: an archived story is immutable history" {
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

@test "R3.4 row 4 / R3.5: a COMPLETE prior supersede refuses and does not duplicate the banner" {
  # The pair that collided at design v3 and was merged into one row: this arm
  # and the interrupted arm below must give DIFFERENT answers to what is
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
  # R3.5's unconditional half: written at most once, EVER.
  [ "$(banner_count 006-widget-flow)" -eq 1 ]
}

# --- R3.5: the interrupted arm, and the state this command cannot produce ----

@test "R3.5: an INTERRUPTED prior run is completed, without a second banner" {
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

  # Completion is now AUTHORIZED, not assumed (R3.5). The unauthorized arm is
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

@test "R3.5 hostile: an INTERRUPTED run is OFFERED completion, and writes nothing until authorized" {
  # The hostile half of the case above, authored against the requirement rather
  # than against the code (7.1). R3.5 says the system SHALL *offer* to complete;
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

@test "R3.5 third element: the authorization flag can never create a banner or unlock a refusal" {
  # 8.1's question asked of the value THIS fix introduced. --complete-interrupted
  # is a new authorization, and a new authorization is only safe if it unlocks
  # exactly one thing. Two ways it could over-reach, both asserted here.
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

@test "R3.5: a status write over open scope is refused, not offered completion" {
  # The recovery table's third row. 8.5 removed an overlap here and left a gap
  # in its place, and with step 2's guard still negative an unclassified state
  # fell through to a SECOND banner — which R3.5 forbids unconditionally. This
  # case is what stops that returning.
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

@test "R3.5: the recovery classification is exhaustive over every banner-bearing state" {
  # Disjointness alone is half a table — that is the lesson b317d1d recorded.
  # Every cell of status x open-box must reach a VERDICT; none may fall through
  # to a second banner. Driven through the script rather than read off the doc.
  # R3.5's authorization is a SECOND AXIS, added when the offer was implemented,
  # so exhaustiveness is now over status x open-box x authorized. A table that
  # was exhaustive before a new input was added is not exhaustive after it —
  # that is 8.1's question asked of this fix's own derived value.
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
      # An unauthorized run never reaches `completed`: that is the arm R3.5
      # turns into an offer, and it is the only cell the axis can move.
      if [ "$auth" = unauthorized ]; then
        echo "$output" | jq -e '.status != "completed"' > /dev/null
      fi
    done
  done
  done
}

# --- R3.1 / R3.2 / R3.3: what a successful run writes ------------------------

@test "R3.1: the banner is prepended and the status set in EVERY artifact" {
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
  # write it is testing succeeds. (This assertion did hard-code 9 in its first
  # draft and was the reason 9.2's first Executor stopped at step 4.)
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

@test "R3.2: the banner carries the date, the target, the rationale, and one row per OPEN sub-task" {
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
  # renders `| task 2.1 — Map legacy fields …`. This assertion omitted it in
  # its first draft, which pushed the implementation off the spec.
  grep -q '^> | task 1.2 ' "$d/story.md"
  grep -q '^> | task 1.3 ' "$d/story.md"
  ! grep -q '^> | task 1.1 ' "$d/story.md"
  ! grep -q '^> | task 1.4 ' "$d/story.md"
  echo "$output" | jq -e '.remap_rows == 2' > /dev/null
}

@test "R3.3: every open sub-task closes as superseded-by, and no closed one is touched" {
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
  ! grep -q 'deferred:' "$d/tasks.md"
  grep -q '^  - \[~\] 1\.4 - dropped (waived: not needed)$' "$d/tasks.md"
  # Nothing is left open, so the story is archivable.
  ! grep -qE '^  - \[ \]' "$d/tasks.md"
  echo "$output" | jq -e '.closed_subtasks == 2' > /dev/null
}

@test "R3.2/R3.3: a story with nothing open supersedes with no rows and no closures" {
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

@test "R3.7 write half: recovery leaves ONE companion key, never two" {
  # 8.1's derived-value question asked of the recovery path. `flip_all` runs
  # over every artifact, and on recovery one of them may ALREADY carry
  # `superseded-by:` from the interrupted run. The de-dup guard drops the old
  # key and re-emits it beside `status:`; without it the artifact ends up with
  # two. Measured: guard removed, story.md carries 2.
  #
  # The damage is silent, which is why it needs a case. `epic-index.sh`'s
  # `front_value` reads the FIRST match, so R3.7's rendering still looks right
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
  [ -z "$output" ] || ! echo "$output" | jq -e . > /dev/null 2>&1
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
  # Same defect class as 4.1's control-character finding on the detector: a
  # user-supplied string reaches an emitted document.
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
