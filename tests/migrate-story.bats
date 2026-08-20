#!/usr/bin/env bats
# Contract tests for scripts/migrate-story.sh (story 015 — migrate and the
# Commit field). Authored Red-first by the Test Advisor from the EARS
# requirements (R1.1-R1.5) and the design.md contract — never from any ToDo.
# Target location after materialization: tests/migrate-story.bats
#
# Contract under test (design.md, Component 1):
#   migrate-story.sh <NNN|story-dir> [--apply]
#   - Dry-run is the DEFAULT (R1.1): ONE JSON object on stdout
#     {story, applied:false, changed_files, rewrites:{t1_headers,
#      covers_fields, boxes_added, wrapper_tags, fast_requirements,
#      commit_subtasks}, validate:null}; unified diff on stderr; nothing
#     written. stdout stays pure JSON — the house contract.
#   - --apply (R1.2): atomic rewrite, CRLF preserved, then validate-story.sh
#     runs and its verdict {errors, warnings, status} is embedded.
#   - Refusals (R1.3): .epic/archive/** target -> exit 1, reason on stderr,
#     applied:false JSON intact. Exit 2 = usage.
#   - Idempotency by grammar (R1.4): second --apply reports zero rewrites and
#     produces no diff. Never a marker file.
#   - version: bumps only in changed artifacts (R1.5).
#
# Test names are prefixed with the sub-task number ("1.1:"/"1.2:") so
# Red/Green evidence is producible per sub-task via `bats --filter '^1\.1:'`.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MIGRATE_SH="$PLUGIN_ROOT/scripts/migrate-story.sh"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  mkdir -p "$PROJ/.epic/stories" "$PROJ/.epic/archive"
  cd "$PROJ"
}

teardown() {
  cd /
  chmod -R u+rwX "$WORK" 2>/dev/null || true
  rm -rf "$WORK"
}

# Deterministic hash of every file in a tree — "byte-identical" made checkable.
tree_hash() {
  (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) | sha256sum | cut -d' ' -f1
}

# make_t1_story <dir-name> [parent-dir] — variant-1 (T1/Covers) fixture.
# The legacy shape lives in tasks.md ONLY; story.md is canonical, so the
# R1.5 version-bump scoping (changed vs untouched artifact) is observable.
make_t1_story() {
  local dir="${2:-$PROJ/.epic/stories}/$1"
  mkdir -p "$dir"
  cat > "$dir/story.md" <<'EOF'
---
story: fixture
type: feature
scale: standard
version: 1
created: 2026-08-16
status: in-progress
---

# Story - fixture

## Requirements

### R1. Fixture requirement

#### Acceptance Criteria

- R1.1: WHEN invoked THE SYSTEM SHALL parse the input
- R1.2: WHEN done THE SYSTEM SHALL emit the output
EOF
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
scale: standard
status: in-progress
---

# Implementation Plan - fixture

## Task List

## T1 Parse the input

Some prose describing the work.

**Covers:** R1.1

## T2 Emit the output

Covers: R1.2

## Quality Gates

- [ ] All task validations pass
EOF
}

# make_crlf_story <dir-name> — CRLF tasks.md carrying one naked wrapper tag
# (variant 3), so a rewrite MUST happen and the surviving bytes prove R1.2's
# line-ending preservation.
make_crlf_story() {
  local dir="$PROJ/.epic/stories/$1"
  mkdir -p "$dir"
  printf '%s\r\n' \
    '---' \
    'version: 1' \
    'created: 2026-08-16' \
    'scale: standard' \
    'status: in-progress' \
    '---' \
    '' \
    '# Implementation Plan - crlf fixture' \
    '' \
    '## Task List' \
    '' \
    '- [ ] 1 - Canonical thing' \
    '  - Validation: ok' \
    '  - Requirements: R1.1' \
    '' \
    '</content>' \
    '' \
    '## Quality Gates' \
    '' \
    '- [ ] All task validations pass' \
    > "$dir/tasks.md"
}

