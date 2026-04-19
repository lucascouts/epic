#!/usr/bin/env bash
# Cross-references requirements between story.md and tasks.md
# Usage: bash scripts/cross-reference.sh <story-directory>
# Exit 0 = all requirements traced, Exit 1 = orphans/phantoms found, Exit 2 = invalid input
# Output: JSON traceability report

set -euo pipefail

# --- Help ---
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'HELP'
Usage: cross-reference.sh <story-directory>

Cross-references R-numbers between story.md and tasks.md.
Reports orphan requirements (in story but not tasks) and
phantom references (in tasks but not story).

Output: JSON traceability report with per-requirement mapping.

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

# Get unique R-numbers from each file
STORY_REQS=$(grep -oE '\bR[0-9]+(\.[0-9]+)?\b' "$STORY_FILE" 2>/dev/null | sort -u || true)
TASK_REQS=$(grep -oE '\bR[0-9]+(\.[0-9]+)?\b' "$TASKS_FILE" 2>/dev/null | sort -u || true)

# --- Build traceability ---
ORPHANS=()    # In story but not tasks
PHANTOMS=()   # In tasks but not story
TRACED=()     # In both

if [[ -n "$STORY_REQS" && -n "$TASK_REQS" ]]; then
  # Requirements in story but not in tasks
  while IFS= read -r req; do
    [[ -n "$req" ]] && ORPHANS+=("$req")
  done < <(comm -23 <(echo "$STORY_REQS") <(echo "$TASK_REQS") 2>/dev/null || true)

  # Requirements in tasks but not in story
  while IFS= read -r req; do
    [[ -n "$req" ]] && PHANTOMS+=("$req")
  done < <(comm -13 <(echo "$STORY_REQS") <(echo "$TASK_REQS") 2>/dev/null || true)

  # Requirements in both
  while IFS= read -r req; do
    [[ -n "$req" ]] && TRACED+=("$req")
  done < <(comm -12 <(echo "$STORY_REQS") <(echo "$TASK_REQS") 2>/dev/null || true)
elif [[ -n "$STORY_REQS" && -z "$TASK_REQS" ]]; then
  while IFS= read -r req; do
    [[ -n "$req" ]] && ORPHANS+=("$req")
  done <<< "$STORY_REQS"
elif [[ -z "$STORY_REQS" && -n "$TASK_REQS" ]]; then
  while IFS= read -r req; do
    [[ -n "$req" ]] && PHANTOMS+=("$req")
  done <<< "$TASK_REQS"
fi

TOTAL_ORPHANS=${#ORPHANS[@]}
TOTAL_PHANTOMS=${#PHANTOMS[@]}
TOTAL_TRACED=${#TRACED[@]}
TOTAL_STORY_REQS=$(echo "$STORY_REQS" | grep -c '\S' 2>/dev/null || echo 0)
TOTAL_TASK_REQS=$(echo "$TASK_REQS" | grep -c '\S' 2>/dev/null || echo 0)
HAS_ISSUES=$([[ $TOTAL_ORPHANS -gt 0 || $TOTAL_PHANTOMS -gt 0 ]] && echo true || echo false)

# --- JSON helper ---
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
    echo -n "\"${arr[$i]}\"$COMMA"
  done
  echo "]"
}

# --- Output ---
echo "{"
echo "  \"story\": \"$STORY_DIR\","
echo "  \"story_requirements\": $TOTAL_STORY_REQS,"
echo "  \"task_references\": $TOTAL_TASK_REQS,"
echo "  \"traced\": $TOTAL_TRACED,"
echo "  \"orphan_requirements\": $(json_array "${ORPHANS[@]}"),"
echo "  \"phantom_references\": $(json_array "${PHANTOMS[@]}"),"
echo "  \"coverage\": \"$TOTAL_TRACED/$TOTAL_STORY_REQS\","
echo "  \"status\": \"$([[ "$HAS_ISSUES" == true ]] && echo 'issues' || echo 'clean')\""
echo "}"

if [[ "$HAS_ISSUES" == true ]]; then
  exit 1
else
  exit 0
fi
