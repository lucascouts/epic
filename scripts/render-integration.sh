#!/usr/bin/env bash
# The LIST annotation and the validate warning, as pure functions of the
# integration detector's JSON (story 006, R2.1-R2.3; design.md component 2, and
# the `Unit (integration rendering)` level added to its Testing Strategy at v8).
#
# Usage: bash scripts/render-integration.sh --list                < detector.json
#        bash scripts/render-integration.sh --validate <NNN>      < detector.json
#        bash scripts/render-integration.sh --should-annotate <status> \
#                                           <story-count> <is-stories-full>
#
#   --list             read the JSON of scripts/story-git-status.sh on stdin and
#                      write the LIST annotation — `integrada`, `não-integrada`
#                      or nothing (references/list-mode.md, Integration
#                      Annotation).
#   --validate <NNN>   same input; write the validate warning for a story that
#                      is not integrated, or nothing
#                      (references/validate-mode.md, Integration Warning).
#                      <NNN> is the story number as the reader knows it and is
#                      interpolated verbatim — `006`, not `6`.
#   --should-annotate  the cost rule (R2.1) as a decision, NOT a rendering: it
#                      reads no stdin and writes no output. Exit 0 = evaluate
#                      this story, exit 1 = skip it. <is-stories-full> is `true`
#                      only for `/epic:epic stories full`.
#
# Exit codes:
#   0  --list / --validate: a rendering was produced, OR deliberately was not.
#      --should-annotate:   evaluate this story.
#   1  --should-annotate ONLY: skip this story. Never returned by a rendering.
#   2  unknown or missing mode — a caller error, not an input condition. It
#      reads no stdin and renders nothing; see "the one non-zero exit" below.
#
# GOVERNING RULE, stated in both references verbatim: **not computable must
# never dress up as a finding.** Everything below follows from it.
#
# EVERY RENDERING PATH EXITS 0, and that is a contract rather than a
# convenience. R2.2 requires the warning to be a warning: "Appending it changes
# nothing else: not the pass, not step 2's status write, not step 3's offer, not
# the validation's exit semantics." A caller that checks `$?` around this script
# would turn that warning into a verdict — precisely the corpus's worst case, a
# project where integration state blocked things it was never meant to gate. So
# empty stdin, unparseable stdin, a missing `integrated` key, a story whose
# state is unknowable and a `jq` that is not installed all mean the SAME thing
# here — render nothing, exit 0 — and none of them is an error to report.
#
# SILENT ON STDERR ON EVERY PATH. THIS IS THE OPPOSITE OF archive-story.sh AND
# IS DELIBERATE; DO NOT "RESTORE" THE DIAGNOSTICS. Two reasons:
#   1. This script reaches no verdict. It has nothing to say that its stdout
#      does not already say, and a diagnostic would be a second author for a
#      sentence the orchestrator is about to speak in the session's own voice.
#   2. bats' plain `run` MERGES stderr into `$output`, and the cases that matter
#      most here assert `[ -z "$output" ]` on exactly the paths where a
#      diagnostic would be most tempting (unparseable input, no input at all).
#      One byte on stderr turns "renders nothing" into "renders something".
#      Silence keeps the pure-function contract true for careless callers too.
#   supersede-story.sh makes the same divergence for reason 2 and keeps exit 2
#   speaking; this script does not, because reason 1 applies to it and not to
#   that one.
#
# THE ONE NON-ZERO EXIT THAT IS NOT --should-annotate: an unknown or missing
# mode exits 2, the plugin-wide "invalid input, no verdict reached" code
# (validate-story.sh, archive-story.sh, supersede-story.sh). It is not reachable
# from any well-formed call, so it cannot touch a verdict; and exiting 0 there
# would answer "I rendered nothing" to a caller whose real problem is that it
# called this script wrong. `--validate` with no <NNN>, by contrast, is an INPUT
# condition and stays on the exit-0 path.
#
# Reads nothing but stdin, writes nothing but stdout: no files, no git, no
# state. The detector (scripts/story-git-status.sh) does the measuring; this
# turns its answer into text and is the only place the two contract strings and
# the warning sentence are spelled.

