#!/usr/bin/env bash
# Regenerates the managed story-index block inside .epic/EPIC.md.
#
# The index is a GENERATED BLOCK delimited by two HTML-comment markers:
#
#   <!-- epic:index:start -->   ...generated table...   <!-- epic:index:end -->
#
# Everything OUTSIDE those markers is the project's own hand-written content
# and is copied through byte for byte (R5.3). Regenerating the block from disk
# state is what makes the links correct by construction: archiving a story
# moves its directory, the next regeneration re-derives the link (R5.1/R5.2) —
# no sed surgery on a file humans also edit, which is the failure mode a
# hand-maintained index produced (a frozen index became the reason archives
# stopped happening).
#
# Usage: epic-index.sh [--epic-dir <dir>] [--help]
#
# Exit codes:
#   0  index regenerated, already up to date, or nothing to do
#   1  regeneration failed (malformed marker pair, unreadable/unwritable file)
#   2  invalid input (unknown flag, no .epic directory found)
#
# All writes happen here via Bash. hook-archive-guard.sh (PreToolUse) blocks
# the Edit/Write tools under .epic/archive/** ONLY, so .epic/EPIC.md is in
# fact reachable by the orchestrator's file tools — this script writes it
# anyway, for symmetry with the rest of the tooling and so a headless run
# needs no tool at all.

set -euo pipefail

# Byte semantics (${#var} counts bytes, not characters) and a stable collation
# for sort(1). Both are load-bearing: the splice below is computed in byte
# offsets, and row ordering must not depend on the caller's locale.
export LC_ALL=C

# --- Help ---
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'HELP'
Usage: epic-index.sh [--epic-dir <dir>] [--help]

Regenerates the managed story-index block in <epic-dir>/EPIC.md from disk
state: one table row per story directory found under stories/ and archive/,
with a link resolving to the story's CURRENT location.

Options:
  --epic-dir <dir>   Path to the .epic directory. Default: the nearest .epic
                     directory at or above the current working directory.
  --help, -h         Show this help.

Behavior:
  * Only the block between <!-- epic:index:start --> and
    <!-- epic:index:end --> is rewritten; every byte outside it is preserved.
  * Index file absent -> created (with the markers) only when the project has
    at least one story, so an empty repository stays quiet.
  * Index file present with NO markers -> the block is appended, existing
    content untouched.
  * A broken marker pair (start without end, end without start, duplicated, or
    end before start) is REFUSED: exit 1, file untouched. The block boundary
    would otherwise have to be guessed, and every guess can swallow
    hand-written content.
  * Regenerating twice with no state change writes nothing at all.

Exit codes:
  0  regenerated, already up to date, or nothing to do
  1  regeneration failed
  2  invalid input
HELP
  exit 0
fi

