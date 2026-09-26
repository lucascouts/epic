#!/usr/bin/env bash
# SessionStart(clear) hook: after a /clear, lists story drafts not touched in
# 30+ days. Never deletes — the user reviews and decides.
#
# SessionStart adds plain stdout to Claude's context, so the notice reaches the
# session that follows the clear. Each orphan gets its own removal line: a glob
# over .epic/stories/*/.draft/ would also delete every live draft.

set -euo pipefail

STORIES_ROOT=".epic/stories"
[ -d "$STORIES_ROOT" ] || exit 0

ORPHANS=$(find "$STORIES_ROOT" -mindepth 2 -maxdepth 2 -type d -name .draft -mtime +30 2>/dev/null || true)
[ -n "${ORPHANS:-}" ] || exit 0

echo "Epic: story drafts not touched in 30+ days. If they are no longer needed, the user can remove each one:"
while IFS= read -r draft; do
  [ -n "$draft" ] && printf '  rm -rf %q\n' "$draft"
done <<< "$ORPHANS"

exit 0
