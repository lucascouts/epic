#!/usr/bin/env bash
# SessionEnd(clear) hook: lists orphaned drafts older than 30 days after
# a /clear. Does not delete — the user reviews and decides.
#
# Writes the findings to stderr so they appear in the session transcript
# tail. Exit 0 always (SessionEnd output/exit-code is advisory; the
# session is already ending).

set -euo pipefail

STORIES_ROOT=".epic/stories"
[ -d "$STORIES_ROOT" ] || exit 0

# Find .draft directories not touched in 30+ days.
ORPHANS=$(find "$STORIES_ROOT" -mindepth 2 -maxdepth 2 -type d -name .draft -mtime +30 2>/dev/null || true)
[ -n "${ORPHANS:-}" ] || exit 0

{
  echo "Epic: abandoned drafts detected after /clear (not touched in 30+ days):"
  while IFS= read -r draft; do
    [ -n "$draft" ] && echo "  - $draft"
  done <<< "$ORPHANS"
  echo
  echo "Review and delete manually if no longer needed:"
  echo "  rm -rf .epic/stories/*/.draft/"
} >&2

exit 0