# --- Flags ---
EPIC_DIR_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --epic-dir)
      if [[ $# -lt 2 ]]; then
        echo "Error: --epic-dir requires a directory argument." >&2
        exit 2
      fi
      EPIC_DIR_ARG="$2"
      shift 2
      ;;
    --epic-dir=*)
      EPIC_DIR_ARG="${1#*=}"
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Error: unknown argument '$1'." >&2
      echo "Usage: epic-index.sh [--epic-dir <dir>] [--help]" >&2
      exit 2
      ;;
  esac
done
if [[ $# -gt 0 ]]; then
  echo "Error: unknown argument '$1'." >&2
  echo "Usage: epic-index.sh [--epic-dir <dir>] [--help]" >&2
  exit 2
fi

# --- Resolve the .epic directory ---
# Discovery walks UP from the cwd so the script works from any subdirectory,
# the same way git finds its repository root.
find_epic_dir() {
  local d="$PWD"
  while :; do
    if [[ -d "$d/.epic" ]]; then
      printf '%s' "$d/.epic"
      return 0
    fi
    [[ "$d" == "/" || -z "$d" ]] && return 1
    d=$(dirname "$d")
  done
}

if [[ -n "$EPIC_DIR_ARG" ]]; then
  EPIC_DIR="${EPIC_DIR_ARG%/}"
  if [[ ! -d "$EPIC_DIR" ]]; then
    echo "Error: --epic-dir '$EPIC_DIR_ARG' is not a directory." >&2
    exit 2
  fi
else
  EPIC_DIR=$(find_epic_dir) || {
    echo "Error: no .epic directory found at or above '$PWD'." >&2
    exit 2
  }
fi

INDEX_FILE="$EPIC_DIR/EPIC.md"
STORIES_DIR="$EPIC_DIR/stories"
ARCHIVE_DIR="$EPIC_DIR/archive"

MARK_START='<!-- epic:index:start -->'
MARK_END='<!-- epic:index:end -->'
TAB=$'\t'

TMP_BUILD=""
TMP_SWAP=""
# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() {
  if [[ -n "$TMP_BUILD" ]]; then rm -f "$TMP_BUILD"; fi
  if [[ -n "$TMP_SWAP" ]]; then rm -f "$TMP_SWAP"; fi
  return 0
}
trap cleanup EXIT

fail() {
  echo "epic-index: $1" >&2
  exit 1
}

# --- Small text helpers ---

# trim <string> — strips leading and trailing ASCII whitespace.
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# md_cell <string> — makes a value safe inside a markdown table cell: one
# line, no unescaped pipes (which would split the row into extra columns) and
# no bracket that could start a link.
md_cell() {
  local s="$1"
  s="${s//$'\r'/ }"
  s="${s//$'\n'/ }"
  s="${s//$'\t'/ }"
  s="${s//\\/\\\\}"
  s="${s//|/\\|}"
  s="${s//\[/\\[}"
  s="${s//\]/\\]}"
  printf '%s' "$s"
}

# url_escape <path> — percent-encodes only the bytes that would terminate a
# markdown inline link or split a table row. Iterating bytes is safe under
# LC_ALL=C: every byte that is not in the set is copied through unchanged, so
# multi-byte UTF-8 sequences reassemble exactly.
url_escape() {
  local s="$1" out="" c i
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      ' ') out+='%20' ;;
      '(') out+='%28' ;;
      ')') out+='%29' ;;
      '<') out+='%3C' ;;
      '>') out+='%3E' ;;
      '|') out+='%7C' ;;
      *)   out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}

# strip_zeros <digits> — "007" -> "7", "000" -> "0", "10" -> "10".
# Pure parameter expansion on purpose: $((10#$n)) reads a leading zero as
# octal only for some inputs and silently wraps around on a 20-digit name.
strip_zeros() {
  local d="$1" lead
  lead="${d%%[!0]*}"
  d="${d#"$lead"}"
  [[ -z "$d" ]] && d=0
  printf '%s' "$d"
}

