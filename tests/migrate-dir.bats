#!/usr/bin/env bats
# scripts/migrate-dir.sh — moves a pre-Epico layout (.epic/, EPIC.md, the
# epic:* markers, the .gitignore entry) to the current names, once. Real temp
# directories and real git repos: the script's whole job is the filesystem and
# git state it leaves behind.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MIG="$ROOT/scripts/migrate-dir.sh"
  WORK=$(mktemp -d)
  unset CLAUDE_PROJECT_DIR
}

teardown() {
  rm -rf "$WORK"
}

init_repo() {
  git -C "$WORK" init -q
  git -C "$WORK" config user.email "test@example.com"
  git -C "$WORK" config user.name "Test"
  git -C "$WORK" config commit.gpgsign false
}

legacy_layout() {
  mkdir -p "$WORK/.epic/stories/001-a"
  printf '# Epic — Story Index\n\n<!-- epic:index:start -->\n| row |\n<!-- epic:index:end -->\n' > "$WORK/.epic/EPIC.md"
  printf 'tasks\n' > "$WORK/.epic/stories/001-a/tasks.md"
  printf '# Mine\n\nmy text mentions <!-- epic:start --> inline\n\n<!-- epic:start — managed by the Epic plugin -->\n## Epic\n<!-- epic:end -->\n' > "$WORK/CLAUDE.md"
  printf 'node_modules/\n.epic/\n.epic-cache\ndocs/.epic\n' > "$WORK/.gitignore"
}

@test "an untracked layout moves whole: folder, index, markers, CLAUDE.md markers and the exact .gitignore entry" {
  legacy_layout
  run bash "$MIG" --root "$WORK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "moved" and .git == null'
  [ ! -e "$WORK/.epic" ]
  [ -f "$WORK/.epico/EPICO.md" ] && [ ! -e "$WORK/.epico/EPIC.md" ]
  [ -f "$WORK/.epico/stories/001-a/tasks.md" ]
  grep -qx '<!-- epico:index:start -->' "$WORK/.epico/EPICO.md"
  grep -qx '<!-- epico:index:end -->' "$WORK/.epico/EPICO.md"
  [ "$(grep -c 'epic:index' "$WORK/.epico/EPICO.md")" -eq 0 ]
  grep -q '^<!-- epico:start' "$WORK/CLAUDE.md"
  grep -qx '<!-- epico:end -->' "$WORK/CLAUDE.md"
  # Prose that only mentions a marker mid-line is the user's text, not a marker.
  grep -qF 'my text mentions <!-- epic:start --> inline' "$WORK/CLAUDE.md"
  [ "$(cat "$WORK/.gitignore")" = "$(printf 'node_modules/\n.epico/\n.epic-cache\ndocs/.epic')" ]
}

@test "a tracked layout moves with git mv: staged, never committed, untracked files carried along" {
  legacy_layout
  init_repo
  git -C "$WORK" add -f .epic/EPIC.md .gitignore
  git -C "$WORK" commit -qm init
  head=$(git -C "$WORK" rev-parse HEAD)
  run bash "$MIG" --root "$WORK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "moved" and (.git | test("git mv"))'
  [ "$(git -C "$WORK" rev-parse HEAD)" = "$head" ]
  git -C "$WORK" status --short | grep -qE '^R[ M] \.epic/EPIC\.md -> \.epico/EPICO\.md$'
  [ -f "$WORK/.epico/stories/001-a/tasks.md" ]
  [ ! -e "$WORK/.epic" ]
}

@test "with both layouts present nothing moves, and the refusal says why" {
  legacy_layout
  mkdir -p "$WORK/.epico"
  run bash "$MIG" --root "$WORK"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and (.notes | test("both"))'
  [ -f "$WORK/.epic/EPIC.md" ]
  [ -z "$(ls -A "$WORK/.epico")" ]
}

@test "no legacy layout is nothing to do" {
  mkdir -p "$WORK/.epico"
  run bash "$MIG" --root "$WORK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "nothing"'
  run bash "$MIG" --root "$(mktemp -d)"
  echo "$output" | jq -e '.status == "nothing"'
}

@test "run from a subdirectory, it finds the layout above, the way the other scripts do" {
  legacy_layout
  mkdir -p "$WORK/src/deep"
  cd "$WORK/src/deep"
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [ -d "$WORK/.epico" ] && [ ! -e "$WORK/.epic" ]
}

@test "--hook: silent with nothing to do, one line when it moves, exit 0 even when blocked" {
  mkdir -p "$WORK/.epico"
  run bash "$MIG" --root "$WORK" --hook
  [ "$status" -eq 0 ] && [ -z "$output" ]
  rm -rf "$WORK/.epico"
  legacy_layout
  CLAUDE_PROJECT_DIR="$WORK" run bash "$MIG" --hook
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
  [[ "$output" == "Epico: moved $WORK/.epic/ to $WORK/.epico/"* ]]
  mkdir -p "$WORK/.epic"
  run bash "$MIG" --root "$WORK" --hook
  [ "$status" -eq 0 ]
  [[ "$output" == "Epico: both "* ]]
}

@test "the doctor names a legacy layout as an error that points at the migration" {
  legacy_layout
  cd "$WORK"
  run bash "$ROOT/scripts/doctor.sh"
  echo "$output" | jq -e '.status == "legacy" and .findings[0].check == "legacy-layout" and (.findings[0].detail | test("epico-migrate-dir"))'
  run bash "$ROOT/scripts/doctor.sh" --summary
  [[ "$output" == "epico-doctor: 1 error(s)"*"epico-migrate-dir"* ]]
}

@test "the index regenerates over legacy markers without a second block" {
  mkdir -p "$WORK/.epico/stories"
  printf '# Index\n\n<!-- epic:index:start -->\nold\n<!-- epic:index:end -->\n\nafter\n' > "$WORK/.epico/EPICO.md"
  run bash "$ROOT/scripts/epico-index.sh" --epico-dir "$WORK/.epico"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'index:start' "$WORK/.epico/EPICO.md")" -eq 1 ]
  grep -qx '<!-- epico:index:start -->' "$WORK/.epico/EPICO.md"
  grep -qx 'after' "$WORK/.epico/EPICO.md"
}

@test "the CLAUDE.md block replaces a legacy block instead of appending a second one" {
  mkdir -p "$WORK/.epico"
  printf '# Mine\n\n<!-- epic:start — managed by the Epic plugin -->\nold\n<!-- epic:end -->\n\ntail\n' > "$WORK/CLAUDE.md"
  run bash "$ROOT/scripts/claude-md.sh" write --root "$WORK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "replaced"'
  [ "$(grep -c ':start' "$WORK/CLAUDE.md")" -eq 1 ]
  [ "$(grep -c 'epic:' "$WORK/CLAUDE.md")" -eq 0 ]
  grep -qx 'tail' "$WORK/CLAUDE.md"
}
