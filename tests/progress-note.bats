#!/usr/bin/env bats
# Progress notes: one JSON line per protocol step in .draft/progress.log.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  STORY="$WORK/.epico/stories/004-login"
  mkdir -p "$STORY"
}

teardown() {
  rm -rf "$WORK"
}

note() { bash "$PLUGIN_ROOT/scripts/progress-note.sh" "$@"; }

@test "one line per call, the six fields, .draft/ created on demand" {
  run note --story "$STORY" --task 2.1 --step context --status started
  [ "$status" -eq 0 ]
  run note --story "$STORY" --task 2.1 --step validation --status done --evidence "go test ./... exit 0"
  [ "$(wc -l < "$STORY/.draft/progress.log")" -eq 2 ]
  tail -n 1 "$STORY/.draft/progress.log" | jq -e '
    keys == ["at","evidence","status","step","story","task"]
    and .story == "004-login" and .task == "2.1" and .step == "validation" and .status == "done"
    and .evidence == "go test ./... exit 0" and (.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))'
}

@test "evidence is one line of at most 300 characters, quotes and newlines kept parseable" {
  long=$(printf 'x%.0s' $(seq 1 400))
  run note --story "$STORY" --task 1 --step report --status failed --evidence $'line one "quoted"\nline two '"$long"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$STORY/.draft/progress.log")" -eq 1 ]
  jq -e '(.evidence | length) == 300 and (.evidence | startswith("line one \"quoted\" line two"))' "$STORY/.draft/progress.log"
}

@test "bad usage exits 2 and writes nothing" {
  run note --story "$STORY" --task 1 --step x --status maybe
  [ "$status" -eq 2 ]
  run note --story "$STORY" --step x --status done
  [ "$status" -eq 2 ]
  run note --story "$WORK/nope" --task 1 --step x --status done
  [ "$status" -eq 2 ]
  [ ! -e "$STORY/.draft/progress.log" ]
}

@test "concurrent writers never interleave inside a line" {
  for i in $(seq 1 20); do note --story "$STORY" --task "$i" --step s --status done --evidence "$(printf 'y%.0s' $(seq 1 250))" & done
  wait
  [ "$(wc -l < "$STORY/.draft/progress.log")" -eq 20 ]
  jq -s -e 'length == 20' "$STORY/.draft/progress.log"
}
