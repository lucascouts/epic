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
#   2. weight/binary guard ...... sub-task 2.1  (implemented — R1.2/R1.4)
#   3. secrets guard ............ sub-task 2.2  (implemented — R1.3/R1.4/R1.8)
#   4. prune .draft/logs ........ sub-task 3.1  (implemented — R2.1/R2.3)
#      prune .draft copies ...... sub-task 3.2  (implemented — R2.2/R2.3)
#   5. manifest append .......... sub-task 1.2  (implemented — before the move, R3.4)
#   6. move ..................... sub-task 1.3  (implemented — git mv / mv, R6.1/R6.2)
#   7. status: archived ......... sub-task 1.3  (implemented)
#   8. index regeneration ....... sub-tasks 4.1 / 4.2 (implemented — R5.2)
# Step 4 is the FIRST DESTRUCTIVE STEP, and its position is asserted in the
# script (GUARDS_PASSED, read by BOTH of its halves), not only stated here.
# Step 8 is LAST, and it is the one step that never rolls back: the index is a
# RENDERING of the move, so a failure there warns (`index: "regen-failed"`) and
# the archive still stands.

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
guard{violations[{file, size, reason}]}, secrets, index, overrides_used,
manifest_entry}. Diagnostics on stderr.

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
                       # `skipped` is the INITIAL value and it means exactly
                       # that: a refusal or a guard block exited before step 8,
                       # so the index still matches the disk. It is never
                       # written by step 8 itself — see regenerate_index.
SECRETS_JSON='{}'      # filled by the secrets guard (sub-task 2.2)
MANIFEST_JSON='{}'     # filled by the manifest step (sub-task 1.2)
# guard.violations[] holds RENDERED JSON OBJECTS — {file, size, reason} — not
# raw strings: R1.2 asks for the size and the reason of every offender, and a
# consumer that has to parse those back out of one prose sentence is a consumer
# that will parse them wrong. Append only through add_violation, and read only
# through json_array_raw (json_array would re-quote the objects into strings).
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
  violations=$(json_array_raw ${GUARD_VIOLATIONS[@]+"${GUARD_VIOLATIONS[@]}"})
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

# --- Weight/binary guard (step 2) -------------------------------------------
# R1.2: a file larger than 10 MB, or one that is not text, blocks the archive
# with every offender listed and NOTHING moved. The corpus evidence is a single
# 2.3 GB binary and 104 PNGs that went into an archive nobody could clone again.
#
# THE LIMIT IS INCLUSIVE: R1.2 blocks a file LARGER than 10 MB, so exactly
# 10485760 bytes (10 MiB) passes and one byte more does not.
GUARD_MAX_BYTES=10485760

# The census convention: a manual integer counter, never ${#arr[@]} on an array
# that may be empty. GUARD_OFFENDER_TEXT is the same list rendered as prose, for
# the human `reason` — built beside the objects so the two cannot drift.
GUARD_VIOLATION_COUNT=0
GUARD_OFFENDER_TEXT=""
GUARD_SCANNED=0

# add_violation <display-path> <size|""> <reason> — one entry of
# guard.violations[]. `size` is emitted as a JSON NUMBER, or as `null` when it
# could not be established: a size the guard failed to read must not be
# reported as a size it read. Every string goes through quote_scalar — a
# filename may legally contain a quote, a newline, a DEL or a C1 byte, and this
# one is the union escaper that both JSON and YAML accept.
add_violation() {
  local file="$1" size="$2" reason="$3" size_json="null" shown="$1"
  [[ "$size" =~ ^[0-9]+$ ]] && size_json="$size"
  GUARD_VIOLATIONS+=("$(printf '{ "file": %s, "size": %s, "reason": %s }' \
    "$(quote_scalar "$file")" "$size_json" "$(quote_scalar "$reason")")")
  GUARD_VIOLATION_COUNT=$((GUARD_VIOLATION_COUNT + 1))
  [[ "$size_json" == "null" ]] || shown="$file ($size bytes)"
  GUARD_OFFENDER_TEXT="${GUARD_OFFENDER_TEXT:+$GUARD_OFFENDER_TEXT; }$shown: $reason"
  return 0
}

# file_size <path> — the PORTABLE PAIR, and both halves are needed: `-c` is a
# GNU format string, `-f` is the BSD one — and on GNU stat `-f` means the FILE
# SYSTEM, so it fails there and the GNU form has already answered. The output is
# then VALIDATED as digits, because the losing form does not always fail
# silently: GNU `stat -f %z <file>` prints a diagnostic AND a block of file
# information. A size that cannot be established is not a size to assume small.
FILE_SIZE=""
file_size() {
  local f="$1" out
  FILE_SIZE=""
  out=$(stat -c %s "$f" 2>/dev/null) || out=$(stat -f %z "$f" 2>/dev/null) || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  FILE_SIZE="$out"
  return 0
}

# file_times <path> — the same portable pair as file_size, for the LAST-MODIFIED
# time R2.1 asks the log summary to record (step 4). One stat call yields both
# forms, split on the first space:
#   FILE_MTIME       epoch seconds — what "the most recently modified log" is
#                    decided on. A number, so no date parsing is ever needed.
#   FILE_MTIME_TEXT  the host's human form, for the summary a person reads.
# The OUTPUT is validated, not the exit code, for the reason file_size documents:
# GNU `stat -f` prints a diagnostic AND a block of filesystem information, so a
# losing form does not always fail silently. Formatting an arbitrary epoch back
# into a date is NOT portable (`date -d @N` is GNU, `date -r N` is BSD), which is
# why the display string is taken from stat itself; when stat gives no second
# field the epoch is shown as `@N` rather than an empty cell.
FILE_MTIME=""
FILE_MTIME_TEXT=""
file_times() {
  local f="$1" out=""
  FILE_MTIME=""
  FILE_MTIME_TEXT=""
  out=$(stat -c '%Y %y' "$f" 2>/dev/null) || out=""
  if [[ ! "${out%% *}" =~ ^[0-9]+$ ]]; then
    out=$(stat -f '%m %Sm' "$f" 2>/dev/null) || out=""
  fi
  [[ "${out%% *}" =~ ^[0-9]+$ ]] || return 1
  FILE_MTIME="${out%% *}"
  FILE_MTIME_TEXT="${out#* }"
  [[ "$FILE_MTIME_TEXT" == "$out" ]] && FILE_MTIME_TEXT="@$FILE_MTIME"
  return 0
}

# is_text <path> <size> — the design's heuristic, verbatim: `LC_ALL=C grep -qI .`
# (`-I` = --binary-files=without-match, so grep reports NO MATCH for a file it
# considers binary). LC_ALL=C is load-bearing: in a UTF-8 locale grep also calls
# a file binary on an ENCODING error, which would flag any artifact holding a
# stray non-UTF-8 byte; under C the test collapses to what the design specifies,
# a NUL byte.
#   0 = text        1 = non-text (binary)        2 = the file could not be read
#
# THREE documented edges, because a heuristic that is not written down gets
# rediscovered as a bug:
#   * UTF-16/UTF-32 — an ASCII-range character encodes with a NUL byte, so a
#     perfectly good UTF-16 text file IS reported as binary. Deliberate, and it
#     stays: the alternative (exempt files whose first bytes are a BOM) both
#     misses BOM-less UTF-16 and hands any 2.3 GB blob a two-byte prefix that
#     buys it a free pass — the exact hole this guard exists to close. The
#     archive's own toolchain (grep/sed/frontmatter_field) reads artifacts as
#     UTF-8, so re-encoding is the real fix; --allow-heavy is the escape, and
#     the reason text says both.
#   * `grep -q` stops at the first match and grep decides "binary" from the
#     buffer it has read, so a NUL far past the start of an otherwise-text file
#     is not seen. This is a first-buffer heuristic, not a full scan — which is
#     also why it costs one read, not one read per gigabyte.
#   * "no match" is NOT the same as "binary": a file with no character on any
#     line (empty, or nothing but newlines) also matches nothing. The empty case
#     is settled by the size, the newline-only case by re-asking with the empty
#     pattern, which matches EVERY line and is still suppressed by -I. That
#     second call runs only on the rare no-match path.
IS_TEXT_ERR=""
is_text() {
  local f="$1" size="$2" out rc
  IS_TEXT_ERR=""
  [[ "$size" -eq 0 ]] && return 0
  out=$(LC_ALL=C grep -qI . "$f" 2>&1) && return 0 || rc=$?
  if [[ $rc -ge 2 ]]; then
    IS_TEXT_ERR=${out//$'\n'/; }
    return 2
  fi
  LC_ALL=C grep -qI '' "$f" 2>/dev/null && return 0
  return 1
}

# scan_weight_binary — step 2 over the WHOLE story tree, `.draft/` included: a
# 2 GB blob is no lighter for sitting one directory down. Returns 0 when the
# story is clean, non-zero when GUARD_VIOLATIONS holds at least one offender —
# the empty violation list IS the success condition, so the verdict and the list
# cannot drift apart the way a separate boolean would.
#
# Regular files only (`-type f`): a symlink is moved as a link, so its target's
# weight never enters the archive, and following it would let a link to /dev/zero
# hang the guard.
#
# ORDER INSIDE THE LOOP is size, then text. An oversized file is already blocked,
# so it is never read a second time to also be called binary — that is what
# keeps the 2 GB case a stat(2) instead of a 2 GB read.
#
# A .draft/logs/ file bigger than the limit BLOCKS even though step 4 would have
# collapsed it into a summary. That is the step order doing its job: pruning is
# destructive, and nothing destructive may run before the guards pass.
#
# EVERY failure is a violation, never a silent pass: a file the guard cannot
# measure or cannot read is a file it cannot clear (fail-closed, R1.2).
scan_weight_binary() {
  local tmp find_err list_err="" f display size rc
  local files=()
  GUARD_SCANNED=0

  # The list goes through a temp file rather than a process substitution
  # BECAUSE OF find's EXIT STATUS: `while … done < <(find …)` throws it away, so
  # an unreadable subdirectory would silently shrink the scan to the files find
  # did manage to print — a guard passing on a tree it never saw.
  tmp=$(mktemp "${TMPDIR:-/tmp}/archive-guard.XXXXXX" 2>/dev/null) || {
    add_violation "$STORY_PATH" "" "cannot create a temporary file to list the story's files — the guard cannot clear what it cannot enumerate"
    return 1
  }
  # $STORY_ABS, not $STORY_PATH: find reads a leading `-` as a predicate, and a
  # story reached as `archive-story.sh -- -005-x` from inside stories/ would
  # otherwise turn into "unknown predicate". The absolute path can never do that,
  # and the offender list is mapped back to the caller's path below.
  find_err=$({ find "$STORY_ABS" -type f -print0 > "$tmp"; } 2>&1) ||
    list_err="'find' exited non-zero${find_err:+: ${find_err//$'\n'/; }}"
  # `{ …; :; } 2>/dev/null < f || …` is the form that CATCHES a failed
  # redirection: `2>` before `<` suppresses bash's own message and the trailing
  # `:` pins the group's status to the redirection instead of to the loop.
  {
    while IFS= read -r -d '' f; do files+=("$f"); done
    :
  } 2>/dev/null < "$tmp" || list_err="${list_err:+$list_err; }the file list could not be read back"
  rm -f "$tmp" 2>/dev/null || true
  if [[ -n "$list_err" ]]; then
    add_violation "$STORY_PATH" "" "cannot enumerate every file under the story ($list_err) — a file the guard cannot see is a file it cannot clear"
  fi

  for f in ${files[@]+"${files[@]}"}; do
    GUARD_SCANNED=$((GUARD_SCANNED + 1))
    # Reported relative to the path the CALLER used, so the offender can be
    # copy-pasted into an `ls` or an `rm` from where the command was run — the
    # scan itself stays on the absolute path.
    display="$STORY_PATH/${f#"$STORY_ABS"/}"
    if ! file_size "$f"; then
      add_violation "$display" "" "cannot read the file's size ('stat -c %s' and 'stat -f %z' both failed) — a file the guard cannot measure is a file it cannot clear"
      continue
    fi
    size="$FILE_SIZE"
    if [[ "$size" -gt "$GUARD_MAX_BYTES" ]]; then
      add_violation "$display" "$size" "larger than the ${GUARD_MAX_BYTES}-byte (10 MB) limit"
      continue
    fi
    is_text "$f" "$size" && rc=0 || rc=$?
    case "$rc" in
      0) ;;
      2)
        add_violation "$display" "$size" "cannot be read to check whether it is text${IS_TEXT_ERR:+ ($IS_TEXT_ERR)} — a file the guard cannot read is a file it cannot clear"
        ;;
      *)
        # Kept to ONE line on purpose: this reason is repeated per offender, and
        # the zeo-shaped case is 104 of them. The fix ("re-encode as UTF-8, or
        # --allow-heavy") is spelled out once, in the block message.
        add_violation "$display" "$size" "not a text file (holds NUL bytes; a UTF-16/UTF-32 text file trips this too)"
        ;;
    esac
  done

  [[ "$GUARD_VIOLATION_COUNT" -eq 0 ]]
}

