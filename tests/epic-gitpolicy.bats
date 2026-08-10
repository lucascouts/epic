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

# --- Appended at story 007, task 4.1 -----------------------------------------
# WHAT THE SIX CASES ABOVE LEAVE UNPINNED, AND WHY IT MATTERED. A tech review of
# task 3.1 found two contract gaps, and BOTH FIXES ADDED A JSON KEY AFTER THIS
# FILE WAS FROZEN — `gitignore_source` on the git path, `policy` on the non-git
# one. Nothing above holds either. Until the four cases below, deleting either
# key left `bats tests/` entirely green while two reference documents went on
# instructing agents to read it. That is orphan wiring, and an untested claim is
# what story 004 measured and rejected.
#
# 1. `gitignore_source` (R4.1) answers WHICH exclude file matched, which the
#    boolean beside it cannot. Git consults three sources and
#    `gitignore_ignores_epic: true` fires for any of them, but only the
#    workspace-root `.gitignore` is a file init may offer to edit:
#    references/init-mode.md gates its removal offer on
#    `gitignore_source == ".gitignore"`, reports `.git/info/exclude` as a file
#    local to the clone that it does not touch, and treats anything else as the
#    user's global core.excludesFile, which governs every repository on the
#    machine. references/list-mode.md prints the same field verbatim in its
#    notice. So the first two cases pin the two answers the boolean conflates,
#    and each is written to stay GREEN under the other's regression — a pair
#    that dies together pins one fact, not two.
#
# 2. The `null` case asserts the jq TYPE, and that is the whole case.
#    `jq -r .gitignore_source` prints the same four letters for a JSON null, for
#    the STRING "null" — a path named "null", which a consumer's `!= null` test
#    would miss, and precisely why the script emits the literal bare — and for a
#    key that is not in the document at all. Three different objects, one
#    identical line of output, so the obvious assertion cannot tell the contract
#    from two regressions. `| type` separates the string from the other two and
#    `has()` separates absent from present; both are asserted.
#
# 3. `policy` on the non-git object (R4.3) is the one key the two specs
#    disagreed about — the task ToDo said `{git: false, verdict: "consistent"}`
#    "and nothing else", design.md's error-handling note also sketched `policy`
#    — and the script resolved it in design.md's favour, because the declared
#    policy is read from a plain file that needs no repository and withholding
#    it would force init, whose defining workspace is a folder nobody has
#    `git init`-ed yet, to grow a second parser for `.epic/.gitpolicy`.
#    "Nothing else" still governs the four MEASUREMENT keys, which stay absent
#    because nobody measured them and because a consumer reading one there
#    aborts under `set -u`. That case therefore pins the exact key SET, not just
#    the one key.
#
# FIXTURE ISOLATION, and why only these cases carry it. A global
# core.excludesFile ignoring `.epic` — or an XDG `~/.config/git/ignore`, which
# git reads with no config entry at all, and which is where this machine keeps
# its global rules — turns the "nothing ignores it" case into `true` with the
# developer's own home directory as the source, on one machine and not another.
# Measured: with a hostile `$XDG_CONFIG_HOME/git/ignore` the identical fixture
# reports `gitignore_source: "/…/home/.config/git/ignore"`. `isolate_git_env`
# points every exclude source git can consult at a directory that DOES NOT
# EXIST:
#   HOME + XDG_CONFIG_HOME  the global config, and the ignore file git finds at
#                           $XDG_CONFIG_HOME/git/ignore or $HOME/.config/git/
#                           ignore even when core.excludesFile is unset
#   GIT_CONFIG_NOSYSTEM     /etc/gitconfig, which may set core.excludesFile
#   GIT_TEMPLATE_DIR=       the init template, whose info/exclude is copied into
#                           every new repository
# GIT_CONFIG_GLOBAL is the more obvious spelling and is deliberately NOT used:
# redirecting HOME and XDG_CONFIG_HOME already covers every global config path,
# while GIT_CONFIG_GLOBAL would put a git >= 2.32 floor on this file for
# nothing. The directory is never created — git treats an absent HOME as an
# empty one, silently, measured — so the worktree under test stays pristine and
# the frozen `teardown` still reclaims everything under $WORK. The empty
# template is why the `.git/info/exclude` case creates that directory itself.

