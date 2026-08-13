#!/usr/bin/env bats
# Contract tests for the secrets guard's allowlist anchoring
# (story 009 - root-anchored-secrets-scan).
# Authored Red-first from EARS requirements + design contract.
# Target location after materialization: tests/secrets-allowlist.bats
#
# Contract under test (design.md, Components 1-3):
#   The guard expresses its scan source RELATIVE to a resolved project root, so
#   every gitleaks Fingerprint is project-root-relative and a committed
#   .gitleaksignore can match it. The resolved root is reported as
#   `secrets.allowlist_root` — a TOTAL key, null when no allowlist governed the
#   scan. An unresolvable root falls back to today's absolute scan and says so;
#   it never scans less.
#
#   Root resolution: git top level first (gitleaks specifies .gitleaksignore at
#   the repository root), then the nearest ancestor owning `.epic/`, then none.
#
# EVERY case here is Integration, and that is a property of the subject, not a
# shortcut: archive-story.sh executes on invocation and cannot be sourced, so
# secrets_project_root() is observable only through the guard's output.
#
# THE FIXTURES ARE REAL AWS-SHAPED LITERALS ON PURPOSE. A key gitleaks ignores
# would make every suppression case below a tautology — the same reasoning the
# repository's own .gitleaksignore header already records. They authenticate
# against nothing and exist only here.
#
# Test names are prefixed with the sub-task number so Red/Green evidence can be
# produced per sub-task via `bats --filter '^1\.2:'`.

bats_require_minimum_version 1.5.0

# An AWS-access-key-SHAPED string. Not a credential; see the header.
FIXTURE_KEY_A='AKIAQWERTYUIOPASDFGH'
FIXTURE_KEY_B='AKIAZXCVBNMLKJHGFDSA'

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ARCHIVE_SH="$PLUGIN_ROOT/scripts/archive-story.sh"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  mkdir -p "$PROJ/.epic/stories"
  cd "$PROJ"
}

teardown() {
  cd /
  chmod -R u+rwX "$WORK" 2>/dev/null || true
  rm -rf "$WORK"
}

