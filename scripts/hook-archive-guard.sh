#!/usr/bin/env bash
# PreToolUse hook: enforces the read-only invariant on .epic/archive/.
# Archived stories preserve historical context and must never be mutated
# in-place by an interactive Edit/Write.
#
# It blocks TOOL calls only. Bash file operations are invisible to it by
# design, which is what makes scripts/archive-story.sh the one sanctioned way
# in: that script moves the story, appends the manifest entry and stamps
# `status: archived` — all of it guarded, derived and recorded. The refusal
# below therefore points at the script, not at a mode: a user who lands here
# wants an archive operation, and there is exactly one that is sanctioned.
#
# Pattern uses leading wildcard to catch both relative and absolute paths
# (*"/.epic/archive/"* — a partial path leaking into .epic/archive/ is the
# only signal we need).
#
# Exit 2 blocks the tool call and surfaces stderr back to the model.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

case "$FILE_PATH" in
  *".epic/archive/"*)
    echo 'Archived stories are read-only. Use scripts/archive-story.sh for sanctioned archive operations.' >&2
    exit 2
    ;;
esac

exit 0
