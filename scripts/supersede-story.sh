#!/usr/bin/env bash
# Supersedes story NNN with story MMM — the MECHANICAL half of the supersede
# operation (references/supersede-mode.md; design.md component 3, amended v8).
#
# Usage: bash scripts/supersede-story.sh <NNN|story-dir> --by <MMM>
#        [--rationale <text>] [--remap <N.N=target>]...
#
# Exit 0 = superseded (a fresh run) or completed (an interrupted run finished)
# Exit 1 = refused — the refusal matrix, or a banner-bearing state this command
#          cannot produce. Nothing is written on a refusal.
# Exit 2 = invalid input (unknown flag, missing --by, unresolvable story)
#
# Output: ONE JSON object on stdout on every path that reaches a verdict, so a
# consumer can pipe stdout straight into jq. Usage errors (exit 2) print no JSON
# at all — there is no story to report on yet (the convention validate-story.sh
# and archive-story.sh already share).
#
# TWO DOCUMENTED EXCEPTIONS to "JSON on stdout", both of which reach no verdict:
#   --help/-h  prints usage prose on stdout and exits 0 (no story is resolved).
#   exit 2     usage errors, as above: stderr only.
#
# SILENT ON STDERR WHERE archive-story.sh TALKS — A DELIBERATE DIVERGENCE FROM
# THE SIBLING, NOT AN OVERSIGHT. DO NOT "RESTORE" THE DIAGNOSTICS. Archive
# prints `Refused: …` for the human and reports the same thing in JSON; this
# script prints nothing at all on any path that emits JSON. Two reasons, and the
# first one is FORCING:
#   1. bats' `run` MERGES stderr into `$output` unless it is told not to
#      (`--separate-stderr`), so a diagnostic lands in the middle of the object
#      the caller is parsing. Thirteen of the fifteen cases in
#      tests/supersede-story.bats pipe that `$output` into jq. One byte on
#      stderr turns every one of them red — and, more to the point, would turn
#      any consumer that pipes stdout into jq red the same way. Silence keeps
#      "one JSON object on stdout" true for every caller, not only the careful
#      ones.
#   2. The split design.md component 3 makes: supersede's CONVERSATION belongs
#      to the orchestrator, which reads `reason` / `index_error` out of the
#      report and says them in the session's own voice. A second,
#      differently-worded copy on stderr would be a second author for the same
#      sentence.
# Exit 2 is the exception and keeps speaking on stderr: it reaches no verdict,
# emits no JSON, and there is nothing for a consumer to parse.
#
# STEP ORDER IS LOAD-BEARING (references/supersede-mode.md, Procedure):
#   1. verify ............ rows 1-3 of the refusal matrix; any hit refuses
#                          before anything is written
#   2. banner ............ written ONLY when NNN carries no banner AT ALL. The
#                          guard is positive on purpose: a banner-bearing story
#                          is handed to the recovery classification first, whose
#                          rows are disjoint AND exhaustive, so no state can
#                          fall through to a second banner (R3.5)
#   3. close, THEN flip .. every open sub-task closes as `[~] (superseded-by:
#                          MMM)` first; only then does `status: superseded` plus
#                          `superseded-by: MMM` land in every artifact. The
#                          status write is the COMMIT POINT: doing it first
#                          would leave an interruption looking finished with
#                          unremapped scope still open
#   4. index ............. regenerated; a non-zero exit warns in the report and
#                          never blocks — the index is a RENDERING of the op
#   5. offer ............. NOT here. The archive offer is conversational and
#                          stays with the orchestrator (design.md component 3).
#
# The `Edit`-not-`Write` constraint of the prose procedure is met by
# construction: the validate hook's PostToolUse matcher observes Claude's tool
# calls, and this script's own writes are not tool calls at all.

set -euo pipefail

USAGE='Usage: supersede-story.sh <NNN|story-dir> --by <MMM> [--rationale <text>] [--remap <N.N=target>]...'

print_help() {
  cat <<'HELP'
Usage: supersede-story.sh <NNN|story-dir> --by <MMM> [--rationale <text>]
                          [--remap <N.N=target>]...

Supersedes story NNN with story MMM: the supersede banner, one remap row per
open sub-task, every open sub-task closed as `[~] (superseded-by: MMM)`, and
`status: superseded` plus `superseded-by: MMM` in every artifact — closures
first, status writes last.

Arguments:
  <NNN|story-dir>   Story being superseded: number (006) or directory
                    (.epic/stories/006-slug)

Flags:
  --by <MMM>        REQUIRED. The replacement story, which must already exist —
                    creating it is a separate operation, so a typo here can
                    never mint a story.
  --rationale <t>   The one-line reason, asked from the user at op time. A
                    default is recorded when it is omitted.
  --remap <N.N=t>   Where sub-task N.N's scope went. Repeatable. The default is
                    `MMM / re-scoped`; `--remap 1.2=dropped: reason` records
                    scope that dies with the story.
  --help, -h        Show this help

Output: JSON on stdout — {story, path, by, status, reason, banner_written,
remap_rows, closed_subtasks, artifacts_flipped[], index, index_error}.

Exit codes:
  0  Superseded (fresh run), or completed (an interrupted run finished)
  1  Refused — nothing was written
  2  Invalid input (unknown flag, missing --by, unresolvable story)
HELP
}

# --- Report state -----------------------------------------------------------
# Every field of the JSON contract lives in a variable so that ONE emitter
# renders every exit path: a caller can jq the same shape whatever happened.
STORY_ID=""            # canonical identity of NNN, e.g. 006-widget-flow
STORY_PATH=""          # path as resolved (kept relative when given relative)
BY_NUM=""              # MMM as it is written into artifacts, e.g. 012
BY_ID=""               # MMM's canonical identity, e.g. 012-successor
STATUS=""              # superseded | completed | refused
REASON=""              # human-readable why, for refused
BANNER_WRITTEN=false   # JSON boolean literal — true only when THIS run wrote it
REMAP_ROWS=0           # rows generated by THIS run (recovery writes none)
CLOSED_SUBTASKS=0      # boxes closed by THIS run
ARTIFACTS_FLIPPED=()   # artifacts THIS run wrote the status pair into
INDEX_STATE="skipped"  # ok | regen-failed | skipped (step 4 never ran)
                       # `skipped` is the INITIAL value and means exactly that:
                       # a refusal exited before step 4, so the index still
                       # matches the disk. It is never written by step 4 itself.