# make_story <dir-name> — a complete story the archive would accept.
# Deliberately the same fixture shape as tests/archive-story.bats, so a case
# that blocks here blocks for the secrets guard and for nothing else.
make_story() {
  local dir="$PROJ/.epic/stories/$1"
  mkdir -p "$dir"
  cat > "$dir/story.md" <<EOF
---
story: ${1#*-}
type: feature
scale: standard
version: 1
created: 2026-08-01
status: done
---

# Story - fixture
EOF
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-01
---

## Task List
- [x] 1 - First done thing
  - Validation: ok
- [x] 2 - Second done thing
  - Validation: ok
EOF
}

# git_init_isolated <dir> — a git repository with NO influence from the machine.
# Story 007 established why every variable here is needed: GIT_CONFIG_GLOBAL
# alone does not do it, because a global ignore commonly arrives through the XDG
# path rather than through core.excludesFile, and the init template carries its
# own info/exclude. A leaked global ignore would change what gitleaks sees.
git_init_isolated() {
  local dir=$1
  # The template directory must EXIST and be empty. Pointing at a missing path
  # works but makes git warn on stderr, and a diagnostic nobody asked for is
  # noise a later reader will spend time on.
  mkdir -p "$WORK/faketemplate" "$WORK/fakehome" "$WORK/fakexdg" "$dir"
  ( cd "$dir" \
    && HOME="$WORK/fakehome" \
       XDG_CONFIG_HOME="$WORK/fakexdg" \
       GIT_CONFIG_NOSYSTEM=1 \
       GIT_TEMPLATE_DIR="$WORK/faketemplate" \
       git init -q . ) || return 1
}

# put_secret <story-dir> <file> <key>
put_secret() {
  printf 'aws_access_key_id = "%s"\n' "$3" > "$PROJ/.epic/stories/$1/$2"
}

# classify <story-dir> <file> <line> — pin a finding in the PROJECT's allowlist,
# written project-root-relative, which is the form gitleaks documents and the
# form this story exists to make matchable.
classify() {
  printf '.epic/stories/%s/%s:aws-access-token:%s\n' "$1" "$2" "$3" \
    >> "$PROJ/.gitleaksignore"
}

require_gitleaks() {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
}

# ---------------------------------------------------------------------------
# 1.1 — Root resolution (R1.1, R1.2, R1.3, R1.4, R3.2)
# Observable only through `secrets.allowlist_root`, per the header.
# ---------------------------------------------------------------------------

@test "1.1: a git-rooted project resolves the git top level as the allowlist root" {
  require_gitleaks
  git_init_isolated "$PROJ"
  make_story 010-clean
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/010-clean
  [ "$status" -eq 0 ]
  # `pwd -P` because the guard normalises physically and mktemp may hand back a
  # symlinked path on some platforms — comparing the raw $PROJ would test the
  # harness, not the guard.
  echo "$output" | jq -e --arg root "$(cd "$PROJ" && pwd -P)" \
    '.secrets.allowlist_root == $root' > /dev/null
}

@test "1.1: a non-git project resolves the directory that owns .epic/" {
  require_gitleaks
  make_story 010-clean
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/010-clean
  [ "$status" -eq 0 ]
  echo "$output" | jq -e --arg root "$(cd "$PROJ" && pwd -P)" \
    '.secrets.allowlist_root == $root' > /dev/null
}

@test "1.1: a root that resolves without containing the story falls back, and says so" {
  require_gitleaks
  # The REACHABLE half of R3.1. "No root at all" cannot be produced from the
  # command line — the entry point refuses a story outside `.epic/` at exit 2,
  # before the guard runs — so this is the half a test can honestly cover.
  # An inherited git environment is how it happens in the wild: a git hook
  # exports GIT_DIR and GIT_WORK_TREE, and the guard would then resolve a top
  # level that has nothing to do with the story it is scanning.
  git_init_isolated "$WORK/elsewhere_init"
  make_story 010-elsewhere
  put_secret 010-elsewhere creds.md "$FIXTURE_KEY_A"
  GIT_DIR="$WORK/elsewhere_init/.git" GIT_WORK_TREE="$WORK/elsewhere_init" \
    run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/010-elsewhere
  # The scan still happens and still reports — the fallback never scans less.
  echo "$output" | jq -e '.secrets.scanned == true' > /dev/null
  echo "$output" | jq -e '.secrets.findings == 1' > /dev/null
  # `has()` AND the null check together: `== null` alone passes today, because
  # jq renders an absent key and a null key identically. That is the exact trap
  # story 008 documented, and asserting only the second half would make this
  # case green against code that never emits the key at all.
  echo "$output" | jq -e '.secrets | has("allowlist_root")' > /dev/null
  echo "$output" | jq -e '.secrets.allowlist_root == null' > /dev/null
}

@test "1.1: a git project reached through a symlink still resolves and still suppresses" {
  require_gitleaks
  # R1.4 in one case. `git rev-parse --show-toplevel` may answer with a LOGICAL
  # path while STORY_ABS is physical; without normalising both, the prefix strip
  # fails and this project silently degrades to the unanchored fallback.
  git_init_isolated "$PROJ"
  make_story 010-linked
  put_secret 010-linked creds.md "$FIXTURE_KEY_A"
  classify 010-linked creds.md 1
  ln -s "$PROJ" "$WORK/link"
  cd "$WORK/link"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/010-linked
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.secrets.findings == 0' > /dev/null
  echo "$output" | jq -e '.secrets.allowlist_root != null' > /dev/null
}

# ---------------------------------------------------------------------------
# 1.2 — Suppression and coverage (R1.1, R2.1, R2.2, R3.3)
# ---------------------------------------------------------------------------

@test "1.2: a fingerprint classified in the project allowlist no longer blocks the archive" {
  require_gitleaks
  make_story 010-classified
  put_secret 010-classified creds.md "$FIXTURE_KEY_A"
  classify 010-classified creds.md 1
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/010-classified
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "archived"' > /dev/null
  echo "$output" | jq -e '.secrets.findings == 0' > /dev/null
  echo "$output" | jq -e '.secrets.scanned == true' > /dev/null
  [ -d "$PROJ/.epic/archive/010-classified" ]
}

@test "1.2: a classified fixture beside an unclassified secret still blocks, reporting only the real one" {
  require_gitleaks
  # THE case this story exists for. Without it, "the allowlist works" and "the
  # guard was switched off" produce identical evidence. Suppression must be
  # per-finding, never per-story.
  make_story 010-mixed
  put_secret 010-mixed fixture.md "$FIXTURE_KEY_A"
  put_secret 010-mixed real.md "$FIXTURE_KEY_B"
  classify 010-mixed fixture.md 1
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/010-mixed
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked"' > /dev/null
  echo "$output" | jq -e '.secrets.findings == 1' > /dev/null
  echo "$output" | jq -e '.moved == false' > /dev/null
  [ -d "$PROJ/.epic/stories/010-mixed" ]
  [ ! -d "$PROJ/.epic/archive/010-mixed" ]
}

@test "1.2: re-rooting does not shrink the scan — every finding survives when nothing is classified" {
  require_gitleaks
  # The fail-open pin, expressed through the only channel the contract exposes:
  # a file gitleaks skips contributes no finding. Three distinct secrets, in
  # three files, at three depths, with NO allowlist present — the anchored scan
  # must report exactly what the unanchored one did.
  make_story 010-coverage
  mkdir -p "$PROJ/.epic/stories/010-coverage/.draft/nested"
  put_secret 010-coverage top.md "$FIXTURE_KEY_A"
  printf 'aws_access_key_id = "%s"\n' "$FIXTURE_KEY_B" \
    > "$PROJ/.epic/stories/010-coverage/.draft/nested/deep.md"
  printf 'aws_access_key_id = "%s"\n' "$FIXTURE_KEY_A" \
    > "$PROJ/.epic/stories/010-coverage/.draft/mid.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/010-coverage
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.secrets.findings == 3' > /dev/null
}

@test "1.2: a .gitignore covering the story does not reduce what the guard reads" {
  require_gitleaks
  # The specific fail-open this fix could introduce: `gitleaks dir` does not
  # honour .gitignore today, which is why re-rooting is safe. If a future
  # gitleaks started honouring it, an anchored scan of a gitignored `.epic/`
  # would report a clean story that is not clean. This case reddens then,
  # instead of the guard disarming in silence.
  git_init_isolated "$PROJ"
  printf '.epic/\n' > "$PROJ/.gitignore"
  make_story 010-ignored
  put_secret 010-ignored creds.md "$FIXTURE_KEY_A"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/010-ignored
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.secrets.findings == 1' > /dev/null
}

@test "1.2: a project with no .gitleaksignore behaves exactly as before" {
  require_gitleaks
  # R2.2 — anchoring must be silent when there is nothing to apply.
  make_story 010-nolist
  put_secret 010-nolist creds.md "$FIXTURE_KEY_A"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/010-nolist
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.secrets.findings == 1' > /dev/null
  echo "$output" | jq -e '.secrets.error == null' > /dev/null
}

# ---------------------------------------------------------------------------
# 1.3 — Disclosure (R2.3, R3.1, R3.2)
# ---------------------------------------------------------------------------

@test "1.3: allowlist_root is null under --skip-secrets, because no allowlist governed a scan that did not happen" {
  require_gitleaks
  make_story 010-skipped
  put_secret 010-skipped creds.md "$FIXTURE_KEY_A"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/010-skipped --skip-secrets
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.secrets.scanned == false' > /dev/null
  # `has()` first, for the reason spelled out in the R3.1 fallback case: without
  # it, `== null` passes against code that never emits the key.
  echo "$output" | jq -e '.secrets | has("allowlist_root")' > /dev/null
  echo "$output" | jq -e '.secrets.allowlist_root == null' > /dev/null
}

@test "1.3: allowlist_root is present on every scanning path, never merely on the anchored one" {
  require_gitleaks
  # Totality. Story 008 established the rule: a consumer must branch on a key's
  # VALUE, never on its presence, because `jq -r` renders an absent key and a
  # null key identically. `has()` is the assertion that tells them apart.
  make_story 010-total
  put_secret 010-total creds.md "$FIXTURE_KEY_A"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/010-total
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.secrets | has("allowlist_root")' > /dev/null
}

@test "1.3: a story blocked before the scanner runs still reports an empty secrets object" {
  require_gitleaks
  # Unchanged behaviour, and the reason the new key must not leak into `{}`:
  # "blocked before anything looked" and "scanned and clean" must stay
  # distinguishable in a permanent record.
  make_story 010-cleanbin
  printf 'ab\0cd' > "$PROJ/.epic/stories/010-cleanbin/blob.dat"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/010-cleanbin
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.secrets == {}' > /dev/null
}