# --- Frontmatter reader ---
# Same contract as validate-story.sh: the file must OPEN with a `---` line and
# the key is anchored at column 0, so a nested or compound key (`review_status:`,
# `  status:`) can never fake a value. Two deliberate refinements over that
# implementation, both of which matter for a renderer:
#   * the value is TRIMMED, not squeezed with `tr -d '[:space:]'` (which
#     rewrites `done  # closed early` into `done#closedearly`);
#   * an UNTERMINATED frontmatter block yields nothing, instead of letting the
#     open `/^---$/` range run to EOF and read a body line as a key.
# CRLF-tolerant, and implemented in bash rather than sed|grep so a `\r` needs
# no GNU-only regex escape.
#
# front_value <file> <key> -> prints the value, exit 1 when absent/unreadable.
front_value() {
  local f="$1" key="$2"
  local line first=true closed=false val="" found=false rc=0
  [[ -f "$f" ]] || return 1
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      if [[ "$first" == true ]]; then
        first=false
        [[ "$line" == '---' ]] || break
        continue
      fi
      if [[ "$line" == '---' ]]; then
        closed=true
        break
      fi
      if [[ "$found" == false && "$line" == "$key:"* ]]; then
        val="${line#"$key":}"
        found=true
      fi
    done
    :
  } 2>/dev/null < "$f" || rc=1
  [[ $rc -eq 0 ]] || return 1
  [[ "$closed" == true && "$found" == true ]] || return 1

  val=$(trim "$val")
  # A quoted scalar keeps its content verbatim; a plain one ends at an inline
  # ` #` comment (YAML's rule).
  if [[ ${#val} -ge 2 && "${val:0:1}" == '"' && "${val: -1}" == '"' ]]; then
    val="${val:1:${#val}-2}"
  elif [[ ${#val} -ge 2 && "${val:0:1}" == "'" && "${val: -1}" == "'" ]]; then
    val="${val:1:${#val}-2}"
  else
    case "$val" in
      '#'*)   val="" ;;
      *' #'*) val=$(trim "${val%% #*}") ;;
    esac
  fi
  [[ -n "$val" ]] || return 1
  printf '%s' "$val"
}

# --- Checkbox census (story 004 grammar) ---
# One line grammar, three box states: `[ ]` open, `[x]` closed, `[~]` closed
# WITHOUT the work being done — qualified on the same line by one of
# deferred: / waived: / n-a: / superseded-by:.
#
# The GRAMMAR is shared verbatim with validate-story.sh and hook-precompact.sh.
# The AGGREGATION is per-consumer, and this script is the third consumer:
#   * validate-story.sh folds every qualified [~] into `closed` (it only needs
#     "is anything still open?");
#   * archive-story.sh partitions closed/deferred/open for the manifest (three
#     disjoint numbers a reader must be able to add up);
#   * this index RENDERS FOR A HUMAN, exactly like hook-precompact.sh — so it
#     reuses that script's split verbatim: terminal qualifiers close the box,
#     `deferred:` is reported apart (that work is settled in the plan but still
#     owed by an external actor), `deferred:` wins when a line carries both,
#     and an unqualified [~] — the grammar error validate-story.sh reports —
#     counts in the total and closes nothing.
# The index and the pre-compact snapshot therefore can never disagree about
# the same story, which is the property that matters when both are read side
# by side in one session.
#
# Counters are plain integers incremented in the loop, never ${#assoc[@]} on a
# possibly-empty associative array (that trips set -u on bash 5.3).
CENSUS_TOTAL=0
CENSUS_DONE=0
CENSUS_DEFERRED=0
census() {
  local f="$1" line rc=0
  CENSUS_TOTAL=0
  CENSUS_DONE=0
  CENSUS_DEFERRED=0
  [[ -f "$f" ]] || return 1
  local box_re='^[[:space:]]*- \[([ x~])\]'
  local deferred_re='(^|[^[:alnum:]_-])deferred:'
  local terminal_re='(^|[^[:alnum:]_-])(waived|n-a|superseded-by):'
  # `[[ -f ]]` says the file EXISTS, not that it OPENS. A bare failed
  # redirection under set -e kills the shell with no output, and `if ! { …; } < f`
  # reads as success — the `2>` before the `<`, plus the trailing `:`, is what
  # makes the failure catchable.
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ $box_re ]] || continue
      CENSUS_TOTAL=$((CENSUS_TOTAL + 1))
      case "${BASH_REMATCH[1]}" in
        'x') CENSUS_DONE=$((CENSUS_DONE + 1)) ;;
        '~')
          if [[ "$line" =~ $deferred_re ]]; then
            CENSUS_DEFERRED=$((CENSUS_DEFERRED + 1))
          elif [[ "$line" =~ $terminal_re ]]; then
            CENSUS_DONE=$((CENSUS_DONE + 1))
          fi
          ;;
      esac
    done
    :
  } 2>/dev/null < "$f" || rc=1
  return $rc
}

# --- Scan: one pass to enumerate, one to render ---
# Two passes because a `superseded-by: MMM` pointer can only be resolved once
# every story number in the project is known.
S_AREA=()   # stories | archive
S_DIR=()    # directory basename, as written on disk
S_NUM=()    # normalized number ("" when the name is not NNN-slug)
S_SLUG=()   # slug ("" when the name is not NNN-slug)
KNOWN_NUMS="|"

