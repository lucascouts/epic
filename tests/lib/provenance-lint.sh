#!/usr/bin/env bash
# Provenance lint: flags development history (dated runs, session anecdotes,
# the author's own story IDs, costs, personal setup) in the files the model
# loads as instructions. Versioned text states the rule and its reason, not
# when or where the rule was learned.
#
# Usage: provenance-lint.sh [--strict] [file...]
#   No files: every tracked *.md under skills/, agents/, references/, assets/.
#   Prints path:line:text per hit. Exit 0 in report mode; with --strict,
#   exit 1 when anything is hit. Lines inside fenced code blocks are skipped,
#   because examples carry dates on purpose. Deliberate hits are listed in
#   tests/provenance-allowlist.txt as ERE matched against "path:line:text".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PATTERNS="$ROOT/tests/provenance-patterns.txt"
ALLOW="$ROOT/tests/provenance-allowlist.txt"
STRICT=false
if [ "${1:-}" = "--strict" ]; then STRICT=true; shift; fi

files=("$@")
if [ ${#files[@]} -eq 0 ]; then
  mapfile -t files < <(git -C "$ROOT" ls-files -- 'skills/*.md' 'agents/*.md' 'references/*.md' 'assets/*.md' | sed "s|^|$ROOT/|")
fi

hits=0
for f in "${files[@]}"; do
  rel="${f#"$ROOT"/}"
  while IFS= read -r line; do
    if [ -f "$ALLOW" ] && printf '%s\n' "$line" | command grep -qEf "$ALLOW"; then continue; fi
    printf '%s\n' "$line"
    hits=$((hits + 1))
  done < <(awk -v p="$rel" '/^[[:space:]]*```/{fence=!fence; next} !fence{print p ":" FNR ":" $0}' "$f" \
             | command grep -E -f "$PATTERNS" || true)
done

echo "provenance-lint: $hits hit(s)" >&2
if [ "$STRICT" = true ] && [ "$hits" -gt 0 ]; then exit 1; fi
exit 0
