#!/usr/bin/env bash
# Cross-references requirements between story.md and tasks.md
# Usage: bash scripts/cross-reference.sh <story-directory>
# Exit 0 = all requirements traced (or the declared scale has no chain to trace),
# Exit 1 = orphans/phantoms found, Exit 2 = invalid input
# Output: JSON traceability report with a per-requirement task map — or, when the
# story's declared scale carries no requirements chain, the inapplicability
# object below (story 008, R3.4):
#
#   { "story": "…", "scale": "spike", "status": "no-requirements-chain" }
#
# CONSUMER RULE — BRANCH ON `status`, NEVER ON A MEASUREMENT KEY BEING PRESENT.
# `story`, `scale` and `status` are TOTAL ON EVERY PATH THAT EMITS JSON — which
# is not every path: `--help` prints prose, and the three input-validation
# failures print to stderr and emit NO stdout at all (exit 2, pinned as such).
# So the rule is reachable only after the caller has established that the exit
# code is not 2; `status` is then guaranteed present and one of the four values
# named at the bottom of this block.
# Every other key is a MEASUREMENT (story_requirements, task_references,
# parseable_tasks, traced, orphan_requirements, phantom_references, coverage,
# mapping) and is ABSENT from that object rather than zeroed, because `traced: 0`
# with `coverage: "0/0"` claims a measurement was made and came back empty —
# a different statement from "there was nothing here to measure" — and an
# `orphan_requirements: []` claims a look was taken with identical force. Same
# shape and same reason as epic-gitpolicy.sh's non-git object.
# The practical half of the rule: `jq -r` renders an ABSENT key as the literal
# text `null`, not as `0` or `[]`, so a consumer reading one unconditionally does
# not read a zero — it reads `null`, and `[[ "$(jq -r .traced …)" -gt 0 ]]`
# aborts under `set -u` with "null: unbound variable". Gate on `status`.
#
# `status` values: clean | issues | untraceable-format | no-requirements-chain.

set -euo pipefail

# --- Help ---
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'HELP'
Usage: cross-reference.sh <story-directory>

Cross-references R-numbers between story.md and tasks.md.
Reports orphan requirements (in story but not tasks) and
phantom references (in tasks but not story).

Output: JSON traceability report. The "mapping" object lists, per story
requirement, the sub-tasks that declare it in a Requirements: field.

A story whose declared scale carries no requirements chain (fast, spike) is
not measured at all. The output is then

  { "story": "...", "scale": "spike", "status": "no-requirements-chain" }

with the measurement keys ABSENT rather than zeroed — nothing was measured,
so nothing is reported as measured. Branch on "status", never on a key
being present.

Exit codes:
  0  All requirements traced, or the declared scale has no chain to trace
  1  Orphans or phantoms found
  2  Invalid input (missing files)
HELP
  exit 0
fi

# --- Input validation ---
STORY_DIR="${1:-.}"

if [[ ! -d "$STORY_DIR" ]]; then
  echo "Error: Directory '$STORY_DIR' not found." >&2
  exit 2
fi

# LOAD-BEARING AFTER R3.4, AND NOT AN OVERSIGHT BESIDE IT. `fast` and `spike`
# are tasks-only scales, so this exit 2 means a CONFORMING story at either scale
# never reaches the report at all — and that is the stronger statement, not a gap
# in the no-requirements-chain handling below: a scale with no chain to trace is
# not ROUTED THROUGH a traceability tool, rather than routed through it and
# handed a verdict. The tempting "fix" is to make a missing story.md exit 0 now
# that a spike is allowed to have none; it would swallow a genuinely malformed
# lifecycle story — one whose story.md was deleted by mistake — under the same
# silence. Pinned by tests/scale-resolution.bats ("a conforming tasks-only spike
# still exits 2 with no report"): no JSON at all, so no consumer can read a
# verdict out of this.
# The consequence is that the object below is reachable ONLY on the
# leftover-artifact shape — a spike beside a story.md surviving an earlier
# attempt — which is exactly the shape story 008 exists to fix, and why nothing
# caught this script before.
if [[ ! -f "$STORY_DIR/story.md" ]]; then
  echo "Error: No story.md found in '$STORY_DIR'." >&2
  exit 2
fi

if [[ ! -f "$STORY_DIR/tasks.md" ]]; then
  echo "Error: No tasks.md found in '$STORY_DIR'." >&2
  exit 2
fi

STORY_FILE="$STORY_DIR/story.md"
TASKS_FILE="$STORY_DIR/tasks.md"