set -euo pipefail

# The two LIST contract strings, spelled once (references/list-mode.md: "The
# labels `integrada` and `não-integrada` are contract strings; render them
# verbatim"). Portuguese and accented on purpose — this is the user-facing
# vocabulary the reference fixes, not a translatable label, and the `ã` is
# U+00E3 encoded as UTF-8 (0xC3 0xA3). A file re-saved in another encoding
# breaks the contract without breaking the syntax.
ANNOTATION_INTEGRATED="integrada"
ANNOTATION_NOT_INTEGRATED="não-integrada"

# The cost rule's threshold (R2.1): "when the project has more than 50 stories
# skip the per-story evaluation". MORE THAN, so 50 itself is still evaluated.
ANNOTATION_SWEEP_THRESHOLD=50

# The five states `integrated` can arrive in, as one jq expression. FIVE, not
# two, and keeping them apart is the whole point of this filter:
#   true        the queries ran and found evidence
#   false       the queries RAN and found nothing — a positive claim
#   null        no queryable revision, so nothing was ever asked (R1.5, the arm
#               8.6 made reachable)
#   absent      an object with no `integrated` key — not this script's producer
#   unreadable  not an object, or `integrated` holding something that is not a
#               boolean and not null
# `null` AND `false` MUST NOT BE FOLDED TOGETHER, however tempting it is that
# three of the five states render nothing. They are opposite claims: `false`
# says a search happened and came back empty, `null` says no search was
# possible. Folding them makes the renderer say "not integrated" about a story
# nobody could look at — the exact dressing-up the governing rule forbids, and
# the reason each state below gets its own arm and its own reason for rendering
# what it renders.
# NB: `//` is unusable here. In jq, `false // x` yields x — the alternative
# operator treats `false` and `null` alike, which is the one distinction this
# filter exists to preserve.
INTEGRATED_STATE_FILTER='
  if type == "object" then
    if has("integrated") then
      .integrated
      | if . == true then "true"
        elif . == false then "false"
        elif . == null then "null"
        else "unreadable"
        end
    else "absent"
    end
  else "unreadable"
  end
'

# The main branch NAME, and only when it really is a name. The detector reports
# it as a string or as JSON null (`main_branch` is gated on the NAME resolving,
# `integrated` on the REVISION resolving — two fields, two questions), so
# anything that is not a string is no name at all and yields the empty string.
MAIN_BRANCH_FILTER='
  if type == "object" then
    if (.main_branch | type) == "string" then .main_branch else "" end
  else ""
  end
'

# jq_read <filter> <json>: <filter> applied to <json>, or the empty string when
# jq cannot answer — a parse failure, no input, or no jq on this machine.
# TOTAL: it always exits 0, because it is read through a command substitution in
# an assignment, where a non-zero status would trip `set -e`. jq's stderr is
# silenced for the same reason the whole script is silent: a parse error is an
# ordinary input condition here, not something to report.
# Only the FIRST line of the answer is returned. jq emits one line per input
# document, and a stdin carrying two objects would otherwise produce a two-line
# "state" that no `case` arm matches — this makes that input degrade to the
# first object's answer instead of to an unmatched string.
jq_read() {
  local filter="$1" json="$2" out="" rc=0
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  out=$(jq -r "$filter" 2>/dev/null <<< "$json") || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    return 0
  fi
  printf '%s' "${out%%$'\n'*}"
  return 0
}

# read_stdin: everything on stdin, or the empty string. Guarded like every
# external call in this plugin, and slurped ONCE because both renderings may
# need two different reads of the same document and a pipe cannot be rewound.
read_stdin() {
  local input="" rc=0
  input=$(cat 2>/dev/null) || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    return 0
  fi
  printf '%s' "$input"
  return 0
}

