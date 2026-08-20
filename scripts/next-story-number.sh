#!/usr/bin/env bash
# Allocates the next story number for an Epic project — and, with --reserve,
# claims numbers on disk so a second allocator cannot hand out the same one.
#
# Usage:
#   bash scripts/next-story-number.sh              # answer only, nothing written
#   bash scripts/next-story-number.sh --reserve N  # claim N numbers
#
# Output: ONE JSON object on stdout, diagnostics on stderr.
#   {"next":"NNN","reserved":["NNN",...],"collisions":[{...}]}
#
# Exit codes:
#   0  allocated (and reserved, when asked)
#   1  refused — the 999 cap, or a reservation that could not be settled
#   2  usage error
#
# WHY IT SCANS ARCHIVE/ TOO. Numbers are never recycled: an archived story
# keeps its number permanently. A stories-only scan is the known bug shape —
# it re-hands a number the archive already owns, and the collision surfaces
# much later as two stories with one identity. Both roots are scanned, and the
# maximum across them is what `next` is derived from.
#
# WHAT "RESERVED" MEANS. Directory existence IS the reservation: a placeholder
# `NNN-reserved/` under .epic/stories/ is what makes the number unavailable to
# the next scan. There is no lock file and no registry to go stale — the same
# glob that answers `next` is what the reservation writes into.
#
# THE RACE THIS CLOSES. Between the scan that picks a number and the mkdir
# that claims it, another creator can take the same number. Re-scanning AFTER
# creation is what detects it: a directory `NNN-*` that is not our own
# placeholder means the number is contested. The rule then is asymmetric and
# deliberate — WE move, they do not. Our placeholder is removed (rmdir, so it
# can only ever remove the empty directory we just made), the collision is
# recorded, and the slot is re-taken at the new tail. A foreign directory is
# never removed, never overwritten, and never renamed: it may hold a story
# somebody is in the middle of writing.
#
# ALL-OR-NOTHING AT THE CAP. The cap is checked against the whole request
# before the first mkdir, so a --reserve that would cross 999 leaves nothing
# behind. A partial reservation would be worse than a refusal: the caller gets
# fewer numbers than it asked for and has no way to tell which are real.

set -euo pipefail

STORIES_DIR=".epic/stories"
ARCHIVE_DIR=".epic/archive"
MAX_NUMBER=999
RESLOT_ATTEMPTS=200

print_usage() {
  cat <<HELP
Usage: next-story-number.sh [--reserve N]

Allocates the next story number across .epic/stories/ AND .epic/archive/.

Flags:
  --reserve N   Claim N numbers by creating NNN-reserved/ placeholders.
                Directory existence is the reservation.
  --help, -h    Show this help (on stderr, exit 2 — stdout is JSON only)

Output: one JSON object — {"next","reserved","collisions"} — on stdout.
HELP
}

die() { printf '%s\n' "$*" >&2; exit 1; }
usage_error() { printf '%s\n' "$*" >&2; print_usage >&2; exit 2; }

json_escape() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  printf '%s' "$s"
}

pad() { printf '%03d' "$1"; }
placeholder_name() { printf '%s-reserved' "$(pad "$1")"; }

# The highest NNN- prefix in use, across both roots. 0 when the project is empty.
scan_max() {
  local max=0 root d base num
  for root in "$STORIES_DIR" "$ARCHIVE_DIR"; do
    [ -d "$root" ] || continue
    for d in "$root"/*; do
      [ -d "$d" ] || continue
      base=${d##*/}
      case "$base" in
        [0-9][0-9][0-9]-*)
          num=$((10#${base%%-*}))
          if [ "$num" -gt "$max" ]; then max=$num; fi
          ;;
      esac
    done
  done
  printf '%s' "$max"
}

# Prints the basename of a directory claiming <num> that is NOT our
# placeholder, and returns 0. Returns 1 when the number is uncontested.
foreign_claim() {
  local num=$1 mine d base
  mine=$(placeholder_name "$num")
  for d in "$STORIES_DIR/$(pad "$num")-"* "$ARCHIVE_DIR/$(pad "$num")-"*; do
    [ -d "$d" ] || continue
    base=${d##*/}
    if [ "$base" != "$mine" ]; then
      printf '%s' "$base"
      return 0
    fi
  done
  return 1
}

# Creates our placeholder for <num>. Returns 1 without writing when the name
# is already taken — the caller treats that as a collision like any other.
claim() {
  local num=$1 path
  path="$STORIES_DIR/$(placeholder_name "$num")"
  [ -e "$path" ] && return 1
  mkdir "$path" 2>/dev/null || return 1
  return 0
}

emit() {
  local next=$1 reserved_json=$2 collisions_json=$3
  printf '{"next":"%s","reserved":%s,"collisions":%s}\n' \
    "$(json_escape "$next")" "$reserved_json" "$collisions_json"
}

join_json() {
  local first=1 out="[" x
  for x in "$@"; do
    if [ "$first" -eq 1 ]; then first=0; else out="$out,"; fi
    out="$out$x"
  done
  printf '%s]' "$out"
}

quote_all() {
  local out=() x
  for x in "$@"; do out+=("\"$(json_escape "$x")\""); done
  join_json ${out+"${out[@]}"}
}

RESERVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) print_usage >&2; exit 2 ;;
    --reserve)
      shift
      [ $# -gt 0 ] || usage_error "--reserve requires a count"
      RESERVE=$1
      case "$RESERVE" in
        ''|*[!0-9]*) usage_error "--reserve takes a positive integer, got '$RESERVE'" ;;
      esac
      [ "$RESERVE" -ge 1 ] || usage_error "--reserve takes a positive integer, got '$RESERVE'"
      shift
      ;;
    *) usage_error "Unknown argument: $1" ;;
  esac
