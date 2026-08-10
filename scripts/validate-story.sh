#!/usr/bin/env bash
# Validates an epic story directory for common issues.
# Usage: bash scripts/validate-story.sh <story-directory> [--cross-ref] [--strict]
# Exit 0 = all checks pass, Exit 1 = issues found, Exit 2 = invalid input
# Output: JSON with passed/failed checks for structured consumption

set -euo pipefail

# --- Help ---
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'HELP'
Usage: validate-story.sh <story-directory> [--cross-ref] [--strict]

Validates epic story artifacts for structural correctness.

Arguments:
  <story-directory>  Path to the story directory containing *.md files
  --cross-ref        Enable cross-reference checks (R-numbers in tasks vs story)
  --strict           Promote warnings to errors (exit 1 on any warning).
                     Use in CI gates for stories expected to be production-ready.

Output: JSON with errors, warnings, and status (pass/fail)

Exit codes:
  0  All checks pass (or only warnings without --strict)
  1  Validation issues found (see JSON output)
  2  Invalid input (missing directory, not a story directory)
HELP
  exit 0
fi

# --- Input validation ---
STORY_DIR="${1:-.}"

if [[ ! -d "$STORY_DIR" ]]; then
  echo "Error: Directory '$STORY_DIR' not found." >&2
  echo "Usage: validate-story.sh <story-directory>" >&2
  exit 2
fi

ERRORS=()
WARNINGS=()

# --- Helpers ---
add_error() { ERRORS+=("$1"); }
add_warning() { WARNINGS+=("$1"); }

# Minimal JSON string escape: messages can embed content read from the
# artifacts (quotes, backslashes, control chars) and must never break the
# jq consumers downstream (hooks, CI).
json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

# frontmatter_field <file> <key> — the value of a column-0 frontmatter key, or
# nothing at all when the file, the frontmatter or the key is absent.
# Same contract as the version:/status: parsing further down, factored out
# because the scale is declared in story.md OR in tasks.md and both have to be
# read: the file must OPEN with a `---` line, the block ends at the next one
# (`sed '$d'` drops that closing line — GNU-only `head -n -1` aborted the whole
# validation on BSD/macOS under set -e + pipefail), and the value is squeezed of
# whitespace. Anchored at column 0 like the templates write it, so a compound or
# nested key (`review_scale:`) can never fake a value. <key> is a caller-supplied
# literal, never user input — it is interpolated into the regex as-is.
frontmatter_field() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  head -1 "$file" | grep -q '^---$' 2>/dev/null || return 0
  # `|| true`: a key that is simply absent makes grep exit 1, and under
  # pipefail that would abort the caller's command substitution.
  sed -n '2,/^---$/p' "$file" | sed '$d' | grep -E "^$key:" | head -1 |
    sed "s/.*$key:\s*//" | tr -d '[:space:]' || true
}

# xr_in_list <needle> <haystack...> — membership test for the cross-ref check.
xr_in_list() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# --- Infer scale from files present ---
# The FALLBACK, not the source of truth: a declared `scale:` governs (see the
# block right below), and this inference is what a story with no such field
# gets — unchanged, because 340+ legacy stories predate the field.
HAS_STORY=false
HAS_TASKS=false
IS_BUGFIX=false

[[ -f "$STORY_DIR/story.md" ]] && HAS_STORY=true
[[ -f "$STORY_DIR/tasks.md" ]] && HAS_TASKS=true

if [[ "$HAS_TASKS" == false ]]; then
  add_error "Missing tasks.md — every story must have tasks"
fi

# Detect bugfix from frontmatter
if [[ "$HAS_STORY" == true ]]; then
  if head -10 "$STORY_DIR/story.md" | grep -qi 'type:.*bugfix' 2>/dev/null; then
    IS_BUGFIX=true
  fi
fi

# --- Read the DECLARED scale (R2.1, R2.3) ---
# Until this block existed the validator only ever inferred the scale from the
# files present and never read the field, which is how `scale: medium` shipped
# unnoticed and how a spike would have been mis-validated as Fast.
#
# Grammar rule, identical to `status:` below: fail-CLOSED on a present-but-wrong
# value (an invented scale is an error), fail-OPEN on absence (no field means
# the file inference above stands alone, with no error, no warning and no extra
# output line — the pre-change bytes, exactly).
#
# One source of truth for the enum: the alternation drives both the `[[ =~ ]]`
# check and the human-readable message (a `case` pattern cannot — bash does not
# re-parse `|` from an expanded variable as alternation, only `[[ =~ ]]` does).
SCALE_ENUM='fast|standard|full|spike'
SCALE_ENUM_TEXT=${SCALE_ENUM//|/, }
DECLARED_SCALE=""       # the resolved scale; "" = no artifact declares one
DECLARED_SCALE_FILE=""  # the artifact it was read from, for the messages

# WHERE the scale is declared depends on the scale itself: a full/standard story
# declares it in its own story.md, while a fast/spike story is tasks-only and
# can only declare it in tasks.md. So both are read, story.md FIRST — it is the
# story's own frontmatter and therefore wins when the two disagree.
# Every declaration is enum-checked, not just the winning one: a `medium` in
# tasks.md is the defect this check exists to catch, and it must not be
# swallowed by a valid value in story.md.
for SCALE_SRC in story.md tasks.md; do
  SCALE_VAL=$(frontmatter_field "$STORY_DIR/$SCALE_SRC" scale)
  if [[ -z "$SCALE_VAL" ]]; then
    continue
  fi
  if ! [[ "$SCALE_VAL" =~ ^($SCALE_ENUM)$ ]]; then
    add_error "$SCALE_SRC frontmatter 'scale' is not a story scale: found '$SCALE_VAL' — must be one of: $SCALE_ENUM_TEXT"
    # An invented value resolves to NOTHING: every later check would have to
    # guess what `medium` meant, and a guess must never dress up as a finding.
    continue
  fi
  if [[ -z "$DECLARED_SCALE" ]]; then
    DECLARED_SCALE="$SCALE_VAL"
    DECLARED_SCALE_FILE="$SCALE_SRC"
  fi
done

# --- Declared scale vs files present (R2.3) ---
# Each scale names an artifact set (references/tasks.md): fast and spike are
# tasks-only, standard adds story.md, full adds design.md on top. A declaration
# that contradicts the files on disk means ONE of the two sides is wrong, and
# which one is the author's call — so it is a warning naming BOTH sides, never
# an error that picks a winner.
# Skipped whole when nothing was declared, which is the fail-open rule made
# structural rather than merely restated.
#
# scale_mismatch <what the scale implies> <what the files show> <the fix>
# ONE skeleton for all three shapes, so "names BOTH sides" is guaranteed by
# construction and not by three authors remembering it: the declaration and the
# file it lives in on the left, the filesystem on the right, and a fix for each
# side — the warning deliberately does not pick which one is wrong.
scale_mismatch() {
  add_warning "declared scale '$DECLARED_SCALE' (in $DECLARED_SCALE_FILE) contradicts the files present: $1, but $2 — $3, or declare the scale the files actually describe"
}

if [[ -n "$DECLARED_SCALE" ]]; then
  # SCALE_ARTIFACT is the file being CONTRADICTED, never the one the
  # declaration was read from (that is DECLARED_SCALE_FILE).
  case "$DECLARED_SCALE" in
    fast|spike)
      for SCALE_ARTIFACT in story.md design.md; do
        if [[ -f "$STORY_DIR/$SCALE_ARTIFACT" ]]; then
          scale_mismatch "a '$DECLARED_SCALE' story is tasks-only" \
            "$SCALE_ARTIFACT is present" "remove $SCALE_ARTIFACT"
        fi
      done
      ;;
    standard)
      # design.md is OPTIONAL at standard scale, so its presence says nothing;
      # only a missing story.md contradicts the declaration.
      if [[ ! -f "$STORY_DIR/story.md" ]]; then
        scale_mismatch "a 'standard' story carries story.md + tasks.md" \
          "there is no story.md" "add it"
      fi
      ;;
    full)
      for SCALE_ARTIFACT in story.md design.md; do
        if [[ ! -f "$STORY_DIR/$SCALE_ARTIFACT" ]]; then
          scale_mismatch "a 'full' story carries story.md + design.md + tasks.md" \
            "there is no $SCALE_ARTIFACT" "add it"
        fi
      done
      ;;
  esac