# --- 1.1 Skeleton: dry-run, JSON verdict, refusal arms (R1.1, R1.3) ---

@test "1.1: dry-run stdout is one JSON object — applied:false, validate:null, all six rewrite counters" {
  make_t1_story 090-t1-fixture
  run --separate-stderr bash "$MIGRATE_SH" .epic/stories/090-t1-fixture
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'type == "object" and .applied == false and .validate == null' > /dev/null
  echo "$output" | jq -e '.rewrites | has("t1_headers") and has("covers_fields") and has("boxes_added") and has("wrapper_tags") and has("fast_requirements") and has("commit_subtasks")' > /dev/null
}

@test "1.1: dry-run detects the variant, writes the unified diff to stderr, and leaves the tree byte-identical" {
  make_t1_story 090-t1-fixture
  local before
  before=$(tree_hash "$PROJ")
  run --separate-stderr bash "$MIGRATE_SH" .epic/stories/090-t1-fixture
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.rewrites.t1_headers + .rewrites.covers_fields) > 0' > /dev/null
  echo "$output" | jq -e '.changed_files | length > 0' > /dev/null
  [[ "$stderr" == *'@@'* ]]
  [ "$(tree_hash "$PROJ")" = "$before" ]
}

@test "1.1: a story under .epic/archive/ is refused — exit 1, reason on stderr, applied:false JSON intact, nothing written" {
  make_t1_story 090-t1-fixture "$PROJ/.epic/archive"
  local before
  before=$(tree_hash "$PROJ")
  run --separate-stderr bash "$MIGRATE_SH" .epic/archive/090-t1-fixture
  [ "$status" -eq 1 ]
  [[ "$stderr" == *archive* ]]
  echo "$output" | jq -e '.applied == false' > /dev/null
  [ "$(tree_hash "$PROJ")" = "$before" ]
}

@test "1.1: no arguments is a usage error — exit 2" {
  run --separate-stderr bash "$MIGRATE_SH"
  [ "$status" -eq 2 ]
}

# --- 1.2 Apply: embedded validate, idempotency, CRLF, version bump (R1.2, R1.4, R1.5) ---

@test "1.2: --apply rewrites and embeds the validate-story verdict" {
  make_t1_story 090-t1-fixture
  run --separate-stderr bash "$MIGRATE_SH" .epic/stories/090-t1-fixture --apply
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.applied == true' > /dev/null
  echo "$output" | jq -e '.validate | type == "object" and has("errors") and has("warnings") and has("status")' > /dev/null
  run ! grep -q '^## T1' "$PROJ/.epic/stories/090-t1-fixture/tasks.md"
}

@test "1.2: a second --apply reports zero rewrites and produces no diff — idempotency by grammar" {
  make_t1_story 090-t1-fixture
  bash "$MIGRATE_SH" .epic/stories/090-t1-fixture --apply > /dev/null 2>&1
  local mid
  mid=$(tree_hash "$PROJ")
  run --separate-stderr bash "$MIGRATE_SH" .epic/stories/090-t1-fixture --apply
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.rewrites[]] | add == 0' > /dev/null
  [[ "$stderr" != *'@@'* ]]
  [ "$(tree_hash "$PROJ")" = "$mid" ]
}

@test "1.2: CRLF line endings round-trip through --apply" {
  make_crlf_story 091-crlf
  bash "$MIGRATE_SH" .epic/stories/091-crlf --apply > /dev/null 2>&1
  local f="$PROJ/.epic/stories/091-crlf/tasks.md"
  run ! grep -qF '</content>' "$f"
  # every surviving line still ends CRLF — zero lines without a trailing \r
  [ "$(awk '!/\r$/' "$f" | wc -l)" -eq 0 ]
}

@test "1.2: version: bumps only in the changed artifact — the untouched sibling keeps its version" {
  make_t1_story 090-t1-fixture
  bash "$MIGRATE_SH" .epic/stories/090-t1-fixture --apply > /dev/null 2>&1
  grep -q '^version: 2' "$PROJ/.epic/stories/090-t1-fixture/tasks.md"
  grep -q '^version: 1' "$PROJ/.epic/stories/090-t1-fixture/story.md"
}

