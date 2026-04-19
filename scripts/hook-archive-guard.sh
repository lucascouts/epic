#!/usr/bin/env bash
# PreToolUse hook: enforces the read-only invariant on .epic/archive/.
# Archived stories preserve historical context and must never be mutated
# in-place — refinements must go through /epic:task stories refine NNN.
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
    echo 'Archived stories are read-only. Use /epic:task stories refine NNN instead.' >&2
    exit 2
    ;;
esac

exit 0
