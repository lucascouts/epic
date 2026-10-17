#!/usr/bin/env bash
# Checks a layperson-facing text for process words (assets/jargon-terms.txt).
# Reads the text from --file or stdin; inline code spans and fenced blocks are
# skipped, because the command a beginner is told to type is not jargon.
#
# Output: one JSON object {pass, hits: [{term, count}]}. Exit 0 when no term is
# found, 1 when one is, 2 on bad usage. The orchestrator rewrites the closing in
# plain words and runs this again until it exits 0.

set -euo pipefail

usage() { echo "Usage: jargon-check.sh [--file <path>] [--terms <path>]   (text on stdin when no --file)"; }

FILE="" TERMS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/assets/jargon-terms.txt"
while [ $# -gt 0 ]; do
  case "$1" in
    --file) FILE="${2-}"; shift 2 ;;
    --terms) TERMS="${2-}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "jargon-check.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -r "$TERMS" ] || { echo "jargon-check.sh: term list not readable: $TERMS" >&2; exit 2; }
if [ -n "$FILE" ]; then
  [ -r "$FILE" ] || { echo "jargon-check.sh: not readable: $FILE" >&2; exit 2; }
  TEXT=$(cat "$FILE")
else
  TEXT=$(cat)
fi

# Drop fenced blocks, then inline code spans (the backticks are literal).
# shellcheck disable=SC2016
PROSE=$(printf '%s\n' "$TEXT" | awk '/^[[:space:]]*(```|~~~)/ { f = !f; next } !f' | sed -E 's/`[^`]*`//g')

json_escape() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "$s"; }

HITS=()
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  mode=${line%%:*} re=${line#*:}
  flag=-E; [ "$mode" = ci ] && flag=-Ei
  found=$( { printf '%s\n' "$PROSE" | grep -o "$flag" -- "$re" 2>/dev/null || true; } )
  [ -n "$found" ] || continue
  n=$(printf '%s\n' "$found" | wc -l | tr -d ' ')
  HITS+=("{\"term\": \"$(json_escape "$(printf '%s\n' "$found" | head -n 1)")\", \"count\": $n}")
done < "$TERMS"

if [ ${#HITS[@]} -eq 0 ]; then
  printf '{"pass": true, "hits": []}\n'
  exit 0
fi
joined=$(printf '%s, ' "${HITS[@]}"); joined=${joined%, }
printf '{"pass": false, "hits": [%s]}\n' "$joined"
exit 1
