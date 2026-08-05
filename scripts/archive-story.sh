#!/usr/bin/env bash
# Archives a completed story into .epic/archive/, under guard.
#
# Usage: bash scripts/archive-story.sh <NNN|story-dir> [--allow-heavy]
#        [--skip-secrets] [--keep-logs] [--keep-copies] [--force <reason>]
#
# Exit 0 = story archived (the move completed)
# Exit 1 = refused (preflight) or blocked (guard) — nothing was moved
# Exit 2 = invalid input (unknown flag, unresolvable story)
#
# Output: ONE JSON object on stdout on every path that reaches a verdict; every
# human-readable diagnostic goes to stderr, so a consumer can pipe stdout
# straight into jq. Usage errors (exit 2) print no JSON at all — there is no
# story to report on yet (same convention as validate-story.sh).
#
# TWO DOCUMENTED EXCEPTIONS to "JSON on stdout", both of which reach no verdict:
#   --help/-h  prints usage prose on stdout and exits 0. It never resolves a
#              story, so there is nothing to report on (pinned by a contract
#              test — the behavior is intended, not an oversight).
#   exit 2     usage errors, as above: stderr only.
#
# STEP ORDER IS LOAD-BEARING (design.md, component 1): nothing destructive runs
# before every guard has passed, the manifest entry is appended BEFORE the move,
# and index regeneration is last.
#   1. preflight ................ sub-task 1.1  (implemented)
#   2. weight/binary guard ...... sub-task 2.1   (stub)
#   3. secrets guard ............ sub-task 2.2   (stub)
#   4. prune .draft ............. sub-tasks 3.1 / 3.2 (stub)
#   5. manifest append .......... sub-task 1.2  (implemented — before the move, R3.4)
#   6. move ..................... sub-task 1.3  (implemented — git mv / mv, R6.1/R6.2)
#   7. status: archived ......... sub-task 1.3  (implemented)
#   8. index regeneration ....... sub-tasks 4.1 / 4.2 (stub)
# Steps 2-4 and 8 are not implemented yet; each is a marked stub below.

set -euo pipefail

USAGE='Usage: archive-story.sh <NNN|story-dir> [--allow-heavy] [--skip-secrets] [--keep-logs] [--keep-copies] [--force <reason>]'

print_help() {
  cat <<'HELP'
Usage: archive-story.sh <NNN|story-dir> [--allow-heavy] [--skip-secrets]
                        [--keep-logs] [--keep-copies] [--force <reason>]

Archives a completed story: preflight, guards, evidence pruning, a manifest
entry derived from the checkboxes, the move into .epic/archive/ and the index
regeneration — in that order, with nothing destructive before the guards pass.

Arguments:
  <NNN|story-dir>   Story number (005) or its directory (.epic/stories/005-slug)

Flags:
  --allow-heavy     Archive despite files >10 MB or non-text (recorded)
  --skip-secrets    Skip the secrets scan (recorded)
  --keep-logs       Keep .draft/logs/ instead of collapsing it to a summary (recorded)
  --keep-copies     Keep .draft/ files identical to their promoted sibling (recorded)
  --force <reason>  Archive an incomplete story. The reason is REQUIRED and is
                    recorded in the manifest entry.
  --help, -h        Show this help

Completion (story 004 semantics): frontmatter status is done/validated/superseded
OR no `- [ ]` checkbox remains. A `scale: spike` story (story 007) is complete
when its `## Verdict` status is `wont-do`, or `promote` with a `promoted-to:`
reference recorded.

Output: JSON on stdout — {story, path, status, moved, reason, tasks, pruned,
guard{violations}, secrets, index, overrides_used, manifest_entry}.
Diagnostics on stderr.

Exit codes:
  0  Story archived (move completed)
  1  Refused (preflight) or blocked (guard) — nothing was moved
  2  Invalid input (unknown flag, unresolvable story)
HELP
}

# --- Report state -----------------------------------------------------------
# Every field of the JSON contract lives in a variable so that ONE emitter
# renders every exit path: a caller can jq the same shape whatever happened.
STORY_ID=""            # canonical story identity, e.g. 005-archive-in-the-flow
STORY_PATH=""          # path as resolved (kept relative when given relative)
STATUS=""              # archived | blocked | refused
REASON=""              # human-readable why, for refused/blocked
MOVED=false            # JSON boolean literal — true only after a completed move
PRUNED_LOGS_KB=0
PRUNED_COPIES=0
INDEX_STATE="skipped"  # ok | regen-failed | skipped (step 8 never ran)
SECRETS_JSON='{}'      # filled by the secrets guard (sub-task 2.2)
MANIFEST_JSON='{}'     # filled by the manifest step (sub-task 1.2)
GUARD_VIOLATIONS=()
OVERRIDES_USED=()

# Checkbox census (see census_tasks) — initialized here because the emitter
# reads them even on paths where tasks.md was never opened.
BOX_TOTAL=0
BOX_OPEN=0
BOX_CLOSED=0
BOX_DEFERRED=0

# One "N.N — title (qualifier: reason)" string per `[~]` box, filled by
# collect_deferred_items at step 5 (R4.4 records the ITEMS, not just a count).
DEFERRED_ITEMS=()

