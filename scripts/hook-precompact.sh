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
# the current session is actively working on. Portable (no GNU find
# -printf) and safe for paths containing spaces.
ACTIVE_STORY=""
NEWEST=0
while IFS= read -r f; do
  ts=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
  if [ "$ts" -gt "$NEWEST" ]; then
    NEWEST=$ts
    ACTIVE_STORY=$(dirname "$f")
  fi
done < <(find "$STORIES_ROOT" -mindepth 2 -maxdepth 2 -name tasks.md 2>/dev/null)
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
    # Counting follows the three-state checkbox grammar (R3.5): `[ ]` open,
    # `[x]` closed, `[~]` closed WITHOUT doing the work. Terminal qualifiers
    # (waived:/n-a:/superseded-by:) count as done; `deferred:` is reported
    # apart, because that work is settled in the plan but still owed by an
    # external actor — folding it into either number would make this snapshot
    # lie to the model it is injected into. When a line carries both,
    # `deferred:` wins, matching validate-story.sh's census.
    # Keep the `[ x~]` class in sync with validate-story.sh,
    # cross-reference.sh and hook-task-completed.sh; monitor-stale.sh is the
    # deliberate exception — pending is `[ ]` and only `[ ]` (R4.3).
    # grep -c already prints 0 on zero matches (while exiting 1); the old
    # `|| echo 0` appended a SECOND line, yielding "0\n0" as the value.
    TOTAL=$(grep -cE '^\s*- \[[ x~]\]' "$ACTIVE_STORY/tasks.md" 2>/dev/null || true)
    DONE_X=$(grep -cE '^\s*- \[x\]' "$ACTIVE_STORY/tasks.md" 2>/dev/null || true)
    DONE_T=$(grep -E '^\s*- \[~\].*[^[:alnum:]_-](waived|n-a|superseded-by):' "$ACTIVE_STORY/tasks.md" 2>/dev/null \
      | grep -cvE '[^[:alnum:]_-]deferred:' || true)
    DEFERRED=$(grep -cE '^\s*- \[~\].*[^[:alnum:]_-]deferred:' "$ACTIVE_STORY/tasks.md" 2>/dev/null || true)
    TOTAL=${TOTAL:-0}
    DONE=$(( ${DONE_X:-0} + ${DONE_T:-0} ))
    DEFERRED=${DEFERRED:-0}
    NEXT=$(grep -nE '^\s*- \[ \]' "$ACTIVE_STORY/tasks.md" 2>/dev/null | head -1 || true)
    echo "## Progress"
    if [ "$DEFERRED" -gt 0 ]; then
      echo "- Tasks: $DONE/$TOTAL completed (+$DEFERRED deferred)"
    else
      echo "- Tasks: $DONE/$TOTAL completed"
    fi
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
