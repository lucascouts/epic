#!/usr/bin/env bats
# epico-claude-md: the managed block of a project's CLAUDE.md.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  R=$(mktemp -d)
  mkdir -p "$R/.epico"
  printf '# Constitution\n\n## Defaults\n- x\n\n## Quality\n- Lint — `eslint .`\n- Types — `tsc --noEmit`\n\n## Invariants\n- Never store a card number — the PCI audit finding\n' > "$R/.epico/constitution.md"
}

teardown() {
  rm -rf "$R"
}

md() { bash "$PLUGIN_ROOT/scripts/claude-md.sh" "$@" --root "$R"; }

@test "no CLAUDE.md: write creates it with the block only, under 100 lines" {
  run md write
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "appended" and .lines < 100'
  head -n 1 "$R/CLAUDE.md" | command grep -q '^<!-- epico:start'
  tail -n 1 "$R/CLAUDE.md" | command grep -qx '<!-- epico:end -->'
}

@test "an existing CLAUDE.md keeps every byte outside the markers, and a rewrite replaces in place" {
  printf '# Mine\n\nKeep this.\n' > "$R/CLAUDE.md"
  md write >/dev/null
  printf '\nAfter the block, also mine.\n' >> "$R/CLAUDE.md"
  sed -i 's/tsc --noEmit/tsc -p ./' "$R/.epico/constitution.md"
  run md write
  echo "$output" | jq -e '.status == "replaced"'
  [ "$(command grep -c '^<!-- epico:start' "$R/CLAUDE.md")" -eq 1 ]
  head -n 3 "$R/CLAUDE.md" | command grep -q 'Keep this.'
  tail -n 1 "$R/CLAUDE.md" | command grep -q 'After the block, also mine.'
  command grep -q 'tsc -p \.' "$R/CLAUDE.md"
}

@test "the block carries the constitution pointer, its Quality commands, its invariants, the lookup order and the code rules" {
  touch "$R/ARCHITECTURE.md"; mkdir -p "$R/docs/adr" "$R/examples"
  md write >/dev/null
  for want in '.epico/constitution.md' 'eslint \.' 'Never store a card number' 'Where to look, in order' 'installed dependency at the lockfile version' 'under 500 lines' 'JSON, one event per line' '`ARCHITECTURE.md`, `docs/adr`' '`examples/`'; do
    command grep -q -- "$want" "$R/CLAUDE.md" || { echo "missing: $want"; return 1; }
  done
}

@test "AGENTS.md: one @AGENTS.md line before the block, never twice" {
  touch "$R/AGENTS.md"
  printf '# Mine\n' > "$R/CLAUDE.md"
  md write >/dev/null
  md write >/dev/null
  [ "$(command grep -cx '@AGENTS.md' "$R/CLAUDE.md")" -eq 1 ]
}

@test "check: absent and stale exit 1, current exits 0; a section with no source is left out" {
  rm "$R/.epico/constitution.md"
  run md check
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.present == false'
  md write >/dev/null
  run md check
  [ "$status" -eq 0 ]
  if command grep -q 'Before committing\|### Invariants' "$R/CLAUDE.md"; then echo "invented a section"; return 1; fi
  printf '# C\n\n## Quality\n- Lint — `ruff check`\n' > "$R/.epico/constitution.md"
  run md check
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.present == true and .current == false'
}

@test "docs are found at the root and under docs/: ARCHITECTURE, ROADMAP, stages, OVERVIEW" {
  mkdir -p "$R/docs/stages" "$R/docs/adr"
  touch "$R/docs/ARCHITECTURE.md" "$R/docs/ROADMAP.md" "$R/docs/OVERVIEW.md" "$R/ROADMAP.md"
  md write >/dev/null
  line=$(command grep '^- Project docs:' "$R/CLAUDE.md")
  for want in '`docs/ARCHITECTURE.md`' '`ROADMAP.md`' '`docs/ROADMAP.md`' '`docs/stages`' '`docs/OVERVIEW.md`' '`docs/adr`'; do
    [[ "$line" == *"$want"* ]] || { echo "missing $want in: $line"; return 1; }
  done
  [[ "$line" != *'`ARCHITECTURE.md`'* ]] || { echo "listed a root ARCHITECTURE.md that does not exist"; return 1; }
}