# --- String quoting ---------------------------------------------------------
# EVERY string this script writes — to stdout as JSON, to manifest.yaml as a
# double-quoted YAML scalar — goes through json_escape. The inputs are arbitrary
# by construction: a `--force` reason is typed (or pasted, colour codes and all)
# by a human, and a `[~]` line is copied out of tasks.md.
#
# The two formats do NOT accept the same raw bytes, so the escape set is the
# UNION of what each forbids, not the intersection:
#   JSON (RFC 8259 §7): U+0000-U+001F must be escaped.
#   YAML (1.2 §5.1, "printable characters"): the same C0 block, AND DEL (U+007F),
#     AND the C1 block U+0080-U+009F except NEL (U+0085) — anywhere in the
#     stream, quoted or not.
# So a DEL in a --force reason yields perfectly valid JSON and a manifest.yaml
# that no YAML parser will ever load again. Since the manifest is appended at
# step 5 and nothing re-reads it, that damage is silent AND permanent.
#
# `\uXXXX` is the one form BOTH accept, so everything outside the five named
# short escapes is written that way. The escape table is built once, at load,
# from literal byte sequences: a C1 character is its UTF-8 pair (0xC2 0x80-0x9F),
# which matches identically whether bash is running in a UTF-8 locale (one
# character) or in C (two bytes) — the substitution is locale-independent either
# way. NUL needs no entry: a bash string cannot hold one.
#
# NOT covered (they cannot reach here from a text artifact, and escaping them
# would mean re-encoding, not quoting): bytes that are not valid UTF-8 at all,
# and U+FFFE/U+FFFF/lone surrogates, which YAML also forbids.
JSON_ESC_RAW=()   # needle: the literal byte sequence to replace
JSON_ESC_REP=()   # replacement: its \uXXXX form
# The `printf -v needle "$needle"` pair below is a TWO-STAGE printf and the
# variable-as-format is the point of it: stage 1 builds the literal text `\x1b`,
# stage 2 makes printf interpret that escape into the byte itself. Writing the
# byte directly is not an option — it is what we are trying to produce.
# shellcheck disable=SC2059
_json_escape_table() {
  local i needle rep
  # C0 minus the five with a short escape (\b \t \n \f \r = 8 9 10 12 13).
  for i in 1 2 3 4 5 6 7 11 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 127; do
    printf -v needle '\\x%02x' "$i"
    printf -v needle "$needle"
    printf -v rep '\\u%04x' "$i"
    JSON_ESC_RAW+=("$needle")
    JSON_ESC_REP+=("$rep")
  done
  # C1: U+0080-U+009F, as their UTF-8 pair. NEL (U+0085) is legal in YAML but
  # escaping it is legal too, so it stays in the table — one rule, no carve-out
  # to get wrong.
  for ((i = 128; i <= 159; i++)); do
    printf -v needle '\\xc2\\x%02x' "$i"
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

# quote_scalar — ONE double-quoted token that is simultaneously a valid JSON
# string and a valid YAML double-quoted scalar, because json_escape emits only
# escapes both formats decode the same way. That equivalence is not a
# convenience: it is what lets manifest_read_entry splice a value RECORDED in
# the manifest straight back into the JSON report, with no unescape/re-escape
# round trip that could drift.
# Everything derived from an artifact is quoted: a title with a `:` or a `#`, a
# reason with a quote, or a bare `005` that YAML would otherwise read as 5.
quote_scalar() {
  printf '"%s"' "$(json_escape "$1")"
}

# yaml_list <indent> <key> <items...> — a block sequence, or `key: []` when
# there is nothing to list. The empty case is spelled out because a block
# sequence with no items parses as null, and a consumer reading
# `overrides_used` or `deferred_items` would have to special-case it.
yaml_list() {
  local indent="$1" key="$2" item
  shift 2
  if [[ $# -eq 0 ]]; then
    printf '%s%s: []\n' "$indent" "$key"
    return 0
  fi
  printf '%s%s:\n' "$indent" "$key"
  for item in "$@"; do
    printf '%s  - %s\n' "$indent" "$(quote_scalar "$item")"
  done
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
  local violations overrides
  # ${arr[@]+"${arr[@]}"} — not plain "${arr[@]}": expanding an EMPTY array that
  # way is an unbound-variable abort under `set -u` on bash < 4.4 (macOS ships
  # 3.2), and this emitter runs on the paths where both arrays are empty.
  violations=$(json_array ${GUARD_VIOLATIONS[@]+"${GUARD_VIOLATIONS[@]}"})
  overrides=$(json_array ${OVERRIDES_USED[@]+"${OVERRIDES_USED[@]}"})
  cat <<JSON
{
  "story": "$(json_escape "$STORY_ID")",
  "path": "$(json_escape "$STORY_PATH")",
  "status": "$(json_escape "$STATUS")",
  "moved": $MOVED,
  "reason": "$(json_escape "$REASON")",
  "tasks": { "total": $BOX_TOTAL, "closed": $BOX_CLOSED, "deferred": $BOX_DEFERRED, "open": $BOX_OPEN },
  "pruned": { "logs_kb": $PRUNED_LOGS_KB, "copies_removed": $PRUNED_COPIES },
  "guard": { "violations": $violations },
  "secrets": $SECRETS_JSON,
  "index": "$(json_escape "$INDEX_STATE")",
  "overrides_used": $overrides,
  "manifest_entry": $MANIFEST_JSON
}
JSON
}

# --- Terminators ------------------------------------------------------------
# usage_error: invalid input. No JSON — nothing has been resolved to report on.
usage_error() {
  printf 'Error: %s\n' "$1" >&2
  printf '%s\n' "$USAGE" >&2
  exit 2
}

# refuse: preflight said no. Nothing has been touched at this point, by
# construction — preflight is step 1 and runs before anything destructive.
refuse() {
  STATUS="refused"
  REASON="$1"
  printf 'Refused: %s\n' "$REASON" >&2
  emit_report
  exit 1
}

# block: a guard hit (or the pipeline stopped short). Fail-closed: nothing moved.
block() {
  STATUS="blocked"
  REASON="$1"
  printf 'Blocked: %s\n' "$REASON" >&2
  emit_report
  exit 1
}

# --- Artifact readers -------------------------------------------------------
# Frontmatter parsing follows validate-story.sh: a leading `---` line, the block
# up to the next `---`, and keys anchored at column 0 so a compound or nested
# key (`review_status:`) can never fake a value. `$d` instead of `head -n -1`
# because the latter is GNU-only.
#
# CRLF: the delimiter regex tolerates a trailing `\r` (FM_DELIM_RE). On a
# checkout with core.autocrlf=true every artifact ends `---\r`, and an `^---$`
# that rejects it does not fail loudly — it makes the file look like it has no
# frontmatter, which downstream means "nothing to correct" and archives a story
# whose artifacts contradict each other. Worse, the CLOSING delimiter matters
# just as much as the opening one: an unmatched `/^---$/` range runs to EOF and
# the "frontmatter" would then include body lines.
#
# The value is TRIMMED, not squeezed. `tr -d '[:space:]'` (validate-story.sh's
# form) deletes whitespace INSIDE the value too, so `status: done  # closed
# early` becomes `done#closedearly` — which is written verbatim into the
# manifest as a derived field that appears nowhere in the source artifact, and
# which no longer equals `done`, so the completion branch refuses a story that
# is genuinely done. validate-story.sh gets away with it because the mangled
# value hits an enum check and is reported; here it is persisted.
FM_DELIM_RE=$'^---\r?$'
frontmatter_field() {
  local file="$1" key="$2" front val
  [[ -f "$file" ]] || return 0
  head -1 "$file" | grep -Eq "$FM_DELIM_RE" 2>/dev/null || return 0
  front=$(sed -En "2,/${FM_DELIM_RE}/p" "$file" | sed '$d') || return 0
  val=$(printf '%s\n' "$front" | grep -E "^$key:" | head -1 | sed "s/.*$key:[[:space:]]*//") || val=""
  # A YAML comment starts at a `#` preceded by whitespace (or at the value's
  # very start); a `#` glued to text is part of the value.
  if [[ "$val" == '#'* ]]; then
    val=""
  elif [[ "$val" =~ ^(.*[[:space:]])#.*$ ]]; then
    val="${BASH_REMATCH[1]}"
  fi
  # Trim the edges only — parameter expansion, no fork. `[:space:]` covers the
  # trailing `\r` of a CRLF line.
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  printf '%s' "$val"
}

# story_field <key> — the story's lifecycle fields live in story.md when there
# is one, and in tasks.md for the tasks-only scales (fast, spike).
story_field() {
  local key="$1" val
  val=$(frontmatter_field "$STORY_PATH/story.md" "$key")
  if [[ -z "$val" ]]; then
    val=$(frontmatter_field "$STORY_PATH/tasks.md" "$key")
  fi
  printf '%s' "$val"
}

# census_tasks <tasks.md> — the checkbox census, in the ONE grammar shared with
# validate-story.sh / cross-reference.sh / hook-precompact.sh:
#   - [ ] open   - [x] closed   - [~] closed WITHOUT doing the work.
# Counters are plain integers incremented in the loop, never ${#assoc[@]} on a
# possibly-empty associative array (that trips set -u on bash 5.3).
#
# The AGGREGATION here is archive's own, and it is a partition —
# open + closed + deferred == total:
#   closed   = [x]              (work done)
#   deferred = [~], any qualifier (closed without doing the work)
# That is deliberately NOT validate-story.sh's aggregation (which folds a
# qualified [~] into `closed`), because the manifest entry reports
# tasks_total/tasks_closed/tasks_deferred as three disjoint numbers. One
# grammar, per-consumer aggregation — the same split hook-precompact.sh makes.
# The [~] qualifier tokens (`deferred:` vs terminal `waived:|n-a:|superseded-by:`)
# are NOT read here — nothing in preflight consumes them. They are parsed once,
# at step 5, by collect_deferred_items, which needs the reason text.
#
# READING IS FALLIBLE, so every reader below returns non-zero instead of dying.
# `[[ -f ]]` says the file EXISTS, not that it can be opened: an existing but
# unreadable tasks.md makes `done < "$file"` fail, and a bare failed redirection
# at top level under `set -e` kills the shell with no JSON on stdout at all —
# the one thing the output contract promises never happens. The `{ …; :; }
# 2>/dev/null < "$file" || return 1` form is the one that actually catches it:
# `2>` BEFORE `<` suppresses bash's own message, `|| return` catches the failed
# redirection (an `if ! { …; } < f` does NOT — it reads as success), and the
# trailing `:` pins the group's status to the redirection rather than to
# whatever the loop body last evaluated.
census_tasks() {
  local file="$1" line
  local box_re='^[[:space:]]*- \[([ x~])\]'
  BOX_TOTAL=0
  BOX_OPEN=0
  BOX_CLOSED=0
  BOX_DEFERRED=0
  [[ -f "$file" ]] || return 0
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ $box_re ]] || continue
      BOX_TOTAL=$((BOX_TOTAL + 1))
      case "${BASH_REMATCH[1]}" in
        ' ') BOX_OPEN=$((BOX_OPEN + 1)) ;;
        'x') BOX_CLOSED=$((BOX_CLOSED + 1)) ;;
        '~') BOX_DEFERRED=$((BOX_DEFERRED + 1)) ;;
      esac
    done
    :
  } 2>/dev/null < "$file" || return 1
  return 0
}

