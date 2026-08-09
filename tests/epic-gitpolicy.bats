#!/usr/bin/env bats
# Story 007, Task 3.1 — scripts/epic-gitpolicy.sh contradiction lint.
# Contract (design §2, R4.1/R4.3): read-only script, run from the workspace
# root, emitting JSON:
#   {policy: tracked-md|local-only|undeclared, gitignore_ignores_epic: bool,
#    tracked_md: N, tracked_draft: N, verdict: consistent|contradiction|partial}
# Verdicts:
#   consistent    — reality matches the declared policy (or undeclared+untracked)
#   contradiction — tracked .epic files under an ignoring gitignore (kpranois),
#                   or tracked-md declared but gitignore blocks tracking
#   partial       — .draft/ files tracked, or subset tracking
# Non-git workspace: {git: false, verdict: "consistent"} and nothing else.
# Exit 0 always (except usage errors, 2). Uses real temp git repos — no
# mocked git state (fidelity: the lint's whole job is reading git reality).

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

init_repo() {
  cd "$WORK"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git config commit.gpgsign false
}

make_epic_artifacts() {
  mkdir -p "$WORK/.epic/stories/001-sample/.draft"
  cat > "$WORK/.epic/stories/001-sample/story.md" <<'EOF'
---
story: sample
version: 1
created: 2026-08-02
---
# Story
EOF
  cat > "$WORK/.epic/stories/001-sample/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-02
---
- [ ] 1 - Do it
EOF
  echo "wip note" > "$WORK/.epic/stories/001-sample/.draft/notes.md"
}

run_lint() {
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/epic-gitpolicy.sh"
}

@test "local-only policy with ignoring gitignore and nothing tracked is consistent" {
  init_repo
  make_epic_artifacts
  echo ".epic/" > "$WORK/.gitignore"
  echo "local-only" > "$WORK/.epic/.gitpolicy"
  git add .gitignore
  git commit -qm "init"
  run_lint
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . > /dev/null
  [ "$(echo "$output" | jq -r '.policy')" = "local-only" ]
  [ "$(echo "$output" | jq -r '.verdict')" = "consistent" ]
}

@test "tracked-md policy with tracked artifacts and .draft ignored is consistent" {
  init_repo
  make_epic_artifacts
  echo "tracked-md" > "$WORK/.epic/.gitpolicy"
  printf '.draft/\n*.wip\n' > "$WORK/.epic/.gitignore"
  git add .epic/.gitignore .epic/.gitpolicy .epic/stories/001-sample/story.md .epic/stories/001-sample/tasks.md
  git commit -qm "track epic artifacts"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.policy')" = "tracked-md" ]
  [ "$(echo "$output" | jq -r '.verdict')" = "consistent" ]
  [ "$(echo "$output" | jq -r '.tracked_md')" -gt 0 ]
  [ "$(echo "$output" | jq -r '.tracked_draft')" = "0" ]
}

@test "kpranois shape: tracked .epic files under an ignoring gitignore is a contradiction" {
  init_repo
  make_epic_artifacts
  echo ".epic/" > "$WORK/.gitignore"
  git add .gitignore
  git add -f .epic/stories/001-sample/story.md .epic/stories/001-sample/tasks.md
  git commit -qm "tracked through an ignoring gitignore"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.verdict')" = "contradiction" ]
  [ "$(echo "$output" | jq -r '.gitignore_ignores_epic')" = "true" ]
  [ "$(echo "$output" | jq -r '.tracked_md')" -gt 0 ]
}

@test "tracked .draft files yield verdict partial" {
  init_repo
  make_epic_artifacts
  echo "tracked-md" > "$WORK/.epic/.gitpolicy"
  git add .epic/.gitpolicy .epic/stories/001-sample/story.md \
    .epic/stories/001-sample/tasks.md .epic/stories/001-sample/.draft/notes.md
  git commit -qm "over-tracked: .draft in history"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.verdict')" = "partial" ]
  [ "$(echo "$output" | jq -r '.tracked_draft')" -gt 0 ]
}

@test "undeclared policy with nothing tracked is consistent" {
  init_repo
  make_epic_artifacts
  git commit -q --allow-empty -m "no epic tracking, no policy"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.policy')" = "undeclared" ]
  [ "$(echo "$output" | jq -r '.verdict')" = "consistent" ]
}

@test "non-git workspace reports git:false, verdict consistent, exit 0" {
  mkdir -p "$WORK/.epic"
  echo "tracked-md" > "$WORK/.epic/.gitpolicy"
  run_lint
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . > /dev/null
  [ "$(echo "$output" | jq -r '.git')" = "false" ]
  [ "$(echo "$output" | jq -r '.verdict')" = "consistent" ]
}
