#!/usr/bin/env bash
# SessionStart(compact) hook: after the conversation is summarized, renders the
# active story's state from disk and prints it. SessionStart adds plain stdout
# to Claude's context. Everything shown lives in files compaction never
# touches, so it is read now rather than saved before compaction.
#
# Active story: the one whose tasks.md was modified most recently. No
# .epic/stories, or no tasks.md yet: exit 0 silently — nothing to restore.
#
# Claude Code shows a hook's context in full only up to 10,000 characters;
# past that Claude gets a short preview. Progress and the next pending item
# come first, and the output is cut at MAX_CHARS with a pointer to the files.

set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
STORIES_ROOT="$ROOT/.epic/stories"
[ -d "$STORIES_ROOT" ] || exit 0

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
STORY_NAME=$(basename "$ACTIVE_STORY")
REL_STORY="${ACTIVE_STORY#"$ROOT"/}"
HEAD_SHA=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "(not a git repo)")
MAX_CHARS=8000

render() {
  echo "# Epic — active story state after compaction"
  echo
  echo "- **Story**: $STORY_NAME"
  echo "- **HEAD**: $HEAD_SHA"
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    echo "- **Protocols**: compaction dropped the mode references read before it; the run protocol is $CLAUDE_PLUGIN_ROOT/references/run-mode.md, and every mode's is listed in the Epic skill's Mode Dispatch"
  fi
  echo

  # Counting follows the three-state checkbox grammar: `[ ]` open, `[x]`
  # closed, `[~]` closed WITHOUT doing the work. Terminal qualifiers
  # (waived:/n-a:/superseded-by:) count as done; `deferred:` is reported apart,
  # because that work is settled in the plan but still owed by an external
  # actor. When a line carries both, `deferred:` wins
  # (references/tasks.md#checkbox-grammar). monitor-stale.sh is the deliberate
  # exception to the shared grammar: pending is `[ ]` and only `[ ]`.
    TOTAL=0
    DONE=0
    DEFERRED=0
    box_re='^[[:space:]]*- \[([ x~])\]'
    deferred_re='(^|[^[:alnum:]_-])deferred:'
    terminal_re='(^|[^[:alnum:]_-])(waived|n-a|superseded-by):'
    while IFS= read -r line || [ -n "$line" ]; do
      [[ "$line" =~ $box_re ]] || continue
      TOTAL=$((TOTAL + 1))
      case "${BASH_REMATCH[1]}" in
        'x') DONE=$((DONE + 1)) ;;
        '~')
          if [[ "$line" =~ $deferred_re ]]; then
            DEFERRED=$((DEFERRED + 1))
          elif [[ "$line" =~ $terminal_re ]]; then
            DONE=$((DONE + 1))
          fi
          # An unqualified [~] is a grammar error validate-story.sh reports;
          # here it simply counts in the total and closes nothing.
          ;;
      esac
    done < "$ACTIVE_STORY/tasks.md"
  NEXT=$(grep -nE '^\s*- \[ \]' "$ACTIVE_STORY/tasks.md" 2>/dev/null | head -1 || true)
  echo "## Progress"
  if [ "$DEFERRED" -gt 0 ]; then
    echo "- Tasks: $DONE/$TOTAL completed (+$DEFERRED deferred)"
  else
    echo "- Tasks: $DONE/$TOTAL completed"
  fi
  [ -n "$NEXT" ] && echo "- Next pending: $NEXT"
  echo

  if [ -f "$ACTIVE_STORY/story.md" ]; then
    echo "## Requirements (R-numbers)"
    grep -oE '\bR[0-9]+(\.[0-9]+)?\b' "$ACTIVE_STORY/story.md" \
      | sort -u | paste -sd ' ' - || true
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
}

BODY=$(render)
if [ "${#BODY}" -gt "$MAX_CHARS" ]; then
  printf '%s\n\n(Truncated at %s characters; the rest is in %s/tasks.md and %s/.draft/.)\n' \
    "${BODY:0:$MAX_CHARS}" "$MAX_CHARS" "$REL_STORY" "$REL_STORY"
else
  printf '%s\n' "$BODY"
fi

exit 0