# --- Secrets guard (step 3) -------------------------------------------------
# R1.3: where a secrets scanner is installed, scan the story BEFORE the move and
# block on findings, reporting the count. R1.8: where none is installed, proceed
# and note the skipped scan.
#
# THAT ASYMMETRY IS THE ONE PLACE THIS SCRIPT IS NOT FAIL-CLOSED, so the line is
# drawn here, once, where nobody can widen it by accident:
#     a scanner that is ABSENT       -> a documented degradation: proceed, say so
#     a scanner that RAN AND FAILED  -> a block, like every other guard
# Collapsing the two turns every broken scanner into a free pass — which is
# exactly the state R1.3 exists to end. "No findings" must mean "something
# looked", never "nothing looked".
#
# THE EXIT CODE ALONE IS NOT A DISCRIMINATOR, and that is the load-bearing fact
# of this whole step (probed on gitleaks 8.30.1): gitleaks exits 1 for FINDINGS
# *and* for its own fatal errors — an unparseable config, an unwritable report
# path and a target that does not exist all print `FTL` and exit 1. Reading
# exit 1 as "leaks found" reports a scan that never ran as a findings block;
# reading "0 findings, therefore clean" reports it as CLEAN, which is the
# dangerous half. THE REPORT FILE is the discriminator: gitleaks writes it only
# after a scan that actually ran, and a run with nothing to report writes `[]`.
GITLEAKS_MAX_MB=15

# More BYTES than this and gitleaks skips the file silently — nothing in its
# report, nothing in its exit code (probed: 15000000 bytes is scanned, 15000001
# is not; the unit is decimal MB, not MiB). Step 2 already blocks anything over
# 10 MB, so a file can only reach the scanner unscanned when --allow-heavy was
# passed — and when it does, the count below is the difference between "clean"
# and "clean apart from the biggest file in the tree", which is the precise
# failure R1.3 exists to prevent.
GITLEAKS_SKIP_BYTES=15000000

SECRETS_FINDINGS=0
SECRETS_REPORT=""      # gitleaks' own JSON report, kept only when it is evidence
SECRETS_ERR=""
SECRETS_TMPDIR=""
# "" until count_unscanned_large has actually taken the census, so that a path
# where it never ran (an absent scanner, --skip-secrets) reports `null` rather
# than a confident `0`. Same rule as `findings`: a number nobody measured must
# not read as a measurement that came back empty.
SECRETS_UNSCANNED=""
SECRETS_UNSCANNED_TEXT=""

# What this guard established about the story's FILE CONTENTS, in one sentence,
# for step 4's log summary to carry into the archive. The summary is written
# AFTER this scan and is therefore never scanned itself (see the note at the
# prune), so it states what its own contents were cleared by — "scanned and
# clean" and "nobody looked" must never be indistinguishable in the permanent
# record. Set on every path that continues past this step.
SECRETS_COVERAGE=""

# set_secrets_json <scanned> <findings|""> <report|""> <skipped|""> <error|"">
# The `secrets` key of the report. ONE uniform shape on every path the guard
# reaches, because the difference a consumer must never miss is "not scanned"
# vs "scanned and clean" — and an absent key reads as neither:
#   clean    scanned:true  findings:0    skipped:null   error:null
#   findings scanned:true  findings:N    report:<path>
#   skipped  scanned:false findings:null skipped:"<why>"
#   error    scanned:false findings:null error:"<what failed>"
# `{}` (the initial value) keeps its own meaning: the guard NEVER RAN, because
# an earlier step blocked first.
#
# EVERY COUNT IS null WHEN NOBODY TOOK IT — `findings` on the three paths where
# no scan happened, `unscanned_files` on the two where the size census never
# ran. A number that was never measured must not read as a measurement that
# came back empty; that is the same mistake as `size: 0` in guard.violations[].
# `unscanned_files` is the count of files LARGER than the scanner's
# --max-target-megabytes limit, which it skips without reporting the skip.
set_secrets_json() {
  local scanned="$1" findings="$2" report="$3" skipped="$4" err="$5"
  local f_json="null" r_json="null" s_json="null" e_json="null" u_json="null"
  [[ "$findings" =~ ^[0-9]+$ ]] && f_json="$findings"
  [[ "$SECRETS_UNSCANNED" =~ ^[0-9]+$ ]] && u_json="$SECRETS_UNSCANNED"
  [[ -n "$report" ]] && r_json=$(quote_scalar "$report")
  [[ -n "$skipped" ]] && s_json=$(quote_scalar "$skipped")
  [[ -n "$err" ]] && e_json=$(quote_scalar "$err")
  SECRETS_JSON=$(printf '{ "scanner": "gitleaks", "scanned": %s, "findings": %s, "unscanned_files": %s, "report": %s, "skipped": %s, "error": %s }' \
    "$scanned" "$f_json" "$u_json" "$r_json" "$s_json" "$e_json")
  return 0
}

# count_unscanned_large — how many files the scanner will skip for their size,
# and which. Asked of the filesystem rather than of gitleaks, because gitleaks
# does not put the skip in its report or its exit code: without this, a story
# whose biggest file holds a plaintext key archives as "scanned, 0 findings".
# The list goes through a temp file for the same reason step 2's does — a
# process substitution throws find's exit status away.
count_unscanned_large() {
  local tmp f
  SECRETS_UNSCANNED=0
  SECRETS_UNSCANNED_TEXT=""
  tmp=$(mktemp "${TMPDIR:-/tmp}/archive-secrets-size.XXXXXX" 2>/dev/null) || {
    SECRETS_UNSCANNED_TEXT="(the oversized-file list could not be built: no temporary file)"
    return 0
  }
  # $STORY_ABS, not $STORY_PATH: find reads a leading `-` as a predicate.
  # `-size +Nc` is an exact byte comparison — no block rounding.
  find "$STORY_ABS" -type f -size +"${GITLEAKS_SKIP_BYTES}"c -print0 > "$tmp" 2>/dev/null ||
    SECRETS_UNSCANNED_TEXT="(the oversized-file list is incomplete: 'find' exited non-zero)"
  {
    while IFS= read -r -d '' f; do
      SECRETS_UNSCANNED=$((SECRETS_UNSCANNED + 1))
      SECRETS_UNSCANNED_TEXT="${SECRETS_UNSCANNED_TEXT:+$SECRETS_UNSCANNED_TEXT; }$STORY_PATH/${f#"$STORY_ABS"/}"
    done
    :
  } 2>/dev/null < "$tmp" || SECRETS_UNSCANNED_TEXT="${SECRETS_UNSCANNED_TEXT:+$SECRETS_UNSCANNED_TEXT; }(the oversized-file list could not be read back)"
  rm -f "$tmp" 2>/dev/null || true
  return 0
}

# report_is_array <path> — did gitleaks actually WRITE a JSON report here? The
# whole "scanned" vs "never scanned" distinction rests on this: `[[ -f ]]` says
# the file exists, not that it opens or that it holds a report, so the first
# byte is read and must be the `[` of a JSON array.
report_is_array() {
  local first
  first=$(head -c 1 "$1" 2>/dev/null) || return 1
  [[ "$first" == "[" ]]
}

