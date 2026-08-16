#!/usr/bin/env bash
# Closes exactly ONE checkbox in a live story's tasks.md — the one sanctioned
# writer for the checkbox grammar (design.md, component 1; story 010).
#
# Usage: bash scripts/close-subtask.sh <NNN|story-dir> <N.N|N|gate:<text-prefix>>
#                                      [--tilde "<qualifier>: <reason>"]
#
# Exit 0 = the box was closed
# Exit 1 = refused — NOTHING was written, not even a temp file
# Exit 2 = invalid input (missing or malformed arguments, unknown flag)
#
# Output: ONE JSON object on stdout on every path that reaches a verdict, so a
# consumer can pipe stdout straight into jq; every human-readable diagnostic
# goes to stderr. Usage errors (exit 2) print no JSON at all — no story has been
# resolved, so there is nothing to report on yet (the convention
# validate-story.sh, archive-story.sh and supersede-story.sh already share).
#
# TWO DELIBERATE DIVERGENCES FROM THE SIBLING SCRIPTS. Both are contract, pinned
# by tests/close-subtask.bats, and neither is an oversight to be "restored":
#
#   1. `--help` PRINTS ON STDERR AND EXITS 2. archive-story.sh and
#      supersede-story.sh print help on stdout and exit 0, as a documented
#      exception to "JSON on stdout". This script has no such exception: its
#      caller is the orchestrator, whose stdout handling is `jq`, and stdout is
#      JSON or nothing on EVERY path. `--help` reaches no verdict, so it joins
#      the other no-verdict, stderr-only path — usage.
#
#   2. AN UNRESOLVABLE STORY IS A REFUSAL (exit 1), NOT A USAGE ERROR (exit 2).
#      The siblings classify that as bad input. Here exit 2 means exactly one
#      thing — the COMMAND LINE is malformed — and every statement about the
#      state of the disk (no such story, the story is archived, no tasks.md) is
#      a refusal that names its reason and writes nothing (R1.3, R1.4). One
#      rule, so a caller can act on the code alone: 2 = fix the call, 1 = fix
#      the world. It also keeps R1.4's arm reportable: a refusal emits the JSON
#      object carrying `reason`, a usage error emits nothing.
#
# STEP ORDER IS LOAD-BEARING (design.md, component 1). Every refusal arm has its
# say BEFORE anything is written, and every write is a whole-file rewrite
# renamed into place — so no reader can ever catch one of them half-done:
#   1. parse, resolve, refusal arms ..... sub-task 1.1 (implemented)
#   2. locate and mark the box .......... sub-task 1.2 (implemented — R1.1/R1.2/R1.3/R1.6/R1.7)
#   3. census + status transition ....... sub-task 2.1 (implemented — R2.1/R2.2)
#   4. self-invoked validate-story.sh ... sub-task 2.2 (implemented — R1.5/R2.3/R2.4)
#
# THE MARKING IS ONE REWRITE, THE STATUS STAMP IS ANOTHER PER ARTIFACT, and that
# is the strongest shape available rather than a compromise. The box and the
# group header it settles are ONE rewrite of tasks.md, so R1.7's pair is never
# left half-written; the census then MEASURES the file that landed instead of
# projecting what the write was supposed to do; the stamp then rewrites each
# artifact that carries frontmatter on its own, because no shell can rename
# three files at once — a reader can always catch a story between two of them.
# That transient is the one validate-story.sh:992-999 names as legitimate: "a
# validate run between the last checkbox marking and rule 1's status write lands
# exactly here, and should say so rather than fail". And it is not this script's
# own reader — step 4's self-validation runs after every one of these writes.
#
# NO SHARED LIBRARY, BY CONVENTION. `scripts/` has none — every script here is
# invoked standalone by path — so the house patterns below (the JSON escaper,
# the single `emit_report`, `find_epic_dir` / `resolve_by_number`) are COPIED
# from archive-story.sh and supersede-story.sh rather than sourced. The shared
# checkbox grammar is copied the same way and its consumers move together; who
# they are and why no count is written down is settled in the block above
# BOX_RE. The difference that is this script's whole point: they READ that
# grammar, and this one WRITES it.

set -euo pipefail

USAGE='Usage: close-subtask.sh <NNN|story-dir> <N.N|N|gate:<text-prefix>> [--tilde "<qualifier>: <reason>"]'

print_help() {
  cat <<'HELP'
Usage: close-subtask.sh <NNN|story-dir> <N.N|N|gate:<text-prefix>>
                        [--tilde "<qualifier>: <reason>"]

Closes exactly one checkbox in a live story's tasks.md, runs the status census,
stamps the story's `status:` and reports the whole transaction as one JSON
object. One box per invocation.

Arguments:
  <NNN|story-dir>   Story number (010) or its directory (.epic/stories/010-slug)
  <N.N|N|gate:...>  Which box: a sub-task (1.2), a task group (1), or a Quality
                    Gate named by a prefix of its text (gate:All task validations)

Flags:
  --tilde "<qualifier>: <reason>"
                    Close the box as `[~] (qualifier: reason)` — closed WITHOUT
                    the work being done. The qualifier is one of the four the
                    shared checkbox grammar defines (references/tasks.md):
                    deferred: / waived: / n-a: / superseded-by: NNN
  --help, -h        Show this help (on stderr, exit 2 — stdout is JSON only)

Output: JSON on stdout — {story, task, box, qualifier, census{total, open,
closed, deferred}, status_written{from, to}|null, validate{errors, warnings,
status}, reason}. Diagnostics on stderr.

Exit codes:
  0  The box was closed
  1  Refused — nothing was written
  2  Invalid input (missing or malformed arguments, unknown flag)
HELP
}

# --- Report state -----------------------------------------------------------
# Every field of the JSON contract lives in a variable so that ONE emitter
# renders every exit path: a caller can jq the same shape whatever happened.
STORY_ID=""            # canonical story identity, e.g. 012-widget
STORY_PATH=""          # path as resolved (kept relative when given relative)
STORY_ABS=""           # its PHYSICAL path — what the archive check is made on
TASKS_FILE=""          # $STORY_PATH/tasks.md, the one artifact this script writes
TASK_ID=""             # the box as the caller named it: 1.2, 1, or gate:<prefix>
BOX=""                 # "x" | "~" — what was WRITTEN; "" renders as JSON null
QUALIFIER=""           # the bare token (deferred|waived|n-a|superseded-by)
REASON=""              # human-readable why, for refusals

# --tilde's argument, verbatim. The reason TEXT stays here and is written into
# the file by sub-task 1.2 — it is deliberately NOT part of the JSON: the
# contract reports the qualifier token, and the reason lives in tasks.md
# (design.md, component 1).
TILDE_GIVEN=false
TILDE_RAW=""

# Checkbox census (sub-task 2.1). Initialized here because the emitter reads
# them even on the paths where tasks.md was never opened — same reason
# archive-story.sh initializes its own counters at declaration.
BOX_TOTAL=0
BOX_OPEN=0
BOX_CLOSED=0
BOX_DEFERRED=0

# Rendered JSON sub-objects, `null` until the step that fills them runs. `null`
# is the honest initial value and it means exactly that: nobody measured. A
# refusal wrote no box, so no status could transition and there was nothing new
# to validate — reporting `{"from": "", "to": ""}` or `{"errors": 0}` there
# would be a measurement nobody took, rendered as one that came back empty.
STATUS_WRITTEN_JSON="null"   # {from, to} once step 3 writes a transition
VALIDATE_JSON="null"         # {errors, warnings, status} once step 4 has a verdict

# --- String quoting ---------------------------------------------------------
# EVERY string this script emits as JSON goes through json_escape. The inputs
# are arbitrary by construction: a story directory name and a `--tilde` reason
# are typed (or pasted, control codes and all) by a human, and the reason text
# reaches the report's `reason` field on refusals.
#
# The escape set is JSON's (RFC 8259 §7): U+0000-U+001F, plus the quote and the
# backslash. It is deliberately NARROWER than archive-story.sh's, whose table is
# the UNION of JSON's and YAML's because that script also writes manifest.yaml —
# DEL and the C1 block are illegal in YAML and perfectly legal inside a JSON
# string. This script writes no YAML, so escaping them would be re-encoding
# rather than quoting. NUL needs no entry: a bash string cannot hold one.
JSON_ESC_RAW=()   # needle: the literal byte to replace
JSON_ESC_REP=()   # replacement: its \uXXXX form
# The `printf -v needle "$needle"` pair below is a TWO-STAGE printf and the
# variable-as-format is the point of it: stage 1 builds the literal text `\x1b`,
# stage 2 makes printf interpret that escape into the byte itself. Writing the
# byte directly is not an option — it is what we are trying to produce.
# shellcheck disable=SC2059
_json_escape_table() {
  local i needle rep
  # C0 minus the five with a short escape (\b \t \n \f \r = 8 9 10 12 13).
  for i in 1 2 3 4 5 6 7 11 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31; do
    printf -v needle '\\x%02x' "$i"
    printf -v needle "$needle"
    printf -v rep '\\u%04x' "$i"
    JSON_ESC_RAW+=("$needle")
    JSON_ESC_REP+=("$rep")
  done
}
_json_escape_table
unset -f _json_escape_table

