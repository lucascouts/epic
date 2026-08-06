#!/usr/bin/env bash
# SessionStart(compact) hook: re-injects the pre-compact snapshot into
# Claude's context after the conversation is summarized. Any text written
# to stdout from a SessionStart hook is added to the context.
#
# Looks for the active story's .draft/compact-snapshot.md (produced by
# hook-precompact.sh). If missing, exit 0 silently — nothing to restore.

set -euo pipefail

STORIES_ROOT=".epic/stories"
[ -d "$STORIES_ROOT" ] || exit 0

# Portable newest snapshot (no GNU find -printf); the old awk '{print $2}'
# also truncated any path containing a space.
SNAPSHOT=""
NEWEST=0
while IFS= read -r f; do
  ts=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
  if [ "$ts" -gt "$NEWEST" ]; then
    NEWEST=$ts
    SNAPSHOT="$f"
  fi
done < <(find "$STORIES_ROOT" -mindepth 3 -maxdepth 3 -path '*/.draft/compact-snapshot.md' 2>/dev/null)
[ -n "${SNAPSHOT:-}" ] && [ -f "$SNAPSHOT" ] || exit 0

cat "$SNAPSHOT"
echo
echo "---"
echo "_Restored by Epic after context compaction. Delete_ \`${SNAPSHOT}\` _once the work continues._"

exit 0