done

MAX=$(scan_max)

if [ "$RESERVE" -eq 0 ]; then
  NEXT=$((MAX + 1))
  if [ "$NEXT" -gt "$MAX_NUMBER" ]; then
    die "Refused: the highest story number in use is $(pad "$MAX") and story numbers are capped at $MAX_NUMBER. Archive stories to free space; numbers are never recycled."
  fi
  emit "$(pad "$NEXT")" "[]" "[]"
  exit 0
fi

if [ $((MAX + RESERVE)) -gt "$MAX_NUMBER" ]; then
  die "Refused: reserving $RESERVE number(s) from $(pad "$((MAX + 1))") would pass the $MAX_NUMBER cap (highest in use: $(pad "$MAX")). Nothing was reserved — a partial reservation is worse than a refusal."
fi

mkdir -p "$STORIES_DIR"

RESERVED=()
COLLISIONS=()

# Pass 1 — claim the tail, re-scanning before each so an already-visible
# neighbour is skipped rather than fought over.
i=0
while [ "$i" -lt "$RESERVE" ]; do
  i=$((i + 1))
  cand=$(( $(scan_max) + 1 ))
  if [ "$cand" -gt "$MAX_NUMBER" ]; then
    die "Refused: the $MAX_NUMBER cap was reached while reserving. Placeholders already created: ${RESERVED[*]:-none}."
  fi
  if claim "$cand"; then
    RESERVED+=("$cand")
  else
    RESERVED+=("$cand")   # recorded, then settled by the sweep below
  fi
done

# Pass 2 — the re-scan that detects a creator who moved inside the window.
# The three arrays stay parallel by index: a collision is one row across
# COLLIDED_NUM / COLLIDED_BY / RESLOT_TO, assembled into JSON once at the end.
# Building the object in one place is what keeps the emitted shape honest —
# an entry can never carry a reslot target the run did not actually take.
COLLIDED_NUM=()
COLLIDED_BY=()
RESLOT_TO=()
KEPT=()
for num in "${RESERVED[@]}"; do
  if claimed_by=$(foreign_claim "$num"); then
    rmdir "$STORIES_DIR/$(placeholder_name "$num")" 2>/dev/null || true
    COLLIDED_NUM+=("$num")
    COLLIDED_BY+=("$claimed_by")
  else
    KEPT+=("$num")
  fi
done

# Pass 3 — re-take each contested slot at the current tail, and verify the
# replacement is itself uncontested before accepting it.
for num in ${COLLIDED_NUM+"${COLLIDED_NUM[@]}"}; do
  attempts=0
  while :; do
    attempts=$((attempts + 1))
    if [ "$attempts" -gt "$RESLOT_ATTEMPTS" ]; then
      die "Refused: could not settle a reservation for $(pad "$num") after $RESLOT_ATTEMPTS attempts — another creator is claiming numbers as fast as this one."
    fi
    cand=$(( $(scan_max) + 1 ))
    if [ "$cand" -gt "$MAX_NUMBER" ]; then
      die "Refused: re-slotting $(pad "$num") would pass the $MAX_NUMBER cap."
    fi
    if claim "$cand"; then
      if foreign_claim "$cand" >/dev/null; then
        rmdir "$STORIES_DIR/$(placeholder_name "$cand")" 2>/dev/null || true
        continue
      fi
      KEPT+=("$cand")
      RESLOT_TO+=("$cand")
      break
    fi
  done
done

COLLISIONS=()
k=0
while [ "$k" -lt "${#COLLIDED_NUM[@]}" ]; do
  COLLISIONS+=("{\"number\":\"$(pad "${COLLIDED_NUM[$k]}")\",\"claimed_by\":\"$(json_escape "${COLLIDED_BY[$k]}")\",\"reslotted_to\":\"$(pad "${RESLOT_TO[$k]}")\"}")
  k=$((k + 1))
done

PADDED=()
while IFS= read -r n; do
  [ -n "$n" ] && PADDED+=("$n")
done < <(printf '%s\n' ${KEPT+"${KEPT[@]}"} | sort -n | awk 'NF { printf "%03d\n", $1 }')

emit "$(pad "$(( $(scan_max) + 1 ))")" \
     "$(quote_all ${PADDED+"${PADDED[@]}"})" \
     "$(join_json ${COLLISIONS+"${COLLISIONS[@]}"})"
