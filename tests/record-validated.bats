#!/usr/bin/env bats
# epico-validated: the commit a story is validated against, recorded by a script
# before the Auditor's spawn, and carried into the archive manifest.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  P=$(mktemp -d)
  git -C "$P" init -q
  git -C "$P" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  STORY="$P/.epico/stories/001-x"
  mkdir -p "$STORY"
}

teardown() { rm -rf "$P"; }

rec() { bash "$PLUGIN_ROOT/scripts/record-validated.sh" "$STORY"; }

@test "a clean tree records HEAD and dirty: false" {
  run rec
  [ "$status" -eq 0 ]
  head=$(git -C "$P" rev-parse HEAD)
  grep -qx "sha: $head" "$STORY/.draft/validated.yaml"
  grep -qx 'dirty: false' "$STORY/.draft/validated.yaml"
  echo "$output" | jq -e --arg h "$head" '.sha == $h and .dirty == false'
}

@test "changes under .epico/ do not make the tree dirty" {
  echo x > "$STORY/tasks.md"
  run rec
  grep -qx 'dirty: false' "$STORY/.draft/validated.yaml"
}

@test "a change outside .epico/ makes it dirty" {
  echo x > "$P/main.go"
  run rec
  grep -qx 'dirty: true' "$STORY/.draft/validated.yaml"
}

@test "outside a git repository nothing is written and the exit is 2" {
  rm -rf "$P/.git"
  run rec
  [ "$status" -eq 2 ]
  [ ! -e "$STORY/.draft/validated.yaml" ]
}

@test "validate runs it before the Auditor's spawn" {
  grep -qF 'epico-validated <story-dir>' "$PLUGIN_ROOT/references/validate-mode.md"
}