# trim <string> — strip leading and trailing whitespace. Pure parameter
# expansion (no subshell, no `sed`): these run once per checkbox line.
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# collect_deferred_items <tasks.md> — one rendered line per `[~]` box, into
# DEFERRED_ITEMS. R4.4 records the ITEMS, not just a count: "3 deferred" tells
# a future reader nothing about what is still owed, which is the exact failure
# the derived manifest exists to end.
#
# Rendered shape (design.md, step 5): "N.N — title (qualifier: reason)", e.g.
#   - [~] 2.1 - Register the callback URL (deferred: needs the live account)
#     => "2.1 — Register the callback URL (deferred: needs the live account)"
# The QUALIFIER is kept inside the parentheses on purpose: `deferred:` is work
# still owed while `waived:`/`n-a:`/`superseded-by:` are terminal, and dropping
# the token would erase that difference (references/tasks.md#checkbox-grammar).
# A `[~]` with no qualifier is a grammar error validate-story.sh reports; here
# it must still be recorded, so it renders "(no reason recorded)" rather than
# being silently dropped — archive reports what is there, it does not judge it.
collect_deferred_items() {
  local file="$1" line body id rest title qual reason cut item
  local box_re='^[[:space:]]*- \[~\][[:space:]]*(.*)$'
  local id_re='^([0-9]+(\.[0-9]+)*)[[:space:]]*[-:]?[[:space:]]*(.*)$'
  local qual_re='(^|[^[:alnum:]_-])(deferred|waived|n-a|superseded-by):[[:space:]]*(.*)$'
  DEFERRED_ITEMS=()
  [[ -f "$file" ]] || return 0
  {
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ $box_re ]] || continue
    body=$(trim "${BASH_REMATCH[1]}")

    # Task id ("2.1") and the text after it, when the line carries one.
    if [[ "$body" =~ $id_re ]]; then
      id="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[3]}"
    else
      id=""
      rest="$body"
    fi

    # Qualifier + reason. The title is whatever precedes the qualifier token,
    # so the cut is made on the matched text itself (leftmost match, same as
    # ${var%%"$cut"*}) instead of a second, drifting regex.
    qual=""
    reason=""
    title="$rest"
    if [[ "$rest" =~ $qual_re ]]; then
      qual="${BASH_REMATCH[2]}"
      reason=$(trim "${BASH_REMATCH[3]}")
      cut="${BASH_REMATCH[1]}${qual}:"
      title="${rest%%"$cut"*}"
      reason="${reason%')'}"
      reason="${reason%']'}"
      reason=$(trim "$reason")
    fi

    # Drop the delimiter that introduced the qualifier ("title (deferred: …"
    # or "title — deferred: …"). One suffix strip per literal, never a bracket
    # class: `—` is multi-byte and a class would chew a single byte off it.
    title=$(trim "$title")
    title="${title%'('}"
    title="${title%'['}"
    title="${title%'—'}"
    title="${title%'–'}"
    title="${title%'-'}"
    title=$(trim "$title")

    if [[ -n "$qual" ]]; then
      item="($qual)"
      [[ -n "$reason" ]] && item="($qual: $reason)"
    else
      item="(no reason recorded)"
    fi
    [[ -n "$title" ]] && item="$title $item"
    [[ -n "$id" ]] && item="$id — $item"
    DEFERRED_ITEMS+=("$item")
  done
  :
  } 2>/dev/null < "$file" || return 1
  return 0
}

# parse_verdict <tasks.md> — a `scale: spike` story (story 007) has no story.md
# and no requirements chain; its conclusion lives in a mandatory section:
#   ## Verdict
#   - status: open | promote | wont-do
#   - conclusion: <what was learned>
#   - promoted-to: NNN   # required when status: promote
# Only the first value of each key inside the section is read. `promoted-to`
# must start with a digit — that is what "the target is recorded" means, and it
# rejects the unfilled `NNN` placeholder of the template (fail-closed).
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

# assess_completion — THE completion rule, one function so no caller can grow a
# second dialect of it. Reads STORY_PATH, STORY_ID, FM_STATUS and the census
# counters; sets COMPLETE and, when that is false, INCOMPLETE_REASON — the text
# a refusal reports (R1.5). Call census_tasks first.
COMPLETE=false
INCOMPLETE_REASON=""
assess_completion() {
  local scale spike_rule
  COMPLETE=false
  INCOMPLETE_REASON=""
  scale=$(story_field scale)

  # A spike (story 007 R1.7) concludes through its `## Verdict` and only through
  # it: its checkboxes are probe steps, not a contract, so they must not be able
  # to declare it finished. `wont-do`, or `promote` with the follow-up story
  # recorded, is complete; anything else needs --force, the uniform escape hatch
  # (a spike whose lifecycle ended some other way archives through --force too).
  if [[ "$scale" == "spike" ]]; then
    spike_rule="a spike is archivable only with verdict 'wont-do' or 'promote' plus 'promoted-to:', or with --force <reason>"
    # The read is fallible (see census_tasks): report, never abort. Preflight's
    # readability gate normally catches this first — this is the backstop for a
    # permission that changes under us mid-run.
    if ! parse_verdict "$STORY_PATH/tasks.md"; then
      INCOMPLETE_REASON="cannot read '$STORY_PATH/tasks.md' — the spike's '## Verdict' cannot be read, so completion cannot be verified; nothing was modified"
      return 0
    fi
    case "$VERDICT_STATUS" in
      wont-do)
        COMPLETE=true
        ;;
      promote)
        if [[ -n "$VERDICT_PROMOTED_TO" ]]; then
          COMPLETE=true
        else
          INCOMPLETE_REASON="spike '$STORY_ID' has verdict 'promote' with no 'promoted-to:' story recorded — record the follow-up story number, or pass --force <reason>"
        fi
        ;;
      "")
        INCOMPLETE_REASON="spike '$STORY_ID' has no '## Verdict' section with a status — $spike_rule"
        ;;
      *)
        INCOMPLETE_REASON="spike '$STORY_ID' has verdict '$VERDICT_STATUS' — $spike_rule"
        ;;
    esac
    return 0
  fi

  # Every other scale (story 004): the status claims it, OR the boxes prove it.
  # A `[~]` box is closed by grammar and never counts as open.
  if [[ "$FM_STATUS" == "done" || "$FM_STATUS" == "validated" || "$FM_STATUS" == "superseded" ]]; then
    COMPLETE=true
  elif [[ ! -f "$STORY_PATH/tasks.md" ]]; then
    # A seed: story.md without tasks. "No `[ ]` remaining" is vacuously true
    # here, so it must be caught before the checkbox branch — otherwise every
    # seed would archive itself clean (design.md, Error Handling).
    INCOMPLETE_REASON="story '$STORY_ID' has no tasks.md (seed) — refine it, supersede it, or pass --force <reason>"
  elif [[ "$BOX_TOTAL" -eq 0 ]]; then
    # Same vacuous-truth hole: an unrecognized tasks.md dialect proves nothing.
    INCOMPLETE_REASON="story '$STORY_ID' has no parseable checkbox tasks (- [ ] N - ...) — completion cannot be verified; fix the format or pass --force <reason>"
  elif [[ "$BOX_OPEN" -eq 0 ]]; then
    COMPLETE=true
  else
    INCOMPLETE_REASON="story '$STORY_ID' is incomplete: $BOX_OPEN task checkbox(es) still open ([ ]) out of $BOX_TOTAL — pass --force <reason> to archive anyway"
  fi
  return 0
}

# find_epic_dir — walk up from the cwd looking for .epic/, so the NNN form works
# from any subdirectory of the project.
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
# its real reason instead of "not found"). Accepts 5 for 005.
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

# --- Manifest (step 5) ------------------------------------------------------
# The entry's fields, its two renderings (YAML for the file, JSON for the
# report) and the append itself.
#
# STDOUT AND THE MANIFEST AGREE, on both paths, by two different mechanisms:
#   append path — one composer (entry_json) renders the report from the very
#                 scalars manifest_entry_yaml writes, so they cannot drift;
#   resume path — the RECORDED entry is read back (manifest_read_entry) and
#                 reported verbatim. A fresh derivation would differ in
#                 archived_at on every run, and in overrides_used/forced_reason
#                 whenever the two runs were invoked with different flags — so
#                 re-deriving would print a report of an entry that does not
#                 exist. What the file says is what stdout says.

STORY_NUMBER=""
STORY_SLUG=""
STORY_TYPE=""
STORY_SCALE=""
ARCHIVED_AT=""

# derive_archived_at — the entry's timestamp, reported instead of fatal.
# `VAR=$(cmd)` takes the command's status, so a bare `ARCHIVED_AT=$(date …)`
# under `set -e` kills the shell with NO JSON on stdout — and `date -I` is
# GNU-only, so a BSD/macOS host hits exactly that. The POSIX format is tried
# next (same ISO-8601 instant, UTC), and only a host whose clock cannot be read
# at all gets a verdict — a `blocked` one, because an entry with no
# `archived_at` is a derived field the run cannot support.
derive_archived_at() {
  ARCHIVED_AT=$(date -Iseconds 2>/dev/null) && [[ -n "$ARCHIVED_AT" ]] && return 0
  ARCHIVED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) && [[ -n "$ARCHIVED_AT" ]] && return 0
  ARCHIVED_AT=""
  return 1
}

# derive_entry_fields — everything the entry reports, read from the story's own
# artifacts a moment before the move. Nothing here is passed in or declared:
# that is the whole point of R3.1 (the corpus's 71-story sweep stamped
# `complete-merged-to-master` on stories with 0/14 tasks done).
# Identity is <NNN>-<slug>; a directory that does not follow the convention
# still archives, with the fields it cannot fill left empty rather than guessed.
# Returns non-zero when a field cannot be derived; the caller turns that into a
# reported verdict rather than letting `set -e` end the run in silence.
DERIVE_ERR=""
derive_entry_fields() {
  DERIVE_ERR=""
  if [[ "$STORY_ID" =~ ^([0-9]+)-(.*)$ ]]; then
    STORY_NUMBER="${BASH_REMATCH[1]}"
    STORY_SLUG="${BASH_REMATCH[2]}"
  elif [[ "$STORY_ID" =~ ^([0-9]+)$ ]]; then
    STORY_NUMBER="$STORY_ID"
    STORY_SLUG=""
  else
    STORY_NUMBER=""
    STORY_SLUG="$STORY_ID"
  fi
  STORY_TYPE=$(story_field type)
  STORY_SCALE=$(story_field scale)
  if ! derive_archived_at; then
    DERIVE_ERR="cannot read the system clock ('date -Iseconds' and 'date -u +%Y-%m-%dT%H:%M:%SZ' both failed)"
    return 1
  fi
  # The census (BOX_*) already ran in preflight; only the [~] reasons are left.
  if ! collect_deferred_items "$STORY_PATH/tasks.md"; then
    DERIVE_ERR="cannot read '$STORY_PATH/tasks.md' to collect the deferred items"
    return 1
  fi
  return 0
}

