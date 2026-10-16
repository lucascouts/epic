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

@test "a term with its legend in the same text passes, and is reported as explained" {
  run bash -c "printf 'O teste ficou Red antes do código.\n*Red* — o teste foi escrito antes e falha de propósito.\n' | bash '$CHECK'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.pass == true and .hits == [] and .explained == ["Red"]'
}

@test "a legend explains only its own term; the others are still hits" {
  run bash -c "printf 'Ficou Red e fiz um commit.\n*Red* — o teste falha de propósito antes do código.\n' | bash '$CHECK'"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '[.hits[].term] == ["commit"] and .explained == ["Red"]'
}

@test "legend forms: bold, colon, hyphen, quote and list markers; a plural is covered by its singular" {
  text='Salvei dois commits na worktree.\n> **commit**: uma cópia salva do projeto.\n- *worktree* - uma pasta separada para trabalhar.\n'
  run bash -c "printf '$text' | bash '$CHECK'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.explained | sort == ["commits","worktree"]'
}

@test "the legend line is not itself scanned as a use of the term" {
  run bash -c "printf 'Tudo pronto.\n*commit* — uma cópia salva do projeto.\n' | bash '$CHECK'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hits == []'
}

@test "plain-register states the legend rule and its format" {
  grep -qF 'carries its legend' "$PLUGIN_ROOT/references/plain-register.md"
  grep -qF '*term* — what it means here' "$PLUGIN_ROOT/references/plain-register.md"
}
