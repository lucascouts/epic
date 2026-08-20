#!/usr/bin/env bash
# Normalizes a legacy story directory into this framework's canonical shapes.
#
# Usage:
#   bash scripts/migrate-story.sh <NNN|story-dir>            # dry run (default)
#   bash scripts/migrate-story.sh <NNN|story-dir> --apply    # rewrite in place
#
# Output: ONE JSON object on stdout. The unified diff goes to STDERR, always —
# stdout purity is the house contract and a diff on stdout would break every
# jq consumer this script has.
#
# Exit codes:
#   0  reported (dry run) or applied — INCLUDING when the embedded validate
#      run reports errors: the verdict is the channel, never the exit code
#   1  refused (archive target, unknown story, unreadable file, unparseable
#      mixture) — nothing written
#   2  usage error
#
# DRY RUN IS THE DEFAULT, and that is the whole posture. A migration rewrites
# files a person wrote; the tool shows what it would do and waits to be asked
# again. `--apply` is the second decision, never the first.
#
# IDEMPOTENCY BY GRAMMAR, NOT BY MARKER. A canonical line matches no detector,
# so a second run rewrites nothing and reports zero. There is no marker file,
# no `migrated:` frontmatter key, nothing to go stale or to lie after a manual
# edit — the tree itself is the record.
#
# IT NEVER GUESSES. When legacy and canonical shapes are interleaved so that
# no detector can tell which line owns which slot, the run refuses and names
# the lines. A migration that guesses wrong is worse than one that stops: the
# author can fix an unparseable file, but cannot see a wrong rewrite that
# validated clean.
#
# NO ROLLBACK ON A FAILING VALIDATE. The rewrite stands and the verdict is
# embedded. The validator can be unhappy about things migrate did not cause
# and must not fix — a status outside the lifecycle enum, a missing gate — and
# reverting a correct normalization because of an unrelated finding would make
# the tool unusable on exactly the legacy stories it exists for.

set -euo pipefail

STORIES_DIR=".epic/stories"

print_usage() {
  cat <<HELP
Usage: migrate-story.sh <NNN|story-dir> [--apply]

Normalizes a legacy story directory into the canonical shapes.

Arguments:
  <NNN|story-dir>   Story number (015) or its directory (.epic/stories/015-slug)

Flags:
  --apply           Rewrite in place. Without it, nothing is written.
  --help, -h        Show this help (on stderr, exit 2 — stdout is JSON only)

Output: one JSON object on stdout; the unified diff on stderr.
HELP
}

json_escape() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

# The refusal shape: the reason on stderr, an intact applied:false object on
# stdout, exit 1. A consumer that parses stdout sees a well-formed verdict even
# when the run refused — it never has to special-case a truncated document.
refuse() {
  printf '%s\n' "$1" >&2
  printf '{"story":"%s","applied":false,"changed_files":[],"rewrites":{"t1_headers":0,"covers_fields":0,"boxes_added":0,"wrapper_tags":0,"fast_requirements":0,"commit_subtasks":0},"validate":null,"refused":"%s"}\n' \
    "$(json_escape "${STORY_ARG:-}")" "$(json_escape "$2")"
  exit 1
}

usage_error() { printf '%s\n' "$1" >&2; print_usage >&2; exit 2; }

APPLY=false
STORY_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) print_usage >&2; exit 2 ;;
    --apply) APPLY=true; shift ;;
    -*) usage_error "Unknown flag: $1" ;;
    *)
      [ -z "$STORY_ARG" ] || usage_error "Only one story per invocation, got '$STORY_ARG' and '$1'"
      STORY_ARG="$1"; shift ;;
  esac
done
[ -n "$STORY_ARG" ] || usage_error "A story number or directory is required"

# --- Resolve the story -------------------------------------------------------
if [ -d "$STORY_ARG" ]; then
  STORY_DIR="${STORY_ARG%/}"
else
  case "$STORY_ARG" in
    [0-9]*)
      STORY_DIR=""
      for d in "$STORIES_DIR/$STORY_ARG"-*; do
        [ -d "$d" ] && { STORY_DIR="$d"; break; }
      done
      [ -n "$STORY_DIR" ] || refuse "Refused: no story '$STORY_ARG' under $STORIES_DIR/ — nothing to migrate" "unknown-story"
      ;;
    *) refuse "Refused: '$STORY_ARG' is neither a story number nor an existing directory" "unknown-story" ;;
  esac