json_escape() {
  local s="$1" i
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\b'/\\b}
  s=${s//$'\f'/\\f}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  for i in "${!JSON_ESC_RAW[@]}"; do
    s=${s//"${JSON_ESC_RAW[i]}"/"${JSON_ESC_REP[i]}"}
  done
  printf '%s' "$s"
}

# json_or_null <string> — a quoted JSON string, or the literal `null` when the
# value is empty. Two fields of the contract are nullable and both mean "this
# did not happen", not "this happened and was blank": `qualifier` is null on a
# plain `[x]` close (design.md says so), and `box` is null on every refusal,
# because a refusal wrote no box at all.
json_or_null() {
  if [[ -z "$1" ]]; then
    printf 'null'
    return 0
  fi
  printf '"%s"' "$(json_escape "$1")"
}

# emit_report — THE emitter. Every verdict path renders this one shape, so a
# consumer parses the same object whatever happened; `reason` carries the why on
# a refusal and is empty on a success.
emit_report() {
  cat <<JSON
{
  "story": "$(json_escape "$STORY_ID")",
  "task": "$(json_escape "$TASK_ID")",
  "box": $(json_or_null "$BOX"),
  "qualifier": $(json_or_null "$QUALIFIER"),
  "census": { "total": $BOX_TOTAL, "open": $BOX_OPEN, "closed": $BOX_CLOSED, "deferred": $BOX_DEFERRED },
  "status_written": $STATUS_WRITTEN_JSON,
  "validate": $VALIDATE_JSON,
  "reason": "$(json_escape "$REASON")"
}
JSON
}

# --- Terminators ------------------------------------------------------------
# usage_error: the command line is malformed. No JSON — nothing has been
# resolved to report on. This and --help are the only paths that print no JSON.
usage_error() {
  printf 'Error: %s\n' "$1" >&2
  printf '%s\n' "$USAGE" >&2
  exit 2
}

# refuse: the world is not in a state this script may write to. WHAT IS LEFT ON
# DISK IS STATED BY EACH CALL SITE, never promised here: every arm implemented
# today is raised before step 2 and says "nothing was modified" in its own
# message, and step 2's write goes through a temp file renamed into place, so
# even a failure there leaves tasks.md byte-identical (R1.4, R1.6). The claim
# lives with the arms because a blanket "nothing, by construction" in this
# comment is exactly the sentence that goes stale the first time a refusal is
# added downstream of a write — supersede-story.sh:226-242 records that lesson.
# The reason is said twice on purpose: once on stderr for the human, once in the
# report's `reason` for the caller that parses stdout.
#
# BOX AND QUALIFIER ARE CLEARED HERE, on purpose. Both fields report what was
# WRITTEN — `box` is the mark that landed, `qualifier` the token that landed
# beside it — and a refusal wrote neither. Clearing them renders both as `null`
# and keeps `qualifier` inside its enum on the one arm that would otherwise
# break it: the refusal for a qualifier OUTSIDE the four-form grammar, whose
# offending token would otherwise be reported as if it were one of the four.
# The token is not lost, it moves to where a rejected value belongs — the
# `reason` string. Every arm that exists today refuses BEFORE the write; an arm
# added after one would have to revisit this.
refuse() {
  REASON="$1"
  BOX=""
  QUALIFIER=""
  printf 'Refused: %s\n' "$REASON" >&2
  emit_report
  exit 1
}

# --- Helpers ----------------------------------------------------------------
# trim <string> — strip leading and trailing whitespace, no fork.
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# find_epic_dir — walk up from the CWD looking for .epic/, so a bare NNN works
# from any subdirectory of the project. The CWD is the anchor, never this
# script's own location: the plugin's scripts/ lives outside the project being
# worked on (and, under a plugin install, outside its checkout entirely).
find_epic_dir() {
  local dir
  dir=$(pwd -P)
  while :; do
    if [[ -d "$dir/.epic" ]]; then
      printf '%s' "$dir/.epic"
      return 0
    fi
    [[ "$dir" == "/" ]] && return 1
    dir=$(dirname "$dir")
  done
}

# resolve_by_number <NNN> <epic-dir> — <NNN>-<slug> under stories/ first, then
# archive/. Resolving the archived copy is deliberate: an archived number must
# RESOLVE so R1.4 can refuse it by its real reason ("read-only") instead of the
# misleading "not found". Accepts 12 for 012.
resolve_by_number() {
  local num="$1" epic="$2" padded root cand
  padded=$(printf '%03d' "$((10#$num))")
  for root in "$epic/stories" "$epic/archive"; do
    for cand in "$root/$num"-* "$root/$padded"-* "$root/$num" "$root/$padded"; do
      if [[ -d "$cand" ]]; then
        printf '%s' "$cand"
        return 0
      fi
    done
  done
  return 1
}

# --- The shared checkbox grammar — READ HERE, AND WRITTEN BACK ---------------
# COPIED VERBATIM, not sourced (scripts/ has no shared library): BOX_RE from
# archive-story.sh:435 and validate-story.sh:447; TASK_NUM_RE, GATES_RE,
# FENCE_RE and GRP_MAX_DIGITS from validate-story.sh:476, 511, 514, 482;
# TILDE_TOKEN_RE from validate-story.sh:450-451. A variant invented here is a
# grammar fork nobody sees until a box the other consumers count is a box this
# one cannot find — or, worse, one it marks.
#
# HOW MANY CONSUMERS THERE ARE IS DELIBERATELY NOT WRITTEN DOWN. Three
# successive prose enumerations of that list have been wrong, which
# tests/checkbox-grammar.bats:11-15 records: a prose count cannot fail, so it is
# never corrected. The roster that CAN fail is that harness — it drives one
# mixed fixture through every consumer and reddens when one drifts. Any script
# carrying these regexes belongs in it, this one included.
#
# AND THIS ONE IS A WRITER, which raises the bar. A reader that drifts
# mis-counts a file someone else wrote; a writer that drifts produces the file
# every reader then mis-counts. So the agreement is pinned in BOTH directions:
# what this script treats as a task number (TASK_NUM_RE with GRP_MAX_DIGITS) and
# what it treats as a qualifier (TILDE_TOKEN_RE) are what the readers treat as
# one — never a superset, and never a subset either.
BOX_RE='^[[:space:]]*- \[([ x~])\]'
TASK_NUM_RE='^[[:space:]]*- \[([ x~])\][[:space:]]+([0-9]+)(\.[0-9]+)?[[:space:]]+-[[:space:]]'
GATES_RE='^#{1,6}.*quality gates'
FENCE_RE='^(```|~~~)'
# A digit run longer than this is not a GROUP number (validate-story.sh:477-482)
# — and the bound applies to the group number and to NOTHING else, because that
# is the only place the reader applies it. Its own reason for the bound does not
# hold here (nothing in this script turns a number into an array subscript, so
# nothing can wrap to a fatal negative subscript); agreeing with the reader
# about what IS a task number is the reason it is kept. See the sub-task branch
# in locate_box for what applying it one place further cost.
GRP_MAX_DIGITS=9

# The text of a checkbox line — everything after the `]`. Used only by the
# `gate:` target, which names a box by what it SAYS rather than by a number.
GATE_TEXT_RE='^[[:space:]]*- \[[ x~]\][[:space:]]*(.*)$'

# BOX_RE again, split so the box character can be replaced without touching a
# byte on either side of it. The match set is identical BY CONSTRUCTION — same
# anchor, same literals, same character class, and `(\].*)$` cannot fail once
# the `\]` has matched; the parentheses only carve up what BOX_RE already
# matched, and parentheses do not select lines.
BOX_SPLIT_RE='^([[:space:]]*- \[)([ x~])(\].*)$'

# The four qualifier forms, and ONLY these four (references/tasks.md, Checkbox
# Grammar). The token list is the one validate-story.sh:450-451 rejects a `[~]`
# for lacking; applying it here, one step earlier, means a box that would fail
# validation can never be written in the first place. The trailing `(.*)` is the
# reason text — captured, never interpreted.
TILDE_FORM_RE='^[[:space:]]*(deferred|waived|n-a|superseded-by):[[:space:]]*(.*)$'
TILDE_FORMS="'deferred: <reason>', 'waived: <reason>', 'n-a: <reason>', 'superseded-by: NNN'"

# THE SAME FOUR TOKENS AS THE READERS FIND THEM — validate-story.sh:450-451
# verbatim, its `deferred_re` and `terminal_re` folded into one alternation
# because this script needs only "is a token here", not which bucket it falls
# in. The leading `(^|[^[:alnum:]_-])` is theirs and is what makes a qualifier a
# token in its own right: `(n-a: …)` qualifies, the tail of a word like `man-a:`
# does not.
#
# WHY A WRITER NEEDS THE READERS' RULE AND NOT ITS OWN. TILDE_FORM_RE above
# reads the qualifier as the LEADING token of --tilde's argument, and that token
# is what `.qualifier` reports. No reader reads it that way: they scan the WHOLE
# LINE, and `deferred:` outranks a terminal token wherever either one sits
# (validate-story.sh:536-547). So a reason carrying a second token —
# `--tilde "waived: blocked, deferred: until the vendor ships"` — writes a line
# every reader buckets as deferred while this script's own JSON says waived, and
# tasks.md and the report then disagree about the same box. Refused below.
#
# MATCHED AGAINST THE REASON HALF ALONE, which is exactly equivalent to matching
# the line this script would write: the reason lands after `($QUALIFIER: `, so
# the byte in front of it is a space, and a space satisfies the readers'
# `[^[:alnum:]_-]` just as `^` does here. Equivalent, therefore neither wider
# than the readers' grammar (which would refuse reasons they accept) nor
# narrower (which would let the disagreement through).
TILDE_TOKEN_RE='(^|[^[:alnum:]_-])(deferred|waived|n-a|superseded-by):'

# THE SAME FOUR TOKENS, SPLIT INTO THE TWO BUCKETS THE CENSUS NEEDS —
# validate-story.sh:450-451 verbatim again, this time unfolded, because step 3
# asks the question TILDE_TOKEN_RE above deliberately does not: not "is a token
# here" but WHICH ONE, since `deferred:` is the token that blocks `done` and the
# three terminal ones are the tokens that close a box (references/tasks.md,
# Completion). The union above is NOT rebuilt from these two by concatenation:
# its consumer reads BASH_REMATCH[2] for the offending token, and an alternation
# of two prefixed groups renumbers exactly that capture.
TILDE_DEFERRED_RE='(^|[^[:alnum:]_-])deferred:'
TILDE_TERMINAL_RE='(^|[^[:alnum:]_-])(waived|n-a|superseded-by):'

# The frontmatter delimiter, CRLF-tolerant — archive-story.sh:307 and
# supersede-story.sh:284, the same constant for the same reason: with
# core.autocrlf=true every artifact ends `---\r`, and a reader that rejects that
# does not fail loudly, it decides the file has no frontmatter. Here that would
# mean "no status line to stamp" and would leave the story's artifacts
# disagreeing about the lifecycle state — the exact divergence R2.1 exists to
# prevent.
FM_DELIM_RE=$'^---\r?$'

# canon_num <digits> — the number with its leading zeros stripped, into CANON.
# `08` and `8` are ONE group, exactly as validate-story.sh:459 treats them.
# Sets a global rather than printing one: this runs once per numbered checkbox
# line, and a `$(…)` there is a fork per line. String-only, never arithmetic —
# `$((10#$n))` on a 20-digit run is a fatal "value too great for base", and
# these digits come out of a file nobody validated.
CANON=""
canon_num() {
  CANON="$1"
  while [[ "$CANON" == 0* && ${#CANON} -gt 1 ]]; do
    CANON="${CANON#0}"
  done
}

# same_line <text> — text that cannot break out of its own line. R1.2 puts the
# qualifier ON THE SAME LINE as the box, so a CR or an LF inside a reason is not
# content to preserve: it would split the box line in two and leave the tail
# behind as a stray markdown line that no reader of the grammar can parse.
# Flattened to spaces, the way supersede-story.sh's md_cell flattens them for a
# table cell.
same_line() {
  local s="$1"
  s=${s//$'\r'/ }
  s=${s//$'\n'/ }
  printf '%s' "$s"
}

# --- Argument parsing -------------------------------------------------------
# Unknown flag => exit 2, before anything is read or resolved.
TARGET=""
POSITIONAL=0

# take_positional <arg> — fills the two positional slots in order. A counter,
# not `[[ -z "$TARGET" ]]`: an empty first argument must land in the STORY slot
# and be reported as a missing story, never silently promote the box argument
# into it.
take_positional() {
  case "$POSITIONAL" in
    0) TARGET="$1" ;;
    1) TASK_ID="$1" ;;
    *) usage_error "unexpected extra argument '$1' — one box per invocation" ;;
  esac
  POSITIONAL=$((POSITIONAL + 1))
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help | -h)
      print_help >&2
      exit 2
      ;;
    --tilde)
      # The qualifier+reason is REQUIRED: a `[~]` with nothing after it is the
      # grammar error validate-story.sh reports, and this script must not be
      # able to write one (R1.2).
      shift
      if [[ $# -eq 0 ]]; then
        usage_error '--tilde requires an argument: --tilde "<qualifier>: <reason>"'
      fi
      TILDE_GIVEN=true
      TILDE_RAW="$1"
      shift
      ;;
    --)
      # End of options: everything after it is positional, even if it starts
      # with `-`. Without this, a directory named `-012-x` is unreachable — it
      # could only ever be reported as an unknown flag.
      shift
      while [[ $# -gt 0 ]]; do
        take_positional "$1"
        shift
      done
      ;;
    -*)
      usage_error "unknown flag '$1'"
      ;;
    *)
      take_positional "$1"
      shift
      ;;
  esac
done

[[ -n "$TARGET" ]] || usage_error "missing story argument — pass a story number (010) or its directory"
[[ -n "$TASK_ID" ]] || usage_error "missing box argument — say which box to close (1.2, 1, or gate:<text prefix>)"

# The qualifier TOKEN is split out here, as part of parsing; whether it is one
# of the four the grammar allows is sub-task 1.2's refusal (R1.2), so a bad
# token reaches that arm intact rather than being mangled on the way.
if [[ "$TILDE_GIVEN" == true ]]; then
  QUALIFIER=$(trim "${TILDE_RAW%%:*}")
fi

# --- The box argument's SHAPE ------------------------------------------------
# WHAT the caller named is a statement about the command line, so it is decided
# here, before anything touches the disk: an argument outside the documented
# grammar is exit 2 whatever the state of the world, and can never be preempted
# by a refusal about a file it was never going to name. WHETHER that box exists
# is step 2's refusal (R1.3). This is the same split 1.1 already made for
# `--tilde` one statement above — the token is cut during parsing, its legality
# is judged later.
TARGET_KIND=""    # sub | group | gate
TARGET_GROUP=""   # canonical group number, for sub and group
TARGET_SUB=""     # canonical sub-task number, for sub
GATE_PREFIX=""    # the text prefix, for gate

# Trimmed before classification, never after: `.task` reports the box AS THE
# CALLER NAMED IT, so a report can be matched against the call that produced it.
BOX_ARG=$(trim "$TASK_ID")
if [[ "$BOX_ARG" == gate:* ]]; then
  TARGET_KIND=gate
  GATE_PREFIX=$(trim "${BOX_ARG#gate:}")
  [[ -n "$GATE_PREFIX" ]] ||
    usage_error "'gate:' names no gate — pass a prefix of the gate's text, e.g. gate:All task validations"
elif [[ "$BOX_ARG" =~ ^([0-9]{1,9})\.([0-9]{1,9})$ ]]; then
  TARGET_KIND=sub
  canon_num "${BASH_REMATCH[1]}"
  TARGET_GROUP="$CANON"
  canon_num "${BASH_REMATCH[2]}"
  TARGET_SUB="$CANON"
elif [[ "$BOX_ARG" =~ ^([0-9]{1,9})$ ]]; then
  TARGET_KIND=group
  canon_num "${BASH_REMATCH[1]}"
  TARGET_GROUP="$CANON"
else
  # `1.2.3` lands here too, and deliberately: three-level numbering is not in
  # the task grammar (validate-story.sh:474), so there is no such box to close.
  usage_error "box '$TASK_ID' is not a box this grammar can name — pass a sub-task (1.2), a task group (1), or a Quality Gate by a prefix of its text (gate:All task validations)"
fi

# --- Story resolution -------------------------------------------------------
# A story this script cannot reach is a REFUSAL, not a usage error — see the
# divergence note in the header. Each arm names what it looked for, because
# "not found" without the place it looked is a message nobody can act on.
EPIC_DIR=""
if [[ -d "$TARGET" ]]; then
  # The trailing slash is stripped, but never off a bare `/`: `${TARGET%/}`
  # would empty it, and `cd ""` SUCCEEDS in bash without moving — so the story
  # would silently resolve to the current directory and be refused under the
  # project's own name. A refusal that names the wrong story is worse than the
  # refusal it replaces.
  STORY_PATH="$TARGET"
  if [[ "$STORY_PATH" != "/" ]]; then
    STORY_PATH="${STORY_PATH%/}"
  fi
elif [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  EPIC_DIR=$(find_epic_dir) ||
    refuse "no .epic/ directory found from $(pwd) — run this inside an Epic project, or pass the story directory; nothing was modified"
  STORY_PATH=$(resolve_by_number "$TARGET" "$EPIC_DIR") ||
    refuse "story '$TARGET' not found under $EPIC_DIR/stories or $EPIC_DIR/archive — nothing was modified"
else
  refuse "story '$TARGET' not found — pass a story number (010) or its directory; nothing was modified"
fi

STORY_ABS=$(cd "$STORY_PATH" 2>/dev/null && pwd -P) ||
  refuse "cannot enter story directory '$STORY_PATH' — nothing was modified"
STORY_ID=$(basename "$STORY_ABS")

# R1.4 — a story under .epic/archive/ is READ-ONLY, and the refusal happens
# BEFORE anything else looks at it (an archived story with no tasks.md must
# still report its real reason rather than tripping over the missing file).
#
# The test is made on the PHYSICAL path, and on the whole path rather than on
# the parent's name, for two distinct reasons:
#   * `pwd -P` resolves symlinks, so a `.epic/stories/007-old` pointing into
#     `.epic/archive/007-old` is caught. Testing the path the caller typed would
#     rewrite an archived story through a live-looking name.
#   * R1.4 says "lives UNDER .epic/archive/", which includes anything nested
#     deeper than one level — `basename "$(dirname …)" == archive` (the
#     sibling scripts' form) sees only the first level.
if [[ "$STORY_ABS" == */.epic/archive || "$STORY_ABS" == */.epic/archive/* ]]; then
  refuse "story '$STORY_ID' lives under .epic/archive/ ('$STORY_PATH') — an archived story is read-only, so its boxes can no longer be closed (R1.4); nothing was modified"
fi

# tasks.md is the only artifact this script writes, and every box lives in it.
TASKS_FILE="$STORY_PATH/tasks.md"
if [[ ! -f "$TASKS_FILE" ]]; then
  refuse "story '$STORY_ID' has no tasks.md ('$TASKS_FILE') — there is no box to close; nothing was modified"
fi
# `[[ -f ]]` says the file EXISTS, not that it can be opened. Checked here, once
# and early, because a failed redirection at top level under `set -e` would end
# the run with no JSON on stdout at all — the one thing the output contract
# promises never happens.
if [[ ! -r "$TASKS_FILE" ]]; then
  refuse "cannot read '$TASKS_FILE' — the box to close is located by reading it, so a close that cannot read it would be a write aimed at a line nobody checked; fix the permissions and re-run. Nothing was modified"
fi

# ============================================================================
# STEP 2 — LOCATE AND MARK THE BOX (sub-task 1.2 — R1.1/R1.2/R1.3/R1.6/R1.7)
# ============================================================================
# Order: judge the qualifier (needs nothing from disk) → locate the box and the
# group state around it (ONE read) → refuse, or write ONE line and, when R1.7
# says so, its group header — in ONE rewrite. Every refusal below is raised
# before that rewrite, so "nothing was modified" is a property of the code path
# rather than a promise made in a comment.

# --- Locating (one pass) -----------------------------------------------------
LOC_LINE=0        # line number of the target box; 0 = not found
LOC_BOX=""        # its box character, as read
LOC_TEXT=""       # the whole line, so a refusal can quote the state it found
LOC_LINES=""      # every line that answered to the target, space-joined
LOC_COUNT=0       # how many did: >1 is ambiguous, and ambiguity is never written
GRP_HDR_LINE=0    # the target group's header line; 0 = the group has no header
GRP_HDR_BOX=""    # that header's box character
GRP_HDR_LINES=""  # every line claiming to be that header, space-joined
GRP_HDR_COUNT=0   # how many headers claim the number: >1 makes the group unreadable
GRP_OPEN=0        # `[ ]` sub-tasks the target group has, the target INCLUDED

# locate_box <tasks.md> — fills the block above in a single read. The group
# state R1.7 needs is gathered in the SAME pass as the target, because a second
# read is a second file: between them the box could be closed by someone else,
# and the header would then be written against a census that no longer holds.
#
# TWO SECTIONS ARE EXCLUDED, each decided by one line in isolation, exactly as
# validate-story.sh:484-528 decides them:
#   * a FENCED block — an illustrative task list is documentation, not a claim,
#     and marking a box inside one would edit an example;
#   * the QUALITY GATES section, for NUMBERED targets. `- [ ] 3 - Coverage >=
#     80%` is a legal gate AND is shaped exactly like a group header; letting it
#     answer to `3` would mark a gate for a group. The `gate:` target is the
#     mirror image: it looks ONLY inside that section, which is what makes the
#     two namespaces disjoint instead of overlapping.
#
# Reading is fallible, so this returns non-zero instead of dying: `[[ -f ]]`
# says the file exists, not that it can be opened, and a bare failed redirection
# at top level under `set -e` would end the run with no JSON on stdout at all.
# The `{ …; :; } 2>/dev/null < "$file" || return 1` form is archive-story.sh's
# (:427-432) and it is the one that actually catches that.

# record_candidate <line-number> <box-char> <line> — one line that answered to
# the target. EVERY match is counted and its number kept, because the count is
# what makes ambiguity visible; only the FIRST one is described, which is the
# same "first wins" rule validate-story.sh:581-587 applies to a duplicated group
# header. Sets globals rather than printing: it is called from inside the read
# loop, which a redirected group runs in THIS shell, so the values survive.
record_candidate() {
  LOC_COUNT=$((LOC_COUNT + 1))
  LOC_LINES="${LOC_LINES:+$LOC_LINES }$1"
  if [[ "$LOC_LINE" -eq 0 ]]; then
    LOC_LINE="$1"
    LOC_BOX="$2"
    LOC_TEXT="$3"
  fi
}

locate_box() {
  local file="$1"
  local line lineno=0 in_fence=false in_gates=false
  local box grp sub text
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      lineno=$((lineno + 1))
      # The exclusions see EVERY line, so they precede the box filter: a fence
      # and a heading are not checkboxes. A fence line is never content, and a
      # `## Quality Gates` INSIDE a fence is documentation — so the fence is
      # tested first and wins.
      if [[ "$line" =~ $FENCE_RE ]]; then
        if [[ "$in_fence" == true ]]; then in_fence=false; else in_fence=true; fi
      elif [[ "$in_fence" == false && "$in_gates" == false && "${line,,}" =~ $GATES_RE ]]; then
        in_gates=true
      fi
      [[ "$line" =~ $BOX_RE ]] || continue
      box="${BASH_REMATCH[1]}"
      [[ "$in_fence" == false ]] || continue

      if [[ "$TARGET_KIND" == gate ]]; then
        [[ "$in_gates" == true ]] || continue
        [[ "$line" =~ $GATE_TEXT_RE ]] || continue
        text="${BASH_REMATCH[1]}"
        # "$GATE_PREFIX" is QUOTED inside the pattern and the `*` is outside it:
        # the caller's text is matched literally, and a reason or a gate title
        # carrying `*` or `?` cannot turn into a glob.
        [[ "$text" == "$GATE_PREFIX"* ]] || continue
        record_candidate "$lineno" "$box" "$line"
        continue
      fi

      # Numbered targets live in the task list and nowhere else.
      [[ "$in_gates" == false ]] || continue
      [[ "$line" =~ $TASK_NUM_RE ]] || continue
      grp="${BASH_REMATCH[2]}"
      [[ ${#grp} -le $GRP_MAX_DIGITS ]] || continue
      sub="${BASH_REMATCH[3]#.}"
      canon_num "$grp"
      grp="$CANON"
      [[ "$grp" == "$TARGET_GROUP" ]] || continue

      if [[ -z "$sub" ]]; then
        # `N` — the group's own header. The FIRST one wins the box and the line,
        # and every one of them is counted: more than one header IS the reason
        # the group's state cannot be read (validate-story.sh:619-622).
        GRP_HDR_COUNT=$((GRP_HDR_COUNT + 1))
        GRP_HDR_LINES="${GRP_HDR_LINES:+$GRP_HDR_LINES }$lineno"
        if [[ "$GRP_HDR_LINE" -eq 0 ]]; then
          GRP_HDR_LINE=$lineno
          GRP_HDR_BOX="$box"
        fi
        if [[ "$TARGET_KIND" == group ]]; then
          record_candidate "$lineno" "$box" "$line"
        fi
      else
        # `N.M` — a sub-task, owned by the number BEFORE the dot, which is why
        # group 1 owns 1.1 and never owns 10.1.
        #
        # NO DIGIT GUARD ON THE SUB-NUMBER, and the asymmetry with the group
        # guard four lines up is the READER'S OWN: validate-story.sh:558 bounds
        # BASH_REMATCH[2] — the group — and :561-574 then counts the child
        # unconditionally. Guarding it here too made GRP_OPEN a strict SUBSET of
        # the reader's count, and the writer that under-counts open children is
        # the writer that closes a group header over one. Measured: a group
        # whose last remaining `[ ]` child was numbered `1.1234567890123` was
        # counted as settled, its header written `[x]`, and the very next
        # validation reported the error this script had just authored (R1.7).
        # The reader's reason for its bound does not reach the sub-number in
        # either script — no number here becomes an array subscript, and
        # canon_num is string-only by construction, so a 20-digit run is a long
        # string and nothing else.
        canon_num "$sub"
        sub="$CANON"
        # `[ ]` is open, and nothing else is: references/tasks.md makes it the
        # only state that counts as pending. Written as a plain `if`, never
        # `[[ … ]] && …` — a trailing AND-list that fails hands its status to
        # the enclosing construct, and this script runs under `set -e`.
        if [[ "$box" == ' ' ]]; then
          GRP_OPEN=$((GRP_OPEN + 1))
        fi
        if [[ "$TARGET_KIND" == sub && "$sub" == "$TARGET_SUB" ]]; then
          record_candidate "$lineno" "$box" "$line"
        fi
      fi
    done
    :
  } 2> /dev/null < "$file" || return 1
  return 0
}

# --- Writing (one rewrite) ---------------------------------------------------
# rewrite_file is supersede-story.sh:464-483, copied with ONE addition marked
# below. Its three properties are the reason it is copied rather than re-thought:
#   1. `2>` BEFORE `<` suppresses bash's own message on an unreadable file, and
#      the trailing `:` pins the group's status to the REDIRECTION rather than
#      to whatever the emitter last evaluated.
#   2. the temp file is REMOVED on failure — a half-written `.tmp` beside a
#      story artifact is litter the next reader has to know to ignore.
#   3. the rename is what makes the write atomic: an interruption leaves the
#      ORIGINAL, never a truncated tasks.md (R1.6).
#
# FOUR ADDITIONS, each closing something the copied form leaves open:
#
#   A. THE EMITTER'S OWN STATUS. The `:` that pins property 1 also swallows it,
#      so an emitter that gave up mid-file would still be renamed into place.
#      R1.6 says the file is unchanged on ANY mid-write failure, so the status
#      is captured in a flag and checked before the rename. The emitter runs in
#      THIS shell — a redirected group is not a subshell — so the flag survives.
#
#   B. THE EMITTER'S I/O ERRORS, which flag A cannot see. Invoking the emitter
#      as the left operand of `||` suspends `set -e` FOR ITS WHOLE BODY, so a
#      `printf` that fails on a full disk does not end it: the loop runs on and
#      `return 0` reports success over a truncated file. Measured on /dev/full,
#      the shape before this fix returned 0 and would have renamed the stump
#      over tasks.md. Re-enabling `set -e` is not the repair — a failure inside
#      the emitter would then kill the script outright, and the output contract
#      says JSON on stdout on every path that reaches a verdict. So the emitter
#      states its own failures instead: every emitting `printf` carries
#      `|| return 1` (see mark_lines).
#
#   C. AN INDEPENDENT WITNESS THAT THE TMP IS WHOLE. B trusts the writer's
#      report; this reads what actually landed. The emitter counts the newlines
#      it wrote and the tmp is measured before the rename — a short write, a
#      truncation at a line boundary, or a flush that failed at close (which no
#      `printf` status can carry) all show up as a count that does not match.
#      Exact, not approximate: `read -r` splits on newline, so no `$line` can
#      contain one, and the reason text has already been flattened by same_line
#      — one newline per terminated line, and never a stray one.
#
#   D. THE FILE'S PERMISSIONS. `mv -f` makes the TMP'S INODE the survivor, so
#      the mode came from the umask instead of the file: a `600` tasks.md came
#      back `644`, measured. This script is the sanctioned writer of live story
#      artifacts and must not quietly widen access to one, so the original's
#      mode is copied onto the tmp before the rename — before, so a failure to
#      copy it is a rewrite that never happened rather than a file already
#      replaced. (Owner and group cannot be preserved without privilege and are
#      not attempted; a rename does keep the parent directory's ACL default.)
#      supersede-story.sh:464-483, the origin of this function, has the same gap
#      and is deliberately NOT edited here: mode is not part of the shared
#      checkbox grammar, so the "consumers move together" convention does not
#      reach it, and that sibling is not this story's file.
#
# NO `eol_of`/`REWRITE_EOL` HERE, AND STILL NONE NOW THAT A LINE IS ADDED.
# Every line ending this script writes is taken from a line of the file itself,
# never guessed from the file as a whole:
#   * a line it MARKS keeps its own ending, because the qualifier is appended
#     before it (set_box);
#   * the `status:` line it INSERTS into a legacy artifact takes the ending of
#     the closing `---` it is inserted in front of (stamp_lines).
# supersede-story.sh's eol_of reads line 1 and applies that answer to the whole
# file. Taking the ending off the neighbouring line is strictly stronger — it is
# right on a file with mixed endings, where a file-level guess is wrong by
# construction — and it needs no extra read of the file. It is also the reasoning
# this script already applies one function down, so the two writes agree instead
# of each having their own idea of what a line ending is.
REWRITE_EMITTER_RC=0
REWRITE_EMITTER_NL=0   # newlines the emitter reports writing — witness C

# file_mode <path> — the file's permission bits as an octal string, into
# FILE_MODE; returns non-zero (and leaves it empty) when they cannot be read.
# The GNU form first, then the BSD one, and THE OUTPUT IS WHAT DECIDES rather
# than the exit status: `stat -f` on GNU stat prints filesystem information and
# exits 0, so a status-only check would happily accept that as a mode.
# epic-index.sh:1015-1023 is where this shape and that trap were worked out.
FILE_MODE=""
file_mode() {
  FILE_MODE=$(stat -c '%a' "$1" 2> /dev/null) || FILE_MODE=""
  if [[ ! "$FILE_MODE" =~ ^[0-7]{3,4}$ ]]; then
    FILE_MODE=$(stat -f '%Lp' "$1" 2> /dev/null) || FILE_MODE=""
  fi
  if [[ ! "$FILE_MODE" =~ ^[0-7]{3,4}$ ]]; then
    FILE_MODE=""
    return 1
  fi
  return 0
}

# --- The tmp file, when the process does not get to finish ------------------
# Every ordinary failure path inside rewrite_file removes its own tmp. A FATAL
# SIGNAL takes none of them: the process dies between the write and the rename
# and the tmp survives beside the story artifact, which is litter the next
# reader has to know to ignore. Measured, before this trap existed: `ulimit -f
# 0` around one close left tasks.md byte-identical and the box open (R1.6
# honoured) — and a `tasks.md.epic-close.XXXXXX` stump in the story directory.
# archive-story.sh:3056-3059 covers the same gap the same way, with the same
# `|| true` (a trap must never turn a clean verdict into a failure) and the same
# 128+signal exit codes (an exit that lies about how the process ended is worse
# than the litter).
#
# IT CANNOT REACH ANOTHER INVOCATION'S TMP, which matters because two closes
# against one story are exactly what the unique name exists to survive: the only
# path it ever removes is the one THIS process's mktemp created, and it is
# cleared the moment that path stops being live (renamed away, or already
# removed). A concurrent invocation's tmp carries a different random suffix and
# is never named here.
#
# XFSZ IS IN THE LIST because it is the signal the measurement above actually
# produced; INT/TERM/HUP are the three a person or a supervisor sends. EXIT
# covers every ordinary end, including the refusals, where it finds nothing to
# do (REWRITE_TMP is empty on every path that never opened a tmp).
REWRITE_TMP=""
# shellcheck disable=SC2317,SC2329  # invoked from the trap strings below, and
# a trap string is not a call site the linter follows (epic-index.sh:154 carries
# the same pair for the same reason). BOTH codes are needed: 0.10+ reports
# SC2329 once per function, 0.9 (what CI installs) reports SC2317 once per
# COMMAND in the body.
cleanup_rewrite_tmp() {
  if [[ -n "$REWRITE_TMP" ]]; then
    rm -f "$REWRITE_TMP" 2> /dev/null || true
    REWRITE_TMP=""
  fi
  return 0
}
trap 'cleanup_rewrite_tmp || true' EXIT
trap 'cleanup_rewrite_tmp || true; exit 130' INT
trap 'cleanup_rewrite_tmp || true; exit 143' TERM
trap 'cleanup_rewrite_tmp || true; exit 129' HUP
trap 'cleanup_rewrite_tmp || true; exit 153' XFSZ

rewrite_file() {
  # ONE NAME PER `local`, and do NOT fold these back into one statement: in
  # bash 5.3 a `local a=1 b=$a` declares BOTH names first, so `$a` expands to
  # the just-declared (still unset) local and the run aborts under `set -u`.
  local f="$1"
  local emitter="$2"
  local tmp
  local landed
  # A UNIQUE TMP, IN THE FILE'S OWN DIRECTORY — same directory because a rename
  # is only atomic within one filesystem (property 3). The name used to be the
  # fixed `$f.epic-close.tmp`, which two invocations against one story would
  # have written to at once, each truncating the other's half-finished file and
  # one of them renaming the result into place. One fork removes that. mktemp
  # also creates the file `0600`, so the window between written and renamed is
  # the narrowest mode available rather than whatever the umask allows.
  tmp=$(mktemp "$f.epic-close.XXXXXX") || return 1
  # Handed to the signal trap the moment it exists, and taken back from it the
  # moment it stops existing (every `cleanup_rewrite_tmp` below removes it AND
  # clears the global; the successful rename clears it without removing
  # anything, because the path is gone by then). So the trap can only ever
  # remove a tmp this function is in the middle of writing.
  REWRITE_TMP="$tmp"
  REWRITE_EMITTER_RC=0
  REWRITE_EMITTER_NL=0
  { "$emitter" || REWRITE_EMITTER_RC=$?; :; } 2> /dev/null < "$f" > "$tmp" || {
    cleanup_rewrite_tmp
    return 1
  }
  if [[ "$REWRITE_EMITTER_RC" -ne 0 ]]; then
    cleanup_rewrite_tmp
    return 1
  fi
  # Witness C. `-1` on a failed measurement is not a count any emitter can
  # report, so an unmeasurable tmp is a tmp that does not get renamed. The
  # whitespace strip is not decoration: `wc -l` pads its number on some
  # implementations and not on GNU's, and this is a string comparison.
  landed=$(wc -l < "$tmp" 2> /dev/null) || landed=-1
  landed="${landed//[[:space:]]/}"
  if [[ "$landed" != "$REWRITE_EMITTER_NL" ]]; then
    cleanup_rewrite_tmp
    return 1
  fi
  # Addition D — the mode, read off the ORIGINAL and applied to the tmp BEFORE
  # the rename, so a failure to carry it over is a rewrite that never happened
  # rather than a file already replaced. epic-index.sh:1012-1027 solves the same
  # problem the same way, with ONE deliberate difference: it falls back to
  # `0666 & ~umask` when it cannot read a mode, because ITS target may
  # legitimately not exist yet. tasks.md provably exists and is readable by the
  # time this runs — both are refusal arms above — so an unreadable mode here is
  # a measurement that FAILED, and that fallback would silently reproduce the
  # exact widening this closes. Unmeasurable, or unappliable, is a rewrite that
  # does not happen.
  file_mode "$f" || {
    cleanup_rewrite_tmp
    return 1
  }
  chmod "$FILE_MODE" "$tmp" 2> /dev/null || {
    cleanup_rewrite_tmp
    return 1
  }
  mv -f "$tmp" "$f" || {
    cleanup_rewrite_tmp
    return 1
  }
  # The rename consumed the tmp: there is no longer a path for the trap to
  # remove, and leaving a stale one in the global would aim it at a name that
  # mktemp may hand out again.
  REWRITE_TMP=""
  return 0
}

# What the one rewrite writes. Line numbers, not patterns: the lines were chosen
# by the grammar during locate_box, and re-deriving them here would be a second
# reader of the same file with its own chance to disagree.
MARK_LINE=0       # the box the caller asked for
MARK_CHAR=""      # x | ~
MARK_SUFFIX=""    # " (qualifier: reason)" on a `[~]` close, empty otherwise
MARK_HDR_LINE=0   # the group header R1.7 closes with it; 0 = none

# set_box <line> <expected-box> <new-box> <suffix> — the line with its box
# character replaced and, for a `[~]`, the qualifier appended before the line's
# own ending. Returns 1 when the line is not the box it was located as, which is
# how a tasks.md edited between the read and the write stops the rewrite instead
# of being overwritten by it.
#
# THE REASON TEXT IS DATA ON EVERY PATH IT TAKES. It arrives as `$4`, is
# concatenated by parameter expansion, and leaves through `printf '%s'` — never
# a format string, never a pattern, never an argument to a command. There is no
# point at which a `%`, a `$`, a backtick, a quote or a `;` in it is anything
# other than a character to copy (design.md: injection surface, none).
# shellcheck disable=SC2317,SC2329  # invoked indirectly: rewrite_file takes a
# line-emitter BY NAME, so shellcheck's reachability stops at the call site and
# marks this — and everything it calls — as dead. BOTH codes are needed and they
# are not interchangeable: 0.10+ reports SC2329 once per function, 0.9 (what CI
# installs) reports SC2317 once per COMMAND in the body.
set_box() {
  local line="$1" expected="$2" char="$3" suffix="$4"
  local head tail cr=""
  [[ "$line" =~ $BOX_SPLIT_RE ]] || return 1
  [[ "${BASH_REMATCH[2]}" == "$expected" ]] || return 1
  head="${BASH_REMATCH[1]}"
  tail="${BASH_REMATCH[3]}"
  # The line's OWN ending, taken off and put back, so the qualifier lands
  # BEFORE it and a CRLF file stays CRLF on the line it just wrote (R1.6).
  if [[ "$tail" == *$'\r' ]]; then
    cr=$'\r'
    tail="${tail%$'\r'}"
  fi
  if [[ -n "$suffix" ]]; then
    # Trailing whitespace on the original line would otherwise be preserved
    # INSIDE the sentence, as a gap before the qualifier.
    tail="${tail%"${tail##*[![:space:]]}"}"
    tail="$tail$suffix"
  fi
  printf '%s%s%s%s' "$head" "$char" "$tail" "$cr"
}

# shellcheck disable=SC2317,SC2329  # invoked indirectly: rewrite_file takes a
# line-emitter BY NAME, so shellcheck's reachability stops at the call site and
# marks this — and everything it calls — as dead. BOTH codes are needed and they
# are not interchangeable: 0.10+ reports SC2329 once per function, 0.9 (what CI
# installs) reports SC2317 once per COMMAND in the body.
mark_lines() {
  local line out n=0 terminated=true
  # `terminated` goes false only on a last line with no newline after it: `read`
  # returns non-zero having filled the variable. Re-emitting that line WITH a
  # newline would be a byte this script added to a file it was asked to mark
  # (R1.6), so the file gets back exactly the ending it had — including none.
  while IFS= read -r line || { [[ -n "$line" ]] && terminated=false; }; do
    n=$((n + 1))
    if [[ "$n" -eq "$MARK_LINE" ]]; then
      out=$(set_box "$line" ' ' "$MARK_CHAR" "$MARK_SUFFIX") || return 1
      line="$out"
    elif [[ "$MARK_HDR_LINE" -gt 0 && "$n" -eq "$MARK_HDR_LINE" ]]; then
      out=$(set_box "$line" ' ' 'x' '') || return 1
      line="$out"
    fi
    # EVERY EMITTING printf STATES ITS OWN FAILURE (rewrite_file, addition B):
    # `set -e` is suspended for this whole body, so a write that fails on a full
    # disk is invisible unless it is asked. The newline tally is witness C, and
    # it is incremented only where a newline is actually written: a last line
    # with nothing after it contributes none here, exactly as it contributes
    # none to the `wc -l` this is compared against.
    if [[ "$terminated" == true ]]; then
      printf '%s\n' "$line" || return 1
      REWRITE_EMITTER_NL=$((REWRITE_EMITTER_NL + 1))
    else
      printf '%s' "$line" || return 1
    fi
  done
  return 0
}

# --- 2a. The qualifier -------------------------------------------------------
# Judged before the file is opened: it is a statement about the REQUEST, it
# needs nothing from disk, and a caller whose qualifier is wrong has to fix that
# whatever the box turns out to be.
TILDE_REASON=""
if [[ "$TILDE_GIVEN" == true ]]; then
  if [[ ! "$TILDE_RAW" =~ $TILDE_FORM_RE ]]; then
    refuse "'--tilde $TILDE_RAW' does not open with one of the four qualifiers the checkbox grammar defines ($TILDE_FORMS) — '$QUALIFIER' is not one of them, and a [~] box carrying an unrecognized qualifier is a validation error, so it is refused here instead of written now and reported later (R1.2); nothing was modified"
  fi
  QUALIFIER="${BASH_REMATCH[1]}"
  TILDE_REASON=$(trim "${BASH_REMATCH[2]}")
  TILDE_REASON=$(same_line "$TILDE_REASON")
  if [[ -z "$TILDE_REASON" ]]; then
    refuse "'--tilde $TILDE_RAW' names the qualifier '$QUALIFIER' but gives no reason — the grammar is '<qualifier>: <reason>' and a box closed WITHOUT the work being done has to say why on the same line (R1.2); nothing was modified"
  fi
  # A SECOND QUALIFIER SMUGGLED IN THE REASON — see TILDE_TOKEN_RE. Refused
  # after the empty check so a bare `--tilde "deferred:"` still gets the message
  # about its missing reason rather than one about a token it does not carry.
  # The token is lifted into a variable first: `refuse` builds its message from
  # $QUALIFIER, and the next `[[ =~ ]]` anywhere would overwrite BASH_REMATCH.
  if [[ "$TILDE_REASON" =~ $TILDE_TOKEN_RE ]]; then
    TILDE_STOWAWAY="${BASH_REMATCH[2]}"
    refuse "'--tilde $TILDE_RAW' hides a second qualifier ('$TILDE_STOWAWAY:') inside its reason — every reader of the checkbox grammar matches a qualifier ANYWHERE on the line, and 'deferred:' outranks a terminal one wherever it sits, so this box would be written as '$QUALIFIER' and read back as '$TILDE_STOWAWAY': the file and this report would disagree about the same box. Say the reason without that token — rephrase it, or drop its colon — and re-run. Nothing was modified (R1.2)"
  fi
  MARK_CHAR='~'
  MARK_SUFFIX=" ($QUALIFIER: $TILDE_REASON)"
else
  MARK_CHAR='x'
fi

# --- 2b. The box ------------------------------------------------------------
locate_box "$TASKS_FILE" ||
  refuse "cannot read '$TASKS_FILE' — the box to close is located by reading it, so nothing was modified"

if [[ "$LOC_COUNT" -eq 0 ]]; then
  if [[ "$TARGET_KIND" == gate ]]; then
    refuse "no Quality Gate in story '$STORY_ID' opens with '$GATE_PREFIX' — a gate is named by a prefix of its own text and is looked for under the story's Quality Gates heading only; nothing was modified (R1.3)"
  fi
  refuse "story '$STORY_ID' has no box '$TASK_ID' in its task list — the grammar is '- [ ] $BOX_ARG - <title>', and a fenced example or a Quality Gate shaped like one does not answer to it; nothing was modified (R1.3)"
fi

if [[ "$LOC_COUNT" -gt 1 ]]; then
  refuse "box '$TASK_ID' names $LOC_COUNT lines of '$TASKS_FILE' (lines ${LOC_LINES// /, }) — which of them the caller meant is not something this script may guess, so it marks none of them; give the duplicates distinct numbers or gate texts. Nothing was modified (R1.3)"
fi

# Already closed — a REFUSAL that names the state it found, never a silent
# success. During a resumed run the orchestrator reads this as confirmation, so
# the message has to carry what is actually on the line (the qualifier included)
# rather than just "already done".
if [[ "$LOC_BOX" != ' ' ]]; then
  refuse "box '$TASK_ID' of story '$STORY_ID' is already closed [$LOC_BOX] — tasks.md line $LOC_LINE reads '$(trim "$LOC_TEXT")'. Re-closing is refused so a genuine double-close is never silent; nothing was modified (R1.3)"
fi

# --- 2c. What this one close implies for the group header (R1.7) -------------
# The pair (header, children) is a single fact, and validate-story.sh:610-657
# errors on both of its inconsistent shapes. This script is the pair's only
# writer, so it never leaves one half of it for a later invocation to fix.
case "$TARGET_KIND" in
  sub)
    # The target is open (refused above if not), so it is one of GRP_OPEN.
    if [[ $((GRP_OPEN - 1)) -eq 0 && "$GRP_HDR_BOX" == ' ' ]]; then
      if [[ "$GRP_HDR_COUNT" -eq 1 ]]; then
        # `[x]` and not `[~]`: a `[~]` header would need a qualifier of its own
        # (an unqualified one is a validation error), and this script has no
        # honest reason to invent one — the group's work is settled, whatever
        # each child's own mark says about how.
        MARK_HDR_LINE=$GRP_HDR_LINE
      else
        # Two headers claim the number, so the group has no readable state and
        # the validator already refuses to judge the pair. Said out loud rather
        # than passed over: the header this close would normally have closed is
        # being left open on purpose. The DUPLICATE lines are the ones named —
        # they are what the author has to go and look at, and naming the box's
        # own line instead would send them to the one line that is not the
        # problem (validate-story.sh:620 names them for the same reason).
        printf 'Note: group %s has %d headers (lines %s) — its state is not readable, so closing box %s left the group header open.\n' \
          "$TARGET_GROUP" "$GRP_HDR_COUNT" "${GRP_HDR_LINES// /, }" "$TASK_ID" >&2
      fi
    fi
    ;;
  group)
    # The mirror image, and the reason it is a refusal rather than a write: a
    # `[x]` header over a still-open child is the OTHER inconsistent shape, and
    # writing it here would make this script the author of the error the next
    # validation reports. `[~]` is exempt because the pair rule is — a group
    # closed without the work being done says so on its own line, and the
    # validator has no `~` branch.
    if [[ "$MARK_CHAR" == 'x' && "$GRP_OPEN" -gt 0 ]]; then
      refuse "group '$TASK_ID' of story '$STORY_ID' still has $GRP_OPEN open sub-task(s) — closing its header with [x] would claim work that is still owed, which validation reports as an error (R1.7). Close the sub-tasks (the header then closes with the last of them), or pass --tilde to record why the group is closed without the work. Nothing was modified"
    fi
    ;;
esac

# --- 2d. The write -----------------------------------------------------------
MARK_LINE=$LOC_LINE
rewrite_file "$TASKS_FILE" mark_lines ||
  refuse "could not rewrite '$TASKS_FILE' — the box was located but the new text never replaced the old one, so tasks.md is byte-identical to what it was (R1.6); check the directory's permissions and free space, then re-run"

BOX="$MARK_CHAR"

# ============================================================================
# STEP 3 — CENSUS AND STATUS TRANSITION (sub-task 2.1 — R2.1/R2.2)
# ============================================================================
# THE BOX IS CLOSED. Everything below reports on a story that has already been
# written, so NOTHING HERE IS A REFUSAL and nothing here changes the exit code:
# references/run-mode.md's fifth writing rule is explicit that "a failed write
# is reported, and the run continues — `status:` is advisory metadata and must
# never block the run that is producing the actual work". A failure here is said
# on stderr and carried in the report by the ABSENCE of the transition it could
# not write, never by turning a landed marking into an error the caller will
# retry.
#
# THE ORDER IS census -> rules -> stamp, and it is the order references/run-mode.md
# states: "Census the boxes as they now stand … then apply the first rule that
# matches", and only then "Edit the frontmatter line".

# --- 3a. The census ----------------------------------------------------------
# THE BUCKETS ARE references/tasks.md#completion's, not this script's:
#   total    = every box, whatever its state
#   closed   = `[x]` + TERMINAL `[~]` (waived: / n-a: / superseded-by:)
#   deferred = `[~]` qualified `deferred:`
#   open     = `[ ]`, and only `[ ]`
# `deferred:` wins on a line carrying both, which is the precedence the grammar
# gives it (references/tasks.md: "the work is still owed by someone"), and an
# UNQUALIFIED `[~]` — the grammar error validate-story.sh reports — counts in
# the total and closes nothing. That aggregation is hook-precompact.sh's and
# epic-index.sh:386-417's verbatim, which is what makes this script's report and
# the index a reader sees side by side incapable of disagreeing about one story.
#
# EVERY BOX IN THE DOCUMENT, with no fence or Quality-Gates exclusion — the
# exact opposite of locate_box above, and deliberately so. locate_box answers
# "which box did the caller name", where a fenced example is documentation and a
# gate shaped like a group header is not that group; the census answers "what
# does this file now claim", which is the question every OTHER reader of the
# same file answers over the whole document (validate-story.sh:506-507 says so
# in as many words, and its BOX_OPEN/BOX_DEFERRED are what its own status
# warnings run on). Excluding anything here would let this script write `done`
# over a census the validator it invokes in step 4 does not share — authoring,
# in one invocation, the very "status is ahead of the checkboxes" warning the
# transition exists to prevent.
#
# Reading is fallible even now: the file was readable a moment ago, but `[[ -f
# ]]` never said it would open twice. Returns non-zero rather than dying — the
# output contract promises JSON on stdout on every path that reaches a verdict,
# and this path has one.
census_boxes() {
  local file="$1" line
  BOX_TOTAL=0
  BOX_OPEN=0
  BOX_CLOSED=0
  BOX_DEFERRED=0
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ $BOX_RE ]] || continue
      BOX_TOTAL=$((BOX_TOTAL + 1))
      case "${BASH_REMATCH[1]}" in
        ' ') BOX_OPEN=$((BOX_OPEN + 1)) ;;
        'x') BOX_CLOSED=$((BOX_CLOSED + 1)) ;;
        '~')
          if [[ "$line" =~ $TILDE_DEFERRED_RE ]]; then
            BOX_DEFERRED=$((BOX_DEFERRED + 1))
          elif [[ "$line" =~ $TILDE_TERMINAL_RE ]]; then
            BOX_CLOSED=$((BOX_CLOSED + 1))
          fi
          ;;
      esac
    done
    :
  } 2> /dev/null < "$file" || return 1
  return 0
}

# THE FILE IS RE-READ, not projected from what the write was supposed to do.
# The census is in the report so that the orchestrator never has to open
# tasks.md after a marking (design.md, component 1) — which makes it the only
# statement anyone will have about the file, and a statement derived from the
# INTENT of the write cannot contradict a write that did something else. This
# read is what turns it into a measurement.
CENSUS_TAKEN=true
census_boxes "$TASKS_FILE" || CENSUS_TAKEN=false
if [[ "$CENSUS_TAKEN" == false ]]; then
  # Zeros again, which is what they mean everywhere else in this report: nobody
  # measured. A real story always has at least the box just closed, so `total:
  # 0` beside a non-null `box` is not a state a reader can mistake for a census.
  BOX_TOTAL=0
  BOX_OPEN=0
  BOX_CLOSED=0
  BOX_DEFERRED=0
  printf 'Note: the box was closed, but %s could not be re-read for the census — the census is reported as zeros and no status transition was applied. The marking stands.\n' \
    "$TASKS_FILE" >&2
fi

# --- 3b. The story's current status ------------------------------------------
# read_frontmatter <file> — fills FM_HAS (does this artifact carry a frontmatter
# BLOCK, opening delimiter and closing one) and FM_STATUS (the FIRST `status:`
# inside it, empty when absent). One read, no forks per line.
#
# BOTH DELIMITERS ARE REQUIRED, for supersede-story.sh:305-307's reason: an
# unmatched opener would make the whole file read as frontmatter, and the stamp
# would then write its key past the end of the world. An artifact that fails
# that test is not "broken", it simply has no frontmatter — and run-mode is
# explicit that such an artifact is SKIPPED and its silence never counted as
# divergence.
#
# COLUMN 0, exactly as the templates write it and exactly as validate-story.sh
# reads it: a nested or compound key (`review_status:`) is not a status line.
# The value is trimmed and nothing else — no comment stripping, no whitespace
# squeezing. A value this script cannot classify falls through to rule 4 below
# and is left alone for validation to report, which is the safe direction: the
# one thing worse than not writing a status is overwriting one nobody here
# understood.
FM_HAS=false
FM_STATUS=""
read_frontmatter() {
  local f="$1" line n=0 rc=0
  FM_HAS=false
  FM_STATUS=""
  [[ -f "$f" ]] || return 0
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      n=$((n + 1))
      if [[ $n -eq 1 ]]; then
        # No opening delimiter: nothing to look for, and reading on would find
        # a `---` in the body and call it a block.
        [[ "$line" =~ $FM_DELIM_RE ]] || break
        continue
      fi
      if [[ "$line" =~ $FM_DELIM_RE ]]; then
        FM_HAS=true
        break
      fi
      if [[ -z "$FM_STATUS" && "${line%$'\r'}" == status:* ]]; then
        FM_STATUS=$(trim "${line#status:}")
      fi
    done
    :
  } 2> /dev/null < "$f" || rc=1
  # A status found without a closing delimiter is a status found outside a
  # frontmatter block. It is not this story's lifecycle state.
  if [[ "$FM_HAS" == false || "$rc" -ne 0 ]]; then
    FM_HAS=false
    FM_STATUS=""
  fi
  return $rc
}

# WHICH ARTIFACT ANSWERS FOR THE STORY: story.md when it has one, tasks.md
# otherwise — archive-story.sh:328-339's `story_field` order, for its reason.
# tasks.md is the one artifact every scale has, so a tasks-only story (fast,
# spike) still has a lifecycle state to read; story.md is where the field
# belongs when the story has one. design.md is deliberately not consulted for
# the READ (it describes the solution, not the state of the work) and is
# nonetheless WRITTEN below, because run-mode's rule is "the same value in every
# artifact that carries frontmatter" — one artifact answers, all of them agree.
STATUS_FROM=""
read_frontmatter "$STORY_PATH/story.md" || true
STATUS_FROM="$FM_STATUS"
if [[ -z "$STATUS_FROM" ]]; then
  read_frontmatter "$TASKS_FILE" || true
  STATUS_FROM="$FM_STATUS"
fi

# --- 3c. The four transition rules -------------------------------------------
# references/run-mode.md#status-transitions, FIRST MATCH WINS, in the documented
# order — which is why this is one if/elif chain and not three independent
# tests. Rule 2 sits BELOW rule 1 on purpose: a marking that re-completes a
# reopened story writes `done` rather than recording a reopen that the same
# marking just undid.
#
#   1. no `[ ]` and no deferred `[~]`           -> done
#   2. rule 1 did not fire, a `[ ]` remains,
#      and the status reads done | validated    -> in-progress   (the reopen edge)
#   3. rules 1-2 did not fire, status absent
#      or draft                                 -> in-progress
#   4. none fired                               -> write nothing
#
# A DEFERRED BOX BLOCKS RULE 1, deliberately: the work is settled in the plan
# and still owed in the world, and the persisted enum has no value for that —
# `done-except-external` is computed at read time and never written. This is the
# single sharpest difference between the two kinds of `[~]` and it is why the
# census keeps them apart.
#
# RULE 1 DOES NOT OVERWRITE A TERMINAL STATE. `superseded` and `archived` both
# legitimately sit over a fully-closed census, and validate-story.sh:914-918
# already says so in those words — "neither is a state rule 1 would overwrite
# with `done`" — while it decides which statuses its behind-the-checkboxes
# warning may fire on. Reading rule 1 as unconditional would make this script
# erase a supersede the first time a Quality Gate was settled on a superseded
# story. Anything else outside the six-value enum is left alone for the same
# reason: it is not a state this table describes.
STATUS_TO=""
if [[ "$CENSUS_TAKEN" == true ]]; then
  if [[ "$BOX_OPEN" -eq 0 && "$BOX_DEFERRED" -eq 0 ]]; then
    # `done` is a reserved word, so every one of these literals is quoted —
    # bare, it reads as the end of a loop that was never opened.
    case "$STATUS_FROM" in
      '' | 'draft' | 'in-progress' | 'validated' | 'done') STATUS_TO='done' ;;
      *) STATUS_TO="" ;;
    esac
  elif [[ "$BOX_OPEN" -gt 0 && ("$STATUS_FROM" == 'done' || "$STATUS_FROM" == 'validated') ]]; then
    STATUS_TO='in-progress'
  elif [[ -z "$STATUS_FROM" || "$STATUS_FROM" == 'draft' ]]; then
    STATUS_TO='in-progress'
  fi
fi

# --- 3d. The stamp -----------------------------------------------------------
# stamp_lines — ONE line of one artifact: the first `status:` inside the
# frontmatter block gets the new value, or the key is INSERTED before the
# closing `---` when the artifact has none (run-mode's third writing rule: "on a
# legacy story the Edit ADDS the field"). Everything else is copied byte for
# byte, the box this run just marked included.
#
# ONLY THE FIRST ONE, and a duplicate `status:` further down the block is left
# exactly where it is. Every reader of the field takes the first
# (validate-story.sh's `head -1`, archive-story.sh's, the index's), so the story
# reads as the value written here; deleting the other line would be this script
# editing something nobody asked it to edit, on the one path where it is
# already touching a file it does not own.
#
# THE INSERTED LINE TAKES THE ENDING OF THE `---` IT IS INSERTED IN FRONT OF.
# See rewrite_file's note: every ending this script writes comes off a line of
# the file itself. A bare `\n` added to a CRLF artifact is the defect this
# avoids, and it is one no `grep` for the new key would ever show.
# status_line <template-line> — the `status:` line to write, carrying the line
# ending of the line it is derived from: the `status:` being replaced, or the
# closing `---` an inserted key goes in front of. ONE reader of "where does this
# line end", so the replace path and the insert path cannot drift into two
# answers. (set_box does the same read inline and is deliberately left alone: it
# needs the CR AND the remainder with the CR taken off, which is a different
# operation on a line this step never touches.)
# shellcheck disable=SC2317,SC2329  # invoked indirectly: rewrite_file takes a
# line-emitter BY NAME, so shellcheck's reachability stops at the call site and
# marks this — and everything it calls — as dead. BOTH codes are needed and they
# are not interchangeable: 0.10+ reports SC2329 once per function, 0.9 (what CI
# installs) reports SC2317 once per COMMAND in the body.
status_line() {
  local cr=""
  if [[ "$1" == *$'\r' ]]; then
    cr=$'\r'
  fi
  printf '%s' "status: $STATUS_TO$cr"
}

# shellcheck disable=SC2317,SC2329  # invoked indirectly: rewrite_file takes a
# line-emitter BY NAME, so shellcheck's reachability stops at the call site and
# marks this — and everything it calls — as dead. BOTH codes are needed and they
# are not interchangeable: 0.10+ reports SC2329 once per function, 0.9 (what CI
# installs) reports SC2317 once per COMMAND in the body.
stamp_lines() {
  local line n=0 closed=false wrote=false terminated=true
  # `terminated` goes false only on a last line with no newline after it, and it
  # is mark_lines' rule for the same reason: re-emitting that line WITH a newline
  # would be a byte this script added to a file it was asked to edit one line of.
  while IFS= read -r line || { [[ -n "$line" ]] && terminated=false; }; do
    n=$((n + 1))
    if [[ "$n" -gt 1 && "$closed" == false ]]; then
      if [[ "$line" =~ $FM_DELIM_RE ]]; then
        closed=true
        if [[ "$wrote" == false ]]; then
          # INSERTED, in front of the closing delimiter — and always with its own
          # newline, even when that delimiter is an unterminated last line: the
          # one thing worse than a missing ending here is `status: done---`.
          printf '%s\n' "$(status_line "$line")" || return 1
          REWRITE_EMITTER_NL=$((REWRITE_EMITTER_NL + 1))
          wrote=true
        fi
      elif [[ "$wrote" == false && "${line%$'\r'}" == status:* ]]; then
        # REPLACED in place, so the line keeps its own ending and its own
        # termination — the emitter below decides that, exactly as for a line
        # this function did not touch at all.
        line=$(status_line "$line")
        wrote=true
      fi
    fi
    # EVERY EMITTING printf STATES ITS OWN FAILURE, and the newline tally is
    # witness C — rewrite_file, additions B and C. `set -e` is suspended for this
    # whole body, so a write that fails on a full disk is invisible unless asked.
    if [[ "$terminated" == true ]]; then
      printf '%s\n' "$line" || return 1
      REWRITE_EMITTER_NL=$((REWRITE_EMITTER_NL + 1))
    else
      printf '%s' "$line" || return 1
    fi
  done
  return 0
}

# stamp_artifact <file> — 0 written · 1 nothing to write · 2 the write failed.
# supersede-story.sh:785-794's flip_artifact shape, and the three outcomes are
# genuinely different things to report: an artifact with no frontmatter is
# SKIPPED in silence (run-mode: "there is no line to edit, and its silence is
# never counted as divergence"), an artifact already reading the new value needs
# no write at all, and only a real failure is worth a line on stderr.
stamp_artifact() {
  local f="$1"
  read_frontmatter "$f" || return 2
  [[ "$FM_HAS" == true ]] || return 1
  [[ "$FM_STATUS" != "$STATUS_TO" ]] || return 1
  rewrite_file "$f" stamp_lines || return 2
  return 0
}

# EVERY `.md` OF THE STORY, not a hard-coded three. run-mode names story.md,
# design.md and tasks.md and then states the rule they are examples of — "every
# artifact of the story that carries frontmatter". validate-story.sh:922 walks
# `"$STORY_DIR"/*.md` to decide which artifacts declare a status and which of
# them diverge, and supersede-story.sh:799-811 walks the same glob to flip them;
# a stamp over a narrower set would leave behind exactly the artifact the
# validator then reports as divergent.
STAMPED=()        # basenames that took the new value
STAMP_FAILED=()   # basenames that could not
stamp_all() {
  local f name rc
  for f in "$STORY_PATH"/*.md; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f")
    rc=0
    stamp_artifact "$f" || rc=$?
    case $rc in
      0) STAMPED+=("$name") ;;
      1) : ;;
      *) STAMP_FAILED+=("$name") ;;
    esac
  done
  return 0
}

if [[ -n "$STATUS_TO" ]]; then
  stamp_all
  if [[ ${#STAMP_FAILED[@]} -gt 0 ]]; then
    # Reported, and the run continues (run-mode's fifth writing rule). Named,
    # because "a status write failed" without the artifact is not something
    # anyone can go and fix.
    printf 'Note: could not write status: %s into %s of story %s — the box is closed and the rest of the transition stands. Fix the artifact and re-run validation.\n' \
      "$STATUS_TO" "${STAMP_FAILED[*]}" "$STORY_ID" >&2
  fi
  if [[ ${#STAMPED[@]} -gt 0 ]]; then
    # R2.2 — the transition is IN THE OUTPUT, which is how Run mode makes its
    # archive offer on the trigger it already has: the offer keys on "this run
    # wrote `done`", never on the census, because a story that was already
    # `done` before the run started did not become finished here
    # (references/run-mode.md, "End of Run — Validator, archive, index" — cited
    # by name, not by line: story 010 moved that trigger from :583 to :687 and a
    # line number would have gone stale in the same commit that wrote it).
    # That distinction is exactly the difference
    # between `{"from": …, "to": "done"}` and the `null` below.
    STATUS_WRITTEN_JSON="{ \"from\": $(json_or_null "$STATUS_FROM"), \"to\": $(json_or_null "$STATUS_TO") }"
  fi
fi
# STATUS_WRITTEN_JSON stays `null` on every other path, and it means what it has
# meant since 1.1: nothing was written. Rule 4 wrote nothing; a rule that fired
# on a story whose artifacts already read the new value wrote nothing (that is
# rule 1's "nothing to do if the field already reads done"); a story whose
# artifacts carry no frontmatter has no line to write. None of the three is a
# transition, and reporting one would send Run mode to an archive offer for a
# story it did not finish.

# ============================================================================
# STEP 4 — SELF-INVOKED VALIDATION (sub-task 2.2 — R1.5/R2.3/R2.4)
# ============================================================================
# WHY THIS STEP EXISTS AT ALL. Until this script, a checkbox was marked with the
# Write tool and hooks/hooks.json fired hook-validate.sh on it — a PostToolUse
# hook that ran validate-story.sh over the story every single marking. A BASH
# WRITE FIRES NO PostToolUse HOOK. Moving the marking into a script therefore
# deletes that guarantee unless the script carries it itself, which is what R2.3
# asks for and what this step is: the per-marking validation is preserved BY
# CONSTRUCTION rather than left to a hook that no longer runs.
#
# IT RUNS LAST — after the box write (step 2) AND after the status stamp (step
# 3d) — and both halves of that are load-bearing, not stylistic:
#
#   * BEFORE THE BOX WRITE it would describe a story the caller never sees. The
#     census and the transition in the same report are measurements of the file
#     AFTER the marking; a verdict taken before it would be the one field of the
#     object describing a different file, and the caller has no way to tell.
#
#   * BETWEEN THE WRITE AND THE STAMP it would author the very warning the
#     transaction exists to prevent. MEASURED, on the clean fixture of
#     tests/close-subtask-transaction.bats: run there, the verdict comes back
#     `warnings: 1` — "status is behind the checkboxes: design.md says
#     'in-progress' but no task checkbox is still open and none is deferred —
#     run-mode rule 1 writes 'done' at that point". Run after the stamp, on the
#     same fixture: `warnings: 0`. The script would have been reporting a
#     complaint about a state it was one statement away from fixing, and step
#     3's whole point is that a marking and its status move together.
#     validate-story.sh:992-999 names that transient as legitimate for OTHER
#     readers precisely because it is transient — this script's own reader has
#     no excuse to catch it.
#
# NOTHING HERE ROLLS ANYTHING BACK (R2.4). The box is closed, the status is
# stamped, and a verdict is a STATEMENT ABOUT that file, not a veto over it: the
# box state is the truth of what happened, and correcting a story the validator
# is unhappy with is a follow-up action. So this step writes nothing, refuses
# nothing, and changes no exit code — a close whose story fails validation is a
# close that SUCCEEDED and a story that has errors, and the report carries both.
#
# Resolved from THIS script's own location, not from PATH and not from the cwd:
# the validator is a sibling shipped with the plugin, and this script is invoked
# from wherever the operator happens to be (archive-story.sh:2682-2686 and
# supersede-story.sh:829-832 resolve their own sibling the same way). A relative
# `${BASH_SOURCE[0]}` is resolved against the cwd, so this would have to be
# computed before any `cd` — this script never changes directory (every `cd` it
# contains is inside a `$( )` subshell), so "here" and "load time" are the same
# instant. The failure is CARRIED, never fatal: a `VAR=$(cmd)` that fails under
# `set -e` would end the run with no JSON at all, after the box was written.
#
# A PLAIN `if`, NEVER `[[ … ]] && VAR=…`: a trailing AND-list that fails hands
# its status to the enclosing construct, and at top level under `set -e` that
# ends the script. The two siblings above both carry that shape and both would
# die on a story directory they could not resolve; it is deliberately not
# copied, for the reason already recorded in locate_box.
VALIDATE_SCRIPT=""
_epic_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2> /dev/null && pwd -P) || _epic_script_dir=""
if [[ -n "$_epic_script_dir" ]]; then
  VALIDATE_SCRIPT="$_epic_script_dir/validate-story.sh"
fi
unset _epic_script_dir

# THE THREE FIELDS THE CONTRACT EMBEDS, and only these three: validate-story.sh
# also reports `story`, `error_details`, `warning_details` and `strict`, and none
# of them belongs here. `story` is this report's own first field; the two detail
# arrays are the validator's output to read on its own, and copying them would
# make this object grow without bound with text nobody asked this script for.
# `{errors, warnings, status}` is the summary R1.5 names, and a caller that wants
# the details runs the validator — this report tells it whether that is worth
# doing.
VALIDATE_ERRORS=""
VALIDATE_WARNINGS=""
VALIDATE_STATUS=""
VALIDATE_ERR=""     # why there is no verdict, for the human on stderr

# THE VALIDATOR'S JSON IS PARSED IN BASH, WITH NO jq. archive-story.sh,
# supersede-story.sh and this script are the three writers with a JSON contract
# and not one of them forks jq — they render JSON by hand and they read it by
# hand, so a close never fails for want of a tool the marking itself does not
# need. (The hooks do use jq; they are already running inside an agent that has
# it. A story closed from a bare shell is not.)
#
# THE ANCHORS ARE WHAT MAKE THAT SAFE, and the safety is structural rather than
# hopeful. validate-story.sh emits every top-level key on its own line as
# `  "<key>": <value>` and every detail as `    "<escaped string>"<comma>` —
# and a detail string CANNOT forge a key line, because the only way a `"` gets
# into one is through its json_escape, which writes it `\"`. So a line matching
# `"errors":` — closing quote unescaped, immediately followed by the colon — is
# the real key and nothing else. Anchored at BOTH ends on top of that, so the
# value must also be the last thing on the line.
#
# `status` IS CONSTRAINED TO A BARE WORD rather than accepted as any string, and
# that is not paranoia about the validator: the text captured here is already in
# the validator's ESCAPED form, so running it through json_escape again would
# double every backslash it contains. Restricting it to a class that json_escape
# provably does not touch removes the round trip instead of trying to get it
# right — and it still goes through json_or_null below, because "every string in
# this report goes through the escaper" is a rule with no carve-out to forget.
# `pass` and `fail` are what validate-story.sh:1149-1153 emits today; the class
# is wide enough that a third verdict word would not need a change here.
VAL_ERRORS_RE='^[[:space:]]*"errors":[[:space:]]*([0-9]+)[[:space:]]*,?[[:space:]]*$'
VAL_WARNINGS_RE='^[[:space:]]*"warnings":[[:space:]]*([0-9]+)[[:space:]]*,?[[:space:]]*$'
VAL_STATUS_RE='^[[:space:]]*"status":[[:space:]]*"([A-Za-z][A-Za-z0-9_-]*)"[[:space:]]*,?[[:space:]]*$'

# parse_validate_json <text> — fills the triple, or returns 1 having filled
# nothing usable. FIRST MATCH WINS per field and each line fills AT MOST ONE
# field: the keys are emitted once each, and a compacted object that put two of
# them on one line would fail the parse rather than be half-read.
parse_validate_json() {
  local line
  VALIDATE_ERRORS=""
  VALIDATE_WARNINGS=""
  VALIDATE_STATUS=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$VALIDATE_ERRORS" && "$line" =~ $VAL_ERRORS_RE ]]; then
      VALIDATE_ERRORS="${BASH_REMATCH[1]}"
    elif [[ -z "$VALIDATE_WARNINGS" && "$line" =~ $VAL_WARNINGS_RE ]]; then
      VALIDATE_WARNINGS="${BASH_REMATCH[1]}"
    elif [[ -z "$VALIDATE_STATUS" && "$line" =~ $VAL_STATUS_RE ]]; then
      VALIDATE_STATUS="${BASH_REMATCH[1]}"
    fi
  done <<< "$1"
  # ALL THREE OR NONE. A partial triple is what a validator killed mid-emit
  # leaves behind, and reporting `errors: 0` off one is the fail-open answer.
  if [[ -z "$VALIDATE_ERRORS" || -z "$VALIDATE_WARNINGS" || -z "$VALIDATE_STATUS" ]]; then
    return 1
  fi
  return 0
}

# run_validate — 0 with the triple filled, 1 with VALIDATE_ERR saying why not.
#
# THE INVOCATION IS GUARDED, AND THAT GUARD IS THE POINT OF THE WHOLE STEP.
# validate-story.sh EXITS 1 WHEN THE STORY HAS ERRORS — measured, not assumed:
# on the transaction suite's calibrated fixture it exits 1 with `errors: 1`, and
# on the clean one it exits 0. Under `set -e` an unguarded call would therefore
# end this script exactly when it had something to report, AFTER the box was
# already written: a marking that landed on disk and produced no JSON at all,
# which is the worst outcome this contract has. `|| rc=$?` keeps the verdict.
#
# That is the 02/07 fail-open shape read from the other side, and both halves of
# it are refused here. hook-task-completed.sh:48-52 records the same trap from
# the swallowing side — a bare `OUTPUT=$(…)` inheriting the non-zero status and
# aborting the hook before its blocking exit could run. Here the status is
# captured AND used, never captured and dropped.
#
# ONLY STDOUT IS CAPTURED. archive-story.sh:2715 folds its child's stderr into
# the same variable because it parses none of it; this one parses exactly that
# variable, so `2>&1` would splice a diagnostic sentence into the JSON being
# read. The validator's stderr flows to ours instead, which is where every
# diagnostic in this script already goes — and its stdout, captured whole, can
# never reach ours.
#
# Run through `${BASH:-bash}` rather than executed: the validator carries a
# shebang but is not required to be executable (the test suite invokes it the
# same way), and naming the interpreter runs the child under the SAME bash that
# is running this script.
run_validate() {
  local out rc=0
  VALIDATE_ERR=""
  # `[[ -f ]]` says the file EXISTS, not that it opens — this arm is only here
  # to name the ordinary case (an older install, a partial checkout) with a
  # message someone can act on. One that exists and cannot be read fails below,
  # where bash's own diagnostic reaches stderr on its own.
  if [[ -z "$VALIDATE_SCRIPT" || ! -f "$VALIDATE_SCRIPT" ]]; then
    VALIDATE_ERR="the validator is not there (looked for '${VALIDATE_SCRIPT:-<the sibling validate-story.sh of this script>}')"
    return 1
  fi
  out=$("${BASH:-bash}" "$VALIDATE_SCRIPT" "$STORY_PATH") || rc=$?
  # 0 and 1 are the two codes that come WITH a verdict (validate-story.sh:1160-
  # 1165). 2 is its own invalid-input path, and anything else is a validator that
  # died, was not found, or was killed — none of them a story that was judged.
  if [[ "$rc" -ne 0 && "$rc" -ne 1 ]]; then
    VALIDATE_ERR="'$VALIDATE_SCRIPT' exited $rc without reaching a verdict"
    return 1
  fi
  if ! parse_validate_json "$out"; then
    VALIDATE_ERR="'$VALIDATE_SCRIPT' exited $rc but its output carried no readable errors/warnings/status triple"
    return 1
  fi
  # AN INDEPENDENT WITNESS THAT THE PARSE IS THE VERDICT — rewrite_file's
  # witness C, applied to a read instead of a write. The exit code is a second,
  # format-independent statement of the same fact: with no `--strict` (and none
  # is passed), validate-story.sh:1160-1165 exits 1 if and only if it counted at
  # least one error. So a parse that disagrees with the code is a parse that read
  # the wrong thing — a reformatted emitter, a truncated capture — and it is said
  # out loud instead of embedded. Silence here would be the fail-open answer once
  # more: a drifted parse reporting `errors: 0` over a story full of them.
  #
  # `rc` IS COMPARED AS A NUMBER AND THE COUNT AS A STRING, and the asymmetry is
  # deliberate. `rc` is an exit status this script captured itself, always 0-255.
  # The count is text read out of another process's stdout, and bash arithmetic
  # SILENTLY WRAPS a digit run past 64 bits — measured: `[[
  # 999999999999999999999999999 -gt 0 ]]` is FALSE. A wrapped count that tests as
  # zero is a fail-open the witness would then wave through, so the count is
  # never made to do arithmetic. `${#ERRORS[@]}` has no leading zeros, so `== 0`
  # is exactly "no errors". Same reasoning canon_num records one screen up.
  if [[ "$rc" -eq 0 && "$VALIDATE_ERRORS" != 0 ]] || [[ "$rc" -eq 1 && "$VALIDATE_ERRORS" == 0 ]]; then
    VALIDATE_ERR="'$VALIDATE_SCRIPT' exited $rc but its output reports $VALIDATE_ERRORS error(s) — the two disagree, so neither is reported"
    # CLEARED, for refuse()'s reason one screen up: these three report what was
    # MEASURED, and this arm has just decided the measurement is not one. Every
    # other failure arm above returns before the parse could fill them; this is
    # the one that returns with them full, and leaving them there would arm a
    # later reader with a value this function refused to stand behind.
    VALIDATE_ERRORS=""
    VALIDATE_WARNINGS=""
    VALIDATE_STATUS=""
    return 1
  fi
  return 0
}

if run_validate; then
  # The counts are bare JSON numbers and they are provably numeric — the parse
  # captured them through `([0-9]+)` and nothing else could have filled them.
  # The status is a string and goes through the escaper like every other string
  # in this object.
  VALIDATE_JSON="{ \"errors\": $VALIDATE_ERRORS, \"warnings\": $VALIDATE_WARNINGS, \"status\": $(json_or_null "$VALIDATE_STATUS") }"
else
  # `null` keeps meaning what it has meant since 1.1: NOBODY MEASURED. It is the
  # one honest answer here, and specifically not `{"errors": 0}` — a verdict that
  # was never reached, rendered as one that came back clean, is the fail-open
  # report this whole step exists to refuse. The close still stands and still
  # exits 0: the marking is not undone because the validator could not be run
  # (R2.4), it is reported without a verdict beside it.
  printf 'Note: the box was closed and the status transition stands, but the story could not be validated — %s. Run validate-story.sh on %s to see where the story stands.\n' \
    "$VALIDATE_ERR" "$STORY_PATH" >&2
fi

emit_report
exit 0
