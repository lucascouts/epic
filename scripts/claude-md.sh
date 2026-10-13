#!/usr/bin/env bash
# The Epic-managed block of a project's CLAUDE.md.
#
#   claude-md.sh write [--root <dir>]    write or refresh the block
#   claude-md.sh check [--root <dir>]    is the block present and current?
#   claude-md.sh show  [--root <dir>]    print the block that write would write
#
# The block sits between `<!-- epic:start -->` and `<!-- epic:end -->` at the
# end of CLAUDE.md. Nothing outside the markers is ever touched: a CLAUDE.md
# without the block gets it appended; one with it gets the block replaced in
# place. With an AGENTS.md beside it, an `@AGENTS.md` line goes right before
# the block, once, so Claude Code reads both. The block stays under 100 lines:
# it points at the rules and holds only what every session needs.
#
# Built from what the project already has: .epic/constitution.md (its
# ## Quality commands and ## Invariants), the docs found at the root
# (ARCHITECTURE, ROADMAP, PRD, docs/adr/, versions.env) and the examples
# directories. Nothing is invented: a section with no source is left out.
#
# Output: JSON. Exit 0 done (check: current), 1 check found it absent or stale,
# 2 bad usage.

set -euo pipefail

usage() { sed -n '4,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

CMD=${1-}; shift || true
case "$CMD" in write | check | show) ;; -h | --help) usage; exit 0 ;; *) usage >&2; exit 2 ;; esac
ROOT=$PWD
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2-}"; shift 2 ;;
    *) echo "claude-md.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -d "$ROOT" ] || { echo "claude-md.sh: root not found: $ROOT" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd)
MD="$ROOT/CLAUDE.md"
CONST="$ROOT/.epic/constitution.md"
# shellcheck disable=SC2016  # the backticks are literal Markdown
START='<!-- epic:start — managed by the Epic plugin; `/epic:epic init --repair` rewrites everything up to epic:end -->'
END='<!-- epic:end -->'

section() {  # <file> <heading> — the bullet lines under `## <heading>`
  [ -f "$1" ] || return 0
  awk -v h="## $2" '$0 == h { on = 1; next } on && /^## / { exit } on && /^- / { print }' "$1"
}

join() { local out=$1; shift; for x in "$@"; do out="$out, $x"; done; printf '%s' "$out"; }

block() {
  echo "$START"
  echo "## Epic"
  echo
  if [ -f "$CONST" ]; then
    echo "- Project rules: \`.epic/constitution.md\` — Defaults, Quality, Security floor. Read it before deciding anything it covers."
  fi
  echo "- Stories and their plans: \`.epic/stories/\`; the index: \`.epic/EPIC.md\`."
  local docs=() d
  for d in ARCHITECTURE.md ROADMAP.md PRD.md docs/PRD.md docs/adr versions.env; do
    [ -e "$ROOT/$d" ] && docs+=("\`$d\`")
  done
  if [ ${#docs[@]} -gt 0 ]; then
    echo "- Project docs: $(join "${docs[@]}")."
  fi
  echo
  echo "### Where to look, in order"
  echo
  echo "1. The code itself — grep for the name before assuming anything."
  echo "2. Memory, as a pointer only: verify every recalled fact against the code."
  echo "3. The installed dependency at the lockfile version — its source, types and \`--help\`."
  echo "4. The language server (LSP) for definitions, references and types."
  echo "5. The official docs for that exact version."
  echo "6. The dependency's issue tracker — only when its behaviour contradicts its docs."
  echo "7. The web, last."
  local q
  q=$(section "$CONST" Quality)
  if [ -n "$q" ]; then
    echo
    echo "### Before committing"
    echo
    printf '%s\n' "$q"
  fi
  echo
  echo "### Code rules"
  echo
  echo "- Files stay under 500 lines; split by responsibility before one grows past it."
  echo "- Names are unique and greppable: no two symbols share a name across modules."
  echo "- Comments say why, and where a value or rule came from — never what the next line does."
  echo "- One command runs every test."
  echo "- Fakes are named for what they stand in for (\`FakeClock\`, \`InMemoryOrders\`)."
  echo "- Dependencies arrive through parameters or constructors, never through globals."
  echo "- The formatter runs in pre-commit."
  echo "- Logs are JSON, one event per line."
  local inv
  inv=$(section "$CONST" Invariants)
  if [ -n "$inv" ]; then
    echo
    echo "### Invariants"
    echo
    printf '%s\n' "$inv"
  fi
  local ex=()
  for d in examples docs/examples assets/examples; do
    [ -d "$ROOT/$d" ] && ex+=("\`$d/\`")
  done
  if [ ${#ex[@]} -gt 0 ]; then
    echo
    echo "Living examples of these rules: $(join "${ex[@]}")."
  fi
  echo "$END"
}

current_block() {  # the block as it stands in CLAUDE.md, markers included
  [ -f "$MD" ] || return 0
  awk -v s="<!-- epic:start" -v e="$END" 'index($0, s) == 1 { on = 1 } on { print } on && $0 == e { exit }' "$MD"
}

NEW=$(block)
LINES=$(printf '%s\n' "$NEW" | wc -l | tr -d ' ')
[ "$LINES" -lt 100 ] || { echo "claude-md.sh: the block would be $LINES lines; it must stay under 100" >&2; exit 2; }

case "$CMD" in
  show) printf '%s\n' "$NEW"; exit 0 ;;
  check)
    OLD=$(current_block)
    if [ -z "$OLD" ]; then jq -cn --argjson l "$LINES" '{present: false, current: false, lines: $l}'; exit 1; fi
    if [ "$OLD" = "$NEW" ]; then jq -cn --argjson l "$LINES" '{present: true, current: true, lines: $l}'; exit 0; fi
    jq -cn --argjson l "$LINES" '{present: true, current: false, lines: $l}'; exit 1 ;;
esac

TMP=$(mktemp "$ROOT/.CLAUDE.md.XXXXXX")
trap 'rm -f "$TMP" "$TMP.block"' EXIT
ACTION=appended
[ -z "$(current_block)" ] || ACTION=replaced
if [ "$ACTION" = replaced ]; then
  printf '%s\n' "$NEW" > "$TMP.block"
  awk -v s="<!-- epic:start" -v e="$END" -v f="$TMP.block" '
    BEGIN { while ((getline l < f) > 0) blk = blk l "\n" }
    index($0, s) == 1 && !done { on = 1; printf "%s", blk; next }
    on { if ($0 == e) { on = 0; done = 1 } ; next }
    { print }' "$MD" > "$TMP"
  rm -f "$TMP.block"
else
  {
    if [ -f "$MD" ]; then
      cat "$MD"
      [ -z "$(tail -c 1 "$MD")" ] || echo
      echo
    fi
    if [ -f "$ROOT/AGENTS.md" ] && ! grep -qx '@AGENTS.md' "$MD" 2>/dev/null; then echo '@AGENTS.md'; echo; fi
    printf '%s\n' "$NEW"
  } > "$TMP"
fi
mv "$TMP" "$MD"
trap - EXIT
jq -cn --arg a "$ACTION" --argjson l "$LINES" --arg f "$MD" '{status: $a, file: $f, lines: $l}'