fi

case "$STORY_DIR/" in
  */.epic/archive/*|.epic/archive/*)
    refuse "Refused: '$STORY_DIR' lives under the archive, which is read-only by invariant — an archived story is evidence, not a working file" "archive-resident"
    ;;
esac

ARTIFACTS=()
for f in "$STORY_DIR"/*.md; do
  [ -e "$f" ] || continue
  ARTIFACTS+=("$f")
done
[ "${#ARTIFACTS[@]}" -gt 0 ] || refuse "Refused: '$STORY_DIR' holds no .md artifact to migrate" "no-artifacts"

# Readability is checked for EVERY artifact before ANY of them is read, so a
# refusal cannot arrive after half a diff has already gone to stderr.
for f in "${ARTIFACTS[@]}"; do
  [ -r "$f" ] || refuse "Refused: cannot read '$f' — checked before any diff was produced, so nothing partial was emitted" "unreadable"
done

# The resolved scale decides the fast-requirements arm. tasks.md is
# authoritative for `scale:` (the shared scale rule, stated in full at
# validate-story.sh's resolution loop); story.md answers only when tasks.md
# does not.
resolved_scale() {
  local v=""
  for f in "$STORY_DIR/tasks.md" "$STORY_DIR/story.md"; do
    [ -r "$f" ] || continue
    v=$(sed -n '2,/^---$/p' "$f" 2>/dev/null | sed 's/\r$//' | grep -m1 '^scale:' | sed 's/^scale:[[:space:]]*//' || true)
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  done
  printf '%s' ""
}
SCALE=$(resolved_scale)

# --- Detectors and rewriters -------------------------------------------------
# Every pattern below is applied OUTSIDE fenced blocks only. A legacy shape
# inside a fence is documentation ABOUT the shape — the same rule the checkbox
# walker and the EARS lint already keep, so this file joins one fence policy
# rather than inventing a second.
FENCE_RE='^(```|~~~)'
T1_RE='^#{2,3}[[:space:]]+T([0-9]+)[[:space:]]+(.*)$'
COVERS_RE='^[[:space:]]*(\*\*)?[Cc]overs:?(\*\*)?:?[[:space:]]*(.*)$'
BOXLESS_RE='^-[[:space:]]+([0-9]+)[[:space:]]+-[[:space:]]+(.*)$'
WRAPPER_RE='^[[:space:]]*</[A-Za-z_][A-Za-z0-9_:-]*>[[:space:]]*$'
CANON_BOX_RE='^-[[:space:]]+\[[ x~]\][[:space:]]+[0-9]+[[:space:]]+-[[:space:]]'
COMMIT_BOX_RE='^[[:space:]]*-[[:space:]]+\[[ x~]\][[:space:]]+[0-9]+\.[0-9]+[[:space:]]+-[[:space:]]+Commit[[:space:]]*$'
COMMIT_FIELD_RE='^[[:space:]]*-[[:space:]]+Commit:[[:space:]]*(.*)$'
REQ_FIELD_RE='^[[:space:]]*-[[:space:]]+Requirements:'

T1_HEADERS=0; COVERS_FIELDS=0; BOXES_ADDED=0; WRAPPER_TAGS=0; FAST_REQUIREMENTS=0; COMMIT_SUBTASKS=0
CHANGED_FILES=()
MIXTURE_LINES=()