# --- JSON string escape ---
# Minimal escape so paths/tokens with quotes, backslashes or control characters
# never produce invalid JSON for the jq consumers downstream. It sits HERE rather
# than beside the array and mapping helpers it used to live with, because the
# R3.4 early return below emits a COMPLETE object before any measurement is taken
# and needs it; the other two helpers shape measurements and stay next to them.
json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

# --- The declared scale (story 008, R3.4) ---
# frontmatter_field <file> <key> — the value of a column-0 frontmatter key, or
# nothing at all when the file, the frontmatter or the key is absent.
#
# COPIED VERBATIM FROM archive-story.sh:307-326, by decision and not by
# convenience. The repository has three frontmatter readers in two dialects, and
# this one joins the MAJORITY (archive-story.sh, monitor-stale.sh) instead of
# adding a fourth. Two measured properties decide it:
#   * a trailing YAML comment is STRIPPED, so `scale: spike # probe` resolves
#     `spike` rather than the token `spike#probe`;
#   * CRLF is TOLERATED — `^---\r?$` for the delimiters, and the `[:space:]` trim
#     for the `\r` at the end of the value.
# validate-story.sh's reader has NEITHER, and copying that dialect here would
# have been actively harmful rather than merely inconsistent: under it a CRLF
# checkout reads as scale-less, scale-less falls to the predicate's `*` arm and
# is treated as HAVING a requirements chain, and the comparison this whole block
# exists to suppress comes straight back on one class of checkout — silently.
# The divergence between the readers is registered as a Known Divergence in story
# 008's design.md and is deliberately not fixed from here.
#
# `|| val=""` is this dialect's spelling of the `|| true` at
# validate-story.sh:75-78 and is load-bearing for the same reason: this script
# runs under `set -euo pipefail`, an ABSENT key makes `grep` exit 1, and an
# unguarded command substitution would abort the whole run on what is the COMMON
# case — a story that declares no scale anywhere. The same guard on the two lines
# above it, for the file and the frontmatter block.
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

# THE SHARED SCALE RULE — `tasks.md` is AUTHORITATIVE for `scale:`, and every
# reader of a story's scale resolves it that way. tasks.md is the one artifact
# every scale has, so a declaration sitting there is never a leftover; a
# design.md or a story.md surviving an earlier attempt at a differently-shaped
# story is exactly that, and honouring one of those over the live tasks.md is the
# defect story 008 removes. THE FULL ARGUMENT IS STATED ONCE, at
# validate-story.sh's resolution loop (search it for "THE SHARED SCALE RULE") —
# this is a pointer to it, not a second copy that can drift from it.
#
# FIVE READERS RESOLVE A STORY'S SCALE AND MOVE TOGETHER. Named in full,
# including the two that do NOT change, because an inventory listing only the
# movers is the one that goes stale in silence:
#   1. validate-story.sh — turns the scale into validation findings.
#   2. archive-story.sh `story_scale` — the archive preflight and the `scale`
#      recorded in the manifest entry.
#   3. cross-reference.sh (HERE) — decides whether there is a requirements chain
#      to compare against at all.
#   4. monitor-stale.sh:96 `declares_spike_scale` — already reads tasks.md and
#      nothing else. It never carried the defect; this rule is the rest of the
#      codebase agreeing with the precedent it set.
#   5. epic-index.sh:762-768 `status_cell` — knowingly kept on the older
#      precedence and out of scope. It renders a row, it gates nothing, and a
#      renderer that disagrees costs a wrong cell, not a wrong archive.
#
# There is no shared library to import the rule from: `scripts/` has none, every
# script here is invoked standalone by path. So it is duplicated, and the five
# copies move as one.
#
# design.md is not read at all. It is enum-checked and compared by
# validate-story.sh but never resolves (R2.4) — it describes the SOLUTION, not
# the shape of the work — and this script has no divergence report in which its
# declaration could be observable, so reading it would buy nothing.
#
# EVERY VALUE IS ENUM-CHECKED and an out-of-enum one resolves to NOTHING, exactly
# as it does in validate-story.sh: `medium` is not a scale, so it can neither be
# reported as one nor decide whether a requirements chain exists. It is not an
# ERROR here either — validate-story.sh owns invalid values and names them on the
# same story. A traceability tool reporting a scale error would be story 008's
# own category error, one script further along.
SCALE_ENUM='fast|standard|full|spike'
DECLARED_SCALE=""   # "" = no artifact declares a scale this script can honour
# tasks.md is read LAST and assigns unconditionally, which is how the loop at
# validate-story.sh puts the authoritative artifact in force. An invalid value
# `continue`s and so never occupies the slot — a `medium` in tasks.md beside a
# valid declaration elsewhere leaves that valid one resolved, exactly as it does
# there. The loop variable holds a PATH here and a bare filename there; same
# rule, different local shape, hence the different name.
for SCALE_FILE in "$STORY_FILE" "$TASKS_FILE"; do
  SCALE_VAL=$(frontmatter_field "$SCALE_FILE" scale)
  [[ "$SCALE_VAL" =~ ^($SCALE_ENUM)$ ]] || continue
  DECLARED_SCALE="$SCALE_VAL"