# count_report_findings <path> — one finding per `"RuleID":` KEY in the report.
# The count cannot be forged from a secret's own text: every `"` inside a JSON
# string value is written `\"`, so the exact byte sequence `"RuleID":` can only
# ever be the key. `grep -o | wc -l` counts OCCURRENCES (plain `grep -c` counts
# matching LINES and would answer 1 for a compact one-line report); `pipefail`
# is armed, so grep's exit 1 on no-match is caught rather than aborting the run.
REPORT_FINDINGS=0
count_report_findings() {
  local n
  n=$(grep -o '"RuleID":' "$1" 2>/dev/null | wc -l) || n=0
  n=${n//[[:space:]]/}
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  REPORT_FINDINGS="$n"
  return 0
}

# secrets_cleanup_tmp — drop the private scan directory. Called only where the
# report is NOT evidence (a clean scan writes `[]`, which tells nobody anything).
secrets_cleanup_tmp() {
  [[ -n "$SECRETS_TMPDIR" && -d "$SECRETS_TMPDIR" ]] || return 0
  rm -rf "$SECRETS_TMPDIR" 2>/dev/null || true
  SECRETS_TMPDIR=""
  return 0
}

# run_secrets_scan — the scan itself. Three answers, never two:
#   0  scanned, clean
#   1  scanned, SECRETS_FINDINGS > 0, report kept at SECRETS_REPORT
#   2  the scan did not produce a trustworthy result (SECRETS_ERR says why)
#
# WHERE THE REPORT LIVES, and why it is not obvious: gitleaks' JSON report holds
# the MATCHED SECRET ITSELF, plus the file and line it came from. So it must be
# (a) unreadable by other users on the machine — a private `mktemp -d`, which is
# mode 0700, and the report inside it is chmod 600 as well; and (b) OUTSIDE the
# story directory, because anything written inside it travels into
# .epic/archive/ with the move and becomes a permanent, deliberately-hard-to-
# delete copy of the very secret the guard just objected to.
#
# Every failure is captured and returned, never left to `set -e`: a bare abort
# prints no JSON at all, and stdout is what the consumers parse.
run_secrets_scan() {
  local rc out report
  SECRETS_FINDINGS=0
  SECRETS_REPORT=""
  SECRETS_ERR=""
  SECRETS_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/archive-secrets.XXXXXX" 2>/dev/null) || {
    SECRETS_TMPDIR=""
    SECRETS_ERR="cannot create a private temporary directory for the scan report (the report holds the matched secrets, so it is never written inside the story or into a shared location)"
    return 2
  }
  report="$SECRETS_TMPDIR/gitleaks-report.json"
  # --no-color is the one flag added to the designed command line: this output
  # is spliced into a JSON `reason` a human reads, and gitleaks colourizes even
  # into a pipe -- raw ANSI escapes there are noise that quote_scalar then has
  # to encode one byte at a time into a message nobody can read.
  out=$(gitleaks dir "$STORY_ABS" --no-banner --no-color --exit-code 1 \
    --max-target-megabytes "$GITLEAKS_MAX_MB" \
    --report-format json --report-path "$report" 2>&1) && rc=0 || rc=$?
  chmod 600 "$report" 2>/dev/null || true
  out=${out//$'\n'/; }

  # A REPORT PATH IS NAMED ONLY WHERE THE FILE SURVIVES. Every error branch that
  # has nothing to keep deletes the private directory and then says so WITHOUT
  # pointing at it: sending an operator to read a file this function has just
  # removed is the same class of mistake as telling them "nothing was moved"
  # about a directory that moved. When the path IS the diagnosis (an unwritable
  # report), gitleaks' own message carries it, and that message is appended.
  case "$rc" in
    0)
      # Clean — but only if a report was actually written. Exit 0 with no report
      # is a scanner that answered without looking.
      if ! report_is_array "$report"; then
        secrets_cleanup_tmp
        SECRETS_ERR="gitleaks exited 0 but wrote no readable JSON report, so the scan cannot be shown to have run${out:+ — gitleaks said: $out}"
        return 2
      fi
      count_report_findings "$report"
      if [[ "$REPORT_FINDINGS" -ne 0 ]]; then
        # Kept: a report holding findings is evidence whatever the exit code said.
        SECRETS_REPORT="$report"
        SECRETS_ERR="gitleaks exited 0 (clean) while reporting $REPORT_FINDINGS finding(s) in '$report' — its exit code and its report disagree, so neither can be trusted"
        return 2
      fi
      secrets_cleanup_tmp
      return 0
      ;;
    1)
      # Findings OR one of gitleaks' own fatals — the report tells them apart.
      if ! report_is_array "$report"; then
        secrets_cleanup_tmp
        SECRETS_ERR="gitleaks exited 1 without writing a readable JSON report. Exit 1 is BOTH its findings code and its fatal-error code, so with no report this is a scan that FAILED, not a scan that found something${out:+ — gitleaks said: $out}"
        return 2
      fi
      count_report_findings "$report"
      if [[ "$REPORT_FINDINGS" -eq 0 ]]; then
        secrets_cleanup_tmp
        SECRETS_ERR="gitleaks exited 1 (its findings code) with an EMPTY report — nothing was found and the scan still did not complete${out:+ — gitleaks said: $out}"
        return 2
      fi
      SECRETS_FINDINGS="$REPORT_FINDINGS"
      SECRETS_REPORT="$report"
      return 1
      ;;
    *)
      secrets_cleanup_tmp
      SECRETS_ERR="gitleaks exited $rc, which is neither its clean code (0) nor its findings code (1) — the scan produced no verdict this archive can rely on${out:+ — gitleaks said: $out}"
      return 2
      ;;
  esac
}

# --- Evidence pruning: .draft/logs -> summary (step 4) ----------------------
# R2.1: a story archived with `.draft/logs/` keeps ONE summary — every log's
# name, size and last-modified time, plus the tail of the most recently modified
# one — and loses the log files themselves. The corpus archived 55 MB of test
# logs across two pmg stories wholesale; this is what replaces that.
# R2.3: `--keep-logs` keeps them exactly as they are, and the override is
# recorded in the manifest entry.
#
# THE STEP ORDER IS THE SAFETY PROPERTY, and it is asserted IN THE SCRIPT rather
# than only in the comment header: GUARDS_PASSED is set on the one line control
# reaches after step 3, and prune_logs_step refuses to touch anything while it
# is false. This is the first destructive step in the pipeline, so "it cannot
# run before a possible `blocked`" has to be a check, not a convention — and it
# is stated on stderr too, in the prune's own verdict line, where a test can see
# both that it ran and that it ran last.
#
# NOTHING IS DELETED BEFORE ITS EVIDENCE IS ON DISK. The summary is composed in
# a temp file BESIDE its destination and renamed into place, and only then are
# the logs removed. A log whose facts could NOT be captured — stat could not
# measure it, or the tail could not be read — is never deleted: it travels into
# the archive as it is, named in the summary and on stderr. Deleting a log while
# recording nothing about it is the exact inverse of what this step is for.
#
# PRUNE NEVER BLOCKS. It runs after every guard has passed, so a failure here
# leaves the story exactly as the guards cleared it — un-pruned, which is the
# pre-005 status quo and not a correctness violation. Every outcome is reported
# on stderr in the same key=value shape the guards use, and `pruned.logs_kb`
# stays 0, which the report already means as "nothing was freed".
#
# THE TAIL AND THE SECRETS GUARD — the hand-off sub-task 2.2 recorded, decided
# here. Step 3 scans `.draft/logs/*` as they are; this summary is written
# afterwards, so NO GUARD EVER LOOKS AT IT, and 40 lines of arbitrary log output
# enter the archive unscanned. That is accepted deliberately, because PRUNE ONLY
# EVER REMOVES: every byte of the tail was already in the story when gitleaks
# read it, and every one of them would have travelled into the archive verbatim
# under --keep-logs. Collapsing a log cannot introduce a credential the archive
# was not already about to receive — it can only reduce one. Re-scanning would
# re-read a strict subset of what step 3 just read on the default path, and on
# the paths where nothing was scanned (--skip-secrets, no scanner installed) it
# would scan precisely what the operator chose not to scan. Blocking on it is
# worse than either: the verdict would have to be reached AFTER a destructive
# step, which is the one thing this step order forbids.
# What is NOT accepted is silence about the guarantee. Every summary states the
# scan's coverage of the logs it collapsed, including the single case where
# `scanned: true, findings: 0` genuinely does NOT cover the tail — a log larger
# than gitleaks' --max-target-megabytes limit, which it skips without saying so
# (2.2's recorded residual). That case is detected from the log's own size,
# which this step has already measured.

PRUNE_TAIL_LINES=40

# The sequence assertion (see above). False until control has passed step 3.
GUARDS_PASSED=false

# Outcome, for the stderr verdict line and for `pruned.logs_kb`.
PRUNE_LOGS_SEEN=0        # regular files found under .draft/logs/
PRUNE_LOGS_REMOVED=0     # of those, the ones actually deleted
PRUNE_LOGS_FREED=0       # bytes actually freed — measured on the removal, not
                         # on the intention, so the number is what happened
PRUNE_LOGS_KEPT=""       # every file deliberately or accidentally left behind
PRUNE_LOGS_TEXT=""       # why a step failed, for the verdict line

# Collected by prune_logs_collect, consumed by prune_logs_write / _remove.
# Counters are manual integers, never ${#arr[@]} on a possibly-empty array —
# the convention the census and the weight guard already follow.
PRUNE_ROWS=()            # one rendered YAML item per log file
PRUNE_ROWS_N=0
PRUNE_REMOVABLE=()       # absolute paths whose facts WERE captured
PRUNE_REMOVABLE_SIZE=()  # parallel: each one's size, for the freed-bytes sum
PRUNE_REMOVABLE_N=0
PRUNE_NEWEST=""          # the most recently modified log — the tail's source
PRUNE_NEWEST_REL=""
PRUNE_NEWEST_SIZE=0
PRUNE_TAIL_STATE="none"  # ok | unreadable | none
PRUNE_TAIL_TMP=""

# prune_logs_collect <dir> — the per-file facts R2.1 records, and which log is
# the newest. Returns non-zero when the directory could not be enumerated
# COMPLETELY: a list that is not known to be complete is not a list to delete
# from. The enumeration goes through a temp file for the reason the weight guard
# documents — `while … done < <(find …)` throws find's exit status away, and
# find exits non-zero AFTER printing whatever it did reach.
prune_logs_collect() {
  local dir="$1" tmp f rel newest_epoch=-1
  local files=()
  PRUNE_ROWS=()
  PRUNE_ROWS_N=0
  PRUNE_REMOVABLE=()
  PRUNE_REMOVABLE_SIZE=()
  PRUNE_REMOVABLE_N=0
  PRUNE_NEWEST=""
  PRUNE_NEWEST_REL=""
  PRUNE_NEWEST_SIZE=0
  PRUNE_LOGS_SEEN=0
  PRUNE_LOGS_KEPT=""
  PRUNE_LOGS_TEXT=""

  tmp=$(mktemp "${TMPDIR:-/tmp}/archive-prune.XXXXXX" 2>/dev/null) || {
    PRUNE_LOGS_TEXT="no temporary file could be created to list '$dir'"
    return 1
  }
  find "$dir" -type f -print0 > "$tmp" 2>/dev/null ||
    PRUNE_LOGS_TEXT="'find' exited non-zero over '$dir', so the log list may be incomplete"
  {
    while IFS= read -r -d '' f; do files+=("$f"); done
    :
  } 2>/dev/null < "$tmp" ||
    PRUNE_LOGS_TEXT="${PRUNE_LOGS_TEXT:+$PRUNE_LOGS_TEXT; }the log list could not be read back"
  rm -f "$tmp" 2>/dev/null || true
  [[ -z "$PRUNE_LOGS_TEXT" ]] || return 1

  # Regular files only (`-type f`), and in find's own order: sorting a NUL-
  # delimited list portably needs `sort -z`, which is GNU-only, and this script
  # pays its portability taxes deliberately. Ties on mtime keep the FIRST file
  # seen (strict `-gt`), so a run over an unchanged tree always picks the same
  # log even though the order itself is the filesystem's.
  for f in ${files[@]+"${files[@]}"}; do
    PRUNE_LOGS_SEEN=$((PRUNE_LOGS_SEEN + 1))
    rel="${f#"$dir"/}"
    # EVERY string here is a file name, which may legally hold a quote, a
    # newline, a DEL or a C1 byte — so it goes through quote_scalar, the one
    # escaper whose output both JSON and YAML accept. That is also why the file
    # list below is a YAML block and not a markdown table: a name containing `|`
    # would silently grow a column, and inventing a second, weaker escape to
    # prevent that is exactly what this script does not do.
    if ! file_size "$f" || ! file_times "$f"; then
      PRUNE_ROWS+=("$(printf '  - name: %s\n    size_bytes: null\n    modified: null\n    kept: %s' \
        "$(quote_scalar "$rel")" \
        "$(quote_scalar "its size and last-modified time could not be read, so it was left as it is")")")
      PRUNE_ROWS_N=$((PRUNE_ROWS_N + 1))
      PRUNE_LOGS_KEPT="${PRUNE_LOGS_KEPT:+$PRUNE_LOGS_KEPT; }$rel (size/mtime unreadable)"
      continue
    fi
    PRUNE_ROWS+=("$(printf '  - name: %s\n    size_bytes: %d\n    modified: %s' \
      "$(quote_scalar "$rel")" "$FILE_SIZE" "$(quote_scalar "$FILE_MTIME_TEXT")")")
    PRUNE_ROWS_N=$((PRUNE_ROWS_N + 1))
    PRUNE_REMOVABLE+=("$f")
    PRUNE_REMOVABLE_SIZE+=("$FILE_SIZE")
    PRUNE_REMOVABLE_N=$((PRUNE_REMOVABLE_N + 1))
    if [[ "$FILE_MTIME" -gt "$newest_epoch" ]]; then
      newest_epoch="$FILE_MTIME"
      PRUNE_NEWEST="$f"
      PRUNE_NEWEST_REL="$rel"
      PRUNE_NEWEST_SIZE="$FILE_SIZE"
    fi
  done
  [[ "$PRUNE_LOGS_SEEN" -gt 0 ]]
}

