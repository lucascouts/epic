#!/usr/bin/env bash
# PreCompact hook: snapshots the active story's state before context
# compaction. The snapshot is re-injected by hook-session-restore.sh when
# the SessionStart(compact) matcher fires.
#
# Active-story heuristic: most-recently-modified directory under
# .epic/stories/. If the heuristic fails or there's no .epic/, exit 0
# quietly — compaction proceeds unmodified.
#
# Exit 0 always. Returning non-zero or {"decision":"block"} here would
# block compaction, which is not the intent.

set -euo pipefail

STORIES_ROOT=".epic/stories"
[ -d "$STORIES_ROOT" ] || exit 0

# Pick the story whose tasks.md was touched most recently — that's the one
# the current session is actively working on.
ACTIVE_STORY=$(
  find "$STORIES_ROOT" -mindepth 2 -maxdepth 2 -name tasks.md \
    -printf '%T@ %h\n' 2>/dev/null \
    | sort -rn | head -1 | awk '{print $2}'
)
[ -n "${ACTIVE_STORY:-}" ] && [ -d "$ACTIVE_STORY" ] || exit 0

DRAFT_DIR="$ACTIVE_STORY/.draft"
mkdir -p "$DRAFT_DIR"

SNAPSHOT="$DRAFT_DIR/compact-snapshot.md"
STORY_NAME=$(basename "$ACTIVE_STORY")
NOW=$(date -Iseconds)
HEAD_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "(not a git repo)")

{
  echo "# Epic — pre-compact snapshot"
  echo
  echo "- **Story**: $STORY_NAME"
  echo "- **Taken at**: $NOW"
  echo "- **HEAD**: $HEAD_SHA"
  echo

  if [ -f "$ACTIVE_STORY/tasks.md" ]; then
    TOTAL=$(grep -cE '^\s*- \[[ x]\]' "$ACTIVE_STORY/tasks.md" 2>/dev/null || echo 0)
    DONE=$(grep -cE '^\s*- \[x\]' "$ACTIVE_STORY/tasks.md" 2>/dev/null || echo 0)
    NEXT=$(grep -nE '^\s*- \[ \]' "$ACTIVE_STORY/tasks.md" 2>/dev/null | head -1 || true)
    echo "## Progress"
    echo "- Tasks: $DONE/$TOTAL completed"
    [ -n "$NEXT" ] && echo "- Next pending: $NEXT"
    echo
  fi

  if [ -f "$DRAFT_DIR/meta.yaml" ]; then
    echo "## Draft meta"
    echo '```yaml'
    cat "$DRAFT_DIR/meta.yaml"
    echo '```'
    echo
  fi

  if [ -f "$DRAFT_DIR/deviations.yaml" ]; then
    echo "## Deviations registered"
    echo '```yaml'
    cat "$DRAFT_DIR/deviations.yaml"
    echo '```'
    echo
  fi

  if [ -f "$ACTIVE_STORY/story.md" ]; then
    echo "## Requirements (R-numbers)"
    grep -oE '\bR[0-9]+(\.[0-9]+)?\b' "$ACTIVE_STORY/story.md" \
      | sort -u | paste -sd ' ' - || true
    echo
  fi
} > "$SNAPSHOT"

exit 0
