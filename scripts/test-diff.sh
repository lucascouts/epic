#!/usr/bin/env bash
# Diffs each materialized pre-authored test against its authored copy in the
# story's .draft/authored-tests/, and says whether an assertion moved.
#
# Materialization copies .draft/authored-tests/<path> to <project-root>/<path>,
# so the authored copy is the reference for what the test asserts. The Executor
# may repair a test's setup (fixtures, helpers, imports, paths) and never an
# assertion; this script is how that is checked rather than trusted.
#
#   clean    — every file identical to its authored copy
#   surface  — lines changed, none of them an assertion line
#   blocked  — a removed or added line matches the assertion pattern
#              (assert, expect, should, require, t.Fatal, t.Error, panic, raise)
#              or a materialized test is missing
#
# A blocked test is released only by a refine that carries the delta into the
# authored copy — the plan, not the run, decides what a test asserts.
#
# Output: one JSON object. Exit 0 on clean or surface, 1 on blocked, 2 on bad
# usage. Read-only. Parsed with no jq, like the other scripts that close boxes.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: test-diff.sh --story <story-dir> [--root <project-root>] [--file <target-path>]...

  --story <dir>   The story directory (.epico/stories/NNN-slug).
  --root <dir>    The project root the tests were materialized into.
                  Default: the directory that holds .epico/.
  --file <path>   Only this materialized test (path relative to the root, as
                  in red-evidence.yaml's target_path). Repeatable. Default:
                  every file under .draft/authored-tests/.
USAGE
}

STORY="" ROOT="" FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --story) STORY="${2-}"; shift 2 ;;
    --root) ROOT="${2-}"; shift 2 ;;
    --file) FILES+=("${2-}"); shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "test-diff.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
if [ -z "$STORY" ] || [ ! -d "$STORY" ]; then echo "test-diff.sh: --story <dir> is required and must exist" >&2; exit 2; fi
STORY=$(cd "$STORY" && pwd)
AUTH="$STORY/.draft/authored-tests"
[ -n "$ROOT" ] || ROOT=$(cd "$STORY/../../.." && pwd)
[ -d "$ROOT" ] || { echo "test-diff.sh: root not found: $ROOT" >&2; exit 2; }

json_escape() {
  local s=$1
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\t'/\\t}; s=${s//$'\r'/\\r}; s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

ASSERT_RE='(^|[^A-Za-z0-9_])(assert[A-Za-z_]*|expect|should|require|t\.(Fatal|Error)[a-z]*|panic|raise)([^A-Za-z0-9_]|$)'
# An import line names `expect` or calls `require('…')` without asserting anything.
IMPORT_RE='^[[:space:]]*(import[[:space:]]|from[[:space:]]|use[[:space:]]|#include|(const|let|var)[[:space:]].*=[[:space:]]*require[[:space:]]*\([[:space:]]*["'"'"'])'

if [ ${#FILES[@]} -eq 0 ] && [ -d "$AUTH" ]; then
  while IFS= read -r f; do FILES+=("${f#"$AUTH"/}"); done < <(find "$AUTH" -type f | sort)
fi

VERDICT=clean
ENTRIES=()
for rel in "${FILES[@]}"; do
  ref="$AUTH/$rel" live="$ROOT/$rel"
  status=unchanged changed=0 hits=()
  if [ ! -f "$ref" ]; then
    status=no-authored-copy
  elif [ ! -f "$live" ]; then
    status=missing; VERDICT=blocked
  elif ! cmp -s "$ref" "$live"; then
    status=changed
    while IFS= read -r line; do
      changed=$((changed + 1))
      body=${line:1}
      [[ "$body" =~ ^[[:space:]]*$ ]] && continue
      [[ "$body" =~ $IMPORT_RE ]] && continue
      if [[ "$body" =~ $ASSERT_RE ]]; then
        hits+=("{\"change\": \"$([ "${line:0:1}" = "-" ] && echo removed || echo added)\", \"text\": \"$(json_escape "$body")\"}")
      fi
    done < <(diff "$ref" "$live" | grep -E '^[<>]' | sed -e 's/^< /-/' -e 's/^> /+/' || true)
    if [ ${#hits[@]} -gt 0 ]; then
      status=assertion-changed; VERDICT=blocked
    elif [ "$VERDICT" = clean ]; then
      VERDICT=surface
    fi
  fi
  joined=""
  if [ ${#hits[@]} -gt 0 ]; then joined=$(printf '%s, ' "${hits[@]}"); joined=${joined%, }; fi
  ENTRIES+=("{\"file\": \"$(json_escape "$rel")\", \"status\": \"$status\", \"changed_lines\": $changed, \"assertion_changes\": [$joined]}")
done

files_json=""
if [ ${#ENTRIES[@]} -gt 0 ]; then files_json=$(printf '    %s,\n' "${ENTRIES[@]}"); files_json=${files_json%,}; fi
printf '{\n  "story": "%s",\n  "verdict": "%s",\n  "files": [\n%s\n  ]\n}\n' "$(json_escape "$(basename "$STORY")")" "$VERDICT" "$files_json"
[ "$VERDICT" = blocked ] && exit 1
exit 0
