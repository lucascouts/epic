#!/usr/bin/env bash
# Runs a story's Validation commands and generated-gate commands, and writes the
# Auditor's Part 1 report — so the deterministic half of validation costs seconds
# instead of a sub-agent's turns.
#
#   validate-run.sh --story <dir> [--only <id,id,...>] [--timeout <s>]
#
# Reads tasks.md. Every [x] sub-task's `Validation:` field is run from its first
# backtick span; its `Tests:` path must exist; its group's `Commit:` message must
# be in git log. A [~] sub-task is SKIP with its qualifier. Every Quality Gate
# whose text carries a backtick command is run the same way. What cannot be run
# — a prose check, a span that is a file name, a gate with no command — is JUDGE:
# the Auditor settles those, and only those.
#
# --only re-runs the named entries (sub-task ids, or gate:<text prefix>) and keeps
# every other entry of the previous run: a revalidation re-checks the failures,
# never the whole story.
#
# Writes .draft/validation-run.json (the machine form) and
# .draft/validation-report.yaml (the schema validate-mode.md defines, with
# verdict pass | fail | pending — pending while a JUDGE entry is open).
# Output: one JSON line {verdict, pass, fail, skip, judge, report}.
# Exit 0 on pass or pending, 1 on fail, 2 on bad usage.

set -euo pipefail

usage() { sed -n '5,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

STORY="" ONLY="" TIMEOUT=300
while [ $# -gt 0 ]; do
  case "$1" in
    --story) STORY="${2-}"; shift 2 ;;
    --only) ONLY="${2-}"; shift 2 ;;
    --timeout) TIMEOUT="${2-}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "validate-run.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
if [ -z "$STORY" ] || [ ! -f "$STORY/tasks.md" ]; then
  echo "validate-run.sh: --story <dir> is required and must hold tasks.md" >&2; exit 2
fi
case "$TIMEOUT" in '' | *[!0-9]*) echo "validate-run.sh: --timeout takes whole seconds" >&2; exit 2 ;; esac
command -v jq >/dev/null || { echo "validate-run.sh: jq is required" >&2; exit 2; }

STORY="$(cd "$STORY" && pwd)"
# The project root holds .epico/: stories live at .epico/stories/<dir> or
# .epico/archive/<dir>, so it is three levels up.
ROOT="$(cd "$STORY/../../.." && pwd)"
DRAFT="$STORY/.draft"
JSON="$DRAFT/validation-run.json" YAML="$DRAFT/validation-report.yaml"
mkdir -p "$DRAFT"

