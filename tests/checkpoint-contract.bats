#!/usr/bin/env bats
# The checkpoint mode's contract: the user's verdict before Epic's on judgment
# items, no recommended marker there, --auto stops before judgment, documents
# only through the doc writer, the record of every answer.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REF="$ROOT/references/checkpoint-mode.md"
}

has() {  # <extended regex> — case-insensitive, names the miss
  if ! command grep -Eqi -- "$1" "$REF"; then echo "checkpoint-mode.md does not carry: $1"; return 1; fi
}

@test "routed: the cascade arm, the dispatch row and the description" {
  command grep -qF '"checkpoint <N>"' "$ROOT/skills/epic/SKILL.md"
  command grep -qF '| **Checkpoint** | `/epic:epic checkpoint <N>` | Load [checkpoint-mode.md]' "$ROOT/skills/epic/SKILL.md"
}

@test "the user leads: verdict first on judgment items, no recommended marker, --auto stops before judgment" {
  has 'ask for the user.s verdict, and only then give Epic.s own reading'
  has 'carry \*\*no `\(Recommended\)` marker\*\*'
  has 'under `--auto` the checkpoint runs step 1, prints it, and stops before step 2'
  has 'headless: print every step.s evidence and proposed answers, write nothing'
}

@test "step 1 runs epic-checkpoint and handles every state it returns" {
  has 'run `epic-checkpoint --stage <N>`'
  for st in closed in-work unmapped mismatch open; do has "\`$st\` —"; done
  has 'unknown_ids'
}

@test "documents only through the doc writer; findings become stories only here; batch is printed, not run" {
  has 'only through the doc writer'
  has 'a finding becomes a story only here'
  has 'print the `stories create --batch` command for the stage; do not run it'
  has 'never code, never a story'
}

@test "the record keeps the user's verdict, Epic's reading and the final answer" {
  has '\.epic/checkpoints/<N>\.yaml'
  has '^    user: '
  has '^    epic: '
  has '^    final: '
  has 'follows the project.s `\.epic/\.gitpolicy`'
}
