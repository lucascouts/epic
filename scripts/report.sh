#!/usr/bin/env bash
# Reads the Auditor's two report files for the orchestrator, printing only what
# it acts on — so a whole YAML report never lands in its context.
#
#   report.sh --story <dir>                 verdicts and the size of every list
#   report.sh --story <dir> --list <key>    the items of one list, as written
#
# Reads .draft/validation-report.yaml and .draft/audit-report.yaml: top-level
# `key: value` scalars and `key:` lists whose items start `  - ` at column 2.
# A missing file reports `present: false`. Read-only.
#
# Output: JSON (summary) or the raw list lines (--list). Exit 0, or 2 on bad usage.

set -euo pipefail

usage() { sed -n '5,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

STORY="" LIST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --story) STORY="${2-}"; shift 2 ;;
    --list) LIST="${2-}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "report.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
if [ -z "$STORY" ] || [ ! -d "$STORY" ]; then echo "report.sh: --story <dir> is required and must exist" >&2; exit 2; fi

summary() {  # <file> — {present, verdict, story, lists: {key: n}}
  if [ ! -f "$1" ]; then printf '{"present": false}'; return 0; fi
  awk '
    function q(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return "\"" s "\"" }
    /^[A-Za-z_]+:[[:space:]]*$/            { key = substr($0, 1, index($0, ":") - 1); order[++n] = key; count[key] = 0; next }
    /^[A-Za-z_]+:[[:space:]]*\[\][[:space:]]*(#.*)?$/ { key = substr($0, 1, index($0, ":") - 1); order[++n] = key; count[key] = 0; key = ""; next }
    /^[A-Za-z_]+:/ {
      k = substr($0, 1, index($0, ":") - 1); v = substr($0, index($0, ":") + 1)
      sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+#.*$/, "", v); gsub(/^["'"'"']|["'"'"']$/, "", v)
      scalar[k] = v; key = ""; next
    }
    key != "" && /^  - / { count[key]++ }
    END {
      printf "{\"present\": true, \"verdict\": %s, \"story\": %s, \"lists\": {", ("verdict" in scalar ? q(scalar["verdict"]) : "null"), ("story" in scalar ? q(scalar["story"]) : "null")
      for (i = 1; i <= n; i++) printf "%s%s: %d", (i > 1 ? ", " : ""), q(order[i]), count[order[i]]
      printf "}}"
    }' "$1"
}

V="$STORY/.draft/validation-report.yaml" A="$STORY/.draft/audit-report.yaml"
if [ -n "$LIST" ]; then
  for f in "$V" "$A"; do
    [ -f "$f" ] || continue
    awk -v k="$LIST" '
      $0 ~ "^" k ":" { on = 1; next }
      on && /^[A-Za-z_]+:/ { on = 0 }
      on && /^  / { print }' "$f"
  done
  exit 0
fi
printf '{"validation": %s, "audit": %s}\n' "$(summary "$V")" "$(summary "$A")"
