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

# --- Helpers ---
add_error() { ERRORS+=("$1"); }
add_warning() { WARNINGS+=("$1"); }

# Minimal JSON string escape: messages can embed content read from the
# artifacts (quotes, backslashes, control chars) and must never break the
# jq consumers downstream (hooks, CI).
json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

# xr_in_list <needle> <haystack...> — membership test for the cross-ref check.
xr_in_list() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

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
  OLD_FORMAT_COUNT=$(grep -cE '^\s*- \[[ x~]\].*\*\*\[T[0-9]\]\*\*' "$TASKS_FILE" 2>/dev/null || true)
  if [[ "$OLD_FORMAT_COUNT" -gt 0 ]]; then
    add_warning "Found $OLD_FORMAT_COUNT tasks using old [T1]/[T2]/[T3] prefix format — use new format: - [ ] N - Name"
  fi

  # --- Checkbox census (R3.1, R3.2, R3.5) ---
  # One line grammar, three box states:
  #   - [ ] open   - [x] closed   - [~] closed WITHOUT doing the work.
  # A `[~]` MUST say why on the same line. Terminal qualifiers (waived:, n-a:,
  # superseded-by:) end the work for good and count as closed; `deferred:` is
  # counted apart, because that work is resolved in the plan but still owed by
  # an external actor — progress then reads "closed/total (+D deferred)"
  # instead of pretending it happened.
  # Counters are plain integers incremented in the loop, never ${#assoc[@]} on
  # a possibly-empty associative array (that trips set -u on bash 5.3 — the
  # same reason REQ_KEYS exists in cross-reference.sh).
  BOX_OPEN=0         # [ ]
  BOX_CLOSED=0       # [x] plus terminal [~]
  BOX_DEFERRED=0     # [~] deferred: — closed in the plan, open in the world
  BOX_UNQUALIFIED=0  # [~] with no recognized qualifier: a grammar error
  LINE_NO=0
  box_re='^[[:space:]]*- \[([ x~])\]'
  # A qualifier is a token in its own right: `(n-a: ...)` qualifies, the tail
  # of a word like `man-a:` does not.
  deferred_re='(^|[^[:alnum:]_-])deferred:'
  terminal_re='(^|[^[:alnum:]_-])(waived|n-a|superseded-by):'
  tilde_forms="'deferred: <reason>', 'waived: <reason>', 'n-a: <reason>', 'superseded-by: NNN'"
  while IFS= read -r line || [[ -n "$line" ]]; do
    LINE_NO=$((LINE_NO + 1))
    [[ "$line" =~ $box_re ]] || continue
    case "${BASH_REMATCH[1]}" in
      ' ') BOX_OPEN=$((BOX_OPEN + 1)) ;;
      'x') BOX_CLOSED=$((BOX_CLOSED + 1)) ;;
      '~')
        if [[ "$line" =~ $deferred_re ]]; then
          BOX_DEFERRED=$((BOX_DEFERRED + 1))
        elif [[ "$line" =~ $terminal_re ]]; then
          BOX_CLOSED=$((BOX_CLOSED + 1))
        else
          BOX_UNQUALIFIED=$((BOX_UNQUALIFIED + 1))
          add_error "tasks.md line $LINE_NO: [~] checkbox has no qualifier — a box closed without doing the work must say why on the same line, one of: $tilde_forms"
        fi
        ;;
    esac
  done < "$TASKS_FILE" 2>/dev/null || true

  # Count all tasks (parent + sub-tasks) = every box whatever its state;
  # needed by checks inside and outside the HAS_STORY branch below — define
  # once here so set -u doesn't trip Fast mode validation (tasks.md without
  # story.md).
  TASK_COUNT=$(( ${BOX_OPEN:-0} + ${BOX_CLOSED:-0} + ${BOX_DEFERRED:-0} + ${BOX_UNQUALIFIED:-0} ))

  # A tasks.md with ZERO parseable checkbox tasks must never pass: every
  # downstream check is gated on TASK_COUNT > 0, so an unrecognized dialect
  # used to sail through with "pass, 0 errors". Name the variant when we can.
  if [[ "$TASK_COUNT" -eq 0 ]]; then
    VARIANT_HINT=""
    if grep -qE '^\s*-?\s*\*\*Covers:\*\*|^Covers:' "$TASKS_FILE" 2>/dev/null; then
      VARIANT_HINT=" (detected 'Covers:' dialect)"
    elif grep -qE '^#{2,3}\s+T?[0-9]+(\.[0-9]+)?[[:space:]]' "$TASKS_FILE" 2>/dev/null; then
      VARIANT_HINT=" (detected heading-based task dialect)"
    fi
    add_error "tasks.md has no parseable checkbox tasks (- [ ] N - ...)${VARIANT_HINT} — unrecognized format, nothing was validated"
  fi

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
  PARENT_TASK_COUNT=$(grep -cE '^\s*- \[[ x~]\]\s+[0-9]+\s+-\s+' "$TASKS_FILE" 2>/dev/null || true)
  METADATA_COUNT=$(grep -cE '^\s*- _Complexity:' "$TASKS_FILE" 2>/dev/null || true)
  if [[ "$PARENT_TASK_COUNT" -gt 0 && "$METADATA_COUNT" -eq 0 ]]; then
    add_warning "No metadata lines found (expected _Complexity: ... | Tests: ... | ..._) on parent tasks"
  fi

  # Check for Commit fields or sub-tasks
  COMMIT_COUNT=$(grep -ci '^\s*- Commit:' "$TASKS_FILE" 2>/dev/null || true)
  COMMIT_SUBTASK_COUNT=$(grep -ciE '^\s*- \[[ x~]\].*[Cc]ommit' "$TASKS_FILE" 2>/dev/null || true)
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