# prune_logs_coverage — the provenance line, built from what step 3 established
# plus the newest log's own size. The size test is the whole point: gitleaks
# SILENTLY skips a file over --max-target-megabytes (2.2's measured residual —
# no report entry, no exit code, `INF no leaks found`), so a story archived with
# --allow-heavy can report `scanned: true, findings: 0` while the log this tail
# came from was never opened. Said in the artifact, where it survives.
prune_logs_coverage() {
  local note="${SECRETS_COVERAGE:-(the secrets guard did not record its coverage)}"
  if [[ -n "$PRUNE_NEWEST" && "$PRUNE_NEWEST_SIZE" -gt "$GITLEAKS_SKIP_BYTES" ]] &&
    [[ "$SECRETS_COVERAGE" == scanned* ]]; then
    note="$note — BUT the log this tail came from is larger than the scanner's ${GITLEAKS_SKIP_BYTES}-byte limit, which it skips WITHOUT reporting the skip, so these lines were NOT scanned"
  fi
  printf '%s' "$note"
}

# prune_logs_write <summary> — the summary, composed in a temp file beside its
# destination and renamed into place, so a partial write can never land and the
# logs are never deleted against half a record.
#
# The tail is read into a temp FILE rather than a command substitution: `$( )`
# cannot hold a NUL byte and would silently truncate a log that reached here
# through --allow-heavy, and `tail -n N` seeks rather than reading the whole
# file, so a 55 MB log costs one read of its last page.
prune_logs_write() {
  local summary="$1" dir stmp gen="" fence='~~~' i rc=0
  dir=$(dirname "$summary")
  PRUNE_TAIL_STATE="none"
  PRUNE_TAIL_TMP=""
  if [[ -n "$PRUNE_NEWEST" ]]; then
    PRUNE_TAIL_TMP=$(mktemp "${TMPDIR:-/tmp}/archive-prune-tail.XXXXXX" 2>/dev/null) || PRUNE_TAIL_TMP=""
    if [[ -n "$PRUNE_TAIL_TMP" ]] &&
      tail -n "$PRUNE_TAIL_LINES" -- "$PRUNE_NEWEST" > "$PRUNE_TAIL_TMP" 2>/dev/null; then
      PRUNE_TAIL_STATE="ok"
      # A fence long enough that no line of the log can close it early. Tildes,
      # not backticks: a shell transcript is full of backticks and a fenced
      # block is how the tail stays readable as preformatted text. Bounded, so
      # a pathological log cannot spin here — past the bound the fence is only
      # cosmetically wrong and the bytes are still verbatim.
      while [[ ${#fence} -lt 20 ]] && grep -q "^$fence" "$PRUNE_TAIL_TMP" 2>/dev/null; do
        fence="$fence~"
      done
    else
      PRUNE_TAIL_STATE="unreadable"
    fi
  fi

  stmp=$(mktemp "$dir/.logs-summary.XXXXXX" 2>/dev/null) || {
    PRUNE_LOGS_TEXT="the summary file could not be created in '$dir'"
    rm -f "$PRUNE_TAIL_TMP" 2>/dev/null || true
    return 1
  }
  # A timestamp for the artifact. derive_archived_at reports instead of dying,
  # and step 5 re-derives it for the manifest entry, so a host whose clock
  # cannot be read still gets a summary — with the field null rather than
  # invented.
  derive_archived_at && gen="$ARCHIVED_AT" || gen=""

  {
    printf '# Log summary — %s\n\n' "$STORY_ID"
    printf 'This story was archived with `.draft/logs/` present, and those log files\n'
    printf 'were replaced by this one: the archive keeps what the logs proved, not the\n'
    printf 'logs. Re-run with `--keep-logs` to archive them as they are instead.\n\n'
    printf 'Everything the logs are still known to have contained is below. If they had\n'
    printf 'been committed before the archive, git history still holds them; if they had\n'
    printf 'not, this file is all that is left of them.\n\n'
    printf '%syaml\n' "$fence"
    printf 'generated_by: "scripts/archive-story.sh"\n'
    if [[ -n "$gen" ]]; then
      printf 'generated_at: %s\n' "$(quote_scalar "$gen")"
    else
      printf 'generated_at: null\n'
    fi
    printf 'source: ".draft/logs/"\n'
    printf 'files_found: %d\n' "$PRUNE_LOGS_SEEN"
    printf 'secrets_scan: %s\n' "$(quote_scalar "$(prune_logs_coverage)")"
    printf 'logs:\n'
    for ((i = 0; i < PRUNE_ROWS_N; i++)); do
      printf '%s\n' "${PRUNE_ROWS[i]}"
    done
    printf '%s\n\n' "$fence"
    case "$PRUNE_TAIL_STATE" in
      ok)
        printf '## Tail of %s — the most recently modified log, last %d lines\n\n' \
          "$(quote_scalar "$PRUNE_NEWEST_REL")" "$PRUNE_TAIL_LINES"
        printf '%stext\n' "$fence"
        cat -- "$PRUNE_TAIL_TMP"
        # A log whose last line has no newline would otherwise run straight into
        # the closing fence. `$( )` strips trailing newlines, so an empty result
        # from `tail -c 1` IS "the last byte is a newline" — and adding one
        # unconditionally would leave a blank line inside the block instead.
        [[ -z "$(tail -c 1 -- "$PRUNE_TAIL_TMP" 2>/dev/null)" ]] || printf '\n'
        printf '%s\n' "$fence"
        ;;
      unreadable)
        printf '## Tail of %s — NOT RECORDED\n\n' "$(quote_scalar "$PRUNE_NEWEST_REL")"
        printf 'That log is the most recently modified one, and its last %d lines\n' "$PRUNE_TAIL_LINES"
        printf 'could not be read. It was therefore NOT deleted: it is still in\n'
        printf '`.draft/logs/`, exactly as it was.\n'
        ;;
      *)
        printf '## No tail\n\nNo log could be measured, so none was collapsed.\n'
        ;;
    esac
  } > "$stmp" 2>/dev/null || rc=1
  rm -f "$PRUNE_TAIL_TMP" 2>/dev/null || true
  PRUNE_TAIL_TMP=""

  # A write that failed, or landed empty, deletes nothing: `[[ -s ]]` is the
  # cheap re-read that tells "written" from "silently wrote nothing" — the same
  # lesson step 7 learned from `sed -i`.
  if [[ $rc -ne 0 || ! -s "$stmp" ]]; then
    rm -f "$stmp" 2>/dev/null || true
    PRUNE_LOGS_TEXT="the summary could not be written to '$summary'"
    return 1
  fi
  if ! mv -- "$stmp" "$summary" 2>/dev/null; then
    rm -f "$stmp" 2>/dev/null || true
    PRUNE_LOGS_TEXT="the summary could not be moved into place at '$summary'"
    return 1
  fi
  return 0
}

# prune_logs_remove <dir> — the destructive half, and the only one. It runs
# ONLY after prune_logs_write has returned 0, so every file it deletes is a file
# whose name, size and last-modified time are already recorded in the archive.
#
# `pruned.logs_kb` is measured HERE, from the files that were actually removed,
# never from the ones this step meant to remove.
prune_logs_remove() {
  local dir="$1" i path size
  PRUNE_LOGS_REMOVED=0
  PRUNE_LOGS_FREED=0
  for ((i = 0; i < PRUNE_REMOVABLE_N; i++)); do
    path="${PRUNE_REMOVABLE[i]}"
    size="${PRUNE_REMOVABLE_SIZE[i]}"
    # The newest log survives when its tail could not be read: the summary then
    # records its name, size and mtime but nothing of its content, and deleting
    # it would destroy the only copy of lines nothing recorded.
    if [[ "$path" == "$PRUNE_NEWEST" && "$PRUNE_TAIL_STATE" != "ok" ]]; then
      PRUNE_LOGS_KEPT="${PRUNE_LOGS_KEPT:+$PRUNE_LOGS_KEPT; }$PRUNE_NEWEST_REL (its tail could not be read)"
      continue
    fi
    if rm -f -- "$path" 2>/dev/null && [[ ! -e "$path" ]]; then
      PRUNE_LOGS_REMOVED=$((PRUNE_LOGS_REMOVED + 1))
      PRUNE_LOGS_FREED=$((PRUNE_LOGS_FREED + size))
    else
      PRUNE_LOGS_KEPT="${PRUNE_LOGS_KEPT:+$PRUNE_LOGS_KEPT; }${path#"$STORY_ABS"/} (could not be removed)"
    fi
  done
  # KB, rounded UP. Integer division would report 0 for anything under a
  # kilobyte, and `logs_kb: 0` already means "nothing was freed" — a prune that
  # freed bytes must never be indistinguishable from one that freed none.
  PRUNED_LOGS_KB=$(((PRUNE_LOGS_FREED + 1023) / 1024))
  # Directories the removal emptied go too: an empty `logs/` in the archive
  # records nothing, and git does not track it either. `rmdir`, never `rm -r` —
  # it succeeds ONLY on an empty directory, so anything this step did not list
  # (a symlink, a socket, a file it deliberately kept) keeps its directory alive
  # instead of being deleted without ever being named.
  find "$dir" -depth -type d -exec rmdir {} \; 2>/dev/null || true
  return 0
}

# prune_logs_step — step 4's logs half end to end, and the only caller of the
# three helpers above. Every outcome is one stderr line in the guards' key=value
# shape (`prune=logs verdict=…`), so `grep 'prune=logs'` answers "what did the
# prune do, and did it run after the guards" without parsing prose.
prune_logs_step() {
  local dir="$1" summary="$2"

  # THE SEQUENCE ASSERTION. Unreachable by construction — every blocking path in
  # steps 2 and 3 exits — which is exactly why it is worth having: it is what
  # makes a future re-sequencing fail loudly instead of silently deleting a
  # story's logs before a guard could refuse it.
  if [[ "$GUARDS_PASSED" != true ]]; then
    block "internal error: the prune (step 4) was reached before the guards had passed. Nothing was pruned, moved or recorded — this step is destructive and must never run before a guard can return 'blocked'"
  fi

  if [[ "$KEEP_LOGS" == true ]]; then
    printf 'archive-story: prune=logs verdict=skipped reason=--keep-logs guards_passed=%s (the log files are archived as they are; the override is recorded in the manifest entry)\n' \
      "$GUARDS_PASSED" >&2
    return 0
  fi
  if [[ ! -d "$dir" ]]; then
    printf 'archive-story: prune=logs verdict=none reason=no-logs-directory guards_passed=%s\n' \
      "$GUARDS_PASSED" >&2
    return 0
  fi
  # An existing summary is never overwritten. It is the artifact this step
  # produces, so one already sitting there was written by a hand or by an
  # interrupted run — and silently replacing a document about the logs with a
  # generated one is the kind of quiet loss this step exists to end.
  if [[ -e "$summary" || -L "$summary" ]]; then
    printf 'archive-story: prune=logs verdict=skipped reason=summary-exists guards_passed=%s (%s is already there, so the logs were left as they are; remove it or pass --keep-logs)\n' \
      "$GUARDS_PASSED" "$summary" >&2
    return 0
  fi
  if ! prune_logs_collect "$dir"; then
    if [[ -n "$PRUNE_LOGS_TEXT" ]]; then
      printf 'archive-story: prune=logs verdict=failed reason=%s guards_passed=%s (the story is archived with its logs as they are)\n' \
        "$PRUNE_LOGS_TEXT" "$GUARDS_PASSED" >&2
    else
      printf 'archive-story: prune=logs verdict=none reason=no-log-files guards_passed=%s\n' \
        "$GUARDS_PASSED" >&2
    fi
    return 0
  fi
  if ! prune_logs_write "$summary"; then
    printf 'archive-story: prune=logs verdict=failed reason=%s guards_passed=%s (nothing was deleted: the story is archived with its logs as they are)\n' \
      "$PRUNE_LOGS_TEXT" "$GUARDS_PASSED" >&2
    return 0
  fi
  prune_logs_remove "$dir"
  if [[ -n "$PRUNE_LOGS_KEPT" ]]; then
    printf 'archive-story: prune=logs verdict=partial files_found=%d files_removed=%d freed_kb=%d guards_passed=%s kept=%s\n' \
      "$PRUNE_LOGS_SEEN" "$PRUNE_LOGS_REMOVED" "$PRUNED_LOGS_KB" "$GUARDS_PASSED" "$PRUNE_LOGS_KEPT" >&2
  else
    printf 'archive-story: prune=logs verdict=pruned files_found=%d files_removed=%d freed_kb=%d guards_passed=%s summary=%s\n' \
      "$PRUNE_LOGS_SEEN" "$PRUNE_LOGS_REMOVED" "$PRUNED_LOGS_KB" "$GUARDS_PASSED" "$summary" >&2
  fi
  return 0
}