done

# scale_has_requirements_chain — does the resolved scale owe an R-chain?
# WRITTEN AS THE FALSE SET, and the direction is the whole point. A positive list
# — `standard|full|"") return 0 ;; *) return 1` — reads identically today and
# behaves the opposite way tomorrow: every FUTURE enum member would fall through
# `*`, be classified as carrying NO chain, and be opted out of this gate in
# silence. Inverted, a scale this function has never heard of falls to `*`, keeps
# its chain, and is compared loudly on the first run that meets it — wrong and
# loud beats wrong and quiet, because only one of the two gets fixed.
# It decides the LEGACY case by the same rule rather than by accident (R3.3): the
# 340+ stories that predate the `scale:` field resolve to the empty string, fall
# to `*`, and keep their requirements chain BECAUSE THE RULE SAYS SO — not
# because someone remembered to spell `""` into a list.
# Kept in the same direction and the same shape as validate-story.sh's function
# of the same name, where the full argument lives.
scale_has_requirements_chain() {
  case "$DECLARED_SCALE" in
    fast | spike) return 1 ;;
    *) return 0 ;;
  esac
}

# `scale` is a TOTAL key: emitted here AND on the report at the bottom, so a
# consumer never has to tell `spike` from "this build does not report a scale",
# and so the resolved scale is observable somewhere at all — after story 008 no
# other output in the system names it.
# A bare JSON `null` when nothing resolved, NOT `""` and not an invented
# "undeclared": `null` is JSON's own word for "there is none", while `""` is an
# empty string that reads as a scale, and `"undeclared"` would be a fifth
# spelling of a scale that references/tasks.md does not define. Keyed off the
# resolution itself, the way epic-gitpolicy.sh keys `gitignore_source: null` off
# its own probe, so the two cannot drift apart.
if [[ -n "$DECLARED_SCALE" ]]; then
  SCALE_JSON="\"$(json_escape "$DECLARED_SCALE")\""
else
  SCALE_JSON="null"
fi

# --- Nothing to trace (R3.4) ---
# REPORT THE INAPPLICABILITY; DO NOT MEASURE ZERO. A `fast` or `spike` story owes
# no requirements chain, so there is no chain to compare tasks.md against and
# every number this script would print about one is a number nobody measured.
# `traced: 0` with `coverage: "0/0"` says a measurement was made and came back
# empty; `orphan_requirements: []` says a look was taken. Both are different
# statements from "there was nothing here to measure", and the distance between
# those two is the whole subject of story 008 — so the measurement keys are
# ABSENT, not zeroed and not emptied. The precedent is epic-gitpolicy.sh's
# non-git object, which reports the fact that makes the measurement inapplicable
# and omits the measurements it never took.
# THE RULE THIS MAKES EXPLICIT FOR EVERY CONSUMER: branch on `status`, never on a
# measurement key being present.
#
# EXIT 0 ON A SHAPE THAT IS STILL MALFORMED, deliberately. A spike carrying a
# story.md contradicts its own declaration — and that defect is reported by
# validate-story.sh's R2.3 scale-vs-files warning, which is the check that owns
# it. Two gates reporting one defect in two vocabularies is how the original
# defect survived; a traceability tool answering a question nobody asked it is
# what this story removes.
#
# printf rather than echo on every line of this object, for the reason
# epic-gitpolicy.sh:463 states: escaped output is made of backslashes and `echo`
# is only backslash-safe while `xpg_echo` is off, which is an option inherited
# from the environment and not this script's to assume. The report object at the
# bottom predates that lesson and is not rewritten here — that is churn this
# change did not buy.
if ! scale_has_requirements_chain; then
  printf '%s\n' \
    "{" \
    "  \"story\": \"$(json_escape "$STORY_DIR")\"," \
    "  \"scale\": $SCALE_JSON," \
    "  \"status\": \"no-requirements-chain\"" \
    "}"
  exit 0
fi