# migrate_file <path> — prints the migrated content on stdout and increments
# the counters. Reads nothing it has not been given.
migrate_file() {
  local f="$1" line in_fence=false n=0 out=""
  local crlf="" in_commit=false commit_msg=""
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    crlf=""
    case "$line" in *$'\r') crlf=$'\r'; line=${line%$'\r'} ;; esac

    if [[ "$line" =~ $FENCE_RE ]]; then
      if [ "$in_fence" = true ]; then in_fence=false; else in_fence=true; fi
      out+="$line$crlf"$'\n'; continue
    fi
    if [ "$in_fence" = true ]; then out+="$line$crlf"$'\n'; continue; fi

    # Variant 5 — a Commit SUB-TASK becomes a group-level Commit FIELD.
    #
    # WHY THE BOX HAS TO GO. A Commit sub-task is a checkbox that is never the
    # unit of work: it exists to carry a message. Left as a box it makes every
    # group look partially open, which is the false-partial factory the corpus
    # kept reporting. The message is carried VERBATIM — punctuation, em dashes
    # and all — because a commit message that drifts in migration is worse than
    # one that was never moved.
    #
    # THE NUMBER IS NOT REUSED. Dropping `1.3` leaves a gap, and the gap stays:
    # renumbering 2.1 into 1.3 would silently break every `Dependencies: Task
    # N.N` pointer in the file. A gap is readable; a moved pointer is not.
    if [ "$in_commit" = true ]; then
      if [[ "$line" =~ $COMMIT_FIELD_RE ]]; then
        commit_msg="${BASH_REMATCH[1]}"; continue
      fi
      if [[ "$line" =~ ^[[:space:]]{3,}- ]] || [ -z "${line// /}" ]; then
        continue
      fi
      in_commit=false
      if [ -n "$commit_msg" ]; then out+="  - Commit: $commit_msg$crlf"$'\n'; fi
      out+="$crlf"$'\n'
      commit_msg=""
    fi
    if [[ "$line" =~ $COMMIT_BOX_RE ]]; then
      COMMIT_SUBTASKS=$((COMMIT_SUBTASKS + 1))
      in_commit=true; commit_msg=""; continue
    fi

    # Variant 3 — a naked wrapper tag is a leak from a tool that wrote the file,
    # never content. The line goes; a fenced one is documentation and stays.
    if [[ "$line" =~ $WRAPPER_RE ]]; then
      WRAPPER_TAGS=$((WRAPPER_TAGS + 1)); continue
    fi

    # Variant 1a — `## T1 Title` becomes the canonical group box, keeping T's
    # own number so a `Dependencies: Task 2` pointer still resolves.
    if [[ "$line" =~ $T1_RE ]]; then
      T1_HEADERS=$((T1_HEADERS + 1))
      out+="- [ ] ${BASH_REMATCH[1]} - ${BASH_REMATCH[2]}$crlf"$'\n'; continue
    fi

    # Variant 1b — `**Covers:** R1.1` / `Covers: R1.1` is the Requirements field
    # under another name, indented to the field position the canonical shape uses.
    if [[ "$line" =~ $COVERS_RE ]]; then
      COVERS_FIELDS=$((COVERS_FIELDS + 1))
      out+="  - Requirements: ${BASH_REMATCH[3]}$crlf"$'\n'; continue
    fi

    # Variant 2 — a checkbox-less task item gains `[ ]` and ONLY `[ ]`. The
    # honest default: shape is recorded, done-ness is never invented.
    if [[ "$line" =~ $BOXLESS_RE ]]; then
      BOXES_ADDED=$((BOXES_ADDED + 1))
      out+="- [ ] ${BASH_REMATCH[1]} - ${BASH_REMATCH[2]}$crlf"$'\n'; continue
    fi

    # Variant 4 — a fast/spike story has no requirements chain, so a
    # `Requirements:` field there points at nothing. A field carrying the
    # sanctioned `satisfied-by:` suffix is NEVER stripped (story 014's grammar):
    # that one names a real deliverable.
    if [[ ( "$SCALE" = "fast" || "$SCALE" = "spike" ) && "$line" =~ $REQ_FIELD_RE ]]; then
      case "$line" in
        *satisfied-by:*) : ;;
        *) FAST_REQUIREMENTS=$((FAST_REQUIREMENTS + 1)); continue ;;
      esac
    fi

    out+="$line$crlf"$'\n'
  done < "$f"
  if [ "$in_commit" = true ] && [ -n "$commit_msg" ]; then
    out+="  - Commit: $commit_msg"$'\n'
  fi
  printf '%s' "$out"
}

# The mixture guard runs BEFORE any rewriting: a file carrying canonical task
# boxes AND legacy T-headers or Covers fields cannot be classified without
# guessing which line owns which slot.
detect_mixture() {
  local f="$1" line in_fence=false n=0 has_canon=false legacy=()
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1)); line=${line%$'\r'}
    if [[ "$line" =~ $FENCE_RE ]]; then
      if [ "$in_fence" = true ]; then in_fence=false; else in_fence=true; fi
      continue
    fi
    [ "$in_fence" = false ] || continue
    if [[ "$line" =~ $CANON_BOX_RE ]]; then has_canon=true; fi
    if [[ "$line" =~ $T1_RE || "$line" =~ $COVERS_RE ]]; then legacy+=("$f:$n"); fi
  done < "$f"
  if [ "$has_canon" = true ] && [ "${#legacy[@]}" -gt 0 ]; then
    MIXTURE_LINES+=("${legacy[@]}")
  fi
}