# render_list <json>: the LIST annotation for <json>, or nothing.
# references/list-mode.md, Integration Annotation:
#   true  → `integrada`, false → `não-integrada`, null → nothing.
# The caller appends it after a ` · `; the separator is the list's business, not
# this script's, so what comes back is the bare label.
render_list() {
  local state
  state=$(jq_read "$INTEGRATED_STATE_FILTER" "$1")
  case "$state" in
    true)
      printf '%s\n' "$ANNOTATION_INTEGRATED"
      ;;
    false)
      printf '%s\n' "$ANNOTATION_NOT_INTEGRATED"
      ;;
    null)
      # UNKNOWABLE, AND SO NOT ANNOTATED AT ALL. Its own arm, and it must stay
      # its own arm: no main branch was queryable, so no search happened and
      # there is no answer to report. Even a neutral "unknown" would be read as
      # a finding by someone scanning the column — list-mode.md rules the whole
      # class out in as many words, and this is the arm that would break first
      # if `null` were ever folded into `false`.
      :
      ;;
    absent | unreadable)
      # An object this script's producer did not write, or no readable JSON at
      # all — which is the detector's exit-2 path as the caller sees it (a
      # workspace without git is legal, R1.4). Nothing was measured either way,
      # so nothing is claimed: degrade silently — no annotation, no warning, no
      # error. Folded into ONE arm because they differ in cause and not in
      # consequence; the fold that would matter, `null` into `false`, is the one
      # kept apart above.
      :
      ;;
    *)
      # Unreachable: the filter above returns one of the five states or nothing
      # at all. Fail towards silence anyway — the cheap wrong answer here is the
      # missing annotation, never the invented one.
      :
      ;;
  esac
  return 0
}

# render_validate <json> <NNN>: the validate warning for <json>, or nothing.
# references/validate-mode.md, Integration Warning: emitted on `false` ONLY.
# `true` needs no warning and `null` may not carry one — the same three arms as
# render_list, reaching a different pair of texts, and split for the same
# reason.
# THE WARNING'S FIRST THREE WORDS ARE A PRECONDITION THIS SCRIPT CANNOT CHECK.
# "story is done" is true only where the caller applies it — on a passing
# verdict with no `[ ]` left. validate-mode.md's rule 2 (a partial pass) must
# not call this at all, because there the sentence would manufacture the very
# claim rule 2 exists to refuse. The renderer renders; WHEN to ask is the
# orchestrator's decision.
render_validate() {
  local json="$1" story_num="$2" state main
  state=$(jq_read "$INTEGRATED_STATE_FILTER" "$json")
  # <main> is FILLED FROM THE JSON, never assumed. The detector resolves the
  # default branch through four ordered candidates and it is regularly not named
  # `main`; a hard-coded name would print a branch the reader does not have, and
  # story 006 spent a whole sub-task (8.2) on getting that name right.
  # Re-inventing it here would throw that away at the last inch.
  main=$(jq_read "$MAIN_BRANCH_FILTER" "$json")

  # WELL-FORMEDNESS IS ASKED ONCE, HERE, AND NEVER AGAIN INSIDE AN ARM. The
  # warning sentence has exactly two holes — the branch and the story number —
  # and a document that cannot fill both does not yield a warning but a
  # malformed finding, so it joins the documents that cannot be read at all.
  # Neither hole is reachable through the detector (its `integrated: false`
  # implies a resolved name) or through a correct call; both are guarded because
  # this is a pure function of whatever JSON and argv it is handed, and neither
  # is an error — the exit-0 contract covers a missing field like any other.
  #
  # THE PLACEMENT IS THE POINT, AND IT WAS MEASURED RATHER THAN REASONED. This
  # test first sat INSIDE the `false)` arm, and there it silently disarmed the
  # test suite: fold `null` into `false)` — the one collapse this whole file is
  # built to forbid — and the case that exists to catch that fold
  # (tests/render-integration.bats, "integrated null produces no warning") went
  # on passing, because its fixture carries `main_branch: null` and the guard
  # inside the arm swallowed the warning the fold produced. A guard inside one
  # arm is a guard every other arm inherits when someone merges into it. Hoisted
  # here it classifies, and the three-valued decision below then rests on
  # `integrated` ALONE, so no arm of it can be silenced by a later test.
  # Same lesson as scripts/story-git-status.sh's single MAIN_REF gate: a rule
  # applied per arm is a rule a newly added arm skips for free.
  if [[ "$state" == "false" && ( -z "$main" || -z "$story_num" ) ]]; then
    state="unnameable"
  fi

  case "$state" in
    false)
      printf 'story is done but no evidence of integration to %s (no merged feat/%s-* branch, no (%s) commit)\n' \
        "$main" "$story_num" "$story_num"
      ;;
    true)
      # Nothing — the work is on the main branch.
      :
      ;;
    null)
      # Nothing at all: no main branch is resolvable, so the fact is unknowable
      # (R1.4/R1.5). Its own arm for the same reason it is in render_list — and
      # the one that turns red the moment `null` is folded into `false`, which
      # is true only because of where the well-formedness test above sits.
      :
      ;;
    absent | unreadable | unnameable)
      # Exit 2 as the caller sees it, JSON from somewhere else, or a `false`
      # nothing could render: degrade silently. A failed detection must never
      # delay, dirty or block the verdict it decorates.
      :
      ;;
    *)
      # Unreachable; silence is the safe direction. See render_list.
      :
      ;;
  esac
  return 0
}

