#!/usr/bin/env bats
# Unit tests for scripts/render-integration.sh — the LIST annotation and the
# validate warning as a pure function of the detector's JSON (story 006, R2).
#
# WHY THIS FILE EXISTS. R2.1–R2.3 were specified as orchestrator prose, so no
# case could drive them and the acceptance-criteria quality gate could not be
# met for any of the three. But the two renderings are not conversation: given
# `story-git-status.sh`'s JSON, the annotation text and the warning text are
# determined. 9.1 established the split — a step that WRITES DESTRUCTIVELY gets
# a script; a step that is a pure function gets one too, because there is no
# reason for a decidable thing to rest on prose review.
#
# THE STANDARD. Every R2 criterion must have a case that FAILS WHEN ITS
# BEHAVIOUR IS REMOVED. The `null` arm is the one to watch: it is the arm 8.6
# made reachable, and `references/validate-mode.md` states the rule it must
# obey in as many words — "Not computable must never dress up as a finding".
#
# THE VERSION DECLARATION BELOW IS LOAD-BEARING, not boilerplate. The R2.3 case
# drives `archive-story.sh` with `run --separate-stderr`, and flags on `run`
# require bats 1.5.0; without this line bats emits BW02 on every run of the
# whole suite and the guarantee is only incidental. `epic-index.bats` and
# `archive-story.bats` already declare it — this file used the feature without
# joining the convention. Added at story 006's tenth validate.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RENDER="$PLUGIN_ROOT/scripts/render-integration.sh"
  WORK=$(mktemp -d)
}

teardown() { rm -rf "$WORK"; }

# detector_json <integrated> [main] [missing-kinds...]
detector_json() {
  local integrated="$1" main="${2:-main}"
  printf '{"story":"006-widget-flow","main_branch":%s,"integrated":%s,"evidence":[],"checked_at":"2026-08-08T00:00:00Z"}\n' \
    "$([ "$main" = "null" ] && printf 'null' || printf '"%s"' "$main")" "$integrated"
}

# --- R2.1: the LIST annotation ----------------------------------------------

@test "R2.1: integrated true renders the contract string 'integrada'" {
  run bash -c "$(declare -f detector_json); detector_json true | bash '$RENDER' --list"
  [ "$status" -eq 0 ]
  [ "$output" = "integrada" ]
}

@test "R2.1: integrated false renders the contract string 'não-integrada'" {
  run bash -c "$(declare -f detector_json); detector_json false | bash '$RENDER' --list"
  [ "$status" -eq 0 ]
  [ "$output" = "não-integrada" ]
}