# manifest_header — written once, only when the file does not exist (R3.3).
# The policy line is not decoration: recycling a number silently rewrites which
# story every existing reference points at, and once a story leaves stories/
# this file is the only place that still knows the number was ever used.
manifest_header() {
  cat <<'HEADER'
# Epic archive manifest — one entry per archived story, appended by
# scripts/archive-story.sh at the moment of the move.
#
# Every field is DERIVED from the story's own artifacts (checkbox census,
# frontmatter) at move time, never declared by hand: an entry can never claim a
# completion the checkboxes contradict.
#
# POLICY: Numbers are never recycled. A new story always takes the next highest
# number, even when a lower one now exists only in this file.
#
# Append-only. Everything under .epic/archive/ is read-only for tools
# (scripts/hook-archive-guard.sh); this file is written by that one script.
archived:
HEADER
}

# manifest_entry_yaml — the entry itself. `status` is the story's OWN
# frontmatter status, never a verdict this script invents: a --force'd archive
# of an in-progress story says `in-progress` and shows the open boxes (R3.2).
#
# THE KEY ORDER IS THE PARSER'S CONTRACT: manifest_read_entry reads entries back
# from this exact shape (2-space indent for the `- story:` item, 4 for its
# scalars, 6 for `pruned:`'s and for list items). Change one without the other
# and a resumed archive stops being able to report what it recorded.
manifest_entry_yaml() {
  printf '  - story: %s\n' "$(quote_scalar "$STORY_ID")"
  printf '    number: %s\n' "$(quote_scalar "$STORY_NUMBER")"
  printf '    slug: %s\n' "$(quote_scalar "$STORY_SLUG")"
  printf '    type: %s\n' "$(quote_scalar "$STORY_TYPE")"
  printf '    scale: %s\n' "$(quote_scalar "$STORY_SCALE")"
  printf '    status: %s\n' "$(quote_scalar "$FM_STATUS")"
  printf '    tasks_total: %d\n' "$BOX_TOTAL"
  printf '    tasks_closed: %d\n' "$BOX_CLOSED"
  printf '    tasks_deferred: %d\n' "$BOX_DEFERRED"
  printf '    tasks_open: %d\n' "$BOX_OPEN"
  yaml_list '    ' 'deferred_items' ${DEFERRED_ITEMS[@]+"${DEFERRED_ITEMS[@]}"}
  printf '    archived_at: %s\n' "$(quote_scalar "$ARCHIVED_AT")"
  printf '    pruned:\n'
  printf '      logs_kb: %d\n' "$PRUNED_LOGS_KB"
  printf '      copies_removed: %d\n' "$PRUNED_COPIES"
  yaml_list '    ' 'overrides_used' ${OVERRIDES_USED[@]+"${OVERRIDES_USED[@]}"}
  if [[ "$FORCE" == true ]]; then
    printf '    forced_reason: %s\n' "$(quote_scalar "$FORCE_REASON")"
  fi
}

# entry_json — THE renderer of the report's `manifest_entry` object, used by
# both the append path (from the live variables) and the resume path (from the
# scalars read back out of the manifest). One renderer, so the two paths cannot
# report different shapes for the same entry.
# Every scalar argument arrives ALREADY QUOTED (quote_scalar): a value recorded
# in the manifest is therefore spliced back in verbatim, with no unescape /
# re-escape round trip. The forced_reason argument is the empty string when the
# entry has none — the key is then omitted, as it is in the YAML.
entry_json() {
  local story="$1" number="$2" slug="$3" type="$4" scale="$5" status="$6"
  local total="$7" closed="$8" deferred="$9" open="${10}"
  local ditems="${11}" archived_at="${12}" logs="${13}" copies="${14}"
  local overrides="${15}" forced="${16:-}"
  printf '{ "story": %s, "number": %s, "slug": %s, "type": %s, "scale": %s, "status": %s, "tasks_total": %d, "tasks_closed": %d, "tasks_deferred": %d, "tasks_open": %d, "deferred_items": %s, "archived_at": %s, "pruned": { "logs_kb": %d, "copies_removed": %d }, "overrides_used": %s' \
    "$story" "$number" "$slug" "$type" "$scale" "$status" \
    "$total" "$closed" "$deferred" "$open" \
    "$ditems" "$archived_at" "$logs" "$copies" "$overrides"
  [[ -n "$forced" ]] && printf ', "forced_reason": %s' "$forced"
  printf ' }'
}

# json_array_raw <already-quoted items...> — a JSON array of tokens that are
# already valid JSON strings. Distinct from json_array, which quotes raw text.
json_array_raw() {
  local out="[" first=true item
  for item in "$@"; do
    [[ "$first" == true ]] || out+=","
    first=false
    out+="$item"
  done
  printf '%s]' "$out"
}

# manifest_entry_json — the live entry, for the `manifest_entry` report key.
manifest_entry_json() {
  local deferred overrides forced=""
  deferred=$(json_array ${DEFERRED_ITEMS[@]+"${DEFERRED_ITEMS[@]}"})
  overrides=$(json_array ${OVERRIDES_USED[@]+"${OVERRIDES_USED[@]}"})
  [[ "$FORCE" == true ]] && forced=$(quote_scalar "$FORCE_REASON")
  entry_json \
    "$(quote_scalar "$STORY_ID")" "$(quote_scalar "$STORY_NUMBER")" \
    "$(quote_scalar "$STORY_SLUG")" "$(quote_scalar "$STORY_TYPE")" \
    "$(quote_scalar "$STORY_SCALE")" "$(quote_scalar "$FM_STATUS")" \
    "$BOX_TOTAL" "$BOX_CLOSED" "$BOX_DEFERRED" "$BOX_OPEN" \
    "$deferred" "$(quote_scalar "$ARCHIVED_AT")" \
    "$PRUNED_LOGS_KB" "$PRUNED_COPIES" "$overrides" "$forced"
}

