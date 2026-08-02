#!/usr/bin/env bash
# Cross-references requirements between story.md and tasks.md
# Usage: bash scripts/cross-reference.sh <story-directory>
# Exit 0 = all requirements traced, Exit 1 = orphans/phantoms found, Exit 2 = invalid input
# Output: JSON traceability report with a per-requirement task map

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

Exit codes:
  0  All requirements traced
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

if [[ ! -f "$STORY_DIR/story.md" ]]; then
  echo "Error: No story.md found in '$STORY_DIR'." >&2
  exit 2
fi

if [[ ! -f "$STORY_DIR/tasks.md" ]]; then
  echo "Error: No tasks.md found in '$STORY_DIR'." >&2
  exit 2
fi

# --- Extract R-numbers ---
STORY_FILE="$STORY_DIR/story.md"
TASKS_FILE="$STORY_DIR/tasks.md"

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
task_heading_re='^[[:space:]]*-[[:space:]]\[[ x]\][[:space:]]+([0-9]+(\.[0-9]+)?)[[:space:]]+-[[:space:]]'
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
# Minimal string escape so paths/tokens with quotes, backslashes or control
# characters never produce invalid JSON for the jq consumers downstream.
json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

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
echo "{"
echo "  \"story\": \"$(json_escape "$STORY_DIR")\","
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