# should_annotate <status> <story-count> <is-stories-full>: the cost rule
# (R2.1). Exit 0 = evaluate, 1 = skip. Every annotation costs one git
# evaluation, so this is where a 400-story project stops paying for 400 of them.
#
# THE THREE GATES ARE ORDERED, AND THE ORDER IS PART OF THE RULE:
#   1. status — only `done`/`validated` stories are ever annotated. A draft has
#      no integration question to ask, however small the project, so this gate
#      is not a cost control and no sweep flag overrides it.
#   2. the full sweep — `/epic:epic stories full` evaluates "regardless of story
#      count", so it answers before the count is even looked at. That is what
#      makes an unparseable count harmless on this path: it is not consulted.
#   3. the count — more than 50 skips. MORE THAN: 50 evaluates.
should_annotate() {
  local status="${1:-}" count="${2:-}" full="${3:-}"

  case "$status" in
    done | validated) ;;
    *) return 1 ;;
  esac

  # Exactly `true`, nothing looser. Anything else is an ordinary listing, and a
  # sloppy match here would turn every listing into a full sweep — the failure
  # mode this rule exists to prevent.
  if [[ "$full" == "true" ]]; then
    return 0
  fi

  # A count that is not a count proves nothing about being under the threshold,
  # so it skips. The direction is deliberate: failing towards `skip` costs an
  # annotation, failing towards `evaluate` costs the git call the rule was
  # written to avoid.
  if [[ ! "$count" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  if [[ "$count" -gt "$ANNOTATION_SWEEP_THRESHOLD" ]]; then
    return 1
  fi
  return 0
}

# --- Dispatch ---------------------------------------------------------------
# Note which modes read stdin: `--should-annotate` must NOT, or a caller with no
# redirection would block on a terminal for a decision that needs no input.
MODE="${1:-}"
case "$MODE" in
  --list)
    render_list "$(read_stdin)"
    exit 0
    ;;
  --validate)
    render_validate "$(read_stdin)" "${2:-}"
    exit 0
    ;;
  --should-annotate)
    if should_annotate "${2:-}" "${3:-}" "${4:-}"; then
      exit 0
    fi
    exit 1
    ;;
  *)
    # A caller error, not an input condition — and the only path here that is
    # neither a rendering nor the cost decision. Silent on both streams (see the
    # header); the exit code is the whole signal.
    exit 2
    ;;
esac
