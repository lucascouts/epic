#!/usr/bin/env bash
# FileChanged hook (matcher: constitution.md): re-surfaces the constitution
# head whenever the project's .epic/constitution.md is created, modified, or
# deleted on disk. Keeps Claude aware of changes the user made in another
# editor without having to re-read the file proactively.
#
# The matcher already filters by basename "constitution.md", but we double-
# check the full path so we only react to files inside .epic/ (avoids false
# positives if the user has another constitution.md elsewhere).
#
# Exit 0 always — FileChanged cannot block.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // empty')
CHANGE_TYPE=$(echo "$INPUT" | jq -r '.change_type // empty')

[ -n "$FILE_PATH" ] || exit 0

# Only react to .epic/constitution.md (the matcher catches the basename, but
# the user might have unrelated constitution.md files in the tree).
case "$FILE_PATH" in
  */.epic/constitution.md) ;;
  *) exit 0 ;;
esac

case "$CHANGE_TYPE" in
  modified|created)
    echo "Epic constitution ${CHANGE_TYPE}: ${FILE_PATH}"
    if [ -f "$FILE_PATH" ]; then
      echo "Updated head (apply to subsequent decisions):"
      head -15 "$FILE_PATH" | sed 's/^/  /'
    fi
    ;;
  deleted)
    echo "Epic constitution deleted: ${FILE_PATH}."
    echo "Project conventions are no longer enforced. Re-run /epic:task init to recreate."
    ;;
  *)
    # Unknown change type — emit nothing.
    ;;
esac

exit 0
