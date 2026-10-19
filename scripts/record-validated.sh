#!/usr/bin/env bash
# Record which commit a story is validated against.
#
# Usage: record-validated.sh <story-dir>
#
# Writes <story-dir>/.draft/validated.yaml:
#   sha: <HEAD commit>
#   dirty: true|false     — uncommitted changes OUTSIDE .epic/
#   recorded_at: <ISO-8601>
#
# Validate runs it right before the Auditor's spawn, so the record names the
# tree the Auditor is about to check. It is a script, not the Auditor's report,
# because the Auditor is a model and writes its report only on a pass; this
# record exists on a fail too, and nothing a model writes can change it.
# Changes under .epic/ do not make the tree dirty: they are the story's own
# bookkeeping, and counting them would mark every validation dirty.
# Archive copies `sha` into the manifest entry as `validated_sha`.
#
# Output: one JSON line, {"sha", "dirty", "file"}.
# Exit: 0 recorded; 2 bad usage, story not found, or not a git repository —
# nothing is written then, and callers carry on without the record.

set -euo pipefail

usage() { sed -n '4p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

case "${1-}" in -h | --help) usage; exit 0 ;; "") usage >&2; exit 2 ;; esac
STORY_DIR=$1
[ -d "$STORY_DIR" ] || { echo "record-validated.sh: story not found: $STORY_DIR" >&2; exit 2; }
STORY_DIR=$(cd "$STORY_DIR" && pwd)

SHA=$(git -C "$STORY_DIR" rev-parse --verify -q HEAD 2>/dev/null) || {
  echo "record-validated.sh: not a git repository with a commit: $STORY_DIR" >&2
  exit 2
}
TOP=$(git -C "$STORY_DIR" rev-parse --show-toplevel)
if [ -n "$(git -C "$TOP" status --porcelain --untracked-files=normal -- . ':(exclude).epic' 2>/dev/null)" ]; then
  DIRTY=true
else
  DIRTY=false
fi
NOW=$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p "$STORY_DIR/.draft"
OUT="$STORY_DIR/.draft/validated.yaml"
TMP=$(mktemp "$OUT.XXXXXX")
printf 'sha: %s\ndirty: %s\nrecorded_at: %s\n' "$SHA" "$DIRTY" "$NOW" > "$TMP"
mv -f "$TMP" "$OUT"

printf '{"sha":"%s","dirty":%s,"file":".draft/validated.yaml"}\n' "$SHA" "$DIRTY"