fi

# --- Validate story.md ---
if [[ "$HAS_STORY" == true ]]; then
  STORY_FILE="$STORY_DIR/story.md"

  # Check for SHOULD (should be SHALL)
  SHOULD_COUNT=$(grep -ci '\bSHOULD\b' "$STORY_FILE" 2>/dev/null || true)
  if [[ "$SHOULD_COUNT" -gt 0 ]]; then
    add_error "Found $SHOULD_COUNT uses of SHOULD in story.md — use SHALL instead"
  fi

  # Check for SHALL
  SHALL_COUNT=$(grep -ci '\bSHALL\b' "$STORY_FILE" 2>/dev/null || true)
  if [[ "$SHALL_COUNT" -eq 0 ]]; then
    add_warning "No SHALL found in story.md — requirements may not use EARS notation"
  fi

  # Check hierarchical numbering
  if ! grep -qE '^###\s+R[0-9]+' "$STORY_FILE" 2>/dev/null; then
    add_warning "No hierarchical requirement numbering (R1, R2...) found in story.md"
  fi

  # Bugfix: check Unchanged Behavior section
  if [[ "$IS_BUGFIX" == true ]]; then
    if ! grep -qi 'unchanged behavior' "$STORY_FILE" 2>/dev/null; then
      add_error "Bugfix story.md is missing mandatory 'Unchanged Behavior' section"
    else
      CONTINUE_COUNT=$(grep -ci 'SHALL CONTINUE TO' "$STORY_FILE" 2>/dev/null || true)
      if [[ "$CONTINUE_COUNT" -lt 2 ]]; then
        add_error "Bugfix Unchanged Behavior section needs minimum 2 items (found $CONTINUE_COUNT)"
      fi
    fi
  fi
fi