# --- Evidence pruning: byte-identical .draft copies (step 4) ----------------
# R2.2: a `.draft/` file that is BYTE-IDENTICAL to its promoted sibling is a
# duplicate and is removed at archive time — 4+ corpus stories carried exact
# copies of artifacts sitting right beside them. R2.3: `--keep-copies` keeps
# them exactly as they are, and the override is recorded in the manifest entry.
#
# "EXACT" IS THE WHOLE REQUIREMENT. A near-duplicate — one byte changed, one
# trailing newline, the same length with different content — is a DIFFERENT
# DOCUMENT, usually the working draft the promoted artifact grew out of, and it
# is precisely what a reader opens `.draft/` for. So the comparison is `cmp -s`
# on the bytes and nothing else: never a size, never a hash of some normalized
# form, never a "looks the same" heuristic. `-s` is also required rather than
# incidental — without it `cmp` prints "…differ: byte N" on STDOUT, which this
# script reserves for one JSON object.
#
# THE PAIRING RULE. design.md says "promoted sibling"; here that means THE SAME
# RELATIVE PATH one level up: `.draft/<rel>` pairs with `<story>/<rel>`. So
# `.draft/design.md` pairs with `design.md`, and `.draft/adr/002.md` pairs with
# `adr/002.md` and NOT with a top-level `002.md`. Matching on the BASENAME
# instead would delete `.draft/notes/api.md` because some unrelated `api.md`
# exists at the top of the story — a file that was never a copy of anything.
# The path rule is mechanical, it makes "sibling" mean the same thing at every
# depth, and it can never pair two files the story did not itself put at
# matching paths.
#
# BOTH SIDES MUST BE REGULAR FILES, and the symlink half of that is not
# pedantry: `cmp` FOLLOWS symlinks. A promoted `design.md` that is a link to
# `.draft/design.md` therefore reads as "identical", and deleting the draft copy
# would leave the promoted artifact DANGLING — the removal of a duplicate
# turning into the destruction of the only copy. The mirror case (a draft entry
# that is itself a link to the promoted file) is left alone for a quieter
# reason: it holds no bytes of its own, so R2.2's "remove the copy" has nothing
# to remove, and a symlink is how someone deliberately wrote down "same file".
# `find -type f` already excludes both, and the tests repeat it anyway, because
# a rule that lives only inside a find predicate is one the next reader misses.
#
# A COMPARISON THAT COULD NOT RUN IS NEVER "EQUAL" — 3.1's rule for the logs
# half, applied here for the same reason and with more at stake: `[[ -f ]]` says
# a file EXISTS, not that it opens, and reading an unreadable file as a
# duplicate would delete the one copy nobody was able to check. `cmp` answers
# 0 identical / 1 differs / >1 could not compare, and ONLY 0 deletes.
#
# NO SUMMARY ARTIFACT, unlike the logs half, and the asymmetry is the point:
# what this step removes is BY DEFINITION still in the archive under its
# promoted name, byte for byte. Nothing is lost, so there is nothing to record
# beyond the count — which is also why no `.draft/copies-summary.md` exists to
# collide with anything. `.draft/logs-summary.md` (written moments earlier by
# the logs half, which runs first) is treated like any other draft file: it
# becomes a candidate only if the story ALSO carries a top-level
# `logs-summary.md` with the very same bytes, in which case those bytes survive
# there and removing the `.draft` copy loses nothing. A summary this run
# generated carries a `generated_at:` line, so it cannot match one by accident.
#
# PRUNE NEVER BLOCKS (3.1's policy, unchanged): any failure leaves the story
# un-pruned with `verdict=failed`, because this step runs after every guard has
# passed — un-pruned is the pre-005 status quo, not a correctness violation.
# And the SEQUENCE ASSERTION is read HERE TOO, not only by the logs half: step 4
# is destructive on both of its halves, so both must be unable to run before a
# guard could still return `blocked`.

# Outcome, for the stderr verdict line and for `pruned.copies_removed`.
PRUNE_COPIES_SEEN=0      # regular files found anywhere under .draft/
PRUNE_COPIES_PAIRED=0    # of those, the ones actually compared against a
                         # promoted regular file at the matching path
PRUNE_COPIES_REMOVED=0   # of those, the exact copies actually deleted
PRUNE_COPIES_KEPT=""     # every candidate deliberately or accidentally left
PRUNE_COPIES_TEXT=""     # why a step failed, for the verdict line

# Collected by prune_copies_collect, consumed by prune_copies_remove. Manual
# integer counter, never ${#arr[@]} on a possibly-empty array — the convention
# the census, the weight guard and the logs prune all follow.
PRUNE_COPIES_DUPES=()
PRUNE_COPIES_DUPES_N=0

# prune_copies_collect <draft-dir> — every `.draft/` file that is an EXACT copy
# of the promoted artifact at the matching path. Returns non-zero when the
# subtree could not be enumerated COMPLETELY (a list that is not known to be
# complete is not a list to delete from) or when it holds no files at all. The
# enumeration goes through a temp file for the reason the weight guard
# documents: `while … done < <(find …)` throws find's exit status away, and find
# exits non-zero AFTER printing whatever it did reach.
prune_copies_collect() {
  local dir="$1" tmp f disp promoted rc
  local files=()
  PRUNE_COPIES_SEEN=0
  PRUNE_COPIES_PAIRED=0
  PRUNE_COPIES_DUPES=()
  PRUNE_COPIES_DUPES_N=0
  PRUNE_COPIES_KEPT=""
  PRUNE_COPIES_TEXT=""

  tmp=$(mktemp "${TMPDIR:-/tmp}/archive-prune-copies.XXXXXX" 2>/dev/null) || {
    PRUNE_COPIES_TEXT="no temporary file could be created to list '$dir'"
    return 1
  }
  find "$dir" -type f -print0 > "$tmp" 2>/dev/null ||
    PRUNE_COPIES_TEXT="'find' exited non-zero over '$dir', so the draft file list may be incomplete"
  {
    while IFS= read -r -d '' f; do files+=("$f"); done
    :
  } 2>/dev/null < "$tmp" ||
    PRUNE_COPIES_TEXT="${PRUNE_COPIES_TEXT:+$PRUNE_COPIES_TEXT; }the draft file list could not be read back"
  rm -f "$tmp" 2>/dev/null || true
  [[ -z "$PRUNE_COPIES_TEXT" ]] || return 1

  for f in ${files[@]+"${files[@]}"}; do
    PRUNE_COPIES_SEEN=$((PRUNE_COPIES_SEEN + 1))
    disp="${f#"$STORY_ABS"/}"
    # `-type f` already excluded symlinks; stated again where the rule belongs.
    [[ -L "$f" ]] && continue
    promoted="$STORY_ABS/${f#"$dir"/}"
    # No promoted artifact at the matching path. This is MOST of `.draft/` —
    # scratch notes, research, the log summary — and a file that is a copy of
    # nothing can never be a duplicate of anything.
    [[ -e "$promoted" ]] || continue
    # A directory, a device, or a SYMLINK on the promoted side: not a pair. The
    # symlink case is the dangerous one (see the note above) — cmp would follow
    # it and call the story's only copy a duplicate of itself.
    [[ -L "$promoted" || ! -f "$promoted" ]] && continue
    PRUNE_COPIES_PAIRED=$((PRUNE_COPIES_PAIRED + 1))
    cmp -s -- "$f" "$promoted" 2>/dev/null && rc=0 || rc=$?
    case "$rc" in
      0)
        PRUNE_COPIES_DUPES+=("$f")
        PRUNE_COPIES_DUPES_N=$((PRUNE_COPIES_DUPES_N + 1))
        ;;
      1)
        # Differs. A near-duplicate is a different document: untouched, and not
        # worth a word — this is the ordinary outcome for a live draft.
        ;;
      *)
        # >1 is "could not compare", never "equal". `cmp -s` suppresses its own
        # message for an unreadable operand, and an errno string would be
        # localized anyway (a recorded finding of this story), so the reason is
        # stated here in the script's own words.
        PRUNE_COPIES_KEPT="${PRUNE_COPIES_KEPT:+$PRUNE_COPIES_KEPT; }$(quote_scalar "$disp") (the comparison could not be run, so it was left as it is)"
        ;;
    esac
  done
  [[ "$PRUNE_COPIES_SEEN" -gt 0 ]]
}

# prune_copies_remove — the destructive half, and the only one. Every path it
# deletes compared byte-identical to a promoted artifact that is staying, so
# unlike the logs half there is nothing to write down first: the bytes are
# already in the archive under the other name.
#
# `pruned.copies_removed` is measured HERE, from the files that were actually
# removed, never from the ones this step meant to remove.
#
# Deliberately NO `rmdir` sweep, and that is where this half parts company with
# the logs half: there the whole point is that `logs/` collapses, so an emptied
# directory is part of the result. Here the removals are scattered single files,
# an emptied directory is not evidence of anything the step did, and a sweep
# rooted at `.draft/` would delete `.draft` itself — a directory the operator
# (and the logs half, which leaves it standing) expects to survive. This step
# removes exactly the files R2.2 names.
prune_copies_remove() {
  local i path disp
  PRUNE_COPIES_REMOVED=0
  for ((i = 0; i < PRUNE_COPIES_DUPES_N; i++)); do
    path="${PRUNE_COPIES_DUPES[i]}"
    disp="${path#"$STORY_ABS"/}"
    if rm -f -- "$path" 2>/dev/null && [[ ! -e "$path" ]]; then
      PRUNE_COPIES_REMOVED=$((PRUNE_COPIES_REMOVED + 1))
    else
      PRUNE_COPIES_KEPT="${PRUNE_COPIES_KEPT:+$PRUNE_COPIES_KEPT; }$(quote_scalar "$disp") (could not be removed)"
    fi
  done
  PRUNED_COPIES="$PRUNE_COPIES_REMOVED"
  return 0
}

