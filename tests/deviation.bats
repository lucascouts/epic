#!/usr/bin/env bats
# epic-deviation: the one writer of .draft/deviations.yaml.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  S=$(mktemp -d)/004-login
  mkdir -p "$S/.draft"
}

teardown() {
  rm -rf "$(dirname "$S")"
}

dev() { bash "$PLUGIN_ROOT/scripts/deviation.sh" "$@"; }

legacy() {
  cat > "$S/.draft/deviations.yaml" <<'EOF'
# written by hand before the script existed
deviations:
  - task: "2.1"
    component: AppConfig::from_env   # a bare value with a comment
    design: 'Result<Self, AppError>'
    actual: "Result<Self, String>"
    test_surface_adjusted: true
discoveries:
  - task: "5.3"
    tech: "actix-web"
    finding: "HttpMessage trait must be imported for extensions_mut()"
EOF
}

@test "list reads a hand-written register and gives every entry a stable id" {
  legacy
  run dev list --story "$S"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.deviations[0] == {"id":1,"task":"2.1","component":"AppConfig::from_env","design":"Result<Self, AppError>","actual":"Result<Self, String>","test_surface_adjusted":true}'
  echo "$output" | jq -e '.discoveries[0].id == 2'
}

@test "add writes the script's format, keeps every legacy entry, and re-reads identically" {
  legacy
  run dev add deviation --story "$S" --task 3.1 --component "AppError::Display" --design 'says "hi" — ü' --actual a --reason r --impact i --follow-up "split Display"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "added" and .entry.id == 3 and .entry.follow_up == true'
  command grep -q '^  - id: 3$' "$S/.draft/deviations.yaml"
  command grep -q 'design: "says \\"hi\\" — ü"' "$S/.draft/deviations.yaml"
  run dev list --story "$S"
  echo "$output" | jq -e '(.deviations | length) == 2 and .deviations[1].design == "says \"hi\" — ü" and .discoveries[0].finding == "HttpMessage trait must be imported for extensions_mut()"'
}

@test "add discovery on an empty story creates .draft/ content; missing fields exit 2 and write nothing" {
  rm -rf "$S/.draft"
  run dev add discovery --story "$S" --task 1.1 --tech go --finding "net/http: Server.Shutdown needs a context"
  [ "$status" -eq 0 ]
  command grep -q '^deviations: \[\]$' "$S/.draft/deviations.yaml"
  before=$(cksum < "$S/.draft/deviations.yaml")
  run dev add deviation --story "$S" --task 1.2 --component x
  [ "$status" -eq 2 ]
  [ "$(cksum < "$S/.draft/deviations.yaml")" = "$before" ]
}

@test "list --open shows what is owed; discharge pays it once; amend corrects a field" {
  dev add deviation --story "$S" --task 1 --component c --design d --actual a --reason r --impact i --follow-up "owe it" >/dev/null
  dev add deviation --story "$S" --task 2 --component c --design d --actual a --reason r --impact i >/dev/null
  run dev list --story "$S" --open
  echo "$output" | jq -e '[.deviations[].id] == [1]'
  run dev discharge --story "$S" --id 1 --evidence "fixed in abc123"
  [ "$status" -eq 0 ]
  run dev discharge --story "$S" --id 1 --evidence again
  [ "$status" -eq 1 ]
  run dev list --story "$S"
  echo "$output" | jq -e '.deviations[0].follow_up == false and .deviations[0].discharged == "fixed in abc123"'
  run dev amend --story "$S" --id 2 --impact "two callers, not none"
  [ "$status" -eq 0 ]
  run dev list --story "$S"
  echo "$output" | jq -e '.deviations[1].impact == "two callers, not none"'
  run dev amend --story "$S" --id 9 --impact x
  [ "$status" -eq 1 ]
}

@test "a line outside the grammar is refused with its number, and the file is untouched" {
  printf 'deviations:\n  - task: "1"\n    reason: |\n      multi\n      line\n' > "$S/.draft/deviations.yaml"
  before=$(cksum < "$S/.draft/deviations.yaml")
  run dev add discovery --story "$S" --task 1 --tech t --finding f
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused" and (.reason | test("at 3 "))'
  [ "$(cksum < "$S/.draft/deviations.yaml")" = "$before" ]
}

@test "concurrent adds lose no entry and leave a parseable register" {
  for i in $(seq 1 12); do dev add discovery --story "$S" --task "$i" --tech t --finding "f$i" >/dev/null & done
  wait
  run dev list --story "$S"
  echo "$output" | jq -e '(.discoveries | length) == 12 and ([.discoveries[].id] | unique | length) == 12'
  [ ! -e "$S/.draft/.deviations.lock" ]
}