INDEX_ERR=""

# --- String quoting ---------------------------------------------------------
# EVERY string this script emits as JSON goes through json_escape. The inputs
# are arbitrary by construction: `--rationale` is typed (or pasted, control
# codes and all) by a human, and a title is copied out of tasks.md.
#
# The escape set is JSON's (RFC 8259 §7): U+0000-U+001F, plus the quote and the
# backslash. It is deliberately NARROWER than archive-story.sh's, whose table is
# the UNION of JSON's and YAML's because it also writes manifest.yaml — DEL and
# the C1 block are illegal in YAML and perfectly legal inside a JSON string.
# This script writes no YAML, so escaping them would be re-encoding rather than
# quoting. NUL needs no entry: a bash string cannot hold one.
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

json_array() {
  local arr=("$@")
  local len=${#arr[@]} i comma
  if [[ $len -eq 0 ]]; then
    printf '[]'
    return 0
  fi
  printf '['
  for i in "${!arr[@]}"; do
    comma=","
    [[ $i -eq $((len - 1)) ]] && comma=""
    printf '"%s"%s' "$(json_escape "${arr[$i]}")" "$comma"
  done
  printf ']'
}

emit_report() {
  local flipped
  # ${arr[@]+"${arr[@]}"} — not plain "${arr[@]}": expanding an EMPTY array that
  # way is an unbound-variable abort under `set -u` on bash < 4.4 (macOS ships
  # 3.2), and this emitter runs on every refusal, where the array is empty.
  flipped=$(json_array ${ARTIFACTS_FLIPPED[@]+"${ARTIFACTS_FLIPPED[@]}"})
  cat <<JSON
{
  "story": "$(json_escape "$STORY_ID")",
  "path": "$(json_escape "$STORY_PATH")",
  "by": "$(json_escape "$BY_NUM")",
  "status": "$(json_escape "$STATUS")",
  "reason": "$(json_escape "$REASON")",
  "banner_written": $BANNER_WRITTEN,
  "remap_rows": $REMAP_ROWS,
  "closed_subtasks": $CLOSED_SUBTASKS,
  "artifacts_flipped": $flipped,
  "index": "$(json_escape "$INDEX_STATE")",
  "index_error": "$(json_escape "$INDEX_ERR")"
}
JSON
}

# --- Terminators ------------------------------------------------------------
# usage_error: invalid input. No JSON — nothing has been resolved to report on,
# and this is the ONE path allowed to speak on stderr.
usage_error() {
  printf 'Error: %s\n' "$1" >&2
  printf '%s\n' "$USAGE" >&2
  exit 2
}

# refuse: the matrix said no, a banner-bearing state cannot be honestly
# completed, or one of step 3's writes failed. WHAT HAS BEEN WRITTEN BY THEN
# DEPENDS ON WHERE THE REFUSAL IS RAISED — this comment used to claim
# "nothing, by construction", which two of the call sites below break:
#   - Story resolution, step 1 and step 2 leave the story untouched by THIS
#     run, and each of those refusals says so in its own message. The three
#     recovery arms do refuse over a banner, but it is a PRIOR run's; and
#     insert_banner writes through rewrite_file, which renames a temp file
#     into place, so a failed banner write leaves the artifact byte-identical.
#   - Step 3's two — the closure rewrite and the status flip — run AFTER the
#     banner is in place, the flip after the closures, and flip_all can have
#     flipped some artifacts before failing. That is close-then-flip working
#     as designed (R3.3): the story is left visibly unfinished, never falsely
#     complete, and a re-run finishes it. Their messages say so as well.
# The REPORT is what says which of the two happened, not this comment:
# emit_report runs on every refusal, and its banner_written, closed_subtasks
# and artifacts_flipped carry exactly what this run wrote.
refuse() {
  STATUS="refused"
  REASON="$1"
  emit_report
  exit 1
}

# finish: the one success terminator. `superseded` is a fresh run, `completed`
# an interrupted one carried over the line.
finish() {
  STATUS="$1"
  emit_report
  exit 0
}

# --- Artifact readers -------------------------------------------------------
# Frontmatter parsing follows archive-story.sh: a leading `---` line, the block
# up to the next `---`, and keys anchored at column 0 so a nested key can never
# fake a value. The delimiter regex tolerates a trailing `\r`: on a checkout
# with core.autocrlf=true every artifact ends `---\r`, and a reader that rejects
# it does not fail loudly — it makes the file look like it has no frontmatter,
# which here would mean "no status to flip" and would leave the story's
# artifacts contradicting each other.
FM_DELIM_RE=$'^---\r?$'

frontmatter_field() {
  local file="$1" key="$2" front val
  [[ -f "$file" ]] || return 0
  head -1 "$file" | grep -Eq "$FM_DELIM_RE" 2> /dev/null || return 0
  front=$(sed -En "2,/${FM_DELIM_RE}/p" "$file" | sed '$d') || return 0
  val=$(printf '%s\n' "$front" | grep -E "^$key:" | head -1 | sed "s/.*$key:[[:space:]]*//") || val=""
  # A YAML comment starts at a `#` preceded by whitespace (or at the value's
  # very start); a `#` glued to text is part of the value.
  if [[ "$val" == '#'* ]]; then
    val=""
  elif [[ "$val" =~ ^(.*[[:space:]])#.*$ ]]; then
    val="${BASH_REMATCH[1]}"
  fi
  # Trim the edges only — `[:space:]` covers the trailing `\r` of a CRLF line.
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  printf '%s' "$val"
}

# has_frontmatter <file> — a file with an OPENING and a CLOSING delimiter. Both
# halves matter: an unmatched opener would make the whole file read as
# frontmatter, and the flip would then write its keys past the end of the world.
has_frontmatter() {
  local f="$1" line n=0
  [[ -f "$f" ]] || return 1
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      n=$((n + 1))
      if [[ $n -eq 1 ]]; then
        [[ "$line" =~ $FM_DELIM_RE ]] || return 1
        continue
      fi
      [[ "$line" =~ $FM_DELIM_RE ]] && return 0
    done
    :
  } 2> /dev/null < "$f" || return 1
  return 1
}

# eol_of <file> — $'\r' when the file is CRLF, empty otherwise. Every line this
# script WRITES into an artifact takes the file's own line ending, so a CRLF
# artifact does not end up with mixed endings that its next reader has to guess.
eol_of() {
  local f="$1"
  if head -1 "$f" 2> /dev/null | grep -q $'\r$' 2> /dev/null; then
    printf '%s' $'\r'
  fi
}

# trim <string> — strip leading and trailing whitespace, no fork.
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

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
# archive/ (an already-archived number must resolve so it can be REFUSED with
# its real reason instead of "not found"). Accepts 6 for 006.
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

# story_number <name> — the leading digits of a story identity, e.g. 006 from
# `006-widget-flow`. Empty when there are none.
story_number() {
  local name="$1"
  [[ "$name" =~ ^([0-9]+) ]] && printf '%s' "${BASH_REMATCH[1]}"
}

# --- The task list ----------------------------------------------------------
# ONE grammar, shared with validate-story.sh / archive-story.sh / epic-index.sh
# (references/tasks.md#checkbox-grammar):
#   - [ ] open   - [x] done   - [~] closed without doing the work, qualified
# Matching of the `[~]` qualifier is TOKEN-ANCHORED, so `man-a:` inside a title
# does not qualify anything.
SUBTASK_RE='^([[:space:]]*)- \[([ x~])\][[:space:]]+([0-9]+\.[0-9]+)[[:space:]]+-[[:space:]]+(.*)$'
DEFERRED_RE='(^|[^[:alnum:]_-])deferred:'
QUALIFIER_RE='^(.*[^[:space:]])[[:space:]]*\((deferred|waived|n-a|superseded-by):[^)]*\)[[:space:]]*$'

# OPEN scope, and the definition is R3.2's: every `[ ]` and every
# `[~] (deferred: …)`. Deferred work is still owed, so it must land somewhere;
# `[x]` and a TERMINAL `[~]` are settled and a row for either would claim scope
# moved that never did.
OPEN_NUMS=()
OPEN_TITLES=()

# scan_open_subtasks <tasks.md> — fills OPEN_NUMS/OPEN_TITLES. Sub-tasks ONLY,
# which is what `N.N` numbering selects: a task GROUP (`- [ ] 1 - Group`) is a
# header over the sub-tasks below it, not scope of its own, and a remap row for
# it would double-count the work its children already carry. Quality Gates carry
# no number and are likewise not scope.
#
# READING IS FALLIBLE: `[[ -f ]]` says the file EXISTS, not that it opens, and a
# bare failed redirection under `set -e` would end the run with no JSON on
# stdout at all — the one thing the output contract promises never happens.
scan_open_subtasks() {
  local file="$1" line box num title
  OPEN_NUMS=()
  OPEN_TITLES=()
  [[ -f "$file" ]] || return 0
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ "$line" =~ $SUBTASK_RE ]] || continue
      box="${BASH_REMATCH[2]}"
      num="${BASH_REMATCH[3]}"
      title="${BASH_REMATCH[4]}"
      case "$box" in
        'x') continue ;;
        '~')
          [[ "$title" =~ $DEFERRED_RE ]] || continue
          ;;
      esac
      # The qualifier is stripped from the title here, so the remap row and the
      # closure both read the WORK, not the bookkeeping that parked it.
      if [[ "$title" =~ $QUALIFIER_RE ]]; then
        title="${BASH_REMATCH[1]}"
      fi
      OPEN_NUMS+=("$num")
      OPEN_TITLES+=("$(trim "$title")")
    done
    :
  } 2> /dev/null < "$file" || return 1
  return 0
}

