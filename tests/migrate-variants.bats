#!/usr/bin/env bats
# Variant-rewriter tests for scripts/migrate-story.sh (story 015). Authored
# Red-first by the Test Advisor from the EARS requirements (R2.1-R2.4) and the
# design.md variant table — never from any ToDo.
# Target location after materialization: tests/migrate-variants.bats
#
# Contract under test (design.md, Component 2 — one pass, one detector table):
#   1. `## T1`/`### T2` headers + `**Covers:**`/`Covers:` fields -> canonical
#      `- [ ] N - Name` boxes + `- Requirements:` lines (R2.1)
#   2. checkbox-less task lists -> boxes added as `[ ]` ONLY — migrate records
#      shape and never invents done-ness (R2.2)
#   3. leaked `</content>`/`</invoke>` wrapper tags: stripped outside fences,
#      documentation inside them (R2.3)
#   4. `Requirements:` fields and R-tokens removed when the RESOLVED scale
#      (tasks.md authoritative) is fast/spike; any `satisfied-by:` suffix
#      survives byte-for-byte (R2.4)
#   Fence-immunity is the stated immunity line for variants 1 and 3.
#
# Test names carry the sub-task prefix ("2.1:"/"2.2:") for per-sub-task
# Red/Green evidence via `bats --filter '^2\.1:'`.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MIGRATE_SH="$PLUGIN_ROOT/scripts/migrate-story.sh"
  CROSSREF_SH="$PLUGIN_ROOT/scripts/cross-reference.sh"
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

# Canonical story.md carrying R1.1 and R1.2 — the chain the converted
# tasks.md must become traceable against.
write_story_md() {
  cat > "$1/story.md" <<'EOF'
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
}

# --- 2.1 Variants 1-2: T1/Covers house style, checkbox-less lists ---