# --- Refine delta (cross-artifact review): refusal arms + exit-0 pin ---

# make_mixture_story <dir-name> — an unparseable mixture: a T1 header and a
# Covers: field interleaved INSIDE a canonical group, so no detector can
# classify the lines without guessing ownership. R1.3: migrate never guesses.
make_mixture_story() {
  local dir="$PROJ/.epic/stories/$1"
  mkdir -p "$dir"
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
scale: standard
status: in-progress
---

# Implementation Plan - unparseable mixture

## Task List

- [ ] 1 - Canonical group
## T1 Interleaved header claiming the same slot
  - [ ] 1.1 - Whose sub-task is this
**Covers:** R1.1
  - Validation: ok

## Quality Gates

- [ ] All task validations pass
EOF
}

# make_badstatus_wrapper_story <dir-name> — a wrapper-tag variant (so a
# rewrite MUST happen) beside an INDEPENDENT validation error migrate cannot
# and must not fix: a status value outside the lifecycle enum. Calibrated
# against the live validator: `status: bogus` reports 2 errors today.
make_badstatus_wrapper_story() {
  local dir="$PROJ/.epic/stories/$1"
  mkdir -p "$dir"
  cat > "$dir/story.md" <<'EOF'
---
story: fixture
type: feature
scale: standard
version: 1
created: 2026-08-16
status: bogus
---

# Story - fixture

## Requirements

### R1. Fixture requirement

#### Acceptance Criteria

- R1.1: WHEN invoked THE SYSTEM SHALL do the thing
EOF
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
scale: standard
status: bogus
---

# Implementation Plan - calibrated failing validate

## Task List

- [ ] 1 - Canonical thing
  - Validation: ok
  - Requirements: R1.1

</content>

## Quality Gates

- [ ] All task validations pass
EOF
}

@test "1.1: an unparseable mixture is refused — exit 1, offending lines named, applied:false JSON, tree byte-identical" {
  make_mixture_story 092-mixture
  local before
  before=$(tree_hash "$PROJ")
  run --separate-stderr bash "$MIGRATE_SH" .epic/stories/092-mixture --apply
  [ "$status" -eq 1 ]
  # the refusal NAMES the offending lines — migrate never guesses
  [[ "$stderr" =~ [Ll]ine|:[0-9]+ ]]
  echo "$output" | jq -e '.applied == false' > /dev/null
  [ "$(tree_hash "$PROJ")" = "$before" ]
}

@test "1.1: an unknown story number is refused — exit 1, reason on stderr" {
  run --separate-stderr bash "$MIGRATE_SH" 999
  [ "$status" -eq 1 ]
  [ -n "$stderr" ]
  [[ "$stderr" == *999* ]]
}

@test "1.1: an unreadable file refuses before any partial diff is emitted" {
  if [ "$EUID" -eq 0 ]; then
    skip "root reads through chmod 000"
  fi
  make_t1_story 093-unreadable
  chmod 000 "$PROJ/.epic/stories/093-unreadable/tasks.md"
  run --separate-stderr bash "$MIGRATE_SH" .epic/stories/093-unreadable
  [ "$status" -eq 1 ]
  [ -n "$stderr" ]
  # the refusal is the whole story: no truncated diff sneaks out first
  [[ "$stderr" != *'@@'* ]]
}

@test "1.2: a failing embedded validate keeps exit 0 — the verdict is the channel, never the exit code" {
  make_badstatus_wrapper_story 094-badstatus
  run --separate-stderr bash "$MIGRATE_SH" .epic/stories/094-badstatus --apply
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.applied == true and ([.rewrites[]] | add >= 1)' > /dev/null
  echo "$output" | jq -e '.validate.errors >= 1' > /dev/null
  # the rewrite stands — no rollback because the validator complained
  run ! grep -qF '</content>' "$PROJ/.epic/stories/094-badstatus/tasks.md"
}