# --- Validate frontmatter (version, status) ---
# `status:` is the story's single lifecycle state, shared by every artifact.
# Grammar rule: fail-CLOSED on a present-but-wrong value (an invented dialect
# is an error), fail-OPEN on absence (340+ legacy stories have no status: and
# must validate exactly as before — no error, no warning, no extra line).
# One source of truth for the enum: the alternation drives both the check and
# the human-readable message (a `case` pattern cannot — bash does not re-parse
# `|` from an expanded variable as alternation, only `[[ =~ ]]` does).
STATUS_ENUM='draft|in-progress|done|validated|superseded|archived'
STATUS_ENUM_TEXT=${STATUS_ENUM//|/, }
# The states that claim the work is finished — the ones a leftover `[ ]` box
# contradicts.
STATUS_COMPLETE='done|validated'
STATUS_FILES=()   # basenames of the artifacts that actually carry the field
STATUS_VALUES=()  # their values, parallel to STATUS_FILES

for f in "$STORY_DIR"/*.md; do
  [[ -f "$f" ]] || continue
  BASENAME=$(basename "$f")
  if head -1 "$f" | grep -q '^---$' 2>/dev/null; then
    # Check required frontmatter fields ($d is POSIX; GNU-only `head -n -1`
    # aborted the whole validation on BSD/macOS under set -e + pipefail)
    FRONT=$(sed -n '2,/^---$/p' "$f" | sed '$d')
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
    # Lifecycle state. Anchored at column 0 like the templates write it, so a
    # compound or nested key (`review_status:`) can never fake a status value.
    STATUS_VAL=$(echo "$FRONT" | grep -E '^status:' | head -1 | sed 's/.*status:\s*//' | tr -d '[:space:]' || true)
    if [[ -n "$STATUS_VAL" ]]; then
      if ! [[ "$STATUS_VAL" =~ ^($STATUS_ENUM)$ ]]; then
        add_error "$BASENAME frontmatter 'status' is not a lifecycle state: found '$STATUS_VAL' — must be one of: $STATUS_ENUM_TEXT"
      fi
      # An artifact without the field carries no opinion, so it is never
      # divergent: only artifacts that declare a status are compared.
      STATUS_FILES+=("$BASENAME")
      STATUS_VALUES+=("$STATUS_VAL")
    fi
  else
    add_warning "$BASENAME is missing version frontmatter"
  fi
done

# --- Story-level status consistency ---
# Entered only when at least one artifact declared a status: a story with no
# status: field skips this block whole, which is the fail-open rule made
# structural (no error, no warning, byte-identical output to pre-change).
if [[ ${#STATUS_VALUES[@]} -gt 0 ]]; then
  # BOX_OPEN comes from the checkbox census, which runs only when tasks.md
  # exists; under set -u a story without tasks.md would abort here without the
  # ${VAR:-0} guard used throughout this script.
  OPEN_BOXES=${BOX_OPEN:-0}

  # The status lies about the work: it claims done while `[ ]` boxes remain.
  # `[~]` boxes are closed by grammar and must NOT count as open here.
  if [[ "$OPEN_BOXES" -gt 0 ]]; then
    for st_i in "${!STATUS_VALUES[@]}"; do
      if [[ "${STATUS_VALUES[$st_i]}" =~ ^($STATUS_COMPLETE)$ ]]; then
        add_warning "status is ahead of the checkboxes: ${STATUS_FILES[$st_i]} says '${STATUS_VALUES[$st_i]}' but $OPEN_BOXES task checkbox(es) are still open ([ ])"
        break  # one story, one lie — do not repeat it per artifact
      fi
    done
  fi

  # One story, one status: artifacts declaring different values disagree about
  # where the story is.
  STATUS_DIVERGED=false
  for st_v in "${STATUS_VALUES[@]}"; do
    [[ "$st_v" == "${STATUS_VALUES[0]}" ]] || STATUS_DIVERGED=true
  done
  if [[ "$STATUS_DIVERGED" == true ]]; then
    STATUS_PAIRS=""
    for st_i in "${!STATUS_FILES[@]}"; do
      STATUS_PAIRS+="${STATUS_PAIRS:+, }${STATUS_FILES[$st_i]}=${STATUS_VALUES[$st_i]}"
    done
    add_warning "Artifacts of this story declare different 'status' values ($STATUS_PAIRS) — every artifact must carry the same lifecycle state"
  fi
fi

# --- Flag parsing ---
CROSS_REF=false
STRICT=false
for arg in "$@"; do
  [[ "$arg" == "--cross-ref" ]] && CROSS_REF=true
  [[ "$arg" == "--strict" ]] && STRICT=true
done

if [[ "$CROSS_REF" == true && "$HAS_STORY" == true && "$HAS_TASKS" == true ]]; then
  # Requirements are hierarchical: a group header `### Rn.` and its leaf
  # criteria `Rn.m`. Tasks reference the leaves. A one-level token Rn is a
  # requirement of its own only when story.md defines no child Rn.m for it;
  # otherwise Rn is a group header, covered via its leaves. Counting a header
  # as a leaf produced a false orphan for every `### Rn.` heading.
  mapfile -t XR_STORY_LEAVES < <(grep -oE '\bR[0-9]+\.[0-9]+\b' "$STORY_DIR/story.md" 2>/dev/null | sort -u || true)
  mapfile -t XR_STORY_ONELEVEL < <(grep -oE '\bR[0-9]+\b' "$STORY_DIR/story.md" 2>/dev/null | sort -u || true)
  mapfile -t XR_TASK_TOKENS < <(grep -oE '\bR[0-9]+(\.[0-9]+)?\b' "$STORY_DIR/tasks.md" 2>/dev/null | sort -u || true)

  XR_STORY_REQS=("${XR_STORY_LEAVES[@]}")
  XR_STORY_GROUPS=()
  for xr_tok in "${XR_STORY_ONELEVEL[@]}"; do
    xr_has_child=false
    for xr_leaf in "${XR_STORY_LEAVES[@]}"; do
      if [[ "$xr_leaf" == "$xr_tok".* ]]; then
        xr_has_child=true
        break
      fi
    done
    if [[ "$xr_has_child" == true ]]; then
      XR_STORY_GROUPS+=("$xr_tok")
    else
      XR_STORY_REQS+=("$xr_tok")
    fi
  done

  if [[ ${#XR_STORY_REQS[@]} -gt 0 && ${#XR_TASK_TOKENS[@]} -gt 0 ]]; then
    # Story leaf requirements with no matching task reference (orphans).
    for xr_req in "${XR_STORY_REQS[@]}"; do
      if ! xr_in_list "$xr_req" "${XR_TASK_TOKENS[@]}"; then
        add_warning "Requirement $xr_req in story.md has no matching reference in tasks.md"
      fi
    done
    # Task references matching no story requirement (phantoms).
    for xr_tok in "${XR_TASK_TOKENS[@]}"; do
      if ! xr_in_list "$xr_tok" "${XR_STORY_REQS[@]}" && ! xr_in_list "$xr_tok" "${XR_STORY_GROUPS[@]}"; then
        add_warning "Requirement $xr_tok referenced in tasks.md does not exist in story.md"
      fi
    done
  elif [[ ${#XR_STORY_REQS[@]} -gt 0 && ${#XR_TASK_TOKENS[@]} -eq 0 ]]; then
    add_warning "story.md has requirements but tasks.md has no R-number references"
  fi
fi

# --- Output ---
TOTAL_ERRORS=${#ERRORS[@]}
TOTAL_WARNINGS=${#WARNINGS[@]}

echo "{"
echo "  \"story\": \"$(json_escape "$STORY_DIR")\","
echo "  \"errors\": $TOTAL_ERRORS,"
echo "  \"warnings\": $TOTAL_WARNINGS,"

if [[ $TOTAL_ERRORS -gt 0 ]]; then
  echo "  \"error_details\": ["
  for i in "${!ERRORS[@]}"; do
    COMMA=","
    [[ $i -eq $((TOTAL_ERRORS - 1)) ]] && COMMA=""
    echo "    \"$(json_escape "${ERRORS[$i]}")\"$COMMA"
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
    echo "    \"$(json_escape "${WARNINGS[$i]}")\"$COMMA"
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