# --- Extract R-numbers ---
# Requirements are hierarchical: a group header `### Rn.` (one-level token Rn)
# and its leaf acceptance criteria `Rn.m`. Tasks reference the LEAVES. A
# one-level token Rn is a requirement of its own ONLY when the story defines
# no child Rn.m for it (a flat, sub-criteria-less requirement); otherwise Rn
# is a group header, covered via its leaves. Counting a group header as a
# leaf produced a false orphan for every `### Rn.` heading.
mapfile -t STORY_LEAVES < <(grep -oE '\bR[0-9]+\.[0-9]+\b' "$STORY_FILE" 2>/dev/null | sort -u || true)
mapfile -t STORY_ONELEVEL < <(grep -oE '\bR[0-9]+\b' "$STORY_FILE" 2>/dev/null | sort -u || true)

# in_list <needle> <haystack...> — membership test.
in_list() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# Split one-level tokens into standalone leaves (no Rn.m child) and group
# headers (have at least one Rn.m child). Effective requirements = all
# Rn.m leaves + standalone one-level leaves.
STORY_REQS_ARR=("${STORY_LEAVES[@]}")
STORY_GROUPS=()
for tok in "${STORY_ONELEVEL[@]}"; do
  has_child=false
  for leaf in "${STORY_LEAVES[@]}"; do
    if [[ "$leaf" == "$tok".* ]]; then
      has_child=true
      break
    fi
  done
  if [[ "$has_child" == true ]]; then
    STORY_GROUPS+=("$tok")
  else
    STORY_REQS_ARR+=("$tok")
  fi
done

# --- Parse tasks.md structurally (single source of truth) ---
# REQ_MAP maps each R-token declared in a `Requirements:` field to the
# sub-tasks that declare it. Coverage, orphans and phantoms are ALL derived
# from this same structural parse. The previous implementation grepped the
# whole file for tokens, so a requirement mentioned only in prose (an
# Objective, a ToDo, a commit message) counted as "traced" while the mapping
# showed it empty — the exact condition this gate exists to catch.
declare -A REQ_MAP
REQ_KEYS=0   # manual count: ${#REQ_MAP[@]} on an empty assoc array trips set -u (bash 5.3)
CURRENT_TASK=""
PARSEABLE_TASKS=0
# A heading is parseable in all three box states — `[ ]` open, `[x]` closed,
# `[~]` closed without doing the work — because a heading this regex cannot
# see never updates CURRENT_TASK, so the `Requirements:` line under it is
# credited to the PREVIOUS task: deferring a sub-task would silently reassign
# its R-numbers (R4.2). Terminal (`waived:`/`n-a:`/`superseded-by:`) vs
# non-terminal (`deferred:`) makes no difference here — both trace their
# requirements; the qualifier grammar is validate-story.sh's job and is
# deliberately not duplicated. Keep the `[ x~]` class in sync with
# validate-story.sh and hook-task-completed.sh: one drifted copy reopens the
# false-clean/false-orphan class (R4.1). monitor-stale.sh is the deliberate
# exception — it matches `[ ]` only, because it asks what work is still owed
# rather than what counts as a task (R4.3).
task_heading_re='^[[:space:]]*-[[:space:]]\[[ x~]\][[:space:]]+([0-9]+(\.[0-9]+)?)[[:space:]]+-[[:space:]]'
requirements_re='^[[:space:]]*-[[:space:]]Requirements:[[:space:]]*(.+)$'

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ $task_heading_re ]]; then
    CURRENT_TASK="${BASH_REMATCH[1]}"
    PARSEABLE_TASKS=$((PARSEABLE_TASKS + 1))
  elif [[ -n "$CURRENT_TASK" && "$line" =~ $requirements_re ]]; then
    reqs_text="${BASH_REMATCH[1]}"
    while IFS= read -r rtok; do
      [[ -n "$rtok" ]] || continue
      if [[ " ${REQ_MAP[$rtok]:-} " != *" $CURRENT_TASK "* ]]; then
        [[ -z "${REQ_MAP[$rtok]:-}" ]] && REQ_KEYS=$((REQ_KEYS + 1))
        REQ_MAP[$rtok]="${REQ_MAP[$rtok]:-}${REQ_MAP[$rtok]:+ }$CURRENT_TASK"
      fi
    done < <(grep -oE '\bR[0-9]+(\.[0-9]+)?\b' <<< "$reqs_text" || true)
  fi
done < "$TASKS_FILE"

# Task-side tokens = the keys of REQ_MAP (structured references only).
if [[ $REQ_KEYS -gt 0 ]]; then
  mapfile -t TASK_TOKENS < <(printf '%s\n' "${!REQ_MAP[@]}" | sort -u)
else
  TASK_TOKENS=()
fi

# --- Build traceability ---
ORPHANS=()    # Story leaf requirement with no Requirements-field reference
PHANTOMS=()   # Requirements-field reference matching no story requirement
TRACED=()     # Story leaf requirement declared by at least one sub-task