@test "R2.1: integrated null renders NOTHING AT ALL" {
  # The arm 8.6 made reachable. A renderer that emits any text here — even
  # "unknown" — turns a fact nobody could establish into something the reader
  # sees as a finding, which list-mode.md forbids in as many words.
  run bash -c "$(declare -f detector_json); detector_json null | bash '$RENDER' --list"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "R2.1: no JSON at all — the detector's exit-2 path — renders NOTHING" {
  # A workspace without git is legal (R1.4). Degrade silently: no annotation,
  # no warning, no error, and above all no non-zero exit that a caller would
  # have to handle.
  run bash -c ": | bash '$RENDER' --list"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run bash -c "printf 'not json at all\n' | bash '$RENDER' --list"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "R2.1 cost rule: only done/validated stories are evaluated, and 50 is the sweep threshold" {
  # The cost rule is part of R2.1 and is decidable at the same boundary: one
  # annotation is one git evaluation, so the decision of WHETHER to evaluate is
  # a pure function of (status, story count, is-this-`stories full`).
  # Exit 0 = evaluate, 1 = skip.
  run bash "$RENDER" --should-annotate done 10 false;        [ "$status" -eq 0 ]
  run bash "$RENDER" --should-annotate validated 10 false;   [ "$status" -eq 0 ]
  # The hostile half: a status that is NOT done/validated is never evaluated,
  # however small the project.
  run bash "$RENDER" --should-annotate in-progress 1 false;  [ "$status" -eq 1 ]
  run bash "$RENDER" --should-annotate draft 1 false;        [ "$status" -eq 1 ]
  run bash "$RENDER" --should-annotate superseded 1 false;   [ "$status" -eq 1 ]
  # Above 50 stories the per-story evaluation is skipped...
  run bash "$RENDER" --should-annotate done 51 false;        [ "$status" -eq 1 ]
  # ...unless the command is `stories full`, which sweeps regardless of count.
  run bash "$RENDER" --should-annotate done 51 true;         [ "$status" -eq 0 ]
  run bash "$RENDER" --should-annotate done 5000 true;       [ "$status" -eq 0 ]
  # The boundary itself: 50 is not "more than 50".
  run bash "$RENDER" --should-annotate done 50 false;        [ "$status" -eq 0 ]
}

# --- R2.2: the validate warning, and its non-blocking half -------------------

@test "R2.2: a non-integrated story produces the warning, verbatim" {
  run bash -c "$(declare -f detector_json); detector_json false main | bash '$RENDER' --validate 006"
  [ "$status" -eq 0 ]
  [ "$output" = "story is done but no evidence of integration to main (no merged feat/006-* branch, no (006) commit)" ]
}

@test "R2.2: <main> is filled from the JSON, not assumed" {
  # The detector resolves the main branch; a renderer that hard-codes `main`
  # would print a branch the reader does not have. 8.2 exists because that name
  # can be got wrong, so the renderer must not re-invent it.
  run bash -c "$(declare -f detector_json); detector_json false trunk | bash '$RENDER' --validate 006"
  [ "$status" -eq 0 ]
  [[ "$output" == *"integration to trunk"* ]]
  [[ "$output" != *"integration to main"* ]]
}

@test "R2.2: an integrated story produces no warning" {
  run bash -c "$(declare -f detector_json); detector_json true | bash '$RENDER' --validate 006"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "R2.2: integrated null produces no warning — not computable is not a finding" {
  run bash -c "$(declare -f detector_json); detector_json null null | bash '$RENDER' --validate 006"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "R2.2: the non-blocking half is a SEPARATE assertion from the warning half" {
  # Two behaviours, two assertions. A renderer could emit the right text and
  # still break R2.2 by exiting non-zero, because a caller that checks its exit
  # status would then turn a warning into a verdict — which is exactly what
  # R2.2 forbids and what the corpus's worst case did.
  run bash -c "$(declare -f detector_json); detector_json false | bash '$RENDER' --validate 006"
  [ -n "$output" ]        # the warning appeared
  [ "$status" -eq 0 ]     # and the verdict is untouched
}

# --- R2.3: archive never consults integration state --------------------------

@test "R2.3: a NON-INTEGRATED story archives cleanly" {
  # The hostile half is a fixture that would fail if archive consulted the
  # signal at all. The story below is complete and its work has never been
  # merged anywhere — there is no git repo here, so the detector cannot even
  # answer — and the archive must not care.
  local proj="$WORK/proj"
  mkdir -p "$proj/.epic/stories/006-widget-flow"
  cd "$proj"
  local d="$proj/.epic/stories/006-widget-flow"
  cat > "$d/story.md" <<'EOF'
---
story: widget-flow
type: feature
scale: standard
version: 1
created: 2026-08-08
status: done
---

## Introduction
x

### R1. First
#### Acceptance Criteria
- R1.1: WHEN x THE SYSTEM SHALL y
EOF
  cat > "$d/tasks.md" <<'EOF'
---
story: widget-flow
type: feature
scale: standard
version: 1
created: 2026-08-08
status: done
---

## Task List
- [x] 1 - Group
  - [x] 1.1 - done
    - Requirements: R1.1
    - Validation: `true`
  - Commit: "feat: x"

## Quality Gates
- Tests pass
EOF
  # `--separate-stderr`, because archive-story.sh puts its JSON on stdout and
  # its human-readable diagnostics on stderr BY CONTRACT — bats' plain `run`
  # merges the two and the merged stream is not parseable. (This case used
  # plain `run` in its first draft and failed for that reason, which is a
  # broken test rather than valid Red.)
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/archive-story.sh" .epic/stories/006-widget-flow
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "archived"' > /dev/null
  # And the verdict names nothing about integration — the concept must not
  # appear in the archive's report at all.
  echo "$output" | jq -e 'has("integrated") | not' > /dev/null
  [ -d "$proj/.epic/archive/006-widget-flow" ]
}
