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

# --- Helper ---
add_error() { ERRORS+=("$1"); }
add_warning() { WARNINGS+=("$1"); }

# --- Detect scale from files present ---
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
  OLD_FORMAT_COUNT=$(grep -cE '^\s*- \[[ x]\].*\*\*\[T[0-9]\]\*\*' "$TASKS_FILE" 2>/dev/null || true)
  if [[ "$OLD_FORMAT_COUNT" -gt 0 ]]; then
    add_warning "Found $OLD_FORMAT_COUNT tasks using old [T1]/[T2]/[T3] prefix format — use new format: - [ ] N - Name"
  fi

  # Count all tasks (parent + sub-tasks); needed by checks inside and outside
  # the HAS_STORY branch below — define once here so set -u doesn't trip Fast
  # mode validation (tasks.md without story.md).
  TASK_COUNT=$(grep -cE '^\s*- \[[ x]\]' "$TASKS_FILE" 2>/dev/null || true)

  # Check Requirements field (only if story.md exists = standard/full)
  if [[ "$HAS_STORY" == true ]]; then
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
  PARENT_TASK_COUNT=$(grep -cE '^\s*- \[[ x]\]\s+[0-9]+\s+-\s+' "$TASKS_FILE" 2>/dev/null || true)
  METADATA_COUNT=$(grep -cE '^\s*- _Complexity:' "$TASKS_FILE" 2>/dev/null || true)
  if [[ "$PARENT_TASK_COUNT" -gt 0 && "$METADATA_COUNT" -eq 0 ]]; then
    add_warning "No metadata lines found (expected _Complexity: ... | Tests: ... | ..._) on parent tasks"
  fi

  # Check for Commit fields or sub-tasks
  COMMIT_COUNT=$(grep -ci '^\s*- Commit:' "$TASKS_FILE" 2>/dev/null || true)
  COMMIT_SUBTASK_COUNT=$(grep -ciE '^\s*- \[[ x]\].*[Cc]ommit' "$TASKS_FILE" 2>/dev/null || true)
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

# --- Validate version frontmatter ---
for f in "$STORY_DIR"/*.md; do
  [[ -f "$f" ]] || continue
  BASENAME=$(basename "$f")
  if head -1 "$f" | grep -q '^---$' 2>/dev/null; then
    # Check required frontmatter fields
    FRONT=$(sed -n '2,/^---$/p' "$f" | head -n -1)
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
  else
    add_warning "$BASENAME is missing version frontmatter"
  fi
done

# --- Flag parsing ---
CROSS_REF=false
STRICT=false
for arg in "$@"; do
  [[ "$arg" == "--cross-ref" ]] && CROSS_REF=true
  [[ "$arg" == "--strict" ]] && STRICT=true
done

if [[ "$CROSS_REF" == true && "$HAS_STORY" == true && "$HAS_TASKS" == true ]]; then
  # Extract R-numbers from story.md (R1, R1.1, R2, etc.)
  STORY_REQS=$(grep -oE '\bR[0-9]+(\.[0-9]+)?\b' "$STORY_DIR/story.md" 2>/dev/null | sort -u || true)

  # Extract R-numbers referenced in tasks.md
  TASK_REQS=$(grep -oE '\bR[0-9]+(\.[0-9]+)?\b' "$STORY_DIR/tasks.md" 2>/dev/null | sort -u || true)

  if [[ -n "$STORY_REQS" && -n "$TASK_REQS" ]]; then
    # Requirements in story but not in tasks
    ORPHAN_REQS=$(comm -23 <(echo "$STORY_REQS") <(echo "$TASK_REQS") 2>/dev/null || true)
    if [[ -n "$ORPHAN_REQS" ]]; then
      while IFS= read -r req; do
        [[ -n "$req" ]] && add_warning "Requirement $req in story.md has no matching reference in tasks.md"
      done <<< "$ORPHAN_REQS"
    fi

    # Requirements in tasks but not in story
    PHANTOM_REQS=$(comm -13 <(echo "$STORY_REQS") <(echo "$TASK_REQS") 2>/dev/null || true)
    if [[ -n "$PHANTOM_REQS" ]]; then
      while IFS= read -r req; do
        [[ -n "$req" ]] && add_warning "Requirement $req referenced in tasks.md does not exist in story.md"
      done <<< "$PHANTOM_REQS"
    fi
  elif [[ -n "$STORY_REQS" && -z "$TASK_REQS" ]]; then
    add_warning "story.md has requirements but tasks.md has no R-number references"
  fi
fi

# --- Output ---
TOTAL_ERRORS=${#ERRORS[@]}
TOTAL_WARNINGS=${#WARNINGS[@]}

echo "{"
echo "  \"story\": \"$STORY_DIR\","
echo "  \"errors\": $TOTAL_ERRORS,"
echo "  \"warnings\": $TOTAL_WARNINGS,"

if [[ $TOTAL_ERRORS -gt 0 ]]; then
  echo "  \"error_details\": ["
  for i in "${!ERRORS[@]}"; do
    COMMA=","
    [[ $i -eq $((TOTAL_ERRORS - 1)) ]] && COMMA=""
    echo "    \"${ERRORS[$i]}\"$COMMA"
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
    echo "    \"${WARNINGS[$i]}\"$COMMA"
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