# --- Validate tasks.md ---
if [[ "$HAS_TASKS" == true ]]; then
  TASKS_FILE="$STORY_DIR/tasks.md"

  # Check task title format (new format: - [ ] N - Name)
  OLD_FORMAT_COUNT=$(grep -cE '^\s*- \[[ x~]\].*\*\*\[T[0-9]\]\*\*' "$TASKS_FILE" 2>/dev/null || true)
  if [[ "$OLD_FORMAT_COUNT" -gt 0 ]]; then
    add_warning "Found $OLD_FORMAT_COUNT tasks using old [T1]/[T2]/[T3] prefix format — use new format: - [ ] N - Name"
  fi

  # --- Checkbox census (R3.1, R3.2, R3.5) ---
  # One line grammar, three box states:
  #   - [ ] open   - [x] closed   - [~] closed WITHOUT doing the work.
  # A `[~]` MUST say why on the same line, with one of the four qualifiers —
  # that check (R3.2) is the whole reason this loop reads qualifiers at all.
  #
  # BOX_CLOSED IS NOT SPLIT into terminal vs deferred, and that half of
  # sub-task 6.5's decision still holds: `closed` below means "not open, and
  # correctly qualified", because no check reads a closed-by-kind breakdown and
  # R5.1 forbids emitting one — a new count key would break every legacy golden,
  # which design.md §3 records as a settled decision. That constraint is on the
  # JSON, not on this script's internals: BOX_DEFERRED below is never emitted.
  #
  # WHAT CHANGED, AND WHY THE COUNTER IS BACK (sub-task 12.3). 6.5 removed the
  # deferred count on the ground that "nothing in THIS script consumes it", and
  # proved the point by measurement: while it existed here, swapping the two
  # branches left the entire suite green — a split no one reads is not a
  # distinction, it is an untested claim. The status-behind-the-checkboxes
  # warning below is that missing consumer. It cannot be written without the
  # count, because rule 1 of references/run-mode.md makes `done` conditional on
  # "no `[ ]` AND no deferred `[~]`" — a deferred box blocks `done` deliberately,
  # so a story resting at `in-progress` with deferred work owed is CORRECT and
  # must not be warned about. Fold deferred into closed and that story warns
  # falsely; the hostile case in tests/validate-story-status.bats reddens on
  # exactly that fold, which is what 6.5's green mutation could not do.
  #
  # BOX_OPEN counts `[ ]`, and only `[ ]`. It has two consumers: the
  # ahead-of-checkboxes warning (R2.3) and, with BOX_DEFERRED, its converse.
  # Counters are plain integers incremented in the loop, never ${#assoc[@]} on
  # a possibly-empty associative array (that trips set -u on bash 5.3 — the
  # same reason REQ_KEYS exists in cross-reference.sh).
  BOX_OPEN=0         # [ ]
  BOX_CLOSED=0       # [x] plus every qualified [~], terminal or deferred alike
  BOX_DEFERRED=0     # the deferred SUBSET of BOX_CLOSED — internal, never emitted
  BOX_UNQUALIFIED=0  # [~] with no recognized qualifier: a grammar error
  LINE_NO=0
  box_re='^[[:space:]]*- \[([ x~])\]'
  # A qualifier is a token in its own right: `(n-a: ...)` qualifies, the tail
  # of a word like `man-a:` does not.
  deferred_re='(^|[^[:alnum:]_-])deferred:'
  terminal_re='(^|[^[:alnum:]_-])(waived|n-a|superseded-by):'
  tilde_forms="'deferred: <reason>', 'waived: <reason>', 'n-a: <reason>', 'superseded-by: NNN'"

  # --- Group-header consistency, gathered in the same pass ---
  # A group header is a CLAIM about its own sub-tasks, so it can be wrong in two
  # ways and both are the same error (see the verdict right after this loop).
  # Ownership is by NUMBER PREFIX, never by indentation or file order: group 1
  # owns 1.1 and 1.2, and does NOT own 10.1. These are sparse indexed arrays
  # keyed by the group number itself — no associative array, per the counter
  # note above. The key is the arithmetic value (`10#` forces base 10, so a
  # stray `08` is neither octal nor a second group 8); the MESSAGE quotes the
  # spelling instead, so grepping the file for the number it names finds the
  # line it names.
  GRP_LINES=()  # [n] = header line numbers, space-joined — one token per header
  GRP_BOX=()    # [n] = FIRST header's box char
  GRP_LABEL=()  # [n] = FIRST header's number as spelled in the file, e.g. `08`
  GRP_SUBS=()   # [n] = how many sub-tasks group n owns
  GRP_OPEN=()   # [n] = how many of those are `[ ]`
  GRP_BAD=()    # [n] = how many are an unqualified [~], i.e. of unreadable state
  # ONE regex for both shapes, because they differ by one optional group and the
  # number that keys them is the same capture: `N - Title` is the header, and
  # `N.M - Title` is a sub-task of that same N. Splitting it in two duplicated
  # the digit guard and the `10#` below, and a guard kept in two places is a
  # guard that eventually gets applied in one. (`1.2.3` matches neither, which
  # is exactly what it did before: three-level numbering is out of scope here.)
  task_num_re='^[[:space:]]*- \[([ x~])\][[:space:]]+([0-9]+)(\.[0-9]+)?[[:space:]]+-[[:space:]]'
  # A digit run longer than this is not a task number. Past 2^63 it wraps to a
  # NEGATIVE array subscript, which bash treats as fatal — under set -euo
  # pipefail the script died before reaching the emitter and printed NO JSON AT
  # ALL, to consumers that all parse that JSON. Guard the digits before they
  # ever become a subscript; `10#` still handles everything that gets through.
  GRP_MAX_DIGITS=9

  # Quality Gates share the checkbox grammar by design (references/tasks.md), so
  # `- [ ] 3 - Coverage >= 80%` is a legal gate AND is shaped exactly like a
  # group header. Reading the whole document let such a line overwrite a real
  # header's state: it silenced true violations and invented false ones.
  #
  # The exclusion is deliberately NOT section arithmetic. Scoping the gathering
  # to `## Task List` and ending it at the next heading meant deciding where a
  # markdown section ENDS, which is genuinely hard and fails silently in every
  # direction: a decorated or differently-cased heading fell back to the whole
  # document, a `###` Quality Gates never terminated anything, and a column-0
  # `#` inside a fenced block truncated the rest of the file — hiding the exact
  # violation this rule exists to catch. So group state is gathered EVERYWHERE
  # except two places, each decided by ONE line in isolation:
  #
  #   1. from the first `Quality Gates` HEADING onward, to end of file. One way,
  #      no re-entry, no end to locate. Level-agnostic and case-insensitive so
  #      it agrees with the validator's own `grep -qi 'Quality Gates'` presence
  #      check below instead of disagreeing with it.
  #   2. inside a fenced code block. An illustrative task list in a fence is
  #      documentation, not a claim — and a `#` in a fence is not a heading.
  #
  # Nothing depends on how `## Task List` is spelled, because that dependence
  # WAS the defect. NOTE the census above is deliberately NOT excluded from
  # either: it counts every box in the document, exactly as it always has.
  # Matched against the LOWERCASED line, so the case-insensitivity is exact
  # rather than a hand-written [Qq] approximation — the presence check below is
  # `grep -qi`, and the two must not disagree about where the gates section is.
  gates_re='^#{1,6}.*quality gates'
  # Column-0 fence, 3+ chars, either flavour. An unclosed fence therefore runs
  # to end of file, which is what CommonMark says it means, not an oversight.
  fence_re='^(```|~~~)'
  in_gates=false
  in_fence=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    LINE_NO=$((LINE_NO + 1))
    # The two exclusions have to see EVERY line, so they precede the box filter:
    # a fence and a heading are not checkboxes. A fence line is itself never
    # content, and a `## Quality Gates` INSIDE a fence is documentation — so the
    # fence is tested first and wins.
    if [[ "$line" =~ $fence_re ]]; then
      if [[ "$in_fence" == true ]]; then in_fence=false; else in_fence=true; fi
    elif [[ "$in_fence" == false && "$in_gates" == false && "${line,,}" =~ $gates_re ]]; then
      in_gates=true
    fi
    [[ "$line" =~ $box_re ]] || continue
    box_char="${BASH_REMATCH[1]}"
    box_unknown=false   # an unqualified [~]: a box whose state cannot be read
    case "$box_char" in
      ' ') BOX_OPEN=$((BOX_OPEN + 1)) ;;
      'x') BOX_CLOSED=$((BOX_CLOSED + 1)) ;;
      '~')
        if [[ "$line" =~ $deferred_re || "$line" =~ $terminal_re ]]; then
          BOX_CLOSED=$((BOX_CLOSED + 1))
          # `deferred:` WINS over a terminal qualifier on the same line, which is
          # the same precedence references/supersede-mode.md gives it: a line
          # carrying both stays owed. Tested as its own case — a `[~] (deferred:
          # …) (superseded-by: NNN)` line is deferred, not terminal.
          # Written as a plain `if`, not `[[ … ]] && …`: a trailing AND-list that
          # fails hands its non-zero status up to the enclosing `case`, and this
          # script runs under `set -e`.
          if [[ "$line" =~ $deferred_re ]]; then
            BOX_DEFERRED=$((BOX_DEFERRED + 1))
          fi
        else
          BOX_UNQUALIFIED=$((BOX_UNQUALIFIED + 1))
          box_unknown=true
          add_error "tasks.md line $LINE_NO: [~] checkbox has no qualifier — a box closed without doing the work must say why on the same line, one of: $tilde_forms"
        fi
        ;;
    esac
    # Everything from here is group state, and the two exclusions apply to it
    # alone — the census above has already counted this box.
    [[ "$in_gates" == false && "$in_fence" == false ]] || continue
    if [[ "$line" =~ $task_num_re ]] && (( ${#BASH_REMATCH[2]} <= GRP_MAX_DIGITS )); then
      grp_n=$((10#${BASH_REMATCH[2]}))       # the key: `08` and `8` are one group
      grp_spelling="${BASH_REMATCH[2]}"      # what the author actually wrote
      if [[ -n "${BASH_REMATCH[3]:-}" ]]; then
        # `N.M` — a sub-task, owned by the number BEFORE the dot, which is why
        # group 1 owns 1.1 and never owns 10.1.
        GRP_SUBS[grp_n]=$(( ${GRP_SUBS[grp_n]:-0} + 1 ))
        # Readability first: a box the census has just rejected cannot be
        # classified open or closed at all, and it makes its group's verdict not
        # computable. Only then does `[ ]` mean open — and nothing else does,
        # since references/tasks.md makes it the only state that counts as
        # pending.
        if [[ "$box_unknown" == true ]]; then
          GRP_BAD[grp_n]=$(( ${GRP_BAD[grp_n]:-0} + 1 ))
        elif [[ "$box_char" == ' ' ]]; then
          GRP_OPEN[grp_n]=$(( ${GRP_OPEN[grp_n]:-0} + 1 ))
        fi
      else
        # `N` — the group's own header. The FIRST one wins the box, the spelling
        # and the reported line, so a later one can no longer overwrite a
        # violation into silence. Every header still contributes its line
        # number: more than one token IS the duplicate, and the tokens are the
        # lines the author has to go and look at.
        if [[ -z "${GRP_LINES[grp_n]:-}" ]]; then
          GRP_BOX[grp_n]="$box_char"
          GRP_LABEL[grp_n]="$grp_spelling"
          GRP_LINES[grp_n]="$LINE_NO"
        else
          GRP_LINES[grp_n]+=" $LINE_NO"
        fi
      fi
    fi
  done < "$TASKS_FILE" 2>/dev/null || true

  # The verdict needs every child of a group, so it can only be reached once the
  # loop has ended. The rule is an IDENTITY and is therefore enforced in BOTH
  # directions — half of an identity is not the identity.
  #   - a `[ ]` header with no open sub-task claims work still owed that none of
  #     its own sub-tasks still owes;
  #   - a `[x]` header over ANY open sub-task claims work done that is still
  #     owed (the shape group 8 of story 006 shipped).
  # Two states are named, and there are THREE: a `[~]` header is closed without
  # doing the work, which the grammar allows, and NEITHER direction may touch
  # it — hence a `case` with no `~` branch rather than an if/else over `[x]`.
  # Two shapes make the verdict NOT COMPUTABLE and are skipped rather than
  # guessed, because not-computable must never dress up as a finding
  # (references/validate-mode.md): a duplicated group number, and a child whose
  # own box the census has already rejected.
  # GRP_BOX and GRP_LABEL are written in the same branch that first writes
  # GRP_LINES, so every key iterated here carries all three. The ${#} guard
  # keeps the expansion legal under set -u, matching the STATUS_VALUES guard
  # below.
  if [[ ${#GRP_LINES[@]} -gt 0 ]]; then
    for grp_n in "${!GRP_LINES[@]}"; do
      grp_label=${GRP_LABEL[grp_n]}
      grp_lines=${GRP_LINES[grp_n]}
      grp_first=${grp_lines%% *}
      # One number, one group. Two headers claiming it is an identity violation
      # in its own right, and it is the mechanism by which a real violation used
      # to be overwritten into silence — so it is reported, and the consistency
      # verdict for that number is not attempted.
      if [[ "$grp_lines" == *' '* ]]; then
        add_error "tasks.md line $grp_first: group $grp_label has more than one header (lines ${grp_lines// /, }) — a group number names one group, and its state cannot be read while two headers claim it"
        continue
      fi
      # Read both tallies once: a group the loop never saw a sub-task for has
      # no entry at all, and nothing to be consistent with either.
      grp_subs=${GRP_SUBS[grp_n]:-0}
      grp_open=${GRP_OPEN[grp_n]:-0}
      (( grp_subs > 0 )) || continue
      # A child whose box is invalid has no readable state, so neither does its
      # group. An error here would accuse a header that may well be right, and
      # the accusation would evaporate the moment the author fixed the real
      # error the honest way, by writing `- [ ] N.M`.
      (( ${GRP_BAD[grp_n]:-0} == 0 )) || continue
      case "${GRP_BOX[grp_n]}" in
        ' ')
          if (( grp_open == 0 )); then
            # State the condition that was TESTED. The clause this replaces
            # inferred the work was "already done", which is exactly backwards
            # for a deferred child: `[~] deferred:` is nothing pending AND the
            # work not done. The predicate was right; the justification was not.
            add_error "tasks.md line $grp_first: group $grp_label is open ([ ]) but no sub-task is still open ([ ]) — a group header must not claim work that none of its sub-tasks still owes; close it with [x], or with [~] and a qualifier if the work was not done"
          fi
          ;;
        'x')
          if (( grp_open > 0 )); then
            # The count is 1 far more often than not, so the subject and its
            # verb are built together rather than hard-coded plural.
            if (( grp_open == 1 )); then
              grp_subject="1 of its sub-tasks is"
            else
              grp_subject="$grp_open of its sub-tasks are"
            fi
            add_error "tasks.md line $grp_first: group $grp_label is closed ([x]) but $grp_subject still open ([ ]) — a group header must not claim work that is still owed"
          fi
          ;;
      esac
    done
  fi

  # Count all tasks (parent + sub-tasks) = every box whatever its state;
  # needed by checks inside and outside the HAS_STORY branch below — define
  # once here so set -u doesn't trip Fast mode validation (tasks.md without
  # story.md).
  TASK_COUNT=$(( ${BOX_OPEN:-0} + ${BOX_CLOSED:-0} + ${BOX_UNQUALIFIED:-0} ))

  # A tasks.md with ZERO parseable checkbox tasks must never pass: every
  # downstream check is gated on TASK_COUNT > 0, so an unrecognized dialect
  # used to sail through with "pass, 0 errors". Name the variant when we can.
  if [[ "$TASK_COUNT" -eq 0 ]]; then
    VARIANT_HINT=""
    if grep -qE '^\s*-?\s*\*\*Covers:\*\*|^Covers:' "$TASKS_FILE" 2>/dev/null; then
      VARIANT_HINT=" (detected 'Covers:' dialect)"
    elif grep -qE '^#{2,3}\s+T?[0-9]+(\.[0-9]+)?[[:space:]]' "$TASKS_FILE" 2>/dev/null; then
      VARIANT_HINT=" (detected heading-based task dialect)"
    fi
    add_error "tasks.md has no parseable checkbox tasks (- [ ] N - ...)${VARIANT_HINT} — unrecognized format, nothing was validated"
  fi

  # Check Requirements field — only when story.md exists AND the declared scale
  # is not `spike`.
  #
  # THE TWO GATES USED TO DISAGREE, and the author paid for it (story 007,
  # R1.4). This check infers the scale from FILE PRESENCE — a story.md means
  # there is a requirements chain to point at — while the spike R-chain check
  # further down reads the DECLARED scale. A spike carrying a leftover story.md
  # satisfies both, so it was told HERE to add `Requirements:` fields and told
  # THERE that a `Requirements:` field is an error. Obeying either instruction
  # broke the other, and nothing in the output said which one was the bug.
  #
  # What goes away is the ADVICE, not the finding: that story is still
  # malformed, and the R2.3 scale-mismatch warning above still reports it —
  # naming both sides and leaving the author to decide which is wrong (remove
  # story.md, or declare the scale the files actually describe).
  #
  # TWO NON-STRICT GATES DID GET QUIETER, and saying otherwise would be the
  # defect this comment is standing next to. Measured: the shape went from
  # `errors: 1, exit 1` to `errors: 0, warnings: 6, exit 0`, so
  # hook-task-completed.sh (which blocks on exit 1, extracts .error_details[]
  # only, and has no warning branch) now lets it through in silence, and the
  # CI loop references/ci-mode.md documents runs without --strict and now
  # passes it. Under --strict the mismatch warning still fails the run.
  # That trade is deliberate: R2.3 classifies scale-vs-files as a WARNING
  # because which side is wrong is the author's call, and the error that was
  # blocking said something R1.4 makes an error to obey. A gate that blocks on
  # advice you must not follow is not a gate worth keeping.
  #
  # Gated on the DECLARED scale and never on the absence of the field itself: a
  # standard story that simply forgot its `Requirements:` fields is precisely
  # what this check exists to catch, so reading "no fields" as "no chain wanted"
  # would silence its real job. fast, standard, full and an undeclared legacy
  # story (DECLARED_SCALE == "") keep the check unchanged — R2.2's golden in
  # tests/scale-validation.bats pins that last one, and the spike+story.md shape
  # is pinned in tests/spike-validation.bats.
  if [[ "$HAS_STORY" == true && "$DECLARED_SCALE" != "spike" ]]; then
    # Accept both old format (Requirements Coverage) and new format (Requirements:)
    COVERAGE_COUNT_NEW=$(grep -ci '^\s*- Requirements:' "$TASKS_FILE" 2>/dev/null || true)
    COVERAGE_COUNT_OLD=$(grep -ci 'Requirements Coverage' "$TASKS_FILE" 2>/dev/null || true)
    COVERAGE_COUNT=$((COVERAGE_COUNT_NEW + COVERAGE_COUNT_OLD))
    if [[ "$TASK_COUNT" -gt 0 && "$COVERAGE_COUNT" -eq 0 ]]; then
      add_error "tasks.md has $TASK_COUNT tasks but no 'Requirements:' fields"
    fi
  fi

  # Check Quality Gates section
  if ! grep -qi 'Quality Gates' "$TASKS_FILE" 2>/dev/null; then
    add_warning "tasks.md is missing 'Quality Gates' section"
  fi

  # Check for metadata lines (italic format)
  PARENT_TASK_COUNT=$(grep -cE '^\s*- \[[ x~]\]\s+[0-9]+\s+-\s+' "$TASKS_FILE" 2>/dev/null || true)
  METADATA_COUNT=$(grep -cE '^\s*- _Complexity:' "$TASKS_FILE" 2>/dev/null || true)
  if [[ "$PARENT_TASK_COUNT" -gt 0 && "$METADATA_COUNT" -eq 0 ]]; then
    add_warning "No metadata lines found (expected _Complexity: ... | Tests: ... | ..._) on parent tasks"
  fi

  # Check for Commit fields or sub-tasks
  COMMIT_COUNT=$(grep -ci '^\s*- Commit:' "$TASKS_FILE" 2>/dev/null || true)
  COMMIT_SUBTASK_COUNT=$(grep -ciE '^\s*- \[[ x~]\].*[Cc]ommit' "$TASKS_FILE" 2>/dev/null || true)
  TOTAL_COMMITS=$((COMMIT_COUNT + COMMIT_SUBTASK_COUNT))
  if [[ "$PARENT_TASK_COUNT" -gt 0 && "$TOTAL_COMMITS" -eq 0 ]]; then
    add_warning "No Commit fields or Commit sub-tasks found — every task group should have a commit point"
  fi

  # Check for Validation fields
  VALIDATION_COUNT=$(grep -ci '^\s*- Validation:' "$TASKS_FILE" 2>/dev/null || true)
  if [[ "$TASK_COUNT" -gt 0 && "$VALIDATION_COUNT" -eq 0 ]]; then
    add_warning "No 'Validation:' fields found — sub-tasks should have testable validation criteria"
  fi
fi

# --- The spike contract: a Verdict, and no requirements chain (R1.2-R1.4) ---
# A spike is a time-boxed probe whose deliverable is the ANSWER, not shipped
# code (references/tasks.md, Spike Scale Adaptations). Two consequences, and
# this section enforces exactly those two, no more:
#   1. it concludes through a mandatory `## Verdict` section rather than through
#      a lifecycle status, so a missing or unreadable one is an error — a spike
#      without a conclusion is the leak this scale exists to prevent;
#   2. it has no story.md, so every R-number written in it points at nothing —
#      a dangling pointer wearing traceability's clothes.
# What it deliberately does NOT enforce: `Tests` and `Acceptance` are optional
# at spike scale, and `Validation` plus the Quality Gates section are already
# checked for every scale above.
#
# ONE `if` guards the whole thing, which is R2.2 made structural rather than
# merely promised: a story that declares no scale must produce the pre-change
# bytes exactly, and a guard satisfiable only by a DECLARED `spike` cannot leak
# into that path.

# parse_verdict <tasks.md> — the spike's conclusion:
#   ## Verdict
#   - status: open | promote | wont-do
#   - conclusion: <what was learned>
#   - promoted-to: NNN   # required when status: promote
# Only the first value of each key inside the section is read. `promoted-to`
# must start with a digit — that is what "the target is recorded" means, and it
# rejects the unfilled `NNN` placeholder of the template (fail-closed), which is
# precisely what makes the R1.3 error fire on a copy-pasted template.
#
# The GRAMMAR — these four regexes — is shared VERBATIM with the parse_verdict
# of archive-story.sh AND of epic-index.sh, exactly as the checkbox census above
# shares its grammar with epic-index.sh and hook-precompact.sh. THREE full
# consumers now, plus a PARTIAL fourth — monitor-stale.sh's verdict_status,
# which copies the first three regexes verbatim and deliberately omits
# `promoted-to` (staleness keys on the status alone). If 007 ever amends the
# grammar, all four move together. The AGGREGATION is per-consumer and differs
# on purpose: archive-story.sh turns the verdict into a completion verdict (may
# this story be archived?), epic-index.sh RENDERS it for a human,
# monitor-stale.sh turns it into a deadline (has this probe concluded yet?), and
# this script turns it into validation errors.
VERDICT_STATUS=""
VERDICT_PROMOTED_TO=""
parse_verdict() {
  local file="$1" line in_verdict=false
  local heading_re='^#{2,}[[:space:]]'
  local verdict_re='^#{2,}[[:space:]]+[Vv]erdict([[:space:]].*)?$'
  local status_re='^[[:space:]]*(-[[:space:]]+)?status:[[:space:]]*([^[:space:]|]+)'
  local promoted_re='^[[:space:]]*(-[[:space:]]+)?promoted-to:[[:space:]]*([0-9][^[:space:]#]*)'
  VERDICT_STATUS=""
  VERDICT_PROMOTED_TO=""
  [[ -f "$file" ]] || return 0
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ $heading_re ]]; then
        if [[ "$line" =~ $verdict_re ]]; then in_verdict=true; else in_verdict=false; fi
        continue
      fi
      [[ "$in_verdict" == true ]] || continue
      if [[ -z "$VERDICT_STATUS" && "$line" =~ $status_re ]]; then
        VERDICT_STATUS="${BASH_REMATCH[2]}"
      elif [[ -z "$VERDICT_PROMOTED_TO" && "$line" =~ $promoted_re ]]; then
        VERDICT_PROMOTED_TO="${BASH_REMATCH[2]}"
      fi
    done
    :
  } 2>/dev/null < "$file" || return 1
  return 0
}

# The three verdicts, one source of truth for the check and the message, like
# SCALE_ENUM above and STATUS_ENUM below. `promote` (with its target recorded)
# and `wont-do` are terminal and make the spike archivable; `open` is not.
VERDICT_ENUM='open|promote|wont-do'
VERDICT_ENUM_TEXT=${VERDICT_ENUM//|/, }

# no_r_chain <line number> <what was found> — ONE skeleton for both shapes an
# R-chain takes, so the sanctioned wording is spelled once, exactly as
# scale_mismatch above spells its "names BOTH sides" once: R1.4 pins the
# sentence, and a sentence kept in two places is a sentence that eventually gets
# edited in one.
no_r_chain() {
  add_error "tasks.md line $1: found $2 — spikes have no requirements chain — promote to a story for traceability"
}

# HAS_TASKS is part of the guard, not an afterthought: a spike with no tasks.md
# has no Verdict because it has no file, and the missing-tasks.md error above
# already says the only useful thing there is to say. Piling "no Verdict" on top
# would report the same absence twice.
if [[ "$DECLARED_SCALE" == "spike" && "$HAS_TASKS" == true ]]; then
  SPIKE_TASKS="$STORY_DIR/tasks.md"

  # Unreadable and absent land in the same place, as they do for the other two
  # consumers: `|| true` keeps a failed read from aborting the run under set -e,
  # and the empty status below reports it as "no Verdict". Neither is a verdict.
  parse_verdict "$SPIKE_TASKS" || true
  if [[ -z "$VERDICT_STATUS" ]]; then
    add_error "tasks.md has no readable '## Verdict' section with a 'status:' line — a spike concludes through its Verdict, not through a lifecycle status; record one of: $VERDICT_ENUM_TEXT"
  elif ! [[ "$VERDICT_STATUS" =~ ^($VERDICT_ENUM)$ ]]; then
    add_error "tasks.md '## Verdict' status is not a spike verdict: found '$VERDICT_STATUS' — must be one of: $VERDICT_ENUM_TEXT"
  elif [[ "$VERDICT_STATUS" == "promote" && -z "$VERDICT_PROMOTED_TO" ]]; then
    add_error "tasks.md '## Verdict' says 'promote' with no 'promoted-to:' story recorded — name the follow-up story number; the template's unreplaced 'NNN' is not a number and counts as no target"
  fi

  # No requirements chain (R1.4). The scan reads the WHOLE file — frontmatter
  # and fenced blocks included — because that is exactly what the contract
  # promises ("write no R-number anywhere in the file") and because a dangling
  # pointer is no less dangling inside a fence. The Verdict's own prose is in
  # scope for the same reason: `conclusion: pending, see R2.1 upstream` is a
  # reference to a requirement that does not exist here either.
  #
  # ONE error per offending LINE, not per token: the line is what the author
  # edits, and a line carrying both shapes (`- Requirements: R1.1`) is one
  # mistake — so the field wins the description and its token is not re-reported.
  spike_req_re='^[[:space:]]*(-[[:space:]]+)?(\*\*)?[Rr]equirements:'
  # A token in its own right, with an explicit boundary on each side. Same shape
  # the cross-reference check below greps for with `\b`, spelled out because
  # `\b` is a GNU extension and this script also runs on BSD/macOS: `R2D2` is
  # not an R-token, `see R1.` is one.
  spike_r_re='(^|[^[:alnum:]_])(R[0-9]+(\.[0-9]+)?)([^[:alnum:]_]|$)'
  spike_line_no=0
  while IFS= read -r spike_line || [[ -n "$spike_line" ]]; do
    spike_line_no=$((spike_line_no + 1))
    if [[ "$spike_line" =~ $spike_req_re ]]; then
      no_r_chain "$spike_line_no" "a 'Requirements:' field"
    elif [[ "$spike_line" =~ $spike_r_re ]]; then
      no_r_chain "$spike_line_no" "the R-number token '${BASH_REMATCH[2]}'"
    fi
  done < "$SPIKE_TASKS" 2>/dev/null || true
fi

# --- Validate frontmatter (version, status) ---
# `status:` is the story's single lifecycle state, shared by every artifact.
# Grammar rule: fail-CLOSED on a present-but-wrong value (an invented dialect
# is an error), fail-OPEN on absence (340+ legacy stories have no status: and
# must validate exactly as before — no error, no warning, no extra line).
# One source of truth for the enum: the alternation drives both the check and
# the human-readable message (a `case` pattern cannot — bash does not re-parse
# `|` from an expanded variable as alternation, only `[[ =~ ]]` does).
STATUS_ENUM='draft|in-progress|done|validated|superseded|archived'
STATUS_ENUM_TEXT=${STATUS_ENUM//|/, }
# The states that claim the work is finished — the ones a leftover `[ ]` box
# contradicts.
STATUS_COMPLETE='done|validated'
# The states that claim the work is UNFINISHED — the ones an empty box census
# contradicts. `superseded` and `archived` are deliberately in NEITHER set: both
# are terminal, both legitimately sit over a fully-closed census, and neither is
# a state rule 1 would overwrite with `done`.
STATUS_BEHIND='draft|in-progress'
STATUS_FILES=()   # basenames of the artifacts that actually carry the field
STATUS_VALUES=()  # their values, parallel to STATUS_FILES

for f in "$STORY_DIR"/*.md; do
  [[ -f "$f" ]] || continue
  BASENAME=$(basename "$f")
  if head -1 "$f" | grep -q '^---$' 2>/dev/null; then
    # Check required frontmatter fields ($d is POSIX; GNU-only `head -n -1`
    # aborted the whole validation on BSD/macOS under set -e + pipefail)
    FRONT=$(sed -n '2,/^---$/p' "$f" | sed '$d')
    if ! echo "$FRONT" | grep -q 'version:'; then
      add_warning "$BASENAME frontmatter missing 'version' field"
    fi
    if ! echo "$FRONT" | grep -q 'created:'; then
      add_warning "$BASENAME frontmatter missing 'created' field"
    fi
    # Validate version is integer
    VERSION_VAL=$(echo "$FRONT" | grep 'version:' | head -1 | sed 's/.*version:\s*//' | tr -d '[:space:]' || true)
    if [[ -n "$VERSION_VAL" ]] && ! [[ "$VERSION_VAL" =~ ^[0-9]+$ ]]; then
      add_error "$BASENAME frontmatter 'version' must be an integer, found: $VERSION_VAL"
    fi
    # Lifecycle state. Anchored at column 0 like the templates write it, so a
    # compound or nested key (`review_status:`) can never fake a status value.
    STATUS_VAL=$(echo "$FRONT" | grep -E '^status:' | head -1 | sed 's/.*status:\s*//' | tr -d '[:space:]' || true)
    if [[ -n "$STATUS_VAL" ]]; then
      if ! [[ "$STATUS_VAL" =~ ^($STATUS_ENUM)$ ]]; then
        add_error "$BASENAME frontmatter 'status' is not a lifecycle state: found '$STATUS_VAL' — must be one of: $STATUS_ENUM_TEXT"
      fi
      # An artifact without the field carries no opinion, so it is never
      # divergent: only artifacts that declare a status are compared.
      STATUS_FILES+=("$BASENAME")
      STATUS_VALUES+=("$STATUS_VAL")
    fi
  else
    add_warning "$BASENAME is missing version frontmatter"
  fi
done

# --- Story-level status consistency ---
# Entered only when at least one artifact declared a status: a story with no
# status: field skips this block whole, which is the fail-open rule made
# structural (no error, no warning, byte-identical output to pre-change).
if [[ ${#STATUS_VALUES[@]} -gt 0 ]]; then
  # BOX_OPEN comes from the checkbox census, which runs only when tasks.md
  # exists; under set -u a story without tasks.md would abort here without the
  # ${VAR:-0} guard used throughout this script.
  OPEN_BOXES=${BOX_OPEN:-0}

  # The status lies about the work: it claims done while `[ ]` boxes remain.
  # `[~]` boxes are closed by grammar and must NOT count as open here.
  if [[ "$OPEN_BOXES" -gt 0 ]]; then
    for st_i in "${!STATUS_VALUES[@]}"; do
      if [[ "${STATUS_VALUES[$st_i]}" =~ ^($STATUS_COMPLETE)$ ]]; then
        add_warning "status is ahead of the checkboxes: ${STATUS_FILES[$st_i]} says '${STATUS_VALUES[$st_i]}' but $OPEN_BOXES task checkbox(es) are still open ([ ])"
        break  # one story, one lie — do not repeat it per artifact
      fi
    done
  fi

  # The converse: the work is finished and the status has not caught up. Rule 1
  # of references/run-mode.md writes `done` when a marking leaves "no `[ ]` and
  # no deferred `[~]`" — so a story satisfying that condition while still
  # declaring `draft` or `in-progress` is a rule-1 write that never happened.
  #
  # WHY THIS EXISTS AT ALL (sub-task 12.3, finding F2). The condition above was
  # PREVENTED by rule 1 rather than DETECTED by anything, and when the
  # prevention silently failed to fire nothing reported it: story
  # 006-git-aware-lifecycle sat at 64 boxes, all `[x]`, zero `[ ]`, zero
  # deferred, with all three artifacts reading `in-progress` — through a whole
  # validate that passed. The archive offer gated on "rule 1 wrote it in this
  # run" never fires there either, so the story is not merely mislabelled: it
  # falls out of the lifecycle.
  #
  # A WARNING, NOT AN ERROR, and the severity is measured rather than chosen.
  # Swept across all seven stories in .epic/stories/ at the time it shipped, it
  # fires on ZERO of them, so it is not paying for itself with a backlog of
  # violations — but neither is it costing anything, and it is the only thing
  # that can see the state it names. Warning matches its two siblings in this
  # block (ahead-of-checkboxes, divergent-status), and a legitimate transient
  # exists: a validate run between the last checkbox marking and rule 1's status
  # write lands exactly here, and should say so rather than fail.
  #
  # THE DEFERRED ARM IS THE HOSTILE HALF, not a refinement. references/run-mode.md
  # is explicit that a deferred box BLOCKS `done` — a story whose only remaining
  # non-`[x]` boxes are `[~] (deferred: …)` stays `in-progress` on purpose, and
  # its completeness surfaces as the computed condition `done-except-external`,
  # which is never persisted. Warning there would tell the author to write a
  # status the state machine forbids.
  if [[ "$OPEN_BOXES" -eq 0 && "${BOX_DEFERRED:-0}" -eq 0 && "${TASK_COUNT:-0}" -gt 0 ]]; then
    for st_i in "${!STATUS_VALUES[@]}"; do
      if [[ "${STATUS_VALUES[$st_i]}" =~ ^($STATUS_BEHIND)$ ]]; then
        add_warning "status is behind the checkboxes: ${STATUS_FILES[$st_i]} says '${STATUS_VALUES[$st_i]}' but no task checkbox is still open and none is deferred — run-mode rule 1 writes 'done' at that point"
        break  # one story, one lag — do not repeat it per artifact
      fi
    done
  fi

  # One story, one status: artifacts declaring different values disagree about
  # where the story is.
  STATUS_DIVERGED=false
  for st_v in "${STATUS_VALUES[@]}"; do
    [[ "$st_v" == "${STATUS_VALUES[0]}" ]] || STATUS_DIVERGED=true
  done
  if [[ "$STATUS_DIVERGED" == true ]]; then
    STATUS_PAIRS=""
    for st_i in "${!STATUS_FILES[@]}"; do
      STATUS_PAIRS+="${STATUS_PAIRS:+, }${STATUS_FILES[$st_i]}=${STATUS_VALUES[$st_i]}"
    done
    add_warning "Artifacts of this story declare different 'status' values ($STATUS_PAIRS) — every artifact must carry the same lifecycle state"
  fi
fi

# --- Flag parsing ---
CROSS_REF=false
STRICT=false
for arg in "$@"; do
  [[ "$arg" == "--cross-ref" ]] && CROSS_REF=true
  [[ "$arg" == "--strict" ]] && STRICT=true
done

if [[ "$CROSS_REF" == true && "$HAS_STORY" == true && "$HAS_TASKS" == true ]]; then
  # Requirements are hierarchical: a group header `### Rn.` and its leaf
  # criteria `Rn.m`. Tasks reference the leaves. A one-level token Rn is a
  # requirement of its own only when story.md defines no child Rn.m for it;
  # otherwise Rn is a group header, covered via its leaves. Counting a header
  # as a leaf produced a false orphan for every `### Rn.` heading.
  mapfile -t XR_STORY_LEAVES < <(grep -oE '\bR[0-9]+\.[0-9]+\b' "$STORY_DIR/story.md" 2>/dev/null | sort -u || true)
  mapfile -t XR_STORY_ONELEVEL < <(grep -oE '\bR[0-9]+\b' "$STORY_DIR/story.md" 2>/dev/null | sort -u || true)
  mapfile -t XR_TASK_TOKENS < <(grep -oE '\bR[0-9]+(\.[0-9]+)?\b' "$STORY_DIR/tasks.md" 2>/dev/null | sort -u || true)

  XR_STORY_REQS=("${XR_STORY_LEAVES[@]}")
  XR_STORY_GROUPS=()
  for xr_tok in "${XR_STORY_ONELEVEL[@]}"; do
    xr_has_child=false
    for xr_leaf in "${XR_STORY_LEAVES[@]}"; do
      if [[ "$xr_leaf" == "$xr_tok".* ]]; then
        xr_has_child=true
        break
      fi
    done
    if [[ "$xr_has_child" == true ]]; then
      XR_STORY_GROUPS+=("$xr_tok")
    else
      XR_STORY_REQS+=("$xr_tok")
    fi
  done

  if [[ ${#XR_STORY_REQS[@]} -gt 0 && ${#XR_TASK_TOKENS[@]} -gt 0 ]]; then
    # Story leaf requirements with no matching task reference (orphans).
    for xr_req in "${XR_STORY_REQS[@]}"; do
      if ! xr_in_list "$xr_req" "${XR_TASK_TOKENS[@]}"; then
        add_warning "Requirement $xr_req in story.md has no matching reference in tasks.md"
      fi
    done
    # Task references matching no story requirement (phantoms).
    for xr_tok in "${XR_TASK_TOKENS[@]}"; do
      if ! xr_in_list "$xr_tok" "${XR_STORY_REQS[@]}" && ! xr_in_list "$xr_tok" "${XR_STORY_GROUPS[@]}"; then
        add_warning "Requirement $xr_tok referenced in tasks.md does not exist in story.md"
      fi
    done
  elif [[ ${#XR_STORY_REQS[@]} -gt 0 && ${#XR_TASK_TOKENS[@]} -eq 0 ]]; then
    add_warning "story.md has requirements but tasks.md has no R-number references"
  fi
fi

# --- Output ---
TOTAL_ERRORS=${#ERRORS[@]}
TOTAL_WARNINGS=${#WARNINGS[@]}

echo "{"
echo "  \"story\": \"$(json_escape "$STORY_DIR")\","
echo "  \"errors\": $TOTAL_ERRORS,"
echo "  \"warnings\": $TOTAL_WARNINGS,"

if [[ $TOTAL_ERRORS -gt 0 ]]; then
  echo "  \"error_details\": ["
  for i in "${!ERRORS[@]}"; do
    COMMA=","
    [[ $i -eq $((TOTAL_ERRORS - 1)) ]] && COMMA=""
    echo "    \"$(json_escape "${ERRORS[$i]}")\"$COMMA"
  done
  echo "  ],"
else
  echo "  \"error_details\": [],"
fi

if [[ $TOTAL_WARNINGS -gt 0 ]]; then
  echo "  \"warning_details\": ["
  for i in "${!WARNINGS[@]}"; do
    COMMA=","
    [[ $i -eq $((TOTAL_WARNINGS - 1)) ]] && COMMA=""
    echo "    \"$(json_escape "${WARNINGS[$i]}")\"$COMMA"
  done
  echo "  ],"
else
  echo "  \"warning_details\": [],"
fi

# In --strict mode, warnings count as failures for the status and exit code.
if [[ "$STRICT" == true && $TOTAL_WARNINGS -gt 0 ]]; then
  STATUS_STR="fail"
elif [[ $TOTAL_ERRORS -gt 0 ]]; then
  STATUS_STR="fail"
else
  STATUS_STR="pass"
fi

echo "  \"strict\": $STRICT,"
echo "  \"status\": \"$STATUS_STR\""
echo "}"

if [[ $TOTAL_ERRORS -gt 0 ]]; then
  exit 1
elif [[ "$STRICT" == true && $TOTAL_WARNINGS -gt 0 ]]; then
  exit 1
else
  exit 0
fi