# --- Writing an artifact ----------------------------------------------------
# Every destructive write in this script is the same shape — read the artifact,
# emit a transformed copy, put it back — and the shape has three sharp edges
# that are easy to get wrong once each. They are handled HERE, once, so the
# three transformations below are only ever about WHAT to emit:
#
#   1. `[[ -f ]]` says a file EXISTS, not that it opens. A bare failed
#      redirection under `set -e` ends the run with no JSON on stdout at all —
#      the one thing the output contract promises never happens. The
#      `{ …; :; } 2>/dev/null < in > out || …` form is the one that actually
#      catches it: `2>` BEFORE `<` suppresses bash's own message, `||` catches
#      the failed redirection (an `if ! { …; } < f` does NOT — it reads as
#      success), and the trailing `:` pins the group's status to the
#      redirection rather than to whatever the loop body last evaluated.
#   2. The temp file is REMOVED on failure. A half-written `.tmp` beside an
#      artifact is litter that the next reader has to know to ignore.
#   3. The rename is what makes the write atomic: an interruption leaves the
#      ORIGINAL, never a truncated artifact. That matters more here than
#      anywhere else in the plugin, because an interrupted supersede is a state
#      recovery is expected to finish — and it can only finish from artifacts
#      that are still parseable.
#
# The emitter is a plain function reading stdin and writing stdout. It is CALLED
# rather than piped or substituted, so it runs in THIS shell: an emitter that
# counts what it changed (close_lines) keeps its count.
REWRITE_EOL=""   # the artifact's own line ending, for the lines an emitter ADDS

rewrite_file() {
  # ONE NAME PER `local`, and do NOT fold these back into one statement: in
  # bash 5.3 a `local a=1 b=$a` declares BOTH names first, so `$a` expands to
  # the just-declared (still unset) local and the run aborts under `set -u`.
  # The first version of this script did fold them, and every write path died
  # on `f: unbound variable`.
  local f="$1"
  local emitter="$2"
  local tmp="$f.epic-supersede.tmp"
  REWRITE_EOL=$(eol_of "$f")
  { "$emitter"; :; } 2> /dev/null < "$f" > "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv -f "$tmp" "$f" || {
    rm -f "$tmp"
    return 1
  }
  return 0
}

