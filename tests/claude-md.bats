#!/usr/bin/env bats
# epic-claude-md: the managed block of a project's CLAUDE.md.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  R=$(mktemp -d)
  mkdir -p "$R/.epic"
  printf '# Constitution\n\n## Defaults\n- x\n\n## Quality\n- Lint — `eslint .`\n- Types — `tsc --noEmit`\n\n## Invariants\n- Never store a card number — the PCI audit finding\n' > "$R/.epic/constitution.md"
}

teardown() {
  rm -rf "$R"
}

md() { bash "$PLUGIN_ROOT/scripts/claude-md.sh" "$@" --root "$R"; }

@test "no CLAUDE.md: write creates it with the block only, under 100 lines" {
  run md write
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "appended" and .lines < 100'
  head -n 1 "$R/CLAUDE.md" | command grep -q '^<!-- epic:start'
  tail -n 1 "$R/CLAUDE.md" | command grep -qx '<!-- epic:end -->'
}

@test "an existing CLAUDE.md keeps every byte outside the markers, and a rewrite replaces in place" {
  printf '# Mine\n\nKeep this.\n' > "$R/CLAUDE.md"
  md write >/dev/null
  printf '\nAfter the block, also mine.\n' >> "$R/CLAUDE.md"
  sed -i 's/tsc --noEmit/tsc -p ./' "$R/.epic/constitution.md"
  run md write
  echo "$output" | jq -e '.status == "replaced"'
  [ "$(command grep -c '^<!-- epic:start' "$R/CLAUDE.md")" -eq 1 ]
  head -n 3 "$R/CLAUDE.md" | command grep -q 'Keep this.'
  tail -n 1 "$R/CLAUDE.md" | command grep -q 'After the block, also mine.'
  command grep -q 'tsc -p \.' "$R/CLAUDE.md"
}

@test "the block carries the constitution pointer, its Quality commands, its invariants, the lookup order and the code rules" {
  touch "$R/ARCHITECTURE.md"; mkdir -p "$R/docs/adr" "$R/examples"
  md write >/dev/null
  for want in '.epic/constitution.md' 'eslint \.' 'Never store a card number' 'Where to look, in order' 'installed dependency at the lockfile version' 'under 500 lines' 'JSON, one event per line' '`ARCHITECTURE.md`, `docs/adr`' '`examples/`'; do
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
  rm "$R/.epic/constitution.md"
  run md check
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.present == false'
  md write >/dev/null
  run md check
  [ "$status" -eq 0 ]
  if command grep -q 'Before committing\|### Invariants' "$R/CLAUDE.md"; then echo "invented a section"; return 1; fi
  printf '# C\n\n## Quality\n- Lint — `ruff check`\n' > "$R/.epic/constitution.md"
  run md check
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.present == true and .current == false'
}
