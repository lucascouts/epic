#!/usr/bin/env bash
# PostToolUse hook: auto-validates an epic story when any of its artifacts
# (story.md, design.md, tasks.md) is written. Reads the tool payload from
# stdin and dispatches to scripts/validate-story.sh.
#
# Invoked by hooks/hooks.json on Write operations inside .epic/stories/.
# Exit code is always 0 — hook failures must not block the write.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

case "$FILE_PATH" in
  *".epic/stories/"*"/story.md" | *".epic/stories/"*"/design.md" | *".epic/stories/"*"/tasks.md")
    STORY_DIR=$(dirname "$FILE_PATH")
    if [ -f "$STORY_DIR/tasks.md" ]; then
      bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-story.sh" "$STORY_DIR" 2>/dev/null || true
    fi
    ;;
esac

exit 0