# manifest_read_entry — R3.4's other half, and the only thing that may decide a
# run is RESUMING. A run that died between the append and the move left the
# entry written and the story still in stories/; the re-run must FINISH that
# archive, not append a second entry. A story that archived successfully never
# reaches here (preflight refuses it), so an existing entry can only mean an
# unfinished archive.
#
# It keys on a COMPLETE entry, never on the first line of one. `  - story: "X"`
# is what the writer emits FIRST, so a process killed mid-entry leaves exactly
# the token the old check searched for — and the re-run then "resumed", skipped
# the append and archived the story behind a stub that names it and reports
# nothing else, permanently, under a tree that is deliberately hard to repair.
# Every field the writer emits must be present for the entry to count.
#
# Sets MANIFEST_ENTRY_STATE:
#   absent      no entry for this story — append one
#   complete    resume at the move; MANIFEST_RECORDED_JSON holds it, re-rendered
#   partial     a truncated entry — block, and say what to repair. Appending
#               beside it would leave two entries for one story; "resuming" it
#               would archive behind a record that claims nothing (R3.1).
#   unreadable  the manifest exists but could not be opened
MANIFEST_ENTRY_STATE="absent"
MANIFEST_RECORDED_JSON=""
MANIFEST_ENTRY_MISSING=""
manifest_read_entry() {
  local line raw list="" in_entry=false seen=0
  local want
  want="  - story: $(quote_scalar "$STORY_ID")"
  local v_story="" v_number="" v_slug="" v_type="" v_scale="" v_status=""
  local v_archived="" v_forced=""
  local n_total=0 n_closed=0 n_deferred=0 n_open=0 n_logs=0 n_copies=0
  local d_items=() o_items=() k
  MANIFEST_ENTRY_STATE="absent"
  MANIFEST_RECORDED_JSON=""
  MANIFEST_ENTRY_MISSING=""
  [[ -f "$MANIFEST_FILE" ]] || return 0
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      # A `  - ` line at the sequence indent starts a new entry: it ends ours.
      if [[ "$line" == "  - "* ]]; then
        [[ "$in_entry" == true ]] && break
        if [[ "$line" == "$want" ]]; then
          in_entry=true
          v_story=${line#"  - story: "}
          seen=$((seen + 1))
        fi
        continue
      fi
      [[ "$in_entry" == true ]] || continue
      if [[ -n "$list" && "$line" == "      - "* ]]; then
        raw=${line#"      - "}
        if [[ "$list" == deferred_items ]]; then d_items+=("$raw"); else o_items+=("$raw"); fi
        continue
      fi
      list=""
      case "$line" in
        "    number: "*) v_number=${line#"    number: "}; seen=$((seen + 1)) ;;
        "    slug: "*) v_slug=${line#"    slug: "}; seen=$((seen + 1)) ;;
        "    type: "*) v_type=${line#"    type: "}; seen=$((seen + 1)) ;;
        "    scale: "*) v_scale=${line#"    scale: "}; seen=$((seen + 1)) ;;
        "    status: "*) v_status=${line#"    status: "}; seen=$((seen + 1)) ;;
        "    archived_at: "*) v_archived=${line#"    archived_at: "}; seen=$((seen + 1)) ;;
        "    forced_reason: "*) v_forced=${line#"    forced_reason: "} ;;
        "    tasks_total: "*) n_total=${line#"    tasks_total: "}; seen=$((seen + 1)) ;;
        "    tasks_closed: "*) n_closed=${line#"    tasks_closed: "}; seen=$((seen + 1)) ;;
        "    tasks_deferred: "*) n_deferred=${line#"    tasks_deferred: "}; seen=$((seen + 1)) ;;
        "    tasks_open: "*) n_open=${line#"    tasks_open: "}; seen=$((seen + 1)) ;;
        "    deferred_items: []") seen=$((seen + 1)) ;;
        "    deferred_items:") list="deferred_items"; seen=$((seen + 1)) ;;
        "    overrides_used: []") seen=$((seen + 1)) ;;
        "    overrides_used:") list="overrides_used"; seen=$((seen + 1)) ;;
        "    pruned:") seen=$((seen + 1)) ;;
        "      logs_kb: "*) n_logs=${line#"      logs_kb: "}; seen=$((seen + 1)) ;;
        "      copies_removed: "*) n_copies=${line#"      copies_removed: "}; seen=$((seen + 1)) ;;
      esac
    done
    :
  } 2>/dev/null < "$MANIFEST_FILE" || {
    MANIFEST_ENTRY_STATE="unreadable"
    return 0
  }
  [[ "$in_entry" == true ]] || return 0
  # 16 keys: story number slug type scale status tasks_total tasks_closed
  # tasks_deferred tasks_open deferred_items archived_at pruned logs_kb
  # copies_removed overrides_used. forced_reason is optional by design.
  if [[ "$seen" -ne 16 ]]; then
    MANIFEST_ENTRY_STATE="partial"
    MANIFEST_ENTRY_MISSING="$seen of 16 fields present"
    return 0
  fi
  for k in n_total n_closed n_deferred n_open n_logs n_copies; do
    [[ "${!k}" =~ ^-?[0-9]+$ ]] || {
      MANIFEST_ENTRY_STATE="partial"
      MANIFEST_ENTRY_MISSING="a numeric field is not a number"
      return 0
    }
  done
  MANIFEST_RECORDED_JSON=$(entry_json \
    "$v_story" "$v_number" "$v_slug" "$v_type" "$v_scale" "$v_status" \
    "$n_total" "$n_closed" "$n_deferred" "$n_open" \
    "$(json_array_raw ${d_items[@]+"${d_items[@]}"})" "$v_archived" \
    "$n_logs" "$n_copies" \
    "$(json_array_raw ${o_items[@]+"${o_items[@]}"})" "$v_forced")
  MANIFEST_ENTRY_STATE="complete"
  return 0
}

# manifest_append — creates the file with its header when absent (R3.3), then
# appends the entry. Every write reports instead of aborting, so a failure
# becomes a `blocked` verdict with JSON on stdout rather than a bare non-zero
# exit; MANIFEST_ERR carries what the OS actually said, because "permission
# denied", "no space left on device" and "read-only file system" are three
# different fixes and only the kernel knows which one it is.
#
# ONE WRITE PER ENTRY. The entry is composed in memory first and appended with a
# single `printf`, not emitted field by field: a run killed between two of
# fourteen writes used to leave a stub entry on disk that nothing would ever
# repair. With O_APPEND (`>>`) a single write also cannot interleave with a
# concurrent run's.
#
# THE HEADER IS PUBLISHED ATOMICALLY, by writing it to a temp file in the same
# directory and hard-linking it into place: `ln` fails with EEXIST if the name
# is taken, so of two concurrent first-runs exactly one publishes and the other
# just appends. The previous `manifest_header > "$MANIFEST_FILE"` used `>`,
# which TRUNCATES — the second run erased the first run's entry while that run
# went on to report exit 0 and move its story, which is precisely the moved-
# story-without-an-entry state R3.4 exists to make impossible. Creating the file
# empty first (O_EXCL) would not do: the loser would append into the gap before
# the winner had written the header.
MANIFEST_ERR=""
manifest_append() {
  local entry
  entry=$(manifest_entry_yaml) || return 1
  MANIFEST_ERR=$(
    {
      mkdir -p "$ARCHIVE_DIR" || exit 1
      if [[ ! -e "$MANIFEST_FILE" ]]; then
        hdr=$(mktemp "$ARCHIVE_DIR/.manifest-header.XXXXXX") || exit 1
        manifest_header > "$hdr" || {
          rm -f "$hdr"
          exit 1
        }
        # EEXIST here means another run published first — not an error.
        ln "$hdr" "$MANIFEST_FILE" 2> /dev/null || true
        rm -f "$hdr"
      fi
      printf '%s\n' "$entry" >> "$MANIFEST_FILE" || exit 1
    } 2>&1
  ) && return 0
  # Bash prefixes a failed redirection with "<script>: line N: <path>: "; drop
  # both (the caller already names the file) and flatten to one line, so what
  # survives into the JSON report is the part only the kernel could tell us.
  MANIFEST_ERR=${MANIFEST_ERR//$'\n'/; }
  MANIFEST_ERR=${MANIFEST_ERR#*: line *: }
  MANIFEST_ERR=${MANIFEST_ERR#"$MANIFEST_FILE": }
  return 1
}

# --- Move + status transition (steps 6-7) -----------------------------------

# epic_git — git, with the four environment variables that RE-POINT it at
# another repository removed. `git -C <dir>` sets the working directory; it does
# NOT override GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE/GIT_OBJECT_DIRECTORY, which
# are exactly what is set whenever this script runs from a git hook, from
# `git rebase --exec`, or from any wrapper that exports them. Without this, the
# probes below answer about a DIFFERENT repository than the one holding the
# story, and the `git mv` would write the rename into that repository's index.
epic_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY \
    git "$@"
}

# git_dir_above — is there a `.git` anywhere at or above $EPIC_DIR? Asked as a
# FILESYSTEM question so that "git refused to answer" can be told apart from
# "there is genuinely no repository here" without parsing git's messages, which
# are localized. `-e` covers `.git` as a file (submodule / linked work tree).
git_dir_above() {
  local dir="$EPIC_DIR"
  while :; do
    [[ -e "$dir/.git" ]] && return 0
    [[ "$dir" == "/" ]] && return 1
    dir=$(dirname "$dir")
  done
}

# in_git_worktree — is there a git work tree that owns these paths? The question
# is asked from $EPIC_DIR, the common parent of the source and the destination,
# so the answer is about the repo that would own BOTH — never one discovered
# from whatever directory the caller happened to run from.
#
# GIT_STATE records WHICH negative answer it was, and the three are not the
# same fact: `no-binary` is a machine fact, `no-repo` is a workspace fact
# (both mean plain move, R6.2), and `error` means a repository IS there and git
# would not answer about it — dubious ownership (a root-owned checkout, a
# container bind mount, a run under sudo), an unreadable index, a ceiling
# directory. That last one must NOT be read as "no repo": doing so silently
# takes the plain branch on a TRACKED story and drops the history R6.1 exists
# to preserve, so it becomes a block instead.
GIT_STATE=""
GIT_PROBE_ERR=""
in_git_worktree() {
  local out rc
  GIT_PROBE_ERR=""
  if ! command -v git > /dev/null 2>&1; then
    GIT_STATE="no-binary"
    return 1
  fi
  out=$(epic_git -C "$EPIC_DIR" rev-parse --is-inside-work-tree 2>&1) && rc=0 || rc=$?
  if [[ $rc -eq 0 ]]; then
    [[ "$out" == "true" ]] && {
      GIT_STATE="worktree"
      return 0
    }
    GIT_STATE="no-repo" # a bare repo answers "false" — nothing to `git mv` into
    return 1
  fi
  if git_dir_above; then
    GIT_STATE="error"
    GIT_PROBE_ERR=${out//$'\n'/; }
    return 1
  fi
  GIT_STATE="no-repo"
  return 1
}

# story_is_tracked — at least one file under the story directory is in the
# index. `--error-unmatch` turns "matched nothing" into a non-zero exit instead
# of empty output, so the answer IS the exit code and nothing has to be parsed.
#
# Exit 1 (untracked) and exit 128 are DIFFERENT answers and are kept apart here:
# 128 is git failing to answer at all — the story sits in a submodule relative
# to $EPIC_DIR, or outside the work tree, or the index cannot be read. Collapsing
# it into "untracked", as a plain `2>&1; return $?` does, picks the plain move
# for a story whose history git may well be holding. Fail-closed instead:
#   0 -> tracked   1 -> untracked   2 -> git could not answer (GIT_PROBE_ERR)
story_is_tracked() {
  local out rc
  GIT_PROBE_ERR=""
  out=$(epic_git -C "$EPIC_DIR" ls-files --error-unmatch -- "$STORY_ABS" 2>&1 > /dev/null) && rc=0 || rc=$?
  case "$rc" in
    0) return 0 ;;
    1) return 1 ;;
    *)
      GIT_PROBE_ERR=${out//$'\n'/; }
      return 2
      ;;
  esac
}

MOVE_MODE="plain"   # git | plain — which branch step 6 takes
MOVE_WHY=""         # why that branch, for the stderr boundary log
MOVE_ERR=""

# choose_move_mode — the R6.1/R6.2 decision, three inputs and two branches:
#   no git binary / not a work tree -> plain mv   (R6.2)
#   work tree, story untracked      -> plain mv   (R6.2)
#   work tree, story (partly) tracked -> git mv   (R6.1)
#   work tree, git cannot answer    -> non-zero: the caller BLOCKS (fail-closed)
#
# TRACKEDNESS IS DECIDED ON THE DIRECTORY, not per file, and a PARTIALLY tracked
# story (some files committed, some new) takes the git branch. That is the
# fail-safe choice, not the permissive one: `git mv` on a directory is a single
# rename(2) of the whole directory, so untracked files travel with it exactly as
# a plain `mv` would move them, while the tracked ones additionally keep their
# history. The git branch is a strict superset of the plain one — choosing `mv`
# for a partially tracked story would silently drop the history of every file
# git DOES know about, which is the one thing R6.1 forbids.
choose_move_mode() {
  local rc
  if ! in_git_worktree; then
    if [[ "$GIT_STATE" == "error" ]]; then
      MOVE_WHY="git found a repository at or above '$EPIC_DIR' but would not answer about it${GIT_PROBE_ERR:+: $GIT_PROBE_ERR}"
      return 1
    fi
    MOVE_MODE="plain"
    [[ "$GIT_STATE" == "no-binary" ]] && MOVE_WHY="no git binary on PATH" || MOVE_WHY="no git work tree"
    return 0
  fi
  story_is_tracked && rc=0 || rc=$?
  case "$rc" in
    0)
      MOVE_MODE="git"
      MOVE_WHY="story files are tracked"
      ;;
    1)
      MOVE_MODE="plain"
      MOVE_WHY="story files are untracked"
      ;;
    *)
      MOVE_WHY="git could not decide whether '$STORY_ID' is tracked${GIT_PROBE_ERR:+: $GIT_PROBE_ERR}"
      return 1
      ;;
  esac
  return 0
}