make_bento_story() {
  local dir="$PROJ/.epic/stories/$1"
  mkdir -p "$dir"
  write_story_md "$dir"
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
scale: standard
status: in-progress
---

# Implementation Plan - bentoolkit shape

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

make_boxless_story() {
  local dir="$PROJ/.epic/stories/$1"
  mkdir -p "$dir"
  write_story_md "$dir"
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
scale: standard
status: in-progress
---

# Implementation Plan - checkbox-less shape

## Task List

- 1 - First thing
  - Validation: ok
  - Requirements: R1.1
- 2 - Second thing
  - Validation: ok
  - Requirements: R1.2

## Quality Gates

- [ ] All task validations pass
EOF
}

make_fenced_t1_story() {
  local dir="$PROJ/.epic/stories/$1"
  mkdir -p "$dir"
  write_story_md "$dir"
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
scale: standard
status: in-progress
---

# Implementation Plan - fenced T1

## Task List

## T1 Parse the input

**Covers:** R1.1

Documentation of the legacy shape this fixture is about:

```markdown
## T1 Example header
```

## Quality Gates

- [ ] All task validations pass
EOF
}

@test "2.1: T1 headers and Covers fields become canonical boxes with Requirements lines" {
  make_bento_story 090-bento
  bash "$MIGRATE_SH" .epic/stories/090-bento --apply > /dev/null 2>&1
  local f="$PROJ/.epic/stories/090-bento/tasks.md"
  grep -qE '^- \[ \] [0-9]+ - .*Parse the input' "$f"
  grep -qE '^- \[ \] [0-9]+ - .*Emit the output' "$f"
  grep -qE '^[[:space:]]*- Requirements: .*R1\.1' "$f"
  grep -qE '^[[:space:]]*- Requirements: .*R1\.2' "$f"
  run ! grep -qE '^#{2,3} T[0-9]' "$f"
  run ! grep -qi 'Covers:' "$f"
}

@test "2.1: the migrated bentoolkit story is visible to cross-reference.sh — status clean, non-empty mapping" {
  make_bento_story 090-bento
  bash "$MIGRATE_SH" .epic/stories/090-bento --apply > /dev/null 2>&1
  run --separate-stderr bash "$CROSSREF_SH" .epic/stories/090-bento
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "clean" and (.mapping | length > 0)' > /dev/null
}

@test "2.1: checkbox-less list items gain only [ ] boxes — never [x], and field lines stay fields" {
  make_boxless_story 091-boxless
  bash "$MIGRATE_SH" .epic/stories/091-boxless --apply > /dev/null 2>&1
  local f="$PROJ/.epic/stories/091-boxless/tasks.md"
  [ "$(grep -cE '^- \[ \] [0-9]+ - ' "$f")" -eq 2 ]
  run ! grep -qF '[x]' "$f"
  # the honest default: shape is recorded, done-ness is never invented
  grep -qF '  - Validation: ok' "$f"
  run ! grep -qE '^[[:space:]]*- \[[ x~]\] (Validation|Requirements):' "$f"
}

@test "2.1: a T1 header inside a fenced block is documentation and survives" {
  make_fenced_t1_story 092-fenced-t1
  bash "$MIGRATE_SH" .epic/stories/092-fenced-t1 --apply > /dev/null 2>&1
  local f="$PROJ/.epic/stories/092-fenced-t1/tasks.md"
  grep -qF '## T1 Example header' "$f"
  # the naked header converted; only the fenced occurrence remains
  [ "$(grep -c '^## T1' "$f")" -eq 1 ]
  grep -qE '^- \[ \] [0-9]+ - .*Parse the input' "$f"
}

# --- 2.2 Variants 3-4: wrapper tags, fast-scale Requirements ---

make_wrapper_story() {
  local dir="$PROJ/.epic/stories/$1"
  mkdir -p "$dir"
  write_story_md "$dir"
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
scale: standard
status: in-progress
---

# Implementation Plan - wrapper leak

## Task List

- [ ] 1 - Canonical thing
  - Validation: ok
  - Requirements: R1.1

</content>

Documentation of the leak shape:

```text
</invoke>
```

## Quality Gates

- [ ] All task validations pass
EOF
}

# Fast fixture is tasks-only (fast scale carries no story.md) and the scale
# is declared where resolution is authoritative: tasks.md frontmatter.
make_fast_story() {
  local dir="$PROJ/.epic/stories/$1"
  mkdir -p "$dir"
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
scale: fast
status: in-progress
---

# Implementation Plan - fast with dangling pointers

## Task List

- [ ] 1 - Thing with a sanctioned suffix
  - Validation: ok
  - Requirements: R1.1 (satisfied-by: tests/fixture.bats)
- [ ] 2 - Thing with a dangling pointer
  - Validation: ok
  - Requirements: R2.2

## Quality Gates

- [ ] All task validations pass
EOF
}

make_canonical_standard_story() {
  local dir="$PROJ/.epic/stories/$1"
  mkdir -p "$dir"
  write_story_md "$dir"
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-16
scale: standard
status: in-progress
---

# Implementation Plan - already canonical

## Task List

- [ ] 1 - First thing
  - _Complexity: Simple | Tests: None | Risks: None | Dependencies: None_
  - Validation: ok
  - Requirements: R1.1
  - Commit: "feat(093): first thing"
- [ ] 2 - Second thing
  - Validation: ok
  - Requirements: R1.2
  - Commit: "feat(093): second thing"

## Quality Gates

- [ ] All task validations pass
EOF
}

@test "2.2: a naked wrapper tag strips and a fenced one survives" {
  make_wrapper_story 093-wrapper
  run --separate-stderr bash "$MIGRATE_SH" .epic/stories/093-wrapper --apply
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rewrites.wrapper_tags > 0' > /dev/null
  local f="$PROJ/.epic/stories/093-wrapper/tasks.md"
  run ! grep -qF '</content>' "$f"
  grep -qF '</invoke>' "$f"
}

@test "2.2: a fast story loses Requirements fields and R-tokens, keeping satisfied-by byte-for-byte" {
  make_fast_story 094-fast
  run --separate-stderr bash "$MIGRATE_SH" .epic/stories/094-fast --apply
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rewrites.fast_requirements > 0' > /dev/null
  local f="$PROJ/.epic/stories/094-fast/tasks.md"
  # the sanctioned suffix survives byte-for-byte
  grep -qF 'satisfied-by: tests/fixture.bats' "$f"
  # the suffix-less field and its dangling R-token are gone
  run ! grep -qE '^[[:space:]]*- Requirements: R2\.2[[:space:]]*$' "$f"
  run ! grep -q 'R2\.2' "$f"
}

@test "2.2: a fully canonical standard story is a byte-identical no-op" {
  make_canonical_standard_story 095-standard
  local before
  before=$(tree_hash "$PROJ")
  run --separate-stderr bash "$MIGRATE_SH" .epic/stories/095-standard --apply
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.rewrites[]] | add == 0' > /dev/null
  [ "$(tree_hash "$PROJ")" = "$before" ]
  grep -qE '^[[:space:]]*- Requirements: R1\.1' "$PROJ/.epic/stories/095-standard/tasks.md"
}
