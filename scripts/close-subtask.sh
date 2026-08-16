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
# say BEFORE anything is written, and the box write, the group-header repair and
# the status stamp are ONE atomic rewrite — never a sequence a reader can catch
# half-done:
#   1. parse, resolve, refusal arms ..... sub-task 1.1 (implemented)
#   2. locate and mark the box .......... sub-task 1.2 (implemented — R1.1/R1.2/R1.3/R1.6/R1.7)
#   3. census + status transition ....... sub-task 2.1 (pending — R2.1/R2.2)
#   4. self-invoked validate-story.sh ... sub-task 2.2 (pending — R2.3)
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
STATUS_WRITTEN_JSON="null"   # {from, to} once sub-task 2.1 writes a transition
VALIDATE_JSON="null"         # {errors, warnings, status} once sub-task 2.2 runs

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
# No `eol_of`/`REWRITE_EOL` here, and that is not an omission: this script ADDS
# no lines. It replaces one character on lines the file already has and appends
# to them BEFORE their own ending (set_box), which preserves each line's ending
# individually — strictly stronger than a file-level guess, and correct on a
# file with mixed endings too. A future step that appends a line (2.1 stamping a
# `status:` into frontmatter that has none) will need eol_of; copy it then.
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
  REWRITE_EMITTER_RC=0
  REWRITE_EMITTER_NL=0
  { "$emitter" || REWRITE_EMITTER_RC=$?; :; } 2> /dev/null < "$f" > "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if [[ "$REWRITE_EMITTER_RC" -ne 0 ]]; then
    rm -f "$tmp"
    return 1
  fi
  # Witness C. `-1` on a failed measurement is not a count any emitter can
  # report, so an unmeasurable tmp is a tmp that does not get renamed. The
  # whitespace strip is not decoration: `wc -l` pads its number on some
  # implementations and not on GNU's, and this is a string comparison.
  landed=$(wc -l < "$tmp" 2> /dev/null) || landed=-1
  landed="${landed//[[:space:]]/}"
  if [[ "$landed" != "$REWRITE_EMITTER_NL" ]]; then
    rm -f "$tmp"
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
    rm -f "$tmp"
    return 1
  }
  chmod "$FILE_MODE" "$tmp" 2> /dev/null || {
    rm -f "$tmp"
    return 1
  }
  mv -f "$tmp" "$f" || {
    rm -f "$tmp"
    return 1
  }
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
emit_report
exit 0