# move_story <destination> — the move itself, in the chosen mode. Every failure
# is captured and returned instead of aborting: a bare non-zero under `set -e`
# would print no JSON at all, and stdout is what the consumers parse.
#
# There is deliberately NO FALLBACK from `git mv` to `mv`. `git mv` renames the
# directory with one rename(2), so a failure means nothing moved — the manifest
# entry is still there and the re-run resumes at this very step. Retrying as a
# plain `mv` would convert a recoverable stop into the silent loss of exactly
# the history R6.1 exists to preserve.
#
# The git branch runs through epic_git for the same reason the probes do: if the
# ambient GIT_DIR named another repository, the probe and the move would have to
# agree about WHICH repository, and staging a rename into a foreign index is not
# a recoverable stop.
move_story() {
  local dest="$1"
  if [[ "$MOVE_MODE" == "git" ]]; then
    MOVE_ERR=$(epic_git -C "$EPIC_DIR" mv -- "$STORY_ABS" "$dest" 2>&1) && return 0
  else
    MOVE_ERR=$(mv -- "$STORY_ABS" "$dest" 2>&1) && return 0
  fi
  MOVE_ERR=${MOVE_ERR//$'\n'/; }
  return 1
}

# apply_archived_status <moved-story-dir> — step 7. `status: archived` in the
# frontmatter of every artifact the moved story carries: status is a STORY-level
# fact, one story one status, and validate-story.sh reports artifacts that
# disagree with each other. Top-level `*.md` only — the same set validate-story.sh
# reads; `.draft/` holds working copies, not the story's lifecycle claim.
#
# Written with `sed -i` from Bash ON PURPOSE. hook-archive-guard.sh blocks the
# Edit/Write TOOLS anywhere under .epic/archive/**, and cannot see Bash file
# operations — which is why this script is the sanctioned way to touch an
# archived artifact at all (design.md, Overview).
#
# Two cases, because a legacy artifact may carry no `status:` line at all and
# skipping it would leave it claiming nothing forever:
#   present -> substitute, ADDRESS-RESTRICTED to the frontmatter (`1,/^---$/`)
#              so a body line that merely starts with `status:` is never touched
#   absent  -> insert before the CLOSING `---`, the position the templates use
# Then every file is RE-READ. `sed` exits 0 when its address matched nothing —
# an unterminated frontmatter block is the realistic case — so the exit code
# alone cannot tell "written" from "silently did nothing"; only the re-read can.
#
# CRLF: the artifact's own line ending is detected from line 1 and carried into
# both the address and the replacement, so a `---\r` delimiter is recognised and
# the written line keeps the file's ending. Without it, a checkout with
# core.autocrlf=true skipped every CRLF artifact while applying the change to
# the LF ones — the story archived with story.md still claiming `done` and
# tasks.md claiming `archived`, and the "nothing applied" note stayed silent
# because something HAD been applied. Which is why STATUS_SKIPPED_TEXT now
# exists: a PARTIAL application has to be as loud as an empty one.
#
# CAVEAT, `sed -i` on a SYMLINKED artifact: GNU sed writes a temp file and
# renames it over the path, so the symlink is REPLACED by a regular file (and a
# foreign-owned file in a writable directory changes owner to the caller). Rare
# enough inside a story directory not to be worth blocking on, common enough to
# say out loud — each one is named on stderr as it is rewritten.
STATUS_APPLIED=0
STATUS_FAILED_TEXT=""
STATUS_SKIPPED_TEXT=""
apply_archived_status() {
  local dir="$1" f name err eol
  STATUS_APPLIED=0
  STATUS_FAILED_TEXT=""
  STATUS_SKIPPED_TEXT=""
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f")
    # No frontmatter block: the artifact makes no lifecycle claim, so there is
    # none to correct. Inventing a block inside someone's file is over-reach —
    # but it does leave that artifact disagreeing with the rest, so it is named.
    if ! head -1 "$f" | grep -Eq "$FM_DELIM_RE" 2> /dev/null; then
      STATUS_SKIPPED_TEXT="${STATUS_SKIPPED_TEXT:+$STATUS_SKIPPED_TEXT; }$name"
      continue
    fi
    eol=""
    head -1 "$f" | grep -q $'\r$' 2> /dev/null && eol=$'\r'
    [[ -L "$f" ]] && printf 'archive-story: %s is a symlink — sed -i replaces it with a regular file\n' "$f" >&2
    if [[ -n "$(frontmatter_field "$f" status)" ]]; then
      err=$(sed -i "1,/^---$eol\$/s/^status:.*\$/status: archived$eol/" "$f" 2>&1) || true
    else
      err=$(sed -i "2,/^---$eol\$/s/^---$eol\$/status: archived$eol\\n---$eol/" "$f" 2>&1) || true
    fi
    if [[ "$(frontmatter_field "$f" status)" == "archived" ]]; then
      STATUS_APPLIED=$((STATUS_APPLIED + 1))
    else
      err=${err//$'\n'/; }
      STATUS_FAILED_TEXT="${STATUS_FAILED_TEXT:+$STATUS_FAILED_TEXT; }$name${err:+ ($err)}"
    fi
  done
  # Empty text IS the success condition, so the failure list and the verdict
  # cannot drift apart the way a separate counter would.
  [[ -z "$STATUS_FAILED_TEXT" ]]
}

# --- Flag parsing -----------------------------------------------------------
# Unknown flag => exit 2 (invalid input), before anything is read or resolved.
# Every override used is collected for the manifest entry (R1.4, R1.6, R2.3).
TARGET=""
ALLOW_HEAVY=false
SKIP_SECRETS=false
KEEP_LOGS=false
KEEP_COPIES=false
FORCE=false
FORCE_REASON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help | -h)
      print_help
      exit 0
      ;;
    --allow-heavy)
      ALLOW_HEAVY=true
      OVERRIDES_USED+=("allow-heavy")
      shift
      ;;
    --skip-secrets)
      SKIP_SECRETS=true
      OVERRIDES_USED+=("skip-secrets")
      shift
      ;;
    --keep-logs)
      KEEP_LOGS=true
      OVERRIDES_USED+=("keep-logs")
      shift
      ;;
    --keep-copies)
      KEEP_COPIES=true
      OVERRIDES_USED+=("keep-copies")
      shift
      ;;
    --force)
      # The reason is REQUIRED: a forced archive that cannot say why is exactly
      # the silent mass-sweep this script exists to prevent (R1.6).
      shift
      if [[ $# -eq 0 || -z "${1:-}" || "${1:-}" == -* ]]; then
        usage_error "--force requires a reason argument: --force <reason>"
      fi
      FORCE=true
      FORCE_REASON="$1"
      OVERRIDES_USED+=("force")
      shift
      ;;
    --)
      # End of options: everything after it is the story, even if it starts
      # with `-`. Without this, a directory named `-005-x` is unreachable —
      # it can only ever be reported as an unknown flag.
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

# --- Story resolution -------------------------------------------------------
EPIC_DIR=""
if [[ -d "$TARGET" ]]; then
  STORY_PATH="${TARGET%/}"
elif [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  EPIC_DIR=$(find_epic_dir) ||
    usage_error "no .epic/ directory found from $(pwd) — run inside an Epic project or pass the story directory"
  STORY_PATH=$(resolve_by_number "$TARGET" "$EPIC_DIR") ||
    usage_error "story '$TARGET' not found under $EPIC_DIR/stories or $EPIC_DIR/archive"
else
  usage_error "story '$TARGET' not found — pass a story number (005) or its directory"
fi

STORY_ABS=$(cd "$STORY_PATH" 2>/dev/null && pwd -P) ||
  usage_error "cannot resolve story directory '$STORY_PATH'"
STORY_ID=$(basename "$STORY_ABS")
STORY_PARENT=$(basename "$(dirname "$STORY_ABS")")
# The manifest (step 5, sub-task 1.2) lives at $EPIC_DIR/archive/manifest.yaml.
# EVERY destination is derived from the story's PHYSICAL location, so the two
# checks below are what keep the whole operation inside the project.
EPIC_DIR=$(dirname "$(dirname "$STORY_ABS")")
ARCHIVE_DIR="$EPIC_DIR/archive"
MANIFEST_FILE="$ARCHIVE_DIR/manifest.yaml"

# The story directory must not be a symlink out of the project. `pwd -P`
# resolves it, and everything downstream is then re-derived from the PHYSICAL
# path: a `.epic/stories/005-x -> /elsewhere/shared/stories/005-x` archived
# itself into /elsewhere/shared/archive/, created that directory, wrote the
# manifest there, reported `path: .epic/stories/005-x` (where the story is NOT)
# and exited 0 — while the project's own manifest never learned the story was
# archived and the destination sat outside the tree hook-archive-guard.sh
# protects. Fail closed: the physical parent of the story must be the same
# directory the logical path reaches.
STORY_LOGICAL_PARENT=$(cd "$(dirname "$STORY_PATH")" 2>/dev/null && pwd -P) ||
  usage_error "cannot resolve the parent of story directory '$STORY_PATH'"
if [[ "$STORY_LOGICAL_PARENT" != "$(dirname "$STORY_ABS")" ]]; then
  refuse "'$STORY_PATH' is a symlink to '$STORY_ABS', outside '$STORY_LOGICAL_PARENT' — archive derives the manifest and the destination from the story's real location, so it would write outside this project (and outside what hook-archive-guard.sh protects); nothing was modified"
fi

# ...and that parent chain must be an .epic/ directory. `stories/` alone is not
# enough: `/anywhere/stories/005-x` also has a parent named `stories`.
if [[ "$(basename "$EPIC_DIR")" != ".epic" ]]; then
  usage_error "'$STORY_PATH' does not live in a .epic/ directory (resolved to '$STORY_ABS') — expected <project>/.epic/stories/<NNN>-<slug>"
fi

# ============================================================================
# STEP 1 — PREFLIGHT (R1.5, R1.6, R1.7)
# ============================================================================

# Readability, before anything is read. `[[ -f ]]` says a file EXISTS; it does
# not say it can be opened, and every reader below feeds a `while … done < "$f"`
# whose failed redirection would end the run with no JSON on stdout at all.
# Checked once, here, for the two artifacts the whole script reads — and the
# readers keep their own guards for a permission that changes mid-run.
for _artifact in story.md tasks.md; do
  if [[ -e "$STORY_PATH/$_artifact" && ! -r "$STORY_PATH/$_artifact" ]]; then
    refuse "cannot read '$STORY_PATH/$_artifact' — the manifest entry is DERIVED from it, so an archive that cannot read it would have to invent the numbers it records (R3.1); fix the permissions and re-run. Nothing was modified"
  fi
done
unset _artifact

# Location. Archive operates on .epic/stories/<NNN>-<slug>; a story already in
# archive/ is REFUSED (exit 1, nothing touched — R1.7), anything else is invalid
# input (exit 2). The archived check comes first so R1.7 reports its real reason
# rather than tripping over a missing tasks.md.
FM_STATUS=$(story_field status)

if [[ "$STORY_PARENT" == "archive" || "$FM_STATUS" == "archived" ]]; then
  refuse "story '$STORY_ID' is already archived ($STORY_PATH) — archived stories are read-only, nothing was modified"
fi

if [[ "$STORY_PARENT" != "stories" ]]; then
  usage_error "'$STORY_PATH' is not a story directory — expected .epic/stories/<NNN>-<slug>"
fi

if [[ ! -f "$STORY_PATH/story.md" && ! -f "$STORY_PATH/tasks.md" ]]; then
  usage_error "'$STORY_PATH' holds no story.md or tasks.md — not a story directory"
fi

# Completion (assess_completion holds the rule itself): a spike concludes
# through its Verdict, every other scale through story 004's status-OR-boxes.
if ! census_tasks "$STORY_PATH/tasks.md"; then
  refuse "cannot read '$STORY_PATH/tasks.md' — the checkbox census cannot be taken, so neither completion nor the entry's task counts can be derived; nothing was modified"
fi
assess_completion

if [[ "$COMPLETE" != true ]]; then
  if [[ "$FORCE" == true ]]; then
    # R1.6: forced. The reason travels to the manifest entry (sub-task 1.2) —
    # a forced archive that does not say why is the failure mode this replaces.
    printf 'Forced archive of an incomplete story: %s\n' "$FORCE_REASON" >&2
  else
    # An orphan entry has no command of its own to clean it: run 1 with --force
    # that dies before the move leaves the entry behind, and run 2 WITHOUT
    # --force is refused right here, never reaching the resume. Say so, or the
    # operator has no way to connect the refusal to the record it left.
    manifest_read_entry
    if [[ "$MANIFEST_ENTRY_STATE" != "absent" ]]; then
      INCOMPLETE_REASON="$INCOMPLETE_REASON — NOTE: '$MANIFEST_FILE' already holds a ($MANIFEST_ENTRY_STATE) entry for this story from an interrupted run; re-run with --force <reason> to finish that archive, or delete the entry by hand"
    fi
    refuse "$INCOMPLETE_REASON"
  fi
fi

# ============================================================================
# STUB — STEPS 2-4: WEIGHT/BINARY GUARD, SECRETS GUARD, PRUNE
#                   (sub-tasks 2.1, 2.2, 3.1, 3.2)
# ============================================================================
# They belong HERE, between preflight and the manifest append: nothing
# destructive may run before every guard has passed, and pruning must happen
# before the entry is derived so `pruned {}` reports what actually happened.
# Until they land, guard.violations stays empty, secrets stays {} and pruned
# reports zeroes — which the report says as "not run", never as "clean".

# Boundary log: the run's configuration, once, at the point where preflight has
# passed and the destructive half begins. Which guards were overridden is the
# first question anyone debugging an archive asks, and stdout is reserved for
# the JSON report, so it goes to stderr as key=value.
printf 'archive-story: story=%s allow_heavy=%s skip_secrets=%s keep_logs=%s keep_copies=%s force=%s\n' \
  "$STORY_ID" "$ALLOW_HEAVY" "$SKIP_SECRETS" "$KEEP_LOGS" "$KEEP_COPIES" "$FORCE" >&2

# ============================================================================
# STEP 5 — MANIFEST APPEND (R3.1, R3.2, R3.3, R3.4)
# ============================================================================
# The entry is DERIVED, never declared: every number comes from the story's own
# artifacts read a moment before the move — the checkbox census and the
# frontmatter — so an entry can never claim a completion the checkboxes
# contradict (the corpus's 71-story sweep stamped `complete-merged-to-master`
# on stories with 0/14 tasks; that is what "derived" exists to make impossible).
#
# And it is appended BEFORE the move (R3.4). If the process dies between the
# two, the manifest holds an entry for a story still sitting in stories/ — a
# visible, recoverable inconsistency the next run completes. The reverse order
# would lose the story's record entirely, which nothing can reconstruct.

# ARCHIVE_DIR / MANIFEST_FILE are set at story resolution — preflight's orphan
# note needs them before this point.

if ! derive_entry_fields; then
  block "cannot derive the manifest entry for '$STORY_ID': $DERIVE_ERR — nothing was moved: the entry is written BEFORE the move, so an archive that cannot be recorded does not happen (R3.4)"
fi

manifest_read_entry
case "$MANIFEST_ENTRY_STATE" in
  complete)
    # A previous run wrote the entry and never reached the move. Resume there,
    # and report the entry THAT RUN recorded — not a fresh derivation of it.
    # archived_at alone would already differ on every re-run, and the overrides
    # differ whenever the two runs were invoked with different flags.
    printf 'archive-story: manifest already holds a complete entry for %s (interrupted run) — resuming at the move; the report describes the RECORDED entry\n' \
      "$STORY_ID" >&2
    MANIFEST_JSON="$MANIFEST_RECORDED_JSON"
    ;;
  partial)
    block "'$MANIFEST_FILE' holds a TRUNCATED entry for '$STORY_ID' ($MANIFEST_ENTRY_MISSING) — a run that died mid-append left it. Resuming behind it would archive the story behind a record that claims nothing, and appending beside it would leave two entries for one story: delete the truncated entry by hand and re-run. Nothing was moved"
    ;;
  unreadable)
    block "cannot read '$MANIFEST_FILE' — whether '$STORY_ID' is already recorded cannot be established, and appending blind risks a second entry for one story; nothing was moved"
    ;;
  *)
    if ! manifest_append; then
      block "cannot write the manifest entry to '$MANIFEST_FILE'${MANIFEST_ERR:+: $MANIFEST_ERR} — nothing was moved: the entry is written BEFORE the move, so an archive that cannot be recorded does not happen (R3.4)"
    fi
    MANIFEST_JSON=$(manifest_entry_json)
    ;;