isolate_git_env() {
  export HOME="$WORK/.fixture-home"
  export XDG_CONFIG_HOME="$WORK/.fixture-home/.config"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_TEMPLATE_DIR=
}

init_isolated_repo() {
  isolate_git_env
  init_repo
}

@test "gitignore_source names the root .gitignore when the rule lives there" {
  init_isolated_repo
  make_epic_artifacts
  echo ".epic/" > "$WORK/.gitignore"
  git add .gitignore
  git commit -qm "root gitignore ignores .epic"
  run_lint
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . > /dev/null
  [ "$(echo "$output" | jq -r '.gitignore_ignores_epic')" = "true" ]
  # The one source init may offer to edit, and the only value that unlocks the
  # removal offer in references/init-mode.md step 5.3b.
  [ "$(echo "$output" | jq -r '.gitignore_source')" = ".gitignore" ]
}

@test "gitignore_source names .git/info/exclude when the rule lives there and the root .gitignore is innocent" {
  init_isolated_repo
  make_epic_artifacts
  # The root file EXISTS and says nothing about .epic. That is the shape a
  # consumer assuming ".gitignore" gets wrong: it would quote a line that is not
  # there, or delete one that is not the rule.
  printf 'node_modules/\n*.log\n' > "$WORK/.gitignore"
  # GIT_TEMPLATE_DIR is empty, so `git init` created no .git/info; a real
  # repository always has one, so the fixture makes it the way git would.
  mkdir -p "$WORK/.git/info"
  printf '.epic/\n' >> "$WORK/.git/info/exclude"
  git add .gitignore
  git commit -qm "the exclude rule is local to this clone"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.gitignore_ignores_epic')" = "true" ]
  [ "$(echo "$output" | jq -r '.gitignore_source')" = ".git/info/exclude" ]
}

@test "gitignore_source is JSON null, not the string 'null', when nothing ignores .epic" {
  init_isolated_repo
  make_epic_artifacts
  git commit -q --allow-empty -m "no exclude rule in any source"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.gitignore_ignores_epic')" = "false" ]
  # NOT `jq -r .gitignore_source`: that prints `null` for the contract, for a
  # quoted "null" string and for a deleted key alike. `type` rejects the string;
  # `has` rejects the deletion. The key is emitted on every git path, present
  # and null, which is what makes init's `null` row reachable.
  [ "$(echo "$output" | jq -r '.gitignore_source | type')" = "null" ]
  [ "$(echo "$output" | jq -r 'has("gitignore_source")')" = "true" ]
}

@test "non-git workspace reports the declared policy, and only the three total keys" {
  isolate_git_env
  mkdir -p "$WORK/.epic"
  # local-only, deliberately not the tracked-md the frozen case above writes:
  # the value has to be READ FROM THE FILE, and a hardcoded constant would
  # satisfy a fixture that reused the same spelling.
  echo "local-only" > "$WORK/.epic/.gitpolicy"
  run_lint
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . > /dev/null
  [ "$(echo "$output" | jq -r '.git')" = "false" ]
  [ "$(echo "$output" | jq -r '.policy')" = "local-only" ]
  [ "$(echo "$output" | jq -r '.verdict')" = "consistent" ]
  # "Show nothing" is R4.3's other half: the four measurement keys stay absent
  # because nothing measured them. `keys` is sorted, so this pins the SET rather
  # than the emission order, which is the emitter's business and not a contract
  # any consumer reads.
  [ "$(echo "$output" | jq -r 'keys | join(",")')" = "git,policy,verdict" ]
}
