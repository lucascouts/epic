#!/usr/bin/env bash
# Moves a project's pre-Epico layout to the current names, once:
#
#   .epic/                          -> .epico/
#   .epic/EPIC.md                   -> .epico/EPICO.md
#   <!-- epic:index:start|end -->   -> <!-- epico:index:start|end -->  (index)
#   <!-- epic:start … / epic:end -->-> <!-- epico:start … / epico:end --> (CLAUDE.md)
#   .epic, .epic/, /.epic, /.epic/  -> the same form with .epico      (.gitignore)
#
#   migrate-dir.sh [--root <dir>] [--hook]
#
# The layout is looked for at <dir> (default: $CLAUDE_PROJECT_DIR, else the
# cwd) and every directory above it, the way the other scripts find .epico/.
# When git tracks anything under .epic/, the folder and the index move with
# `git mv`: the rename is staged and NEVER committed — the user reviews and
# commits it. Untracked files inside the folder move with it either way.
# Nothing is merged: with both .epic/ and .epico/ present nothing moves.
#
# Output: JSON {status: moved|nothing|blocked, from, to, git, notes}; exit 0
# moved or nothing, 1 blocked, 2 bad usage. With --hook (the SessionStart
# wiring): one line when something moved or needs a hand, silence otherwise,
# and always exit 0 — a session never fails to start over a migration.

set -euo pipefail

usage() { sed -n '10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

ROOT_ARG="" HOOK=false
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT_ARG="${2-}"; shift 2 ;;
    --hook) HOOK=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "migrate-dir.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

START=${ROOT_ARG:-${CLAUDE_PROJECT_DIR:-$PWD}}
[ -d "$START" ] || { $HOOK && exit 0; echo "migrate-dir.sh: not a directory: $START" >&2; exit 2; }
START=$(cd "$START" && pwd)

emit() {  # <status> <from> <to> <git> <note>
  if $HOOK; then
    case "$1" in
      moved) echo "Epico: moved $2 to $3${4:+ ($4)}.${5:+ $5}" ;;
      blocked) echo "Epico: $5" ;;
    esac
    exit 0
  fi
  jq -cn --arg s "$1" --arg f "$2" --arg t "$3" --arg g "$4" --arg n "$5" \
    '{status: $s, from: (if $f == "" then null else $f end), to: (if $t == "" then null else $t end),
      git: (if $g == "" then null else $g end), notes: (if $n == "" then null else $n end)}'
  [ "$1" = blocked ] && exit 1
  exit 0
}

# The nearest directory holding either layout; the current one wins.
D=""
d=$START
while :; do
  if [ -d "$d/.epico" ] || [ -d "$d/.epic" ]; then D=$d; break; fi
  [ "$d" = "/" ] && break
  d=$(dirname "$d")
done
if [ -z "$D" ] || [ ! -d "$D/.epic" ]; then emit nothing "" "" "" ""; fi
if [ -d "$D/.epico" ]; then
  emit blocked "$D/.epic" "$D/.epico" "" "both $D/.epic/ and $D/.epico/ exist; nothing was moved. Keep the one you use and remove the other, or merge them by hand."
fi

# rewrite <file> <sed program> — in place through a temporary file, so a reader
# never sees half a file; a no-op leaves the file untouched.
rewrite() {
  local f=$1 tmp
  [ -f "$f" ] || return 0
  tmp=$(mktemp "$f.epico-migrate.XXXXXX")
  sed -e "$2" "$f" > "$tmp"
  if cmp -s "$f" "$tmp"; then rm -f "$tmp"; return 0; fi
  chmod --reference="$f" "$tmp" 2>/dev/null || true
  mv "$tmp" "$f"
}

tracked() { [ -n "$GIT_TOP" ] && [ -n "$(git -C "$D" ls-files -- "$1" | head -n 1)" ]; }

GIT_TOP=""
if git -C "$D" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_TOP=$(git -C "$D" rev-parse --show-toplevel)
fi

GITNOTE=""
if tracked .epic; then
  git -C "$D" mv .epic .epico
  GITNOTE="staged with git mv; review and commit it"
else
  mv "$D/.epic" "$D/.epico"
fi

if [ -f "$D/.epico/EPIC.md" ] && [ ! -e "$D/.epico/EPICO.md" ]; then
  if tracked .epico/EPIC.md; then
    git -C "$D" mv .epico/EPIC.md .epico/EPICO.md
  else
    mv "$D/.epico/EPIC.md" "$D/.epico/EPICO.md"
  fi
fi
rewrite "$D/.epico/EPICO.md" 's#^\([[:space:]]*\)<!-- epic:index:\(start\|end\) -->#\1<!-- epico:index:\2 -->#'

# Only the marker lines of the managed block; the user's text is never touched.
rewrite "$D/CLAUDE.md" 's|^<!-- epic:start|<!-- epico:start|; s|^<!-- epic:end -->$|<!-- epico:end -->|'

# Exact .gitignore entries only — a line naming anything else stays as it is.
for gi in "$D/.gitignore" ${GIT_TOP:+"$GIT_TOP/.gitignore"}; do
  rewrite "$gi" 's|^\(/\{0,1\}\)\.epic\(/\{0,1\}\)$|\1.epico\2|'
done

emit moved "$D/.epic/" "$D/.epico/" "$GITNOTE" ""