scan_area() {
  local base="$1" area="$2" d name
  [[ -d "$base" ]] || return 0
  # A bash glob is sorted by the shell, so readdir order never reaches the
  # output; the explicit numeric sort further down is what fixes the ORDER.
  for d in "$base"/*/; do
    [[ -d "$d" ]] || continue
    name="${d%/}"
    name="${name##*/}"
    S_AREA+=("$area")
    S_DIR+=("$name")
    if [[ "$name" =~ ^([0-9]+)-(.+)$ ]]; then
      local num
      num=$(strip_zeros "${BASH_REMATCH[1]}")
      S_NUM+=("$num")
      S_SLUG+=("${BASH_REMATCH[2]}")
      case "$KNOWN_NUMS" in
        *"|$num|"*) : ;;
        *) KNOWN_NUMS+="$num|" ;;
      esac
    else
      # Not NNN-slug. It is still on disk, so it is still in the index —
      # dropping it would make the index quietly disagree with the filesystem,
      # which is the whole failure this generator exists to end.
      S_NUM+=("")
      S_SLUG+=("")
    fi
  done
}

scan_area "$STORIES_DIR" stories
scan_area "$ARCHIVE_DIR" archive

STORY_COUNT=${#S_DIR[@]}

# Nothing to index and no file to maintain: stay quiet (design — "no noise in
# empty repos"). An index that already exists IS maintained even at zero
# stories, because the user asked for it by creating it.
if [[ "$STORY_COUNT" -eq 0 && ! -e "$INDEX_FILE" ]]; then
  echo "epic-index index=$INDEX_FILE stories=0 action=skipped reason=no-stories" >&2
  exit 0
fi

# --- Cell renderers ---

# status_cell <story.md> — the Status column: the frontmatter value; an em dash
# for the 340+ legacy stories that predate the field (an empty cell would read
# as a rendering bug, and crashing on absence would make the index unusable on
# exactly the corpus it has to describe); and, for a superseded story, the
# successor it points at. A pointer that resolves nowhere is SHOWN, not hidden:
# a dangling supersede is precisely what a reader needs to be told about.
status_cell() {
  local f="$1" status sup sup_num cell
  status=$(front_value "$f" status) || status=""
  if [[ -z "$status" ]]; then
    printf '%s' '—'
    return 0
  fi
  cell=$(md_cell "$status")
  if [[ "$status" != "superseded" ]]; then
    printf '%s' "$cell"
    return 0
  fi
  # The companion key is written by story 006; until then no story carries it
  # and every superseded row simply renders `superseded`.
  sup=$(front_value "$f" superseded-by) || sup=""
  if [[ -z "$sup" ]]; then
    printf '%s' "$cell"
    return 0
  fi
  if [[ "$sup" =~ ^([0-9]+) ]]; then
    sup_num=$(strip_zeros "${BASH_REMATCH[1]}")
  else
    sup_num=""
  fi
  # Resolution is NUMERIC, so `superseded-by: 7` finds `007-slug` and an
  # archived successor resolves exactly like an active one.
  if [[ -n "$sup_num" && "$KNOWN_NUMS" == *"|$sup_num|"* ]]; then
    printf '%s' "superseded by $(md_cell "$sup")"
  else
    printf '%s' "superseded by $(md_cell "$sup") (missing)"
  fi
}

# progress_cell <tasks.md> — closed/total, with still-owed work named apart.
# No tasks.md, or one that does not open, renders an em dash: `0/0` would be a
# measurement nobody took.
progress_cell() {
  local prog
  if ! census "$1"; then
    printf '%s' '—'
    return 0
  fi
  prog="$CENSUS_DONE/$CENSUS_TOTAL"
  if [[ "$CENSUS_DEFERRED" -gt 0 ]]; then
    prog+=" (+$CENSUS_DEFERRED deferred)"
  fi
  printf '%s' "$prog"
}

# --- Build the rows ---
ROWS=()
build_rows() {
  local i area dir num slug prog link loc cell_num cell_story cell_status
  local class sort_num keyname row
  for (( i = 0; i < STORY_COUNT; i++ )); do
    area="${S_AREA[$i]}"
    dir="${S_DIR[$i]}"
    num="${S_NUM[$i]}"
    slug="${S_SLUG[$i]}"

    if [[ -n "$num" ]]; then
      class=0
      sort_num="$num"
      cell_num=$(md_cell "${dir%%-*}")
      cell_story=$(md_cell "$slug")
    else
      # Unnumbered directories sort after every numbered one, then by name —
      # they have no place on the number axis, and inventing one would make
      # the order depend on where they happen to live.
      class=1
      sort_num=0
      cell_num='—'
      cell_story=$(md_cell "$dir")
    fi

    # Link target: the story file when there is one, the directory otherwise.
    # Relative to .epic/, which is where EPIC.md lives — that is what makes the
    # link resolve to the story's CURRENT location (R5.1).
    if [[ -f "$EPIC_DIR/$area/$dir/story.md" ]]; then
      link="$area/$(url_escape "$dir")/story.md"
    else
      link="$area/$(url_escape "$dir")/"
    fi

    cell_status=$(status_cell "$EPIC_DIR/$area/$dir/story.md")
    prog=$(progress_cell "$EPIC_DIR/$area/$dir/tasks.md")

    if [[ "$area" == "archive" ]]; then
      loc="archived"
    else
      loc="active"
    fi

    row="| $cell_num | [$cell_story]($link) | $cell_status | $prog | $loc |"
    row="${row//$'\n'/ }"
    # Fields 1-4 are the sort key and must stay tab-free; field 5 is the row.
    keyname="${dir//$TAB/ }"
    keyname="${keyname//$'\n'/ }"
    ROWS+=("$class$TAB$sort_num$TAB$keyname$TAB$area$TAB$row")
  done
}
build_rows

# --- Render the generated block ---
render_block() {
  printf '%s\n' "$MARK_START"
  printf '%s\n' '<!-- Generated by scripts/epic-index.sh — edits inside this block are overwritten. -->'
  printf '\n'
  if [[ ${#ROWS[@]} -eq 0 ]]; then
    printf '%s\n' '_No stories yet._'
  else
    printf '%s\n' '| # | Story | Status | Progress | Location |'
    printf '%s\n' '| --- | --- | --- | --- | --- |'
    # Stable ordering by NUMBER, not by name: `-k2,2n` is what puts 9 before
    # 10 (a lexicographic sort puts "10-x" first). Unnumbered directories come
    # last (`-k1,1`), and equal numbers are broken by name then area so two
    # stories sharing a number still order deterministically.
    printf '%s\n' "${ROWS[@]}" | sort -t "$TAB" -k1,1 -k2,2n -k3,3 -k4,4 | cut -d "$TAB" -f5-
  fi
  printf '\n'
  printf '%s\n' "$MARK_END"
}

# --- Locate the marker pair ---
# Byte offsets, not line numbers: the head and the tail are spliced back with
# head -c / tail -c so that anything the project wrote outside the block —
# trailing spaces, CRLF, a missing final newline — survives untouched (R5.3).
START_COUNT=0
END_COUNT=0
HEAD_BYTES=0
TAIL_OFFSET=0
scan_markers() {
  local f="$1" line stripped bytes=0 rc=0
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      # A marker is a line that IS the marker (indentation and a CRLF ending
      # tolerated) — never one that merely contains the token, so a document
      # explaining the mechanism in prose does not become a marker.
      stripped="${line%$'\r'}"
      stripped=$(trim "$stripped")
      if [[ "$stripped" == "$MARK_START" ]]; then
        START_COUNT=$((START_COUNT + 1))
        # The head ends BEFORE this line; the tail starts AFTER the end marker.
        if [[ "$START_COUNT" -eq 1 ]]; then HEAD_BYTES=$bytes; fi
      fi
      bytes=$((bytes + ${#line} + 1))
      if [[ "$stripped" == "$MARK_END" ]]; then
        END_COUNT=$((END_COUNT + 1))
        if [[ "$END_COUNT" -eq 1 ]]; then TAIL_OFFSET=$bytes; fi
      fi
    done
    :
  } 2>/dev/null < "$f" || rc=1
  return $rc
}

TMP_BUILD=$(mktemp "${TMPDIR:-/tmp}/epic-index.XXXXXX") \
  || fail "could not create a temporary file in ${TMPDIR:-/tmp}"

if [[ -e "$INDEX_FILE" ]]; then
  [[ -f "$INDEX_FILE" ]] || fail "$INDEX_FILE exists but is not a regular file"
  scan_markers "$INDEX_FILE" || fail "$INDEX_FILE could not be read"

  if [[ "$START_COUNT" -eq 0 && "$END_COUNT" -eq 0 ]]; then
    # Adoption path: an index that predates this script keeps everything it
    # has and gains the block at the end. Idempotent — the next run finds the
    # markers and splices.
    {
      cat "$INDEX_FILE"
      if [[ -s "$INDEX_FILE" ]]; then
        LAST_BYTE=$(tail -c 1 "$INDEX_FILE")
        [[ -n "$LAST_BYTE" ]] && printf '\n'
        printf '\n'
      fi
      render_block
    } > "$TMP_BUILD" || fail "could not compose the new index"
  elif [[ "$START_COUNT" -ne 1 || "$END_COUNT" -ne 1 || "$TAIL_OFFSET" -le "$HEAD_BYTES" ]]; then
    # A broken pair has no defensible repair: treating "start with no end" as
    # "block runs to EOF" swallows the rest of the document, and inserting the
    # missing marker reinterprets hand-written text as generated output. Both
    # are exactly the clobbering this block's markers exist to prevent, so the
    # generator refuses and touches nothing.
    fail "$INDEX_FILE has a malformed generated block (start markers: $START_COUNT, end markers: $END_COUNT) — expected exactly one '$MARK_START' followed by one '$MARK_END'. Nothing was written; fix the markers or remove both to let the block be re-appended."
  else
    {
      if [[ "$HEAD_BYTES" -gt 0 ]]; then
        head -c "$HEAD_BYTES" "$INDEX_FILE"
      fi
      render_block
      tail -c "+$((TAIL_OFFSET + 1))" "$INDEX_FILE"
    } > "$TMP_BUILD" || fail "could not compose the new index"
  fi
else
  # Created with a heading above the block: the design's premise is that
  # projects hand-write context around the index, and a bare pair of HTML
  # comments does not invite it.
  {
    printf '%s\n\n' '# Epic — Story Index'
    render_block
  } > "$TMP_BUILD" || fail "could not compose the new index"
fi

# --- Write only when something actually changed ---
# R5.4 at its strongest: a second run with no state change does not open the
# file for writing at all, so neither the bytes nor the mtime move.
if [[ -f "$INDEX_FILE" ]] && cmp -s "$TMP_BUILD" "$INDEX_FILE"; then
  echo "epic-index index=$INDEX_FILE stories=$STORY_COUNT action=unchanged" >&2
  exit 0
fi

# Atomic replace through a sibling temp file: a crash mid-write must never
# leave a truncated EPIC.md, because the truncated part is the project's own
# hand-written content.
# KNOWN RESIDUAL: an EPIC.md that is a SYMLINK is replaced by a regular file —
# the same trade-off archive-story.sh records for `sed -i`. Writing through the
# link would mean giving up the atomic replace, i.e. trading a rare, cosmetic
# surprise for a rare, destructive one.
TMP_SWAP=$(mktemp "$EPIC_DIR/.epic-index.XXXXXX") \
  || fail "could not create a temporary file in $EPIC_DIR (is it writable?)"
cat "$TMP_BUILD" > "$TMP_SWAP" || fail "could not write $TMP_SWAP"

# Keep the file's own permissions; mktemp creates 0600, which would silently
# tighten a committed EPIC.md. With no existing file, reproduce what a plain
# `>` redirection would have created.
NEW_MODE=""
if [[ -f "$INDEX_FILE" ]]; then
  NEW_MODE=$(stat -c '%a' "$INDEX_FILE" 2>/dev/null) || NEW_MODE=""
  # `stat -f` on GNU stat does not fail cleanly (it prints filesystem info and
  # exits 0), so the OUTPUT is validated, never just the exit status.
  if [[ ! "$NEW_MODE" =~ ^[0-7]{3,4}$ ]]; then
    NEW_MODE=$(stat -f '%Lp' "$INDEX_FILE" 2>/dev/null) || NEW_MODE=""
  fi
fi
if [[ ! "$NEW_MODE" =~ ^[0-7]{3,4}$ ]]; then
  NEW_MODE=$(printf '%04o' "$(( 0666 & ~$(umask) ))")
fi
chmod "$NEW_MODE" "$TMP_SWAP" 2>/dev/null || true

mv -f "$TMP_SWAP" "$INDEX_FILE" || fail "could not replace $INDEX_FILE"
TMP_SWAP=""

echo "epic-index index=$INDEX_FILE stories=$STORY_COUNT action=written" >&2
exit 0