# prune_copies_step — step 4's copies half end to end, and the only caller of
# the two helpers above. Every outcome is one stderr line in the guards'
# key=value shape (`prune=copies verdict=…`), so `grep 'prune=copies'` answers
# "what did it do, and did it run after the guards" without parsing prose. The
# logs half greps `prune=logs`, so the two never collide.
#
# WHY THE VERDICT WORD CARRIES THE ran-vs-not-run DISTINCTION. `copies_removed`
# cannot: it is rendered with `%d` by both emit_report and entry_json, and
# manifest_read_entry parses it back as a number and reports any entry whose
# 16 keys do not all validate as `partial` — which BLOCKS. So there is no `null`
# to spend here, and no room for a 17th field. Nor is one needed: unlike
# `secrets.findings: 0` (2.2), which is a SAFETY claim a consumer acts on,
# `copies_removed: 0` is a housekeeping count whose worst misreading is "I
# thought the prune ran". The distinction still has to exist somewhere, so it is
# explicit in the stream that carries every other diagnostic:
#   skipped  --keep-copies (and `keep-copies` in overrides_used, permanently)
#   none     nothing to compare — no `.draft/`, or no files in it
#   clean    every draft file WAS compared and none was an exact copy
#   pruned   at least one exact copy removed
#   partial  removed what it could; `kept=` names what it could not
#   failed   the list could not be trusted, so nothing was deleted
prune_copies_step() {
  local dir="$1" verdict

  # THE SEQUENCE ASSERTION, the copies half. Unreachable by construction — every
  # blocking path in steps 2 and 3 exits — which is exactly why it is worth
  # having: it makes a future re-sequencing fail loudly instead of silently
  # deleting a story's draft files before a guard could refuse the archive.
  if [[ "$GUARDS_PASSED" != true ]]; then
    block "internal error: the prune (step 4) was reached before the guards had passed. Nothing was pruned, moved or recorded — this step is destructive and must never run before a guard can return 'blocked'"
  fi

  if [[ "$KEEP_COPIES" == true ]]; then
    printf 'archive-story: prune=copies verdict=skipped reason=--keep-copies guards_passed=%s (.draft copies identical to a promoted artifact are archived as they are; the override is recorded in the manifest entry)\n' \
      "$GUARDS_PASSED" >&2
    return 0
  fi
  if [[ ! -d "$dir" ]]; then
    printf 'archive-story: prune=copies verdict=none reason=no-draft-directory guards_passed=%s\n' \
      "$GUARDS_PASSED" >&2
    return 0
  fi
  if ! prune_copies_collect "$dir"; then
    if [[ -n "$PRUNE_COPIES_TEXT" ]]; then
      printf 'archive-story: prune=copies verdict=failed reason=%s guards_passed=%s (nothing was deleted: the story is archived with its .draft copies as they are)\n' \
        "$PRUNE_COPIES_TEXT" "$GUARDS_PASSED" >&2
    else
      printf 'archive-story: prune=copies verdict=none reason=no-draft-files guards_passed=%s\n' \
        "$GUARDS_PASSED" >&2
    fi
    return 0
  fi
  if [[ "$PRUNE_COPIES_DUPES_N" -gt 0 ]]; then
    prune_copies_remove
  fi
  # ONE line, one field list, three verdict words. Rendering each verdict with
  # its own printf would be three copies of the same key list, and the next
  # field added to one of them would silently be missing from the other two.
  verdict="pruned"
  if [[ -n "$PRUNE_COPIES_KEPT" ]]; then
    verdict="partial"
  elif [[ "$PRUNE_COPIES_REMOVED" -eq 0 ]]; then
    verdict="clean"
  fi
  printf 'archive-story: prune=copies verdict=%s files_seen=%d compared=%d removed=%d guards_passed=%s%s\n' \
    "$verdict" "$PRUNE_COPIES_SEEN" "$PRUNE_COPIES_PAIRED" "$PRUNE_COPIES_REMOVED" \
    "$GUARDS_PASSED" "${PRUNE_COPIES_KEPT:+ kept=$PRUNE_COPIES_KEPT}" >&2
  return 0
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

# --- The append lock (mutual exclusion between concurrent archives) ----------
#
# WHY A LOCK AT ALL. `printf '%s\n' "$entry" >> file` is NOT one write(2).
# Bash LINE-BUFFERS stdout, so the builtin flushes once per newline: an entry of
# N lines costs N write(2) calls, whatever its total size. O_APPEND makes each
# of those atomic INDIVIDUALLY — no byte is ever lost or overwritten — but it
# says nothing about the group, so two concurrent archives interleave line by
# line INSIDE an entry. MEASURED here on bash 5.3: concurrent writers of a
# 1 066-byte, 22-line entry split into runs of exactly 102 bytes — one
# deferred_items line — and 8 of 30 rounds at 8 writers produced a manifest.yaml
# PyYAML refuses to load ("expected <block end>, but found '<block sequence
# start>'"), entry B's keys sitting in the middle of entry A's list.
#
# The failure is INVISIBLE to a line-counting assertion: interleaving preserves
# every line, so `grep -c '^  - story: '` still reports N and every entry looks
# present. Only parsing the document sees it. And manifest.yaml is the archive's
# permanent record, under .epic/archive/, which is read-only for the Edit/Write
# tools by design — a corrupt one is unreadable to every consumer and not
# repairable through the sanctioned tooling.
#
# THE PRIMITIVE IS `mkdir`, NOT `flock(1)`. mkdir(2) is required by POSIX to
# fail with EEXIST when the name exists, on every filesystem — macOS and NFS
# included. `flock(1)` is util-linux: absent on macOS, where a fail-closed
# script would then have to BLOCK EVERY ARCHIVE rather than append without the
# lock it cannot take. This script already paid that portability tax on purpose
# once (the POSIX `date` fallback), so it does not add a Linux-only hard
# dependency in the one place that decides whether an archive may proceed. The
# cost of mkdir is that waiting is a poll rather than a blocking syscall —
# irrelevant when the critical section is a single append.
#
# STALE LOCKS SELF-HEAL, and the break is IDENTITY-TARGETED so that it can never
# take a LIVE lock:
#   * the holder marks the directory with `owner.<nonce>` the instant it wins.
#     A directory with a marker in it is NOT EMPTY, so `rmdir` on it fails;
#   * a waiter breaks only a lock whose marker NEVER CHANGED for a whole
#     timeout. A holder that finishes hands the lock on to a different nonce,
#     which RESETS the waiter's clock — a busy lock is never read as a dead one;
#   * the break is `rm -f <the marker it observed, by name>` then `rmdir`. If
#     the lock changed hands in between, the new holder's marker is still inside
#     and the rmdir fails with ENOTEMPTY. Two waiters breaking the same corpse
#     at worst remove it once between them;
#   * the one window left is a holder killed BETWEEN the mkdir and its marker —
#     the directory is then genuinely empty, and breakable. The acquirer closes
#     it from the other side: if creating the marker fails, the directory went
#     away underneath it, so it does NOT consider itself the holder and retries.
# The alternative — never break, block forever naming the directory to remove —
# was rejected. A SIGKILL inside a millisecond-long critical section would wedge
# every future archive on the machine, and unlike a truncated manifest entry a
# stale lock holds no information a human has to adjudicate.
#
# TIMEOUT: 30 s against a critical section measured in milliseconds — a margin
# of ~10 000x, so only a corpse (or a SIGSTOPped process) ever reaches it.
# EPIC_ARCHIVE_LOCK_TIMEOUT overrides it so a test can exercise the break
# without waiting 30 s; a non-numeric or zero value is IGNORED, because a
# 0-second timeout would break live locks on sight.
MANIFEST_LOCK_DIR=""      # set beside MANIFEST_FILE at story resolution
MANIFEST_LOCK_HELD=false
MANIFEST_LOCK_MARK=""
MANIFEST_LOCK_NAP=""      # "" unknown | frac | int — fractional sleep support

manifest_lock_timeout() {
  local t="${EPIC_ARCHIVE_LOCK_TIMEOUT:-}"
  if [[ "$t" =~ ^[0-9]+$ ]] && [[ "$t" -gt 0 ]]; then
    printf '%s' "$t"
  else
    printf '30'
  fi
}

# manifest_lock_nap — the poll interval. `sleep 0.02` is not POSIX (POSIX sleep
# takes an integer), so support is probed ONCE, and only on the contended path;
# a host without it polls once a second instead of fifty times.
manifest_lock_nap() {
  if [[ -z "$MANIFEST_LOCK_NAP" ]]; then
    if sleep 0.01 2> /dev/null; then MANIFEST_LOCK_NAP=frac; else MANIFEST_LOCK_NAP=int; fi
  fi
  if [[ "$MANIFEST_LOCK_NAP" == frac ]]; then sleep 0.02; else sleep 1; fi
}

# manifest_lock_owner — the current holder's marker file NAME, or "" when the
# lock directory is empty. The name IS the identity: a breaker removes exactly
# the marker it observed, never "whatever happens to be in there now".
manifest_lock_owner() {
  local f
  for f in "$MANIFEST_LOCK_DIR"/owner.*; do
    [[ -e "$f" ]] || continue
    printf '%s' "${f##*/}"
    return 0
  done
  return 0
}

# manifest_lock_acquire <nonce> — returns 0 holding the lock, or 1 with
# MANIFEST_ERR set. FAIL-CLOSED: a lock that cannot be acquired is never a
# reason to append anyway. The caller turns the non-zero into a `blocked`
# verdict with JSON on stdout and nothing moved (R3.4).
manifest_lock_acquire() {
  local err probe obs prev="" seen=false broke=false
  local naps=0 races=0 per timeout
  timeout=$(manifest_lock_timeout)
  MANIFEST_ERR=""
  while :; do
    if err=$(mkdir "$MANIFEST_LOCK_DIR" 2>&1); then
      # Won the race. Claim it BY NAME before anyone can call it abandoned.
      if : > "$MANIFEST_LOCK_DIR/owner.$1" 2> /dev/null; then
        MANIFEST_LOCK_HELD=true
        MANIFEST_LOCK_MARK="$MANIFEST_LOCK_DIR/owner.$1"
        return 0
      fi
      # The directory vanished between the mkdir and the marker: a waiter broke
      # what looked like an empty corpse. We are NOT the holder — start over.
      rmdir "$MANIFEST_LOCK_DIR" 2> /dev/null || true
      manifest_lock_nap
      continue
    fi
    # mkdir failed. SEVERAL answers hide behind that, and the errno TEXT cannot
    # separate them — it follows the host locale ("Arquivo existe" on this
    # machine, and the JSON report is no place to start matching translated
    # strings). Neither can a second `[[ -e ]]`/`[[ -d ]]` test: EVERY such test
    # is a fresh look at a path other archives are creating and removing, so it
    # answers about a different instant than the mkdir did. Both bugs this
    # classification has had were exactly that — `[[ ! -d ]]` reading a released
    # lock as "impossible", then `[[ -e ]]` reading a RE-taken one as "a file is
    # in the way". Only two facts here are stable under concurrency: whether a
    # lock directory is present, and whether the PARENT can hold one at all.
    if [[ ! -d "$MANIFEST_LOCK_DIR" ]]; then
      # No lock directory at this instant — and an absent lock is a FREE lock,
      # never a reason to fail. Ask the filesystem whether the parent works
      # instead of guessing from the message: if a directory of our own can be
      # created beside it, the failure was about the NAME and is retryable.
      # (`-w` on the parent is not enough: it reads permission bits and answers
      # wrong for a read-only mount, for ENOSPC, and for a mandatory-access-
      # control refusal. Creating one actually settles it.)
      if ! probe=$(mktemp -d "$ARCHIVE_DIR/.manifest-lock-probe.XXXXXX" 2> /dev/null); then
        MANIFEST_ERR="cannot create the manifest lock '$MANIFEST_LOCK_DIR': ${err//$'\n'/; }"
        return 1
      fi
      rmdir "$probe" 2> /dev/null || true
      # A LOST RACE RESOLVES ITSELF; A BLOCKED NAME NEVER DOES — and retrying is
      # what tells them apart without any racy test at all. The holder released
      # between our mkdir and this point (the command substitution around mkdir
      # makes that window MILLISECONDS wide, and it was measured at ~6% of
      # concurrent runs, every one of them a spurious `blocked` verdict): the
      # next attempt or two takes the lock. A regular file sitting at the name,
      # by contrast, fails every attempt identically. Bounded, so the pathology
      # ends in a verdict and never in a spin — ~0.4 s, against a 30 s timeout.
      races=$((races + 1))
      if [[ $races -gt 100 ]]; then
        MANIFEST_ERR="cannot create the manifest lock '$MANIFEST_LOCK_DIR' in 100 consecutive attempts although its parent is writable: ${err//$'\n'/; }"
        if [[ -e "$MANIFEST_LOCK_DIR" && ! -d "$MANIFEST_LOCK_DIR" ]]; then
          # Advisory only, and read AFTER the verdict is already settled — so
          # being wrong about it costs a confusing hint, never a wrong verdict.
          MANIFEST_ERR="$MANIFEST_ERR — a non-directory occupies that path; remove it and re-run"
        fi
        return 1
      fi
      continue
    fi
    races=0   # somebody genuinely holds it: this is contention, not a race
    obs=$(manifest_lock_owner)
    if [[ "$seen" == false || "$obs" != "$prev" ]]; then
      seen=true
      prev="$obs"
      naps=0   # the lock changed hands: it is alive, not stale
    fi
    # Elapsed time is counted in NAPS, not in $SECONDS. $SECONDS has one-second
    # resolution and is measured from the shell's start, so `SECONDS - start >=
    # 1` fires the instant the counter happens to tick — a 1-second timeout that
    # is really zero, which is exactly how a live lock gets broken. Naps are
    # monotonic, need no clock at all (this script already refuses to depend on
    # `date` working), and a loaded machine makes them LONGER, so the timeout
    # errs towards waiting rather than towards breaking.
    if [[ "$MANIFEST_LOCK_NAP" == int ]]; then per=1; else per=50; fi
    if [[ $naps -ge $((timeout * per)) ]]; then
      if [[ "$broke" == true ]]; then
        MANIFEST_ERR="the manifest lock '$MANIFEST_LOCK_DIR' is STILL held ${timeout}s after a stale one was cleared — another archive is running, or that directory cannot be removed; nothing was appended"
        return 1
      fi
      printf 'archive-story: breaking the manifest lock held by %s for %ss — assuming the process that took it died\n' \
        "${obs:-an unmarked holder}" "$timeout" >&2
      # Identity-targeted: the marker is removed BY THE NAME that was observed,
      # so a lock that changed hands keeps its new holder's marker and the
      # rmdir below fails with ENOTEMPTY instead of stealing a live lock.
      if [[ -n "$obs" ]]; then
        rm -f "$MANIFEST_LOCK_DIR/$obs" 2> /dev/null || true
      fi
      rmdir "$MANIFEST_LOCK_DIR" 2> /dev/null || true
      broke=true
      seen=false
      prev=""
      naps=0
      continue
    fi
    manifest_lock_nap
    naps=$((naps + 1))
  done
}

# manifest_lock_release — idempotent, and always 0: it also runs from the EXIT
# trap, where a non-zero would be noise on a path that already has its verdict.
manifest_lock_release() {
  [[ "$MANIFEST_LOCK_HELD" == true ]] || return 0
  MANIFEST_LOCK_HELD=false
  rm -f "$MANIFEST_LOCK_MARK" 2> /dev/null || true
  rmdir "$MANIFEST_LOCK_DIR" 2> /dev/null || true
  return 0
}

# manifest_append — creates the file with its header when absent (R3.3), then
# appends the entry UNDER THE LOCK ABOVE. Every write reports instead of
# aborting, so a failure becomes a `blocked` verdict with JSON on stdout rather
# than a bare non-zero exit; MANIFEST_ERR carries what the OS actually said,
# because "permission denied", "no space left on device" and "read-only file
# system" are three different fixes and only the kernel knows which one it is.
#
# ONE ENTRY PER APPEND. The entry is composed in memory first and written with a
# single `printf`, not emitted field by field: a run killed between two of
# fourteen writes used to leave a stub entry on disk that nothing would ever
# repair. That is about THIS process's own interruption; it is the LOCK, not the
# single printf, that keeps a CONCURRENT run out of the middle of the entry —
# bash line-buffers, so one printf is still one write(2) per line. `>>` stays:
# O_APPEND means even a bug in the locking can only ever misorder whole lines,
# never overwrite an entry that is already on disk.
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
  local entry nonce rc
  entry=$(manifest_entry_yaml) || return 1
  # The lock lives INSIDE the archive directory, so that directory has to exist
  # before the lock can be taken. Its own failure is reported the same way.
  if ! MANIFEST_ERR=$(mkdir -p "$ARCHIVE_DIR" 2>&1); then
    MANIFEST_ERR=${MANIFEST_ERR//$'\n'/; }
    return 1
  fi
  # A per-process nonce. $$ is unique among concurrent processes on a host;
  # HOSTNAME distinguishes hosts sharing the archive over a network filesystem.
  nonce="${HOSTNAME:-h}-$$-${RANDOM}"
  nonce=${nonce//[^A-Za-z0-9_-]/_}
  manifest_lock_acquire "$nonce" || return 1
  MANIFEST_ERR=$(
    {
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
  ) && rc=0 || rc=1
  # Released HERE, not at the end of the run: the move (step 6) is the long part
  # and holding the lock across it would serialize whole archives, not appends.
  manifest_lock_release
  if [[ $rc -eq 0 ]]; then
    return 0
  fi
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

# --- Index regeneration (step 8) --------------------------------------------
# R5.2: after a story is archived, its row in `.epic/EPIC.md` must resolve into
# `.epic/archive/`. The row is not rewritten in place — scripts/epic-index.sh
# REGENERATES the whole managed block from disk state, which is what makes the
# link correct by construction (design.md, component 3: the clubedavoz frozen
# index is the failure mode a hand-maintained one produced).
#
# WHICH IS WHY THIS STEP IS LAST, and not merely by convention: the row is
# derived from where the directory IS (step 6) and from what its frontmatter
# SAYS (step 7). Regenerate before either and the block describes the story as
# it was a moment ago — a freshly generated stale index, which is worse than no
# index at all because it looks current.
#
# A FAILURE HERE NEVER ROLLS BACK (design.md, Error Handling — "Move succeeded,
# index regen failed: warn + manifest already correct; next LIST retries
# regeneration (idempotent)"). The move and the manifest entry ARE the archive;
# the index is a rendering of them. Undoing a completed, recorded move because a
# markdown table could not be rewritten would trade a stale rendering for a
# destroyed archive — and since the generator is idempotent and reads only disk,
# the next regeneration repairs it with no state to reconcile. So this step
# warns, reports `index: "regen-failed"`, and the run still exits 0.
#
# `index` HONESTY — the distinction sub-task 1.1 recorded, which this step must
# not blur:
#   ok            the generator ran and returned 0
#   regen-failed  the generator ran and did not return 0, or could not be run
#   skipped       THIS STEP NEVER RAN — a refusal or a guard block exited first
# `skipped` is NOT a synonym for "no regeneration happened". It says the archive
# never got this far, so nothing moved and the index still agrees with the disk.
# After a completed move that would be a lie in the dangerous direction, because
# the row then points at a `stories/` path that no longer exists. That is why a
# MISSING generator is reported as `regen-failed`, not as `skipped`.

# Resolved from THIS script's own location, not from PATH and not from the cwd:
# the generator is a sibling shipped with the plugin, and archive-story.sh is
# invoked from wherever the operator happens to be. Computed at load time,
# before anything could change directory, and reported instead of fatal — a
# `VAR=$(cmd)` that fails under `set -e` would end the run with no JSON at all.
INDEX_SCRIPT=""
INDEX_ERR=""
_epic_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || _epic_script_dir=""
[[ -n "$_epic_script_dir" ]] && INDEX_SCRIPT="$_epic_script_dir/epic-index.sh"
unset _epic_script_dir

# regenerate_index — step 8 itself. It always returns 0: this step reaches no
# verdict of its own, it only decides between `ok` and `regen-failed` and says
# which, in INDEX_STATE (structurally, on stdout) and INDEX_ERR (for the human).
#
# The generator is run through `${BASH:-bash}` rather than executed. It carries
# a shebang but is not required to be executable — the test suite invokes it the
# same way — and naming the interpreter also runs the child under the SAME bash
# that is running this script, instead of whatever `bash` PATH resolves to.
#
# BOTH of the child's streams are captured into a variable and replayed on
# STDERR. epic-index.sh's contract is that its stdout is empty (every diagnostic
# it has goes to stderr, precisely so it can be called from here) — but THIS
# script's stdout is reserved for one JSON object that a consumer pipes straight
# into jq, so the guarantee is enforced at the call site instead of trusted:
# whatever the child prints, none of it can reach our stdout.
regenerate_index() {
  local out rc
  INDEX_ERR=""
  # `[[ -f ]]` says the file EXISTS, not that it opens — so this check is only
  # here to name the ordinary case (an older install, or someone deleted it)
  # with a message that helps. A file that exists and cannot be read still fails
  # below, where bash's own diagnostic is captured.
  if [[ -z "$INDEX_SCRIPT" || ! -f "$INDEX_SCRIPT" ]]; then
    INDEX_STATE="regen-failed"
    INDEX_ERR="the index generator is not there (looked for '${INDEX_SCRIPT:-<the sibling epic-index.sh of this script>}')"
    return 0
  fi
  out=$("${BASH:-bash}" "$INDEX_SCRIPT" --epic-dir "$EPIC_DIR" 2>&1) && rc=0 || rc=$?
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out" >&2
  fi
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
# Beside the file it guards, so it is on the same filesystem and inside the same
# tree the archive guard protects. Dot-prefixed: it is machinery, not a record.
MANIFEST_LOCK_DIR="$ARCHIVE_DIR/.manifest.lock"

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

# Boundary log: the run's configuration, once, at the point where preflight has
# passed and the destructive half begins. Which guards were overridden is the
# first question anyone debugging an archive asks, and stdout is reserved for
# the JSON report, so it goes to stderr as key=value.
printf 'archive-story: story=%s allow_heavy=%s skip_secrets=%s keep_logs=%s keep_copies=%s force=%s\n' \
  "$STORY_ID" "$ALLOW_HEAVY" "$SKIP_SECRETS" "$KEEP_LOGS" "$KEEP_COPIES" "$FORCE" >&2

# ============================================================================
# STEP 2 — WEIGHT/BINARY GUARD (R1.2, R1.4)
# ============================================================================
# Default-on, and placed HERE for a reason the step order makes load-bearing:
# before the manifest append (step 5), before the move (step 6) and before the
# prune (step 4), so a blocked story leaves NO entry, NO archive directory and
# nothing renamed or deleted. The whole guard is one flag away — `--allow-heavy`
# skips it and is recorded in the manifest entry (R1.4), which is the difference
# between a heavy archive somebody chose and one nobody noticed.
# The three outcomes are logged in the same key=value shape as move_mode and
# status, so `grep 'guard=weight-binary'` on stderr answers "what did the guard
# decide" without parsing prose — stdout stays reserved for the JSON report.
if [[ "$ALLOW_HEAVY" == true ]]; then
  printf 'archive-story: guard=weight-binary verdict=skipped reason=--allow-heavy (files over %d bytes and non-text files are archived as they are; the override is recorded in the manifest entry)\n' \
    "$GUARD_MAX_BYTES" >&2
elif scan_weight_binary; then
  printf 'archive-story: guard=weight-binary verdict=pass files_scanned=%d limit_bytes=%d\n' \
    "$GUARD_SCANNED" "$GUARD_MAX_BYTES" >&2
else
  printf 'archive-story: guard=weight-binary verdict=blocked violations=%d files_scanned=%d\n' \
    "$GUARD_VIOLATION_COUNT" "$GUARD_SCANNED" >&2
  block "$GUARD_VIOLATION_COUNT file(s) fail the weight/binary guard (limit ${GUARD_MAX_BYTES} bytes, and the content must be text): $GUARD_OFFENDER_TEXT — nothing was moved and no manifest entry was written: the guard runs before both (R1.2). Remove or shrink them, re-encode a UTF-16/UTF-32 artifact as UTF-8 (its ASCII-range characters carry NUL bytes, which is what makes it read as binary), or re-run with --allow-heavy to archive them as they are (the override is recorded in the manifest entry)"
fi

# ============================================================================
# STEP 3 — SECRETS GUARD (R1.3, R1.4, R1.8)
# ============================================================================
# Default-on when the scanner is there, and placed HERE for the same reason
# step 2 is: before the prune (step 4), the manifest append (step 5) and the
# move (step 6), so a blocked story leaves no entry, no archive directory and
# nothing deleted. `--skip-secrets` is the one flag past it, and the flag parser
# has already collected it into OVERRIDES_USED, which step 5 records (R1.4) —
# the difference between an unscanned archive somebody chose and one nobody
# noticed.
#
# The verdict is logged on stderr in the same key=value shape as step 2's, so
# `grep 'guard=secrets'` answers "what did the scan decide" without parsing
# prose; stdout stays reserved for the JSON report.
if [[ "$SKIP_SECRETS" == true ]]; then
  # R1.4. Reported as `scanned: false` with the reason, NEVER as `findings: 0`:
  # a skip that looks like a clean scan is worse than no scan at all.
  set_secrets_json false "" "" "--skip-secrets" ""
  SECRETS_COVERAGE="NOT SCANNED — --skip-secrets was passed, so nothing in this story was scanned for credentials"
  printf 'archive-story: guard=secrets verdict=skipped reason=--skip-secrets (the story is archived WITHOUT a secrets scan; the override is recorded in the manifest entry)\n' >&2
elif ! command -v gitleaks > /dev/null 2>&1; then
  # R1.8, and the ONE documented degradation in this script (see the note at the
  # top of the guard). It is noted TWICE, on purpose and in two registers:
  # structurally on stdout, in `secrets.skipped`, because the orchestrator pipes
  # stdout into jq and a note only on stderr would be invisible to it; and in
  # prose on stderr for the human, where every other diagnostic lives.
  set_secrets_json false "" "" "gitleaks not installed" ""
  SECRETS_COVERAGE="NOT SCANNED — no secrets scanner was installed on the machine that archived this story (R1.8)"
  printf 'archive-story: guard=secrets verdict=skipped reason=gitleaks-not-installed (no secrets scanner on PATH — the story is archived UNSCANNED; install gitleaks to turn the guard on)\n' >&2
else
  count_unscanned_large
  run_secrets_scan && SECRETS_RC=0 || SECRETS_RC=$?
  case "$SECRETS_RC" in
    0)
      set_secrets_json true "$SECRETS_FINDINGS" "" "" ""
      SECRETS_COVERAGE="scanned by gitleaks before this summary was written — 0 findings"
      if [[ "$SECRETS_UNSCANNED" -gt 0 ]]; then
        # Not a block: R1.3 asks for a scan and a findings count, not for a size
        # policy — step 2 already owns that, and getting here at all means
        # --allow-heavy was used. But "0 findings" must not be allowed to imply
        # "0 secrets" when the scanner never opened the biggest file in the tree.
        printf 'archive-story: guard=secrets verdict=pass findings=0 unscanned_files=%d WARNING: gitleaks SILENTLY SKIPS any file over %d bytes (--max-target-megabytes %d), so this pass does NOT cover: %s\n' \
          "$SECRETS_UNSCANNED" "$GITLEAKS_SKIP_BYTES" "$GITLEAKS_MAX_MB" "$SECRETS_UNSCANNED_TEXT" >&2
      else
        printf 'archive-story: guard=secrets verdict=pass findings=0 unscanned_files=0\n' >&2
      fi
      ;;
    1)
      # R1.3. The COUNT and the report PATH are what leave this process: the
      # matched secrets stay in gitleaks' own report, mode 600 in a private
      # directory outside the story. Putting them in the reason would copy the
      # leak into every log that captures this run.
      set_secrets_json true "$SECRETS_FINDINGS" "$SECRETS_REPORT" "" ""
      printf 'archive-story: guard=secrets verdict=blocked findings=%d report=%s\n' \
        "$SECRETS_FINDINGS" "$SECRETS_REPORT" >&2
      block "gitleaks found $SECRETS_FINDINGS secret(s) in '$STORY_PATH' — the full report (rule, file and line per finding) is at '$SECRETS_REPORT', outside the project and readable only by you; the matched values are deliberately NOT repeated here. Nothing was moved and no manifest entry was written: the guard runs before both (R1.3). Rotate whatever leaked and remove it from the story's files, or re-run with --skip-secrets to archive them as they are (the override is recorded in the manifest entry)"
      ;;
    *)
      # Fail-closed, and the whole point of the split: an ABSENT scanner is the
      # degradation above; a scanner that RAN and could not answer is a guard
      # hit like any other. Reporting it as `findings: 0` would be this script
      # telling its consumer that something looked when nothing did.
      set_secrets_json false "" "$SECRETS_REPORT" "" "$SECRETS_ERR"
      printf 'archive-story: guard=secrets verdict=blocked reason=scan-failed\n' >&2
      block "the secrets scan of '$STORY_PATH' FAILED, so its result cannot be trusted: $SECRETS_ERR. A scanner that RAN and failed is a block, never a pass — only an ABSENT scanner is a documented degradation (R1.8). Nothing was moved and no manifest entry was written: the guard runs before both (R1.3). Fix the scanner, or re-run with --skip-secrets to archive without a scan (the override is recorded in the manifest entry)"
      ;;
  esac
fi

# ============================================================================
# STEP 4 — PRUNE .draft (R2.1, R2.2, R2.3 — sub-tasks 3.1 and 3.2)
# ============================================================================
# It belongs HERE, between the guards and the manifest append: nothing
# destructive may run before every guard has passed, and pruning must happen
# before the entry is derived so `pruned {}` reports what actually happened.
#
# THIS LINE IS THE SEQUENCE ASSERTION'S ONE WRITER. Control reaches it only by
# falling out of the bottom of steps 2 and 3, every blocking branch of which
# exits through `block`. So GUARDS_PASSED cannot be true unless both guards
# either passed or were explicitly overridden — and BOTH halves of the first
# destructive step in the pipeline read it before they touch anything.
GUARDS_PASSED=true

prune_logs_step "$STORY_ABS/.draft/logs" "$STORY_ABS/.draft/logs-summary.md"

# The logs half runs FIRST, so `.draft/logs-summary.md` already exists when the
# copies half enumerates the subtree. It is inert there unless the story also
# carries a top-level `logs-summary.md` with the very same bytes — see the note
# at prune_copies_collect, which is where that case is reasoned through.
prune_copies_step "$STORY_ABS/.draft"

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

# The append takes a lock (see manifest_lock_acquire). Release it on EVERY way
# out of this process, so that the ordinary interruptions — Ctrl-C, a timeout's
# SIGTERM, a closed terminal — cost the NEXT run nothing at all. Only SIGKILL
# and a power cut can leave the lock behind, and those are what the stale-break
# exists for. Installed here, not at the top: no lock is held before step 5, and
# an EXIT trap that runs on the refusal paths would be dead weight there.
# `|| true`: a trap must never turn a clean verdict into a failure.
trap 'manifest_lock_release || true' EXIT
trap 'manifest_lock_release || true; exit 130' INT
trap 'manifest_lock_release || true; exit 143' TERM
trap 'manifest_lock_release || true; exit 129' HUP

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

# The archive is complete HERE: the story is moved, recorded and consistent with
# its own frontmatter. Everything after this point is a rendering of that fact,
# and nothing after this point may change the verdict.
STATUS="archived"
printf 'archive-story: status=archived artifacts_updated=%d\n' "$STATUS_APPLIED" >&2

# ============================================================================
# STEP 8 — INDEX REGENERATION (R5.2)
# ============================================================================
# LAST, so the regenerated row reflects the archived state: the link comes from
# where the directory now is (step 6) and the status cell from what its
# frontmatter now says (step 7). The verdict line above is printed BEFORE this
# step, so the ordering is assertable from stderr and not merely stated here.
regenerate_index

if [[ "$INDEX_STATE" != "ok" ]]; then
  # A WARNING, NOT A VERDICT — STATUS stays `archived` and the exit stays 0.
  # It is carried on stdout as well as on stderr because the orchestrator pipes
  # stdout into jq: a note only a human can see is invisible to the consumer
  # that would act on it (the same two-register rule step 3 follows for R1.8).
  REASON="'$STORY_ID' IS archived and recorded, but the managed index block in '$EPIC_DIR/EPIC.md' could not be regenerated, so its row still points at the story's old location — $INDEX_ERR. NOTHING WAS ROLLED BACK: the move and the manifest entry stand, and the index is generated from disk state, so re-running 'epic-index.sh' (or the next LIST, which regenerates opportunistically) repairs the row with nothing to reconcile"
fi

# ONE line, one field list, two verdict words — the convention prune_copies_step
# records: a second printf is a second copy of the same key list, and the next
# field added to one of them would be silently missing from the other. So
# `grep 'archive-story: index='` answers with one shape whatever happened.
printf 'archive-story: index=%s generator=%s epic_dir=%s%s\n' \
  "$INDEX_STATE" "${INDEX_SCRIPT:-(not found)}" "$EPIC_DIR" \
  "${INDEX_ERR:+ reason=$INDEX_ERR (the move STANDS — the block is regenerated from disk state, so the next run repairs it)}" >&2

printf 'Archived: %s -> %s\n' "$STORY_PATH" "$ARCHIVE_DIR/$STORY_ID" >&2
emit_report
exit 0