esac

# ============================================================================
# STEP 6 — MOVE (R1.1, R6.1, R6.2)
# ============================================================================
# `git mv` when the story is tracked, plain `mv` otherwise — and the difference
# is not cosmetic. A plain `mv` of tracked files stages nothing: git sees a
# deletion in the work tree and an untracked directory, and only reconstructs
# the rename LATER, by content similarity, if and when somebody commits both
# halves together. Land them in two commits, or let the content drift past the
# similarity threshold, and everything before the archive stops being reachable
# from the archived path. `git mv` records the rename in the index at the moment
# of the move, which is the only form of the guarantee this script can make.

# Every failure BEFORE the move ends the same way: the manifest entry is on
# disk and the story is not, so a re-run skips the append (manifest_read_entry
# reports `complete`) and resumes at this step. Said once here, used by each of
# them. It stops applying the moment the move succeeds — see step 7.
# It carries the --force caveat because a forced archive's entry records flags
# that a re-run WITHOUT --force never gets to reuse: preflight refuses first.
RESUME_HINT="the manifest entry is already written; fix the cause and re-run${FORCE:+ (with the same --force <reason>: preflight refuses an incomplete story before the resume is reached)} to finish this archive"

# The destination's PARENT must exist for both branches: `git mv` fails hard
# (exit 128, "renaming ... failed") when it does not, and step 5 skips its own
# mkdir on the resume path (an entry already written => no manifest_append).
if [[ ! -d "$ARCHIVE_DIR" ]] && ! mkdir -p "$ARCHIVE_DIR" 2> /dev/null; then
  block "cannot create the archive directory '$ARCHIVE_DIR' — nothing was moved; $RESUME_HINT"