for f in "${ARTIFACTS[@]}"; do detect_mixture "$f"; done
if [ "${#MIXTURE_LINES[@]}" -gt 0 ]; then
  refuse "Refused: canonical and legacy shapes are interleaved, so no detector can tell which line owns which slot. Offending line(s): ${MIXTURE_LINES[*]}. migrate never guesses — normalize these by hand and run again." "unparseable-mixture"
fi

# --- Produce the migrated content -------------------------------------------
TMPDIR_MIG=$(mktemp -d)
trap 'rm -rf "$TMPDIR_MIG"' EXIT

for f in "${ARTIFACTS[@]}"; do
  base=$(basename "$f")
  migrate_file "$f" > "$TMPDIR_MIG/$base"
  if ! cmp -s "$f" "$TMPDIR_MIG/$base"; then
    CHANGED_FILES+=("$f")
    diff -u "$f" "$TMPDIR_MIG/$base" >&2 || true
  fi
done

emit_json() {
  local applied="$1" validate="$2" first=1 files="[" f
  for f in ${CHANGED_FILES+"${CHANGED_FILES[@]}"}; do
    if [ "$first" -eq 1 ]; then first=0; else files="$files,"; fi
    files="$files\"$(json_escape "$f")\""
  done
  files="$files]"
  printf '{"story":"%s","applied":%s,"changed_files":%s,"rewrites":{"t1_headers":%d,"covers_fields":%d,"boxes_added":%d,"wrapper_tags":%d,"fast_requirements":%d,"commit_subtasks":%d},"validate":%s}\n' \
    "$(json_escape "$STORY_DIR")" "$applied" "$files" \
    "$T1_HEADERS" "$COVERS_FIELDS" "$BOXES_ADDED" "$WRAPPER_TAGS" "$FAST_REQUIREMENTS" "$COMMIT_SUBTASKS" \
    "$validate"
}

if [ "$APPLY" = false ]; then
  emit_json false null
  exit 0
fi

# --- Apply -------------------------------------------------------------------
# `version:` bumps only in an artifact that actually changed (R1.5): a bump on
# an untouched sibling would claim an edit that never happened.
for f in ${CHANGED_FILES+"${CHANGED_FILES[@]}"}; do
  base=$(basename "$f")
  awk '
    NR == 1 && $0 ~ /^---\r?$/ { infm = 1; print; next }
    infm && $0 ~ /^---\r?$/ { infm = 0; print; next }
    infm && $0 ~ /^version:[[:space:]]*[0-9]+\r?$/ {
      cr = ($0 ~ /\r$/) ? "\r" : ""
      v = $0; sub(/^version:[[:space:]]*/, "", v); sub(/\r$/, "", v)
      printf "version: %d%s\n", v + 1, cr
      next
    }
    { print }
  ' "$TMPDIR_MIG/$base" > "$TMPDIR_MIG/$base.bumped"
  mv -f "$TMPDIR_MIG/$base.bumped" "$TMPDIR_MIG/$base"
  cp -f "$TMPDIR_MIG/$base" "$f"
done

# The migration is proven by the validator it triggers, not by its own report.
VALIDATE_JSON=null
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -x "$SCRIPT_DIR/validate-story.sh" ] || [ -r "$SCRIPT_DIR/validate-story.sh" ]; then
  set +e
  V_OUT=$(bash "$SCRIPT_DIR/validate-story.sh" "$STORY_DIR" 2>/dev/null)
  set -e
  if printf '%s' "$V_OUT" | jq -e . >/dev/null 2>&1; then
    VALIDATE_JSON=$(printf '%s' "$V_OUT" | jq -c '{errors, warnings, status}')
  else
    VALIDATE_JSON='{"errors":null,"warnings":null,"status":"unavailable"}'
  fi
fi

emit_json true "$VALIDATE_JSON"
exit 0
