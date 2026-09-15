#!/usr/bin/env bats
# Integration round-trip for story 015 (sub-task 4.2): one story carrying all
# five legacy variants migrates to a clean embedded validate in ONE --apply,
# the second apply is a proven no-op (R1.4), and a migrated field-form story
# archives with manifest counters derived from the boxes that exist (R4.2).
# Authored Red-first by the Test Advisor from the EARS requirements and the
# design.md contract — never from any ToDo.
# Target location after materialization: tests/migrate-roundtrip.bats
#
# The all-variants fixture is a FAST tasks-only story on purpose: fast scale
# is the only shape that can carry variant 4 (dangling Requirements) while
# variants 1, 2, 3 and 5 ride along in the same file — one story, all five,
# per the sub-task objective. The archive leg uses a standard complete story
# whose commit point is a CLOSED Commit checkbox pre-migration, so the
# counter delta (exactly one box fewer) is attributable to the conversion.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MIGRATE_SH="$PLUGIN_ROOT/scripts/migrate-story.sh"
  ARCHIVE_SH="$PLUGIN_ROOT/scripts/archive-story.sh"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  mkdir -p "$PROJ/.epic/stories" "$PROJ/.epic/archive"
  cd "$PROJ"
}

teardown() {
  cd /
  rm -rf "$WORK"
}

tree_hash() {
  (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) | sha256sum | cut -d' ' -f1
}

box_count() {
  grep -cE '^[[:space:]]*- \[[x~ ]\]' "$1"
}

# All five variants in one fast tasks-only story:
#   variant 1 — `## T1` header + `**Covers:**` field
#   variant 2 — checkbox-less `- 2 - ...` item
#   variant 3 — naked `</content>` (and a fenced `</invoke>` that must survive)
#   variant 4 — dangling `- Requirements: R3.9` (fast scale) + a
#               `satisfied-by:` suffix that must survive byte-for-byte
#   variant 5 — `[x] 3.2 - Commit` sub-task
make_all_variants_story() {
  local dir="$PROJ/.epic/stories/$1"
  mkdir -p "$dir"
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
scale: fast
status: in-progress
---

# Implementation Plan - all five variants

## Task List

## T1 Parse the corpus

Prose for the first section.

**Covers:** R1.1

- 2 - Checkbox-less thing
  - Validation: ok
  - Requirements: R2.1 (satisfied-by: tests/thing.bats)

- [ ] 3 - Canonical group
  - Objective: Close the loop

  - [ ] 3.1 - Do it
    - Validation: ok
    - Requirements: R3.9

  - [x] 3.2 - Commit
    - Validation: 3.1 passes
    - Commit: "feat(090): everything at once"

</content>

Documentation of the leak shapes, fenced on purpose:

```markdown
</invoke>
## T1 Fenced example
```

## Quality Gates

- [ ] All task validations pass
EOF
}

# Standard, complete, archivable story whose only legacy shape is a CLOSED
# Commit checkbox — the R4.2 counter fixture.
make_complete_commit_story() {
  local dir="$PROJ/.epic/stories/$1"
  mkdir -p "$dir"
  cat > "$dir/story.md" <<'EOF'
---
story: field-form
type: feature
scale: standard
version: 1
created: 2026-08-16
status: done
---

# Story - field form fixture

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
status: done
---

# Implementation Plan - field form fixture

## Task List

- [x] 1 - First group
  - Objective: fixture

  - [x] 1.1 - Done thing
    - Validation: ok
    - Requirements: R1.1

  - [x] 1.2 - Commit
    - Validation: 1.1 passes
    - Commit: "feat(091): first group"

- [x] 2 - Second done thing
  - Validation: ok
  - Requirements: R1.1
EOF
}

# --- 4.2 All-variants integration round-trip (R1.4, R4.2) ---

@test "4.2: one --apply migrates all five variants and embeds a clean validate" {
  make_all_variants_story 090-all-variants
  run --separate-stderr bash "$MIGRATE_SH" .epic/stories/090-all-variants --apply
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.applied == true' > /dev/null
  # every one of the six counters fired — all five variants were seen
  echo "$output" | jq -e '.rewrites | (.t1_headers > 0) and (.covers_fields > 0) and (.boxes_added > 0) and (.wrapper_tags > 0) and (.fast_requirements > 0) and (.commit_subtasks > 0)' > /dev/null
  # the migration is proven by the validator it triggers
  echo "$output" | jq -e '.validate.errors == 0 and .validate.status == "pass"' > /dev/null
  local f="$PROJ/.epic/stories/090-all-variants/tasks.md"
  # immunity lines, all honored in the same pass
  run ! grep -qF '</content>' "$f"
  grep -qF '</invoke>' "$f"
  grep -qF '## T1 Fenced example' "$f"
  grep -qF 'satisfied-by: tests/thing.bats' "$f"
  run ! grep -q 'R3\.9' "$f"
  run ! grep -qE '\[[x~ ]\][[:space:]]+3\.2[[:space:]]+-[[:space:]]+Commit' "$f"
  grep -qF -- '- Commit: "feat(090): everything at once"' "$f"
}

@test "4.2: the second apply reports zero rewrites and no diff — the tree does not move" {
  make_all_variants_story 090-all-variants
  bash "$MIGRATE_SH" .epic/stories/090-all-variants --apply > /dev/null 2>&1
  local mid
  mid=$(tree_hash "$PROJ")
  run --separate-stderr bash "$MIGRATE_SH" .epic/stories/090-all-variants --apply
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.rewrites[]] | add == 0' > /dev/null
  [[ "$stderr" != *'@@'* ]]
  [ "$(tree_hash "$PROJ")" = "$mid" ]
}

@test "4.2: a migrated field-form story archives with counters derived from the boxes that exist" {
  make_complete_commit_story 091-field-form
  local f="$PROJ/.epic/stories/091-field-form/tasks.md"
  local pre post
  pre=$(box_count "$f")
  bash "$MIGRATE_SH" .epic/stories/091-field-form --apply > /dev/null 2>&1
  post=$(box_count "$f")
  # exactly the Commit box left the census — and only it
  [ "$post" -eq $((pre - 1)) ]
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/091-field-form
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "archived"' > /dev/null
  # manifest counters derive from the boxes that exist, not from ritual
  echo "$output" | jq -e --argjson n "$post" '.tasks.total == $n and .tasks.closed == $n and .tasks.open == 0' > /dev/null
}