for req in "${STORY_REQS_ARR[@]}"; do
  if [[ -n "${REQ_MAP[$req]:-}" ]]; then
    TRACED+=("$req")
  else
    ORPHANS+=("$req")
  fi
done

for tok in "${TASK_TOKENS[@]}"; do
  # Valid when it is an effective story leaf, or a known group header
  # (a leaf reference Rn.m implicitly covers its group Rn).
  if ! in_list "$tok" "${STORY_REQS_ARR[@]}" && ! in_list "$tok" "${STORY_GROUPS[@]}"; then
    PHANTOMS+=("$tok")
  fi
done

TOTAL_ORPHANS=${#ORPHANS[@]}
TOTAL_PHANTOMS=${#PHANTOMS[@]}
TOTAL_TRACED=${#TRACED[@]}
TOTAL_STORY_REQS=${#STORY_REQS_ARR[@]}
TOTAL_TASK_REQS=${#TASK_TOKENS[@]}

# untraceable-format: the story defines requirements but the structural
# parser found no sub-task headings (unrecognized tasks.md dialect) or no
# Requirements: fields at all. Reporting "clean" here is exactly the
# false-clean this gate must never emit; reporting per-leaf orphans would be
# noise — the actionable fix is the format, not the coverage.
UNTRACEABLE=false
if [[ $TOTAL_STORY_REQS -gt 0 && ( $PARSEABLE_TASKS -eq 0 || $REQ_KEYS -eq 0 ) ]]; then
  UNTRACEABLE=true
fi

HAS_ISSUES=$([[ $TOTAL_ORPHANS -gt 0 || $TOTAL_PHANTOMS -gt 0 || "$UNTRACEABLE" == true ]] && echo true || echo false)

if [[ "$UNTRACEABLE" == true ]]; then
  STATUS_STR="untraceable-format"
elif [[ "$HAS_ISSUES" == true ]]; then
  STATUS_STR="issues"
else
  STATUS_STR="clean"
fi

# --- JSON helpers ---
# json_escape lives further up, above the R3.4 early return that needs it.
json_array() {
  local arr=("$@")
  local len=${#arr[@]}
  if [[ $len -eq 0 ]]; then
    echo "[]"
    return
  fi
  echo -n "["
  for i in "${!arr[@]}"; do
    COMMA=","
    [[ $i -eq $((len - 1)) ]] && COMMA=""
    echo -n "\"$(json_escape "${arr[$i]}")\"$COMMA"
  done
  echo "]"
}

# emit_mapping — JSON object mapping each story requirement to the array of
# sub-task numbers that declare it. An empty array means no task declares it.
emit_mapping() {
  local req entry t sep out=""
  local -a tlist
  for req in "${STORY_REQS_ARR[@]}"; do
    entry="\"$req\": ["
    sep=""
    tlist=()
    read -ra tlist <<< "${REQ_MAP[$req]:-}"
    for t in "${tlist[@]}"; do
      entry+="$sep\"$t\""
      sep=","
    done
    entry+="]"
    if [[ -n "$out" ]]; then
      out+=", "
    fi
    out+="$entry"
  done
  echo -n "{$out}"
}

# --- Output ---
# `scale` is emitted HERE TOO, not only on the no-requirements-chain path: a key
# set that changes shape by scale is a second thing for a consumer to know about
# this contract, and the resolved scale is worth naming on the path where the
# measurement DID happen — it is the fact that decided the measurement was owed.
# Measured safe before it shipped: no case in tests/cross-reference.bats or
# tests/cross-reference-grammar.bats asserts on the key set, and none reads
# `.status` as a closed enum.
echo "{"
echo "  \"story\": \"$(json_escape "$STORY_DIR")\","
echo "  \"scale\": $SCALE_JSON,"
echo "  \"story_requirements\": $TOTAL_STORY_REQS,"
echo "  \"task_references\": $TOTAL_TASK_REQS,"
echo "  \"parseable_tasks\": $PARSEABLE_TASKS,"
echo "  \"traced\": $TOTAL_TRACED,"
echo "  \"orphan_requirements\": $(json_array "${ORPHANS[@]}"),"
echo "  \"phantom_references\": $(json_array "${PHANTOMS[@]}"),"
echo "  \"coverage\": \"$TOTAL_TRACED/$TOTAL_STORY_REQS\","
echo "  \"mapping\": $(emit_mapping),"
echo "  \"status\": \"$STATUS_STR\""
echo "}"

if [[ "$HAS_ISSUES" == true ]]; then
  exit 1
else
  exit 0
fi