# --- The banner (step 2) ----------------------------------------------------
# The template is references/supersede-mode.md's, VERBATIM — the ⛔, the em
# dashes, the table, the closing sentence, and the scope cell's literal `task `
# prefix. The prefix is the spec's, not a preference: the template's placeholder
# reads `<task N.N — title>` and the walkthrough renders
# `| task 2.1 — Map legacy fields to the new schema | 051 / re-scoped |`.
# It looks redundant under a column already headed "This story's open scope",
# and dropping it is exactly the kind of tidy-up that silently forks a shipped
# artifact shape away from the document that defines it. It stays.

# md_cell <text> — a value safe inside a markdown table cell. A `|` would end
# the cell and shift every column after it; titles and remap targets are
# arbitrary text from an artifact or from the command line.
# shellcheck disable=SC2317,SC2329  # invoked indirectly: `rewrite_file <file>
# <fn>` takes a line-emitter by NAME, so shellcheck's reachability stops at the
# call site and marks this — and everything it calls — as dead. BOTH codes are
# needed and they are not interchangeable: 0.10+ reports SC2329 once per
# function, 0.9 (what CI installs) reports SC2317 once per COMMAND in the body.
md_cell() {
  local s="$1"
  s=${s//$'\r'/ }
  s=${s//$'\n'/ }
  s=${s//|/\\|}
  printf '%s' "$s"
}

# remap_target <N.N> — the "Where it went" cell for one sub-task. `--remap`
# supplies it row by row (the conversational half of the op collects them);
# unanswered rows take the default the spec names, `MMM / re-scoped`, so a
# headless run never pauses and never invents a destination.
REMAP_KEYS=()
REMAP_VALS=()
# shellcheck disable=SC2317,SC2329  # invoked indirectly: `rewrite_file <file>
# <fn>` takes a line-emitter by NAME, so shellcheck's reachability stops at the
# call site and marks this — and everything it calls — as dead. BOTH codes are
# needed and they are not interchangeable: 0.10+ reports SC2329 once per
# function, 0.9 (what CI installs) reports SC2317 once per COMMAND in the body.
remap_target() {
  local num="$1" i
  for i in "${!REMAP_KEYS[@]}"; do
    if [[ "${REMAP_KEYS[$i]}" == "$num" ]]; then
      printf '%s / %s' "$BY_NUM" "${REMAP_VALS[$i]}"
      return 0
    fi
  done
  printf '%s / re-scoped' "$BY_NUM"
}

# bline <text> — one banner line, carrying the artifact's own line ending.
# `printf '%s%s\n'` and never `printf "$text"`: a title or a rationale is
# arbitrary text, and a `%` or a `\t` in it must reach the file as itself.
# shellcheck disable=SC2317,SC2329  # invoked indirectly: `rewrite_file <file>
# <fn>` takes a line-emitter by NAME, so shellcheck's reachability stops at the
# call site and marks this — and everything it calls — as dead. BOTH codes are
# needed and they are not interchangeable: 0.10+ reports SC2329 once per
# function, 0.9 (what CI installs) reports SC2317 once per COMMAND in the body.
bline() {
  printf '%s%s\n' "$1" "$REWRITE_EOL"
}

# render_banner — the banner block on stdout, the template verbatim.
# shellcheck disable=SC2317,SC2329  # invoked indirectly: `rewrite_file <file>
# <fn>` takes a line-emitter by NAME, so shellcheck's reachability stops at the
# call site and marks this — and everything it calls — as dead. BOTH codes are
# needed and they are not interchangeable: 0.10+ reports SC2329 once per
# function, 0.9 (what CI installs) reports SC2317 once per COMMAND in the body.
render_banner() {
  local i num
  bline "> ## ⛔ SUPERSEDED ($OP_DATE) — by story $BY_ID"
  bline "> $RATIONALE"
  bline ">"
  if [[ ${#OPEN_NUMS[@]} -eq 0 ]]; then
    # A header row with no data rows renders as an empty table that still
    # announces "here is where the scope went" — for a story with no open scope
    # that is a claim about nothing. Say so in words instead.
    bline "> No open scope to remap — every sub-task was already settled."
  else
    bline "> | This story's open scope | Where it went |"
    bline "> |---|---|"
    for i in "${!OPEN_NUMS[@]}"; do
      num="${OPEN_NUMS[$i]}"
      bline "> | task $num — $(md_cell "${OPEN_TITLES[$i]}") | $(md_cell "$(remap_target "$num")") |"
    done
  fi
  bline ">"
  bline "> Do not execute. Kept for traceability; numbers are never recycled."
}

BANNER_PENDING_FM=false   # set by insert_banner, read by banner_lines

# banner_lines — the emitter. Copies the frontmatter through untouched, opens
# the body with the banner, and puts back exactly one blank line between the two
# halves. A file with NO frontmatter takes the same path with the copy-through
# phase already finished, so "the banner goes first" needs no second branch:
# nothing can be above it in a file that makes no lifecycle claim.
# shellcheck disable=SC2317,SC2329  # invoked indirectly: `rewrite_file <file>
# <fn>` takes a line-emitter by NAME, so shellcheck's reachability stops at the
# call site and marks this — and everything it calls — as dead. BOTH codes are
# needed and they are not interchangeable: 0.10+ reports SC2329 once per
# function, 0.9 (what CI installs) reports SC2317 once per COMMAND in the body.
banner_lines() {
  local line n=0 started=false
  local in_fm="$BANNER_PENDING_FM"
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    if [[ "$in_fm" == true ]]; then
      printf '%s\n' "$line"
      [[ $n -gt 1 && "$line" =~ $FM_DELIM_RE ]] && in_fm=false
      continue
    fi
    if [[ "$started" == false ]]; then
      # Swallow the artifact's own blank separator first: re-creating it BELOW
      # the banner is what makes the banner the first thing under the
      # frontmatter, which is what "prepend" means here.
      [[ -z "$(trim "${line%$'\r'}")" ]] && continue
      render_banner
      bline ""
      started=true
    fi
    printf '%s\n' "$line"
  done
  # A story.md that is nothing BUT frontmatter still gets its banner.
  [[ "$started" == false ]] && render_banner
  return 0
}

# insert_banner <file> — prepend the banner immediately below the frontmatter
# block, before any other content. The blank line the artifact used to separate
# frontmatter from body is re-created BELOW the banner rather than above it, so
# the banner is the first thing a reader opening the file sees.
insert_banner() {
  BANNER_PENDING_FM=false
  has_frontmatter "$1" && BANNER_PENDING_FM=true
  rewrite_file "$1" banner_lines
}

# banner_present <file> — the guard step 2 reads, and it is DELIBERATELY LOOSE:
# any `⛔ SUPERSEDED` anywhere in the file counts. A tighter match (the exact
# heading this script writes) would let a hand-made or older banner slip past
# and become a second one, and R3.5 forbids a second banner unconditionally —
# the guard is positive ("write only when there is none"), so being generous
# about what counts as a banner is the fail-closed direction.
banner_present() {
  grep -q '⛔ SUPERSEDED' "$1" 2> /dev/null
}

# --- The two observations recovery classifies on ----------------------------
# Neither asks "is there a banner" — that question is already answered by the
# time these are called, and answering it twice is what let a *complete* prior
# run and an *interrupted* one collide at design v3. Completeness is what
# separates them, and it is these two axes.

# status_state — n/a | none | some | all, over the artifacts that HAVE
# frontmatter. An artifact without one makes no lifecycle claim, so it cannot be
# missing a status write either; counting it would make `all` unreachable in any
# story that carries a README.
#
# `n/a` is the fourth value the spec's table does not enumerate, because only
# the tasks.md banner fallback can reach it: a story where NO artifact carries
# frontmatter has no status to write, so the axis is not observable — not
# "nothing written yet". Reporting it as `none` is what a first draft did, and
# it made every re-run of such a story answer `completed` forever: `none` can
# never become `all`, so the *Complete* row was unreachable and R3.5's refusal
# with it. Reporting it as `all` fails the other way, refusing an interrupted
# run as unproducible. The axis is genuinely absent, so it says so, and the two
# cells below decide on the box axis alone — which is all completeness can mean
# when there is no status to write.
status_state() {
  local f total=0 flipped=0
  for f in "$STORY_PATH"/*.md; do
    [[ -f "$f" ]] || continue
    has_frontmatter "$f" || continue
    total=$((total + 1))
    [[ "$(frontmatter_field "$f" status)" == "superseded" ]] && flipped=$((flipped + 1))
  done
  if [[ $total -eq 0 ]]; then
    printf 'n/a'
  elif [[ $flipped -eq 0 ]]; then
    printf 'none'
  elif [[ $flipped -eq $total ]]; then
    printf 'all'
  else
    printf 'some'
  fi
}

# open_state — yes | no. The same OPEN_NUMS the remap rows are built from, so
# "what is still owed" cannot drift between the banner and the classification.
open_state() {
  if [[ ${#OPEN_NUMS[@]} -gt 0 ]]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

# --- Closure (step 3, first half) -------------------------------------------
# Every open sub-task closes as `[~] (superseded-by: MMM)`, qualifier on the
# same line per story 004's grammar. On a DEFERRED box the `deferred:` qualifier
# is REPLACED, never joined: a line carrying both stays owed, because
# `deferred:` wins the census — and a story that still owes work is not the
# terminal, archivable state this step exists to reach.
# shellcheck disable=SC2317,SC2329  # invoked indirectly: `rewrite_file <file>
# <fn>` takes a line-emitter by NAME, so shellcheck's reachability stops at the
# call site and marks this — and everything it calls — as dead. BOTH codes are
# needed and they are not interchangeable: 0.10+ reports SC2329 once per
# function, 0.9 (what CI installs) reports SC2317 once per COMMAND in the body.
closure_lines() {
  local line indent box num title
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ ! "${line%$'\r'}" =~ $SUBTASK_RE ]]; then
      printf '%s\n' "$line"
      continue
    fi
    indent="${BASH_REMATCH[1]}"
    box="${BASH_REMATCH[2]}"
    num="${BASH_REMATCH[3]}"
    title="${BASH_REMATCH[4]}"
    if [[ "$box" == 'x' ]] || { [[ "$box" == '~' ]] && [[ ! "$title" =~ $DEFERRED_RE ]]; }; then
      # Settled: `[x]` did the work, a terminal `[~]` said why it will not be
      # done. Neither is this operation's to touch.
      printf '%s\n' "$line"
      continue
    fi
    if [[ "$title" =~ $QUALIFIER_RE ]]; then
      title="${BASH_REMATCH[1]}"
    fi
    title=$(trim "$title")
    printf '%s%s\n' "${indent}- [~] ${num} - ${title} (superseded-by: ${BY_NUM})" "$REWRITE_EOL"
    CLOSED_SUBTASKS=$((CLOSED_SUBTASKS + 1))
  done
  return 0
}

close_subtasks() {
  CLOSED_SUBTASKS=0
  [[ -f "$1" ]] || return 0
  rewrite_file "$1" closure_lines
}

# --- The status pair (step 3, second half) ----------------------------------
# `status: superseded` plus the machine-readable companion `superseded-by: MMM`,
# in every artifact that HAS frontmatter. The companion is what epic-index.sh
# reads to render the supersede target (R3.7), and its reader stops at the
# closing `---` — so the key has to be inside the block, next to the status it
# qualifies, not merely somewhere in the file.
#
# Returns 0 when the file was written, 1 when there was nothing to write (no
# frontmatter, or the pair is already correct), 2 on a write failure.
# print_pair — the two keys, ALWAYS together and always adjacent. They are one
# fact: an artifact carrying only the status is exactly the half-applied shape
# the recovery table's third row has to refuse, so there is no code path here
# that can write one without the other.
# shellcheck disable=SC2317,SC2329  # invoked indirectly: `rewrite_file <file>
# <fn>` takes a line-emitter by NAME, so shellcheck's reachability stops at the
# call site and marks this — and everything it calls — as dead. BOTH codes are
# needed and they are not interchangeable: 0.10+ reports SC2329 once per
# function, 0.9 (what CI installs) reports SC2317 once per COMMAND in the body.
print_pair() {
  printf '%s%s\n' "status: superseded" "$REWRITE_EOL"
  printf '%s%s\n' "superseded-by: ${BY_NUM}" "$REWRITE_EOL"
}

# shellcheck disable=SC2317,SC2329  # invoked indirectly: `rewrite_file <file>
# <fn>` takes a line-emitter by NAME, so shellcheck's reachability stops at the
# call site and marks this — and everything it calls — as dead. BOTH codes are
# needed and they are not interchangeable: 0.10+ reports SC2329 once per
# function, 0.9 (what CI installs) reports SC2317 once per COMMAND in the body.
flip_lines() {
  local line n=0 closed=false wrote=false
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    if [[ $n -eq 1 || "$closed" == true ]]; then
      printf '%s\n' "$line"
      continue
    fi
    if [[ "$line" =~ $FM_DELIM_RE ]]; then
      closed=true
      # No `status:` key in this artifact: the pair is appended rather than
      # dropped, so the artifact cannot end up disagreeing with its siblings.
      if [[ "$wrote" == false ]]; then
        print_pair
        wrote=true
      fi
      printf '%s\n' "$line"
      continue
    fi
    if [[ "${line%$'\r'}" == status:* ]]; then
      print_pair
      wrote=true
      continue
    fi
    # An existing companion is dropped here and re-emitted beside the status
    # above, so a re-pointed supersede leaves ONE key, not two.
    [[ "${line%$'\r'}" == superseded-by:* ]] && continue
    printf '%s\n' "$line"
  done
  return 0
}

flip_artifact() {
  local f="$1"
  has_frontmatter "$f" || return 1
  if [[ "$(frontmatter_field "$f" status)" == "superseded" &&
    "$(frontmatter_field "$f" superseded-by)" == "$BY_NUM" ]]; then
    return 1
  fi
  rewrite_file "$f" flip_lines || return 2
  return 0
}

# flip_all — step 3's second half over every artifact of the story. Records what
# it wrote in ARTIFACTS_FLIPPED (names, not paths: the story directory is
# already in the report).
flip_all() {
  local f name rc
  for f in "$STORY_PATH"/*.md; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f")
    rc=0
    flip_artifact "$f" || rc=$?
    case $rc in
      0) ARTIFACTS_FLIPPED+=("$name") ;;
      1) : ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# --- Index regeneration (step 4) --------------------------------------------
# NNN renders as `superseded by MMM` because epic-index.sh REGENERATES the whole
# managed block from disk state (R3.7) — the row is never rewritten in place,
# which is what makes it correct by construction.
#
# A FAILURE HERE NEVER BLOCKS (references/supersede-mode.md, step 4: "a non-zero
# exit warns and never blocks"). The banner, the closures and the status pair
# ARE the supersede; the index is a rendering of them, the generator is
# idempotent and reads only disk, so the next regeneration repairs it with no
# state to reconcile.
#
# Resolved from THIS script's own location, not from PATH and not from the cwd:
# the generator is a sibling shipped with the plugin, and this script is invoked
# from wherever the operator happens to be.
INDEX_SCRIPT=""
_epic_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2> /dev/null && pwd -P) || _epic_script_dir=""
[[ -n "$_epic_script_dir" ]] && INDEX_SCRIPT="$_epic_script_dir/epic-index.sh"
unset _epic_script_dir

# regenerate_index — always returns 0: this step reaches no verdict of its own,
# it only decides between `ok` and `regen-failed` and says which, in INDEX_STATE
# and INDEX_ERR. BOTH of the child's streams are captured and neither is
# replayed: this script's stdout carries one JSON object, and its stderr is
# silent on every verdict path (see the header).
regenerate_index() {
  local out rc
  INDEX_ERR=""
  if [[ -z "$INDEX_SCRIPT" || ! -f "$INDEX_SCRIPT" ]]; then
    INDEX_STATE="regen-failed"
    INDEX_ERR="the index generator is not there (looked for '${INDEX_SCRIPT:-<the sibling epic-index.sh of this script>}')"
    return 0
  fi
  out=$("${BASH:-bash}" "$INDEX_SCRIPT" --epic-dir "$EPIC_DIR" 2>&1) && rc=0 || rc=$?
  if [[ $rc -eq 0 ]]; then
    INDEX_STATE="ok"
    return 0
  fi
  INDEX_STATE="regen-failed"
  INDEX_ERR="'$INDEX_SCRIPT' exited $rc${out:+ — it said: ${out//$'\n'/; }}"
  return 0
}

# --- Flag parsing -----------------------------------------------------------
# Unknown flag => exit 2 (invalid input), before anything is read or resolved.
TARGET=""
BY_RAW=""
RATIONALE=""
RATIONALE_GIVEN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help | -h)
      print_help
      exit 0
      ;;
    --by)
      shift
      if [[ $# -eq 0 || -z "${1:-}" || "${1:-}" == -* ]]; then
        usage_error "--by requires the replacement story: --by <MMM>"
      fi
      BY_RAW="$1"
      shift
      ;;
    --rationale)
      shift
      if [[ $# -eq 0 ]]; then
        usage_error "--rationale requires a text argument: --rationale <text>"
      fi
      RATIONALE="$1"
      RATIONALE_GIVEN=true
      shift
      ;;
    --remap)
      # `N.N=target`. The target may hold anything, `=` included — only the
      # FIRST `=` separates, so `--remap 1.2=dropped: the v1 sandbox died`
      # arrives intact.
      shift
      if [[ $# -eq 0 || -z "${1:-}" ]]; then
        usage_error "--remap requires an assignment: --remap <N.N=target>"
      fi
      if [[ "$1" != *=* ]]; then
        usage_error "--remap expects <N.N=target>, got '$1'"
      fi
      REMAP_KEYS+=("${1%%=*}")
      REMAP_VALS+=("${1#*=}")
      shift
      ;;
    --)
      # End of options: everything after it is the story, even if it starts
      # with `-`. Without this, a directory named `-006-x` is unreachable.
      shift
      while [[ $# -gt 0 ]]; do
        [[ -z "$TARGET" ]] || usage_error "unexpected extra argument '$1' — one story per invocation"
        TARGET="$1"
        shift
      done
      ;;
    -*)
      usage_error "unknown flag '$1'"
      ;;
    *)
      if [[ -n "$TARGET" ]]; then
        usage_error "unexpected extra argument '$1' — one story per invocation"
      fi
      TARGET="$1"
      shift
      ;;
  esac
done

[[ -n "$TARGET" ]] || usage_error "missing story argument"
[[ -n "$BY_RAW" ]] || usage_error "missing --by <MMM> — supersede has no default replacement, because a story that supersedes nothing in particular is a story nobody can follow"

# The operator's spelling of MMM stands in the report from here on, so a refusal
# raised before MMM resolves can still name what it was asked about. It is
# narrowed to the resolved story's number once there is one.
BY_NUM="$BY_RAW"

# --- Story resolution -------------------------------------------------------
# NNN is resolved FIRST and its failure is exit 2, not a refusal: an
# unresolvable story is bad input, and there is nothing to report on yet. Only
# once NNN is a real directory does the refusal matrix get to speak (exit 1).
EPIC_DIR=""
if [[ -d "$TARGET" ]]; then
  STORY_PATH="${TARGET%/}"
elif [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  EPIC_DIR=$(find_epic_dir) ||
    usage_error "no .epic/ directory found from $(pwd) — run inside an Epic project or pass the story directory"
  STORY_PATH=$(resolve_by_number "$TARGET" "$EPIC_DIR") ||
    usage_error "story '$TARGET' not found under $EPIC_DIR/stories or $EPIC_DIR/archive"
else
  usage_error "story '$TARGET' not found — pass a story number (006) or its directory"
fi

STORY_ABS=$(cd "$STORY_PATH" 2> /dev/null && pwd -P) ||
  usage_error "cannot resolve story directory '$STORY_PATH'"
STORY_ID=$(basename "$STORY_ABS")
STORY_PARENT=$(basename "$(dirname "$STORY_ABS")")
# EVERY path is re-derived from the story's PHYSICAL location, so a symlinked
# story cannot make this operation write outside the project it was aimed at.
EPIC_DIR=$(dirname "$(dirname "$STORY_ABS")")

STORY_LOGICAL_PARENT=$(cd "$(dirname "$STORY_PATH")" 2> /dev/null && pwd -P) ||
  usage_error "cannot resolve the parent of story directory '$STORY_PATH'"
if [[ "$STORY_LOGICAL_PARENT" != "$(dirname "$STORY_ABS")" ]]; then
  refuse "'$STORY_PATH' is a symlink to '$STORY_ABS', outside '$STORY_LOGICAL_PARENT' — supersede rewrites the story in place and regenerates the index from its real location, so it would write outside this project; nothing was modified"
fi

if [[ "$(basename "$EPIC_DIR")" != ".epic" ]]; then
  usage_error "'$STORY_PATH' does not live in a .epic/ directory (resolved to '$STORY_ABS') — expected <project>/.epic/stories/<NNN>-<slug>"
fi

if [[ ! -f "$STORY_PATH/story.md" && ! -f "$STORY_PATH/tasks.md" ]]; then
  usage_error "'$STORY_PATH' holds no story.md or tasks.md — not a story directory"
fi

STORY_NUM=$(story_number "$STORY_ID")

# Readability, before anything is read. `[[ -f ]]` says a file EXISTS, not that
# it can be opened, and a failed redirection at top level under `set -e` would
# end the run with no JSON on stdout at all.
for _artifact in story.md tasks.md design.md; do
  if [[ -e "$STORY_PATH/$_artifact" && ! -r "$STORY_PATH/$_artifact" ]]; then
    refuse "cannot read '$STORY_PATH/$_artifact' — the banner's remap rows and the closures are DERIVED from it, so a supersede that cannot read it would have to invent the scope it claims moved; fix the permissions and re-run. Nothing was modified"
  fi
done
unset _artifact

# The banner lives in story.md. A tasks-only scale (fast, spike) has none, and
# refusing those outright would make supersede unavailable to exactly the
# stories most likely to be replaced wholesale — so the banner falls back to
# tasks.md, which is that scale's front page. Recorded as a deviation.
if [[ -f "$STORY_PATH/story.md" ]]; then
  BANNER_FILE="$STORY_PATH/story.md"
else
  BANNER_FILE="$STORY_PATH/tasks.md"
fi

# ============================================================================
# STEP 1 — VERIFY: rows 1-3 of the refusal matrix (R3.4)
# ============================================================================
# Row 4 is NOT checked here, deliberately. Whether a prior supersede FINISHED is
# the same judgement Interrupted-Run Recovery makes, so it is made once, in step
# 2 — refusing here on the status alone would strand a run interrupted between
# its status write and its closures, which is the collision design v3 shipped.

# Row 1 — NNN == MMM, asked TWICE because it is two questions. Here,
# NUMERICALLY: `--by 6` and `--by 006` name story 006 however they are spelled,
# and two directories sharing a number are a corrupt project in which "supersede
# itself" is still the honest answer. The second asking, once MMM resolves, is
# by IDENTITY — the same directory reached by a different route.
if [[ "$BY_RAW" =~ ^[0-9]+$ && -n "$STORY_NUM" ]] && [[ $((10#$BY_RAW)) -eq $((10#$STORY_NUM)) ]]; then
  refuse "a story cannot supersede itself ($STORY_ID == $BY_RAW)"
fi

# Row 2 — MMM must already exist. Creating the replacement is a separate
# operation, which is what keeps a typo in --by from minting a story.
BY_PATH=""
if [[ "$BY_RAW" =~ ^[0-9]+$ ]]; then
  BY_PATH=$(resolve_by_number "$BY_RAW" "$EPIC_DIR") || BY_PATH=""
else
  for _cand in "$EPIC_DIR/stories/$BY_RAW" "$EPIC_DIR/archive/$BY_RAW"; do
    if [[ -d "$_cand" ]]; then
      BY_PATH="$_cand"
      break
    fi
  done
  unset _cand
fi

if [[ -z "$BY_PATH" ]]; then
  refuse "replacement story $BY_RAW does not exist — create it first, then re-run supersede"
fi

BY_ID=$(basename "$BY_PATH")
# What lands in `superseded-by:` is the NUMBER, because that is what
# epic-index.sh resolves against and what story 004's qualifier grammar spells.
# The operator's own spelling already stands in BY_NUM when they gave a number
# (`012` stays `012`); a directory name is reduced to the number it carries.
if [[ ! "$BY_RAW" =~ ^[0-9]+$ ]]; then
  BY_NUM=$(story_number "$BY_ID")
  [[ -n "$BY_NUM" ]] || BY_NUM="$BY_ID"
fi

# Row 1, second asking — by IDENTITY now that MMM is resolved: `--by
# 012-successor`, `--by 012` and the directory NNN was given as can all be the
# same story wearing different spellings.
if [[ "$BY_ID" == "$STORY_ID" ]]; then
  refuse "a story cannot supersede itself ($STORY_ID == $BY_ID)"
fi

# Row 3 — an archived NNN is immutable history.
FM_STATUS=$(frontmatter_field "$STORY_PATH/story.md" status)
[[ -n "$FM_STATUS" ]] || FM_STATUS=$(frontmatter_field "$STORY_PATH/tasks.md" status)
if [[ "$STORY_PARENT" == "archive" || "$FM_STATUS" == "archived" ]]; then
  refuse "story $STORY_ID is archived — archived stories are immutable history; nothing was modified"
fi

# ============================================================================
# STEP 2 — BANNER, and the recovery classification that guards it (R3.5)
# ============================================================================
OP_DATE=$(date +%Y-%m-%d)
if [[ "$RATIONALE_GIVEN" == true ]]; then
  # One LINE, whatever arrived: the banner's second line is the rationale, and
  # an embedded newline would break the block quote in half.
  RATIONALE=${RATIONALE//$'\r'/ }
  RATIONALE=${RATIONALE//$'\n'/ }
  RATIONALE=$(trim "$RATIONALE")
fi
if [[ -z "$RATIONALE" ]]; then
  RATIONALE="Superseded by story $BY_ID; no rationale was supplied at op time."
fi

scan_open_subtasks "$STORY_PATH/tasks.md" ||
  refuse "cannot read '$STORY_PATH/tasks.md' — the remap rows and the closures are both derived from its checkboxes, so neither could be produced honestly; nothing was modified"

if banner_present "$BANNER_FILE"; then
  # ---- Interrupted-Run Recovery ------------------------------------------
  # The banner alone decides nothing; COMPLETENESS does. Two observations, and
  # the table's three rows are read off them:
  #   status  ∈ {none, some, all}  — artifacts carrying `status: superseded`
  #   open    ∈ {yes, no}          — any sub-task still open
  # The six cells below are the WHOLE product, written out one by one rather
  # than folded into conditions. Exhaustiveness is not decoration here: step 2
  # writes the banner unless a row stops it, so a state that matched NO row
  # would fall straight through to a SECOND banner, which R3.5 forbids
  # unconditionally. A `case` over the product cannot develop that gap silently
  # — a missing cell is a visible hole in a list of six.
  STATUS_STATE=$(status_state)
  OPEN_STATE=$(open_state)

  RECOVERY=""
  case "$STATUS_STATE:$OPEN_STATE" in
    # Row 1 — COMPLETE: every artifact flipped and nothing left open. The prior
    # run finished; this one is a re-run, and re-running duplicates the banner.
    all:no) RECOVERY="refuse-complete" ;;
    # Row 2 — INCOMPLETE: no status written anywhere yet (closures untouched,
    # partial or already done), or every box closed and the status writes
    # reached only some artifacts. Both are shapes step 3's close-then-flip
    # order can leave behind, and both are finishable.
    none:yes | none:no | some:no) RECOVERY="complete" ;;
    # Row 3 — NOT FROM THIS COMMAND: a status write standing over open scope.
    # Step 3 never produces it (closures precede the status write precisely so
    # that the last thing written is the one that declares the op finished), so
    # completing it would mean guessing which half of a hand-edit was intended.
    some:yes | all:yes) RECOVERY="refuse-unproducible" ;;
    # The status axis is not observable (see status_state): completeness is
    # whatever the boxes say, because there is nothing else it could mean.
    n/a:yes) RECOVERY="complete" ;;
    n/a:no) RECOVERY="refuse-complete" ;;
    # Unreachable by construction — the four arms above cover the product. It
    # exists so that a future edit which loses a cell REFUSES rather than falls
    # through to a second banner: the failure mode this table is written to
    # prevent must not be the default.
    *) RECOVERY="refuse-unclassified" ;;
  esac

  case "$RECOVERY" in
    refuse-complete)
      refuse "story $STORY_ID already carries the supersede banner — re-running would duplicate it (R3.5)"
      ;;
    refuse-unproducible)
      refuse "story $STORY_ID carries a supersede banner in a state this command cannot produce (status written with scope still open) — repair the frontmatter by hand, then re-run"
      ;;
    refuse-unclassified)
      refuse "story $STORY_ID carries a supersede banner in a state this command cannot classify (status=$STATUS_STATE, open sub-tasks=$OPEN_STATE) — refusing rather than risking a second banner (R3.5)"
      ;;
  esac
  # Falling through means the prior run was INCOMPLETE. Recovery never touches
  # the banner — it is written at most once, ever — and redoes only what is
  # missing, in step 3's order.
  BANNER_WRITTEN=false
  FINAL_STATUS="completed"
else
  insert_banner "$BANNER_FILE" ||
    refuse "cannot write the supersede banner into '$BANNER_FILE' — nothing was modified"
  BANNER_WRITTEN=true
  REMAP_ROWS=${#OPEN_NUMS[@]}
  FINAL_STATUS="superseded"
fi

# ============================================================================
# STEP 3 — CLOSE, THEN FLIP. The order is the commit-point rule (R3.3)
# ============================================================================
if [[ -f "$STORY_PATH/tasks.md" ]]; then
  close_subtasks "$STORY_PATH/tasks.md" ||
    refuse "cannot rewrite '$STORY_PATH/tasks.md' to close its open sub-tasks — the banner is in place and the status is deliberately NOT written, so the story reads unfinished and a re-run will finish it"
fi

flip_all ||
  refuse "cannot write the status pair into every artifact of '$STORY_PATH' — the closures are in place and the story reads unfinished; a re-run will finish it"

# ============================================================================
# STEP 4 — INDEX (R3.7). Warns, never blocks.
# ============================================================================
regenerate_index

# Step 5 — the archive offer — is conversational and belongs to the caller. The
# story is already in the state archive-story.sh's preflight accepts, so the
# offer needs no preflight of its own.
finish "$FINAL_STATUS"
