#!/usr/bin/env bash
# The one writer of a story's .draft/deviations.yaml — the deviation register.
#
#   add deviation  --task T --component C --design D --actual A --reason R --impact I
#                  [--test-surface-adjusted] [--follow-up "<what is owed>"]
#   add discovery  --task T --tech X --finding F
#   list           [--open]          entries as JSON; --open = follow_up: true only
#   discharge      --id N --evidence "<what paid the debt>"
#   amend          --id N --<field> <value>...   correct an entry (the fail-record fixes)
#
# THE FORMAT IS THIS SCRIPT'S. Two top-level lists, `deviations:` and
# `discoveries:`; each entry a `  - key: value` line followed by `    key: value`
# lines; every string written as a double-quoted JSON string, which is also a
# valid YAML double-quoted scalar. A hand-written file in that shape — quoted,
# single-quoted or bare one-line scalars, comments — is read too. Anything else
# (a multi-line scalar, a nested mapping) is refused with its line number:
# guessing would rewrite someone's register wrong.
#
# Every entry carries a stable `id`; entries written before the field get one,
# in file order, on the next write. Writes go to a temporary file in .draft/
# and are renamed over the register, under a lock, so a reader never sees half
# a file and two writers never interleave.
#
# Output: JSON on stdout. Exit 0 done, 1 refused (nothing written), 2 usage.

set -euo pipefail

usage() {
  sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  echo "Every command takes --story <story-dir>."
}
die() { echo "deviation.sh: $1" >&2; exit "${2:-2}"; }
refuse() { jq -cn --arg r "$1" '{status: "refused", reason: $r}'; exit 1; }

[ $# -ge 1 ] || { usage >&2; exit 2; }
CMD=$1; shift
KIND=""
if [ "$CMD" = add ]; then
  KIND=${1-}; shift || true
  case "$KIND" in deviation | discovery) ;; *) die "add needs 'deviation' or 'discovery'" ;; esac
fi
case "$CMD" in add | list | discharge | amend) ;; -h | --help) usage; exit 0 ;; *) die "unknown command: $CMD" ;; esac

