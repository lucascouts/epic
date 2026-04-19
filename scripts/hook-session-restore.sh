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

SNAPSHOT=$(
  find "$STORIES_ROOT" -mindepth 3 -maxdepth 3 \
    -path '*/.draft/compact-snapshot.md' \
    -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -1 | awk '{print $2}'
)
[ -n "${SNAPSHOT:-}" ] && [ -f "$SNAPSHOT" ] || exit 0

cat "$SNAPSHOT"
echo
echo "---"
echo "_Restored by Epic after context compaction. Delete_ \`${SNAPSHOT}\` _once the work continues._"

exit 0