# One row per entry, fields split by \x1f: kind, id, box, command-or-text,
# tests-path, commit-msg. Not TAB: `read` folds runs of whitespace separators,
# which shifts every field after an empty one.
# Sub-task fields are collected until the next box; a group's Commit applies to
# the sub-task it is written under (the last one of the group, by convention).
entries() {
  awk '
    function flush() {
      if (id != "") printf "sub\037%s\037%s\037%s\037%s\037%s\n", id, box, val, tst, cmt
      id = ""; val = ""; tst = ""; cmt = ""
    }
    function span(s,   a) { if (match(s, /`[^`]+`/)) return substr(s, RSTART + 1, RLENGTH - 2); return "" }
    /^## Quality Gates/ { flush(); gates = 1; next }
    /^## / { flush(); gates = 0; next }
    gates && /^- \[[ x~]\] / {
      b = substr($0, 4, 1); t = substr($0, 7)
      printf "gate\037%s\037%s\037%s\037\037\n", t, b, span(t); next
    }
    /^[[:space:]]*- \[[ x~]\] [0-9]+\.[0-9]+/ {
      flush(); box = substr($0, index($0, "[") + 1, 1)
      s = $0; sub(/^[[:space:]]*- \[[ x~]\] /, "", s); split(s, w, /[ :—-]/); id = w[1]
      if (box == "~") { q = $0; sub(/.*\(/, "", q); sub(/[:)].*/, "", q); val = q }
      next
    }
    /^- \[[ x~]\] / { flush(); next }
    id != "" && /^[[:space:]]+- Validation:/ && box != "~" { val = span($0); if (val == "") val = "!" substr($0, index($0, ":") + 2) }
    id != "" && /^[[:space:]]+- Tests:/ { t = $0; if (index(t, "·")) { t = substr(t, index(t, "·")); tst = span(t) } }
    id != "" && /^[[:space:]]+- Commit:/ { c = $0; sub(/^[^"]*"/, "", c); sub(/".*$/, "", c); cmt = c }
    END { flush() }' "$STORY/tasks.md"
}

runnable() {  # <command> — is its first word something the shell can run?
  local first
  first="$(printf '%s' "$1" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*//' | awk '{print $1}')"
  [ -n "$first" ] || return 1
  case "$first" in
    */*) [ -x "$ROOT/$first" ] || [ -x "$first" ] ;;
    *) command -v "$first" >/dev/null 2>&1 ;;
  esac
}

run_cmd() {  # <command> — prints "<exit>\t<last output line>"
  local out code
  set +e
  out="$(cd "$ROOT" && timeout "$TIMEOUT" bash -c "$1" </dev/null 2>&1)"
  code=$?
  set -e
  [ "$code" -eq 124 ] && out="timed out after ${TIMEOUT}s"
  printf '%s\t%s\n' "$code" "$(printf '%s' "$out" | tr -d '\r' | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' | awk 'NF' | tail -1 | cut -c1-200)"
}

selected() {  # <kind> <id> — is this entry re-run under --only?
  [ -z "$ONLY" ] && return 0
  local want IFS=','
  for want in $ONLY; do
    if [ "$1" = sub ] && [ "$want" = "$2" ]; then return 0; fi
    if [ "$1" = gate ] && [ "${want#gate:}" != "$want" ] && [ "${2#"${want#gate:}"}" != "$2" ]; then return 0; fi
  done
  return 1
}

check() {  # <kind> <id> <box> <value> <tests> <commit> — prints one JSON entry
  local kind=$1 id=$2 box=$3 val=$4 tst=$5 cmt=$6 result detail qualifier="" res code last
  if [ "$box" = "~" ]; then
    result=SKIP qualifier="$val" detail="closed without the work"
  elif [ "$box" = " " ] && [ "$kind" = sub ]; then
    return 0  # not done yet; an open gate is exactly what validation settles
  elif [ -z "$val" ] || [ "${val#!}" != "$val" ] || ! runnable "$val"; then
    result=JUDGE detail="${val#!}"; [ -z "$detail" ] && detail="no command in the text"
  else
    res="$(run_cmd "$val")"; code="${res%%$'\t'*}"; last="${res#*$'\t'}"
    if [ "$code" -eq 0 ]; then result=PASS; else result=FAIL; fi
    detail="\`$val\` exit $code${last:+ — $last}"
  fi
  if [ "$kind" = sub ] && { [ "$result" = PASS ] || [ "$result" = JUDGE ]; }; then
    if [ -n "$tst" ] && [ ! -e "$ROOT/$tst" ]; then result=FAIL detail="test file missing: $tst"; fi
    if [ -n "$cmt" ] && ! git -C "$ROOT" log --fixed-strings --grep="$cmt" -1 --format=%h 2>/dev/null | grep -q .; then
      result=FAIL detail="commit not found: \"$cmt\""
    fi
  fi
  jq -nc --arg kind "$kind" --arg id "$id" --arg result "$result" --arg detail "$detail" --arg q "$qualifier" \
    '{kind: $kind, id: $id, result: $result, qualifier: (if $q == "" then null else $q end), detail: $detail}'
}

PREV='[]'
[ -n "$ONLY" ] && [ -f "$JSON" ] && PREV="$(jq -c '.entries' "$JSON")"
NEW="$(entries | while IFS=$'\x1f' read -r kind id box val tst cmt; do
  if selected "$kind" "$id"; then check "$kind" "$id" "$box" "$val" "$tst" "$cmt"
  else printf '%s' "$PREV" | jq -c --arg k "$kind" --arg i "$id" '.[] | select(.kind == $k and .id == $i)'; fi
done | jq -sc '.')"

# "All task validations pass" is the sub-task results themselves: derived on
# every run — a --only revalidation included — so the Auditor never re-judges
# what the runs just proved, and a stale FAIL never outlives its fix.
NEW="$(printf '%s' "$NEW" | jq -c '
  ([.[] | select(.kind == "sub")]) as $subs
  | map(if .kind == "gate" and (.id | startswith("All task validations pass")) then
      if any($subs[]; .result == "FAIL") then .result = "FAIL" | .detail = "a sub-task validation failed"
      elif any($subs[]; .result == "JUDGE") then .result = "JUDGE" | .detail = "waits on the JUDGE sub-tasks"
      else .result = "PASS" | .detail = "no FAIL in results[]" end
    else . end)')"
verdict="$(printf '%s' "$NEW" | jq -r 'if any(.[]; .result == "FAIL") then "fail" elif any(.[]; .result == "JUDGE") then "pending" else "pass" end')"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n --arg story "$(basename "$STORY")" --arg at "$NOW" --arg verdict "$verdict" --argjson entries "$NEW" \
  '{story: $story, generated_at: $at, generated_by: "epico-validate-run", verdict: $verdict, entries: $entries}' > "$JSON"

# JSON strings are valid YAML double-quoted scalars, so every value goes out
# through tojson and needs no escaping of its own.
jq -r '
  "story: \(.story | tojson)",
  "generated_at: \(.generated_at | tojson)",
  "generated_by: epico-validate-run",
  "verdict: \(.verdict)",
  "results:",
  (.entries[] | select(.kind == "sub") |
    "  - task: \(.id | tojson)", "    result: \(.result)", "    qualifier: \(.qualifier // null | tojson)", "    detail: \(.detail | tojson)"),
  "gates:",
  (.entries[] | select(.kind == "gate") |
    "  - gate: \(.id | tojson)", "    result: \(.result)", "    evidence: \(.detail | tojson)")
' "$JSON" > "$YAML"

jq -c --arg report "$YAML" '{verdict, pass: ([.entries[] | select(.result == "PASS")] | length),
  fail: ([.entries[] | select(.result == "FAIL")] | length), skip: ([.entries[] | select(.result == "SKIP")] | length),
  judge: ([.entries[] | select(.result == "JUDGE")] | length), report: $report}' "$JSON"
[ "$verdict" = fail ] && exit 1
exit 0
