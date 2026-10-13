#!/usr/bin/env bats
# epic-jargon: process words in a layperson-facing closing.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CHECK="$PLUGIN_ROOT/scripts/jargon-check.sh"
}

@test "a plain closing passes, a command in backticks included" {
  run bash -c "printf 'Pronto! Digite \`npm start\` para abrir.\nEle guarda suas cartas num arquivo.\nNão testei no celular.\n' | bash '$CHECK'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.pass == true and .hits == []'
}

@test "process words are found and named as written, with counts" {
  run bash -c "printf 'Fechei a sub-task dois, o Executor fez o commit e outro commit.\nRed confirmado em R1.2, veja tasks.md.\n' | bash '$CHECK'"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.pass == false'
  echo "$output" | jq -e '[.hits[].term] | sort == ["Executor","R1.2","Red","commit","sub-task","tasks.md"]'
  echo "$output" | jq -e '.hits[] | select(.term == "commit") | .count == 2'
}

@test "case-sensitive terms do not flag ordinary words; fenced blocks are skipped" {
  run bash -c "printf 'The red button turns green when saved.\n\`\`\`\ngit commit -m x\n\`\`\`\n' | bash '$CHECK'"
  [ "$status" -eq 0 ]
}

@test "--file reads a file; bad usage exits 2" {
  f=$(mktemp)
  printf 'The orchestrator ran triage.\n' > "$f"
  run bash "$CHECK" --file "$f"
  [ "$status" -eq 1 ]
  rm -f "$f"
  run bash "$CHECK" --bogus
  [ "$status" -eq 2 ]
}

@test "every left-column group of the plain-register table is represented in the term list" {
  for t in 'executor' 'tasks\.md' 'closing block' 'Red' 'commit' 'quality gates' 'engineering level' 'MCP'; do
    command grep -qF -- "$t" "$PLUGIN_ROOT/assets/jargon-terms.txt" || { echo "term list lacks: $t"; return 1; }
  done
}