STORY="" OPEN=false TSA=false ID="" EVIDENCE=""
declare -A F=()
while [ $# -gt 0 ]; do
  case "$1" in
    --story) STORY="${2-}"; shift 2 ;;
    --open) OPEN=true; shift ;;
    --test-surface-adjusted) TSA=true; shift ;;
    --id) ID="${2-}"; shift 2 ;;
    --evidence) EVIDENCE="${2-}"; shift 2 ;;
    --task | --component | --design | --actual | --reason | --impact | --tech | --finding | --follow-up)
      [ $# -ge 2 ] || die "$1 needs a value"
      F[${1#--}]="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$STORY" ] && [ -d "$STORY" ] || die "--story <dir> is required and must exist"
REG="$STORY/.draft/deviations.yaml"

# parse — the register as {deviations: [...], discoveries: [...]}, or an
# {error, line} object when a line is outside the grammar.
parse() {
  [ -f "$REG" ] || { echo '{"deviations": [], "discoveries": []}'; return 0; }
  jq -R -s '
    def scalar:
      if test("^\"") then (capture("^(?<v>\"(?:[^\"\\\\]|\\\\.)*\")").v | fromjson)
      elif test("^'"'"'") then (capture("^'"'"'(?<v>(?:[^'"'"']|'"'"''"'"')*)'"'"'").v | gsub("'"'"''"'"'"; "'"'"'"))
      else (sub("[[:space:]]+#.*$"; "") | sub("[[:space:]]+$"; "")) as $b
        | if $b == "true" then true elif $b == "false" then false elif $b == "null" or $b == "~" then null
          elif ($b | test("^-?[0-9]+$")) then ($b | tonumber) else $b end
      end;
    [splits("\n")] | to_entries
    | reduce .[] as $l ({out: {deviations: [], discoveries: []}, sec: null, err: null};
        if .err != null then .
        else ($l.value) as $t
        | if ($t | test("^[[:space:]]*(#.*)?$")) then .
          elif ($t | test("^(deviations|discoveries):[[:space:]]*(\\[\\])?[[:space:]]*(#.*)?$")) then .sec = ($t | capture("^(?<s>[a-z]+)").s)
          elif .sec != null and ($t | test("^  - [A-Za-z_]+:")) then
            ($t | capture("^  - (?<k>[A-Za-z_]+):[[:space:]]*(?<v>.*)$")) as $m
            | .out[.sec] += [{($m.k): ($m.v | scalar)}]
          elif .sec != null and (.out[.sec] | length) > 0 and ($t | test("^    [A-Za-z_]+:")) then
            ($t | capture("^    (?<k>[A-Za-z_]+):[[:space:]]*(?<v>.*)$")) as $m
            | if ($m.v | test("^[|>]")) then .err = {error: "multi-line scalar", line: ($l.key + 1)}
              else .out[.sec][-1] += {($m.k): ($m.v | scalar)} end
          else .err = {error: "line outside the register grammar", line: ($l.key + 1)}
          end
        end)
    | if .err != null then .err else .out end
    | if has("error") then . else
        ([.deviations[], .discoveries[] | .id | numbers] | max // 0) as $max
        | reduce (["deviations", "discoveries"][]) as $s ({doc: ., next: ($max + 1)};
            reduce range(0; (.doc[$s] | length)) as $i (.;
              if (.doc[$s][$i].id | type) == "number" then .
              else .doc[$s][$i] = ({id: .next} + .doc[$s][$i]) | .next += 1 end))
        | .doc
      end' "$REG"
}

render() {  # stdin: the register JSON → the YAML text
  jq -r '
    def entry: to_entries | to_entries
      | map((if .key == 0 then "  - " else "    " end) + .value.key + ": "
            + (.value.value | if type == "string" then @json else tostring end))
      | join("\n");
    ["deviations", "discoveries"][] as $s
    | if (.[$s] | length) == 0 then "\($s): []"
      else "\($s):\n" + ([.[$s][] | entry] | join("\n")) end'
}

# The lock covers read, change and write: a writer that read before taking it
# would rewrite the register from a stale copy and drop a concurrent entry.
LOCK=""
take_lock() {
  local i=0
  mkdir -p "$STORY/.draft"
  until mkdir "$STORY/.draft/.deviations.lock" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -lt 100 ] || refuse "the register is locked by another writer ($STORY/.draft/.deviations.lock); nothing was written"
    sleep 0.1
  done
  LOCK="$STORY/.draft/.deviations.lock"
  trap '[ -z "$LOCK" ] || rmdir "$LOCK" 2>/dev/null || true' EXIT
}

write_atomic() {  # stdin: the register JSON
  local doc tmp
  doc=$(cat)
  tmp=$(mktemp "$STORY/.draft/.deviations.XXXXXX")
  printf '%s\n' "$doc" | render > "$tmp"
  mv "$tmp" "$REG"
}

[ "$CMD" = list ] || take_lock
DOC=$(parse)
if printf '%s' "$DOC" | jq -e 'has("error")' >/dev/null; then
  refuse "$(printf '%s' "$DOC" | jq -r '"\(.error) at \(.line) of '"$REG"' — this script reads one-line scalars under deviations: and discoveries: only; fix that line by hand, then re-run. Nothing was written"')"
fi

case "$CMD" in
  list)
    printf '%s' "$DOC" | jq --argjson open "$OPEN" '
      if $open then {deviations: [.deviations[] | select(.follow_up == true)], discoveries: [.discoveries[] | select(.follow_up == true)]} else . end'
    ;;
  add)
    if [ "$KIND" = deviation ]; then req=(task component design actual reason impact); else req=(task tech finding); fi
    for k in "${req[@]}"; do [ -n "${F[$k]-}" ] || die "add $KIND needs --$k"; done
    args=(--arg kind "$KIND")
    for k in "${req[@]}"; do args+=(--arg "$k" "${F[$k]}"); done
    NEW=$(printf '%s' "$DOC" | jq "${args[@]}" --argjson tsa "$TSA" --arg owed "${F[follow-up]-}" --arg req "${req[*]}" '
      ([.deviations[], .discoveries[] | .id] | max // 0) as $max
      | ($req | split(" ")) as $keys
      | ({id: ($max + 1)} + (reduce $keys[] as $k ({}; . + {($k): $ARGS.named[$k]}))
         + (if $tsa then {test_surface_adjusted: true} else {} end)
         + (if $owed != "" then {follow_up: true, owed: $owed} else {} end)) as $e
      | (if $kind == "deviation" then "deviations" else "discoveries" end) as $s
      | .[$s] += [$e] | {doc: ., entry: $e}')
    printf '%s' "$NEW" | jq '.doc' | write_atomic
    printf '%s' "$NEW" | jq -c '{status: "added", entry}'
    ;;
  amend)
    [[ "$ID" =~ ^[1-9][0-9]*$ ]] || die "amend needs --id <n>"
    [ ${#F[@]} -gt 0 ] || die "amend needs at least one --<field> <value>"
    printf '%s' "$DOC" | jq -e --argjson id "$ID" '[.deviations[], .discoveries[] | select(.id == $id)] | length == 1' >/dev/null ||
      refuse "no entry with id $ID in $REG; nothing was written"
    patch=$(for k in "${!F[@]}"; do jq -cn --arg k "${k//-/_}" --arg v "${F[$k]}" '{($k): $v}'; done | jq -s 'add')
    printf '%s' "$DOC" | jq --argjson id "$ID" --argjson p "$patch" '
      (.deviations, .discoveries) |= map(if .id == $id then . + $p else . end)' | write_atomic
    jq -cn --argjson id "$ID" --argjson p "$patch" '{status: "amended", id: $id, fields: ($p | keys)}'
    ;;
  discharge)
    [[ "$ID" =~ ^[1-9][0-9]*$ ]] || die "discharge needs --id <n>"
    [ -n "$EVIDENCE" ] || die "discharge needs --evidence"
    found=$(printf '%s' "$DOC" | jq --argjson id "$ID" '[.deviations[], .discoveries[] | select(.id == $id)][0] // null')
    [ "$found" != null ] || refuse "no entry with id $ID in $REG; nothing was written"
    printf '%s' "$found" | jq -e '.follow_up == true' >/dev/null || refuse "entry $ID owes nothing (no follow_up: true); nothing was written"
    printf '%s' "$DOC" | jq --argjson id "$ID" --arg ev "$EVIDENCE" --arg at "$(date -u +%Y-%m-%d)" '
      (.deviations, .discoveries) |= map(if .id == $id then .follow_up = false | .discharged = $ev | .discharged_at = $at else . end)' | write_atomic
    jq -cn --argjson id "$ID" '{status: "discharged", id: $id}'
    ;;
esac