fi

# An occupied slot is always a bug. BOTH `mv` and `git mv` move the source
# INSIDE an existing destination directory (archive/NNN-x/NNN-x) rather than
# failing — a silent corruption — and under "numbers are never recycled" there
# is no legitimate overwrite to perform. Checked before either branch runs.
# `-e || -L`, not `-e` alone: `-e` follows the link and is FALSE for a DANGLING
# symlink, which then lets the move through to fail with a bare ENOTDIR.
if [[ -e "$ARCHIVE_DIR/$STORY_ID" || -L "$ARCHIVE_DIR/$STORY_ID" ]]; then
  block "'$ARCHIVE_DIR/$STORY_ID' already exists — refusing to move '$STORY_ID' into an occupied slot (numbers are never recycled); nothing was moved"
fi

# A move mode this script cannot establish is not a move it may guess at: the
# only guess available is the plain branch, and taking it on a story git DOES
# hold the history of is precisely what R6.1 forbids.
if ! choose_move_mode; then
  block "cannot decide how to move '$STORY_ID' — $MOVE_WHY. Refusing to guess: the fallback would be a plain 'mv', which drops the git history of every tracked file (R6.1). Nothing was moved; $RESUME_HINT"
fi
printf 'archive-story: move_mode=%s reason=%s\n' "$MOVE_MODE" "$MOVE_WHY" >&2

if ! move_story "$ARCHIVE_DIR/$STORY_ID"; then
  # `git mv` writes the index AFTER rename(2), so it can fail non-zero with the
  # directory ALREADY MOVED. Ask the filesystem instead of assuming: telling the
  # operator "nothing was moved; re-run" would be false AND unactionable, since
  # preflight refuses the re-run as already archived.
  if [[ -d "$ARCHIVE_DIR/$STORY_ID" ]]; then
    MOVED=true
    block "${MOVE_ERR:-cannot move '$STORY_PATH' to '$ARCHIVE_DIR/$STORY_ID'} — but '$STORY_ID' IS now at '$ARCHIVE_DIR/$STORY_ID': the rename completed and the step after it did not (git stages the rename only after moving the files). Do NOT re-run — preflight would refuse it as already archived. Finish by hand: 'git add -A' the two paths so the rename is recorded, and set 'status: archived' in the moved artifacts' frontmatter"
  fi
  # The entry is already in the manifest, and that is the direction R3.4
  # chooses: an entry without a move is visible and the next run completes it
  # (manifest_read_entry reports `complete`), while a move without an entry
  # loses the story's record with nothing left to reconstruct it from.
  # mv's / git mv's own message already names both paths and the errno, so it
  # IS the reason; the fallback covers a move that fails without saying why.
  block "${MOVE_ERR:-cannot move '$STORY_PATH' to '$ARCHIVE_DIR/$STORY_ID'} — nothing was moved; $RESUME_HINT"
fi

# A fact about the filesystem, recorded the instant it becomes true. From here
# on EVERY exit path — including a step-7 failure — reports where the story
# actually is; a `moved: false` for a directory demonstrably sitting in
# .epic/archive/ would send its reader looking in the wrong place.
MOVED=true

# ============================================================================
# STEP 7 — STATUS: ARCHIVED (R1.1)
# ============================================================================
# The move alone leaves every artifact claiming the state it had a second ago.
# `status: archived` is what makes the artifacts agree with their own location,
# and it is applied AFTER the move, in place, in the archive — deliberately, so
# there is never a window where a story in stories/ claims to be archived.
#
# NOTE the reason below does NOT offer RESUME_HINT: past the move, a re-run no
# longer resumes anything. Preflight resolves the story in archive/ and REFUSES
# it as already archived (R1.7), which is correct — so the message has to hand
# the operator the repair itself instead of a re-run that will not run.
if ! apply_archived_status "$ARCHIVE_DIR/$STORY_ID"; then
  block "moved '$STORY_ID' to '$ARCHIVE_DIR/$STORY_ID' but could not set 'status: archived' in: $STATUS_FAILED_TEXT — the story is ARCHIVED ON DISK while its frontmatter still says '${FM_STATUS:-(none)}'; repair those files with an editor or Bash (archived artifacts are read-only for the Edit/Write tools) — the archive is NOT complete until they agree"
fi

if [[ "$STATUS_APPLIED" -eq 0 ]]; then
  # Legal, but worth saying out loud: no artifact carries frontmatter, so the
  # archived state is recorded only by the manifest entry and the location.
  printf 'archive-story: no artifact with frontmatter in %s — archived state recorded in the manifest and the location only\n' \
    "$STORY_ID" >&2
elif [[ -n "$STATUS_SKIPPED_TEXT" ]]; then
  # A PARTIAL application is the worse case, and it used to be the silent one:
  # some artifacts say `archived`, the skipped ones still claim what they
  # claimed before the move, and the story is now in archive/ with its own
  # artifacts contradicting each other — the divergence validate-story.sh
  # reports. One story, one status: if they do not agree, say which.
  printf 'archive-story: %s carries no frontmatter and was left claiming its pre-archive state — the artifacts of %s now DISAGREE (%d updated); add a frontmatter block or accept the divergence\n' \
    "$STATUS_SKIPPED_TEXT" "$STORY_ID" "$STATUS_APPLIED" >&2
fi

# ============================================================================
# STUB — STEP 8: INDEX REGENERATION (sub-tasks 4.1, 4.2)
# ============================================================================
# Step 8 regenerates the .epic/EPIC.md index block. Until it lands, `index`
# stays "skipped" — a regeneration that never ran must never report "ok".

STATUS="archived"
printf 'archive-story: status=archived artifacts_updated=%d\n' "$STATUS_APPLIED" >&2
printf 'Archived: %s -> %s\n' "$STORY_PATH" "$ARCHIVE_DIR/$STORY_ID" >&2
emit_report
exit 0
