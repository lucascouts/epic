#!/usr/bin/env bats
# Contract tests for scripts/epic-index.sh (story 005 - archive-in-the-flow).
# Authored Red-first by the Test Advisor from EARS requirements + design contract.
# Target location after materialization: tests/epic-index.bats
#
# Contract under test (design.md, Components 3):
#   epic-index.sh scans .epic/stories/ + .epic/archive/ and rewrites ONLY the
#   block between <!-- epic:index:start --> / <!-- epic:index:end --> in
#   .epic/EPIC.md - one row per story (number, slug, status, progress, link
#   resolving to the story's current location). Idempotent, stable ordering.
#   File absent -> created with markers when the project has >= 1 story.
#
# 4.2 scenarios integrate with the real scripts/archive-story.sh (no stub):
# archiving must retarget the story link, and an index-regen failure must
# never roll back the move.
#
# Test names are prefixed with the sub-task number so Red/Green evidence can
# be produced per sub-task via `bats --filter '^4\.1:'`.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INDEX_SH="$PLUGIN_ROOT/scripts/epic-index.sh"
  ARCHIVE_SH="$PLUGIN_ROOT/scripts/archive-story.sh"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  EPIC_MD="$PROJ/.epic/EPIC.md"
  mkdir -p "$PROJ/.epic/stories"
  cd "$PROJ"
}

teardown() {
  cd /
  chmod -R u+rwX "$WORK" 2>/dev/null || true
  rm -rf "$WORK"
}

# make_story <area:stories|archive> <dir-name> - complete story fixture
# (2 [x] + 1 [~], no [ ] remaining).
make_story() {
  local dir="$PROJ/.epic/$1/$2"
  mkdir -p "$dir"
  cat > "$dir/story.md" <<EOF
---
story: ${2#*-}
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
- [~] 3 - Deferred external thing
  - Validation: ok
EOF
}

# --- 4.1 Generator (R5.1, R5.3, R5.4) ---

@test "4.1: index lists stories with links resolving to their location" {
  make_story stories 001-alpha
  make_story archive 002-beta
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ -f "$EPIC_MD" ]
  grep -q 'epic:index:start' "$EPIC_MD"
  grep -q 'epic:index:end' "$EPIC_MD"
  # R5.1: every story present, link resolving to its current area.
  grep -q 'stories/001-alpha' "$EPIC_MD"
  grep -q 'archive/002-beta' "$EPIC_MD"
}

@test "4.1: content outside the generated markers is preserved unchanged" {
  make_story stories 001-alpha
  cat > "$EPIC_MD" <<'EOF'
# Hand-written program context

keep-me-above the block, byte for byte.

<!-- epic:index:start -->
| old stale row that must be regenerated away |
<!-- epic:index:end -->

keep-me-below the block, byte for byte.
EOF
  awk '/epic:index:start/{exit} {print}' "$EPIC_MD" > "$WORK/head.before"
  awk 'f{print} /epic:index:end/{f=1}' "$EPIC_MD" > "$WORK/tail.before"
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  # R5.3: everything outside the markers is byte-preserved...
  awk '/epic:index:start/{exit} {print}' "$EPIC_MD" > "$WORK/head.after"
  awk 'f{print} /epic:index:end/{f=1}' "$EPIC_MD" > "$WORK/tail.after"
  cmp -s "$WORK/head.before" "$WORK/head.after"
  cmp -s "$WORK/tail.before" "$WORK/tail.after"
  # ...while the block itself is regenerated.
  ! grep -q 'old stale row' "$EPIC_MD"
  grep -q 'stories/001-alpha' "$EPIC_MD"
}

@test "4.1: double regeneration with no state change produces no diff" {
  make_story stories 001-alpha
  make_story archive 002-beta
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  cp "$EPIC_MD" "$WORK/epic.snapshot"
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  # R5.4: second run is a byte-for-byte no-op.
  cmp -s "$EPIC_MD" "$WORK/epic.snapshot"
}

@test "4.1: absent index file is created with markers when a story exists" {
  make_story stories 001-alpha
  [ ! -e "$EPIC_MD" ]
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ -f "$EPIC_MD" ]
  grep -q 'epic:index:start' "$EPIC_MD"
  grep -q 'epic:index:end' "$EPIC_MD"
}

@test "4.1: no index file is created in a project with zero stories" {
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ ! -e "$EPIC_MD" ]
}

# --- 4.1 Generator, additive cases (written at execution) ---
# Each pins a behavior the authored block leaves unpinned and each was
# mutation-checked (break the fix -> case red -> restore -> green). Prefixed
# `4.1:` so they run inside the existing `--filter '^4\.1:'`.

# mk_story <area> <dir> [status] [extra-frontmatter-line] - story.md only.
mk_story() {
  local dir="$PROJ/.epic/$1/$2"
  mkdir -p "$dir"
  {
    echo '---'
    echo "story: ${2#*-}"
    echo 'type: feature'
    echo 'scale: standard'
    echo 'version: 1'
    echo 'created: 2026-08-01'
    if [ -n "${3:-}" ]; then echo "status: $3"; fi
    if [ -n "${4:-}" ]; then echo "$4"; fi
    echo '---'
    echo
    echo '# Story - fixture'
  } > "$dir/story.md"
}

# mk_tasks <area> <dir> - tasks.md body read from stdin.
mk_tasks() {
  local dir="$PROJ/.epic/$1/$2"
  mkdir -p "$dir"
  cat > "$dir/tasks.md"
}

# row_for <dir-name> - the generated row whose link points at that directory.
# Pure bash: no dependency on grep's flavor.
row_for() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *"/$1/"*) printf '%s' "$line"; return 0 ;;
    esac
  done < "$EPIC_MD"
  return 1
}

# link_order - every row's link target, in the order the file lists them.
link_order() {
  local line t out=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *'](stories/'*|*'](archive/'*) ;;
      *) continue ;;
    esac
    t="${line#*](}"
    t="${t%%)*}"
    out="$out$t "
  done < "$EPIC_MD"
  printf '%s' "$out"
}

# count_marker <token> - how many lines carry that marker token.
count_marker() {
  local line n=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *"$1"*) n=$((n + 1)) ;;
    esac
  done < "$EPIC_MD"
  printf '%s' "$n"
}

@test "4.1: rows are ordered by number, not lexicographically" {
  # Created out of order on purpose. The discriminator is the MIXED-WIDTH set:
  # a lexicographic sort puts 010/100 before 2 and 99, a numeric one does not.
  # (009 vs 010 alone proves nothing - both sorts agree on zero-padded pairs.)
  for d in 010-jay 100-century 2-two 009-india 99-nines; do
    mk_story stories "$d" draft
    mk_tasks stories "$d" <<'EOF'
- [x] 1 - done
EOF
  done
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(link_order)" = "stories/2-two/story.md stories/009-india/story.md stories/010-jay/story.md stories/99-nines/story.md stories/100-century/story.md " ]
}

@test "4.1: a story with no status frontmatter renders an em dash" {
  # The legacy case: 340+ corpus stories predate the status: field, and a
  # story.md with no frontmatter at all is the same class of legacy.
  mk_story stories 001-legacy
  mk_tasks stories 001-legacy <<'EOF'
- [x] 1 - done
EOF
  mkdir -p "$PROJ/.epic/stories/002-nofront"
  printf '# heading only, no frontmatter at all\n' > "$PROJ/.epic/stories/002-nofront/story.md"
  mk_tasks stories 002-nofront <<'EOF'
- [ ] 1 - open
EOF
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 001-legacy)" = "| 001 | [legacy](stories/001-legacy/story.md) | — | 1/1 | active |" ]
  [ "$(row_for 002-nofront)" = "| 002 | [nofront](stories/002-nofront/story.md) | — | 0/1 | active |" ]
}

@test "4.1: progress folds no unqualified tilde box into the closed count" {
  # make_story's fixture is 2 [x] + 1 [~] whose line carries NO qualifier
  # ("Deferred external thing" has no `deferred:` token), so per the 004
  # grammar that box counts in the total and closes nothing: 2/3.
  make_story stories 001-alpha
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 001-alpha)" = "| 001 | [alpha](stories/001-alpha/story.md) | done | 2/3 | active |" ]
}

@test "4.1: a deferred box is reported apart while a terminal one closes" {
  mk_story stories 001-owed done
  mk_tasks stories 001-owed <<'EOF'
- [x] 1 - a
- [x] 2 - b
- [~] 3 - vendor ships it (deferred: waiting on vendor)
EOF
  mk_story stories 002-dropped done
  mk_tasks stories 002-dropped <<'EOF'
- [x] 1 - a
- [x] 2 - b
- [~] 3 - not needed (waived: out of scope)
EOF
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 001-owed)" = "| 001 | [owed](stories/001-owed/story.md) | done | 2/3 (+1 deferred) | active |" ]
  [ "$(row_for 002-dropped)" = "| 002 | [dropped](stories/002-dropped/story.md) | done | 3/3 | active |" ]
}

@test "4.1: a superseded story renders the successor it points at" {
  mk_story stories 003-old superseded 'superseded-by: 010'
  mk_tasks stories 003-old <<'EOF'
- [x] 1 - a
EOF
  mk_story stories 010-new in-progress
  mk_tasks stories 010-new <<'EOF'
- [ ] 1 - a
EOF
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 003-old)" = "| 003 | [old](stories/003-old/story.md) | superseded by 010 | 1/1 | active |" ]
}

@test "4.1: a superseded-by pointing nowhere is rendered as missing" {
  # Resolution is numeric, so it also has to survive an archived successor
  # written with a different zero padding.
  mk_story stories 004-orphan superseded 'superseded-by: 042'
  mk_tasks stories 004-orphan <<'EOF'
- [x] 1 - a
EOF
  mk_story archive 007-elsewhere archived
  mk_tasks archive 007-elsewhere <<'EOF'
- [x] 1 - a
EOF
  mk_story stories 005-pointed superseded 'superseded-by: 7'
  mk_tasks stories 005-pointed <<'EOF'
- [x] 1 - a
EOF
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 004-orphan)" = "| 004 | [orphan](stories/004-orphan/story.md) | superseded by 042 (missing) | 1/1 | active |" ]
  [ "$(row_for 005-pointed)" = "| 005 | [pointed](stories/005-pointed/story.md) | superseded by 7 | 1/1 | active |" ]
}

@test "4.1: a non-NNN directory and a story without tasks.md still get a row" {
  # Neither may crash the generator, and neither may silently vanish: an index
  # that disagrees with the filesystem is the failure this generator ends.
  mkdir -p "$PROJ/.epic/stories/notes-scratch"
  printf 'scratch\n' > "$PROJ/.epic/stories/notes-scratch/README.md"
  mk_story stories 005-seed draft
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 005-seed)" = "| 005 | [seed](stories/005-seed/story.md) | draft | — | active |" ]
  [ "$(row_for notes-scratch)" = "| — | [notes-scratch](stories/notes-scratch/) | — | — | active |" ]
}

@test "4.1: markers adjacent to hand-written text keep their bytes exactly" {
  # No blank line above the start marker, none below the end marker, and NO
  # FINAL NEWLINE - the byte-level properties a line-based splice destroys.
  make_story stories 001-alpha
  head_txt='context line, nothing blank follows'$'\n'
  tail_txt='no blank line above, and no final newline'
  printf '%s<!-- epic:index:start -->\n| stale |\n<!-- epic:index:end -->\n%s' \
    "$head_txt" "$tail_txt" > "$EPIC_MD"
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  printf '%s' "$head_txt" > "$WORK/head.expect"
  head -c "${#head_txt}" "$EPIC_MD" > "$WORK/head.after"
  cmp -s "$WORK/head.expect" "$WORK/head.after"
  printf '%s' "$tail_txt" > "$WORK/tail.expect"
  tail -c "${#tail_txt}" "$EPIC_MD" > "$WORK/tail.after"
  cmp -s "$WORK/tail.expect" "$WORK/tail.after"
  # An off-by-one in either offset duplicates the marker it mis-attributes.
  [ "$(count_marker 'epic:index:start')" -eq 1 ]
  [ "$(count_marker 'epic:index:end')" -eq 1 ]
  [ "$(row_for 001-alpha)" = "| 001 | [alpha](stories/001-alpha/story.md) | done | 2/3 | active |" ]
}

@test "4.1: a start marker with no end marker refuses and writes nothing" {
  # Decided behavior: a broken pair is REFUSED (exit 1, file untouched).
  # Treating "no end marker" as "the block runs to EOF" would swallow the rest
  # of the document; inserting the missing marker would reinterpret
  # hand-written text as generated output. Both clobber, so neither is done.
  make_story stories 001-alpha
  cat > "$EPIC_MD" <<'EOF'
# Program notes
<!-- epic:index:start -->
| stale row |

Everything below here is hand-written and must survive.
EOF
  cp "$EPIC_MD" "$WORK/before"
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 1 ]
  cmp -s "$WORK/before" "$EPIC_MD"
  [[ "$stderr" == *"malformed"* ]]
  [[ "$stderr" == *"epic:index:end"* ]]
}

@test "4.1: an index with no markers gains the block and keeps its content" {
  # The adoption path for a project whose EPIC.md predates this script.
  make_story stories 001-alpha
  printf '# Program\n\nhand-written, keep me.\n' > "$EPIC_MD"
  cp "$EPIC_MD" "$WORK/before"
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  head -c "$(wc -c < "$WORK/before")" "$EPIC_MD" > "$WORK/head.after"
  cmp -s "$WORK/before" "$WORK/head.after"
  [ "$(count_marker 'epic:index:start')" -eq 1 ]
  [ "$(count_marker 'epic:index:end')" -eq 1 ]
  [ -n "$(row_for 001-alpha)" ]
  # ...and adopting it is idempotent, so it never appends a second block.
  cp "$EPIC_MD" "$WORK/snap"
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  cmp -s "$WORK/snap" "$EPIC_MD"
}

@test "4.1: a changed checkbox updates the row, outside bytes untouched" {
  make_story stories 001-alpha
  printf 'ABOVE\n' > "$EPIC_MD"
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 001-alpha)" = "| 001 | [alpha](stories/001-alpha/story.md) | done | 2/3 | active |" ]
  mk_tasks stories 001-alpha <<'EOF'
- [ ] 1 - reopened
- [x] 2 - Second done thing
- [~] 3 - Deferred external thing
EOF
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  # The block is a function of CURRENT disk state, not an append-once.
  [ "$(row_for 001-alpha)" = "| 001 | [alpha](stories/001-alpha/story.md) | done | 1/3 | active |" ]
  printf 'ABOVE\n' > "$WORK/above.expect"
  head -c 6 "$EPIC_MD" > "$WORK/above.after"
  cmp -s "$WORK/above.expect" "$WORK/above.after"
}

@test "4.1: --help exits 0 and an unknown flag exits 2, neither writing" {
  make_story stories 001-alpha
  run --separate-stderr bash "$INDEX_SH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"epic:index:start"* ]]
  [ ! -e "$EPIC_MD" ]
  run --separate-stderr bash "$INDEX_SH" --bogus
  [ "$status" -eq 2 ]
  [ ! -e "$EPIC_MD" ]
}

# --- 4.2 Archive integration (R5.2) - real archive-story.sh, no stub ---

@test "4.2: archiving a story retargets its index link into archive" {
  make_story stories 005-gamma
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  grep -q 'stories/005-gamma' "$EPIC_MD"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-gamma
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epic/archive/005-gamma" ]
  # R5.2: the regenerated row now resolves into .epic/archive/.
  grep -q 'archive/005-gamma' "$EPIC_MD"
  ! grep -q 'stories/005-gamma' "$EPIC_MD"
}

@test "4.2: index regen failure warns but the move stands" {
  make_story stories 005-delta
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  cp "$EPIC_MD" "$WORK/epic.snapshot"
  # Make EPIC.md unwritable for both write strategies (in-place and tmp+mv),
  # while stories/, archive/ and the manifest stay fully writable.
  mkdir -p "$PROJ/.epic/archive"
  chmod 444 "$EPIC_MD"
  chmod 555 "$PROJ/.epic"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-delta
  # Design: regen failure warns, never rolls back - the move completed.
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epic/archive/005-delta" ]
  [ ! -d "$PROJ/.epic/stories/005-delta" ]
  cmp -s "$EPIC_MD" "$WORK/epic.snapshot"
}

# --- 4.2 Archive integration, additive cases (written at execution) ---
# The authored failure case above is GREEN FOR THE WRONG REASON on its own: its
# fixture chmods EPIC.md read-only, so `cmp -s` against the snapshot is
# satisfied just as well by a step 8 that DOES NOT EXIST as by one that ran and
# failed. These cases close that gap and pin the decisions step 8 had to make.
# Each was mutation-checked (break the wiring -> red -> restore -> green).
# Prefixed `4.2:` so they run inside the existing `--filter '^4\.2:'`.

@test "4.2: archiving really regenerates the index and reports index ok" {
  # THE REPAIR of the false green: the same archive with EVERYTHING WRITABLE,
  # where the only way for EPIC.md's bytes to move is a regeneration that
  # actually happened. No absent step 8 can satisfy this.
  make_story stories 005-gamma
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  cp "$EPIC_MD" "$WORK/epic.before"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-gamma
  [ "$status" -eq 0 ]
  json="$output"
  # Reported STRUCTURALLY, where the orchestrator's jq can see it — a note only
  # on stderr is invisible to the consumer that acts on it.
  echo "$json" | jq -e '.index == "ok"' > /dev/null
  echo "$json" | jq -e '.status == "archived" and .moved == true' > /dev/null
  # ...and the file really moved. `run` + status, never a bare `! cmp`: an
  # inverted command is exempt from set -e and would assert nothing at all.
  run cmp -s "$WORK/epic.before" "$EPIC_MD"
  [ "$status" -ne 0 ]
  idx=$(cat "$EPIC_MD")
  [[ "$idx" == *"archive/005-gamma"* ]]
  [[ "$idx" != *"stories/005-gamma"* ]]
}

@test "4.2: index regeneration runs LAST, after the move and after the status" {
  # Proven from OUTSIDE the script, two independent ways.
  make_story stories 005-gamma
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-gamma
  [ "$status" -eq 0 ]
  # (1) THE ROW'S OWN CONTENT. Its link resolves into archive/, which is only
  # true after step 6 moved the directory; and its Status cell reads `archived`,
  # which is only true after step 7 rewrote the frontmatter (the fixture says
  # `done`). A regeneration placed before either step would have rendered
  # `stories/005-gamma`, or `done`, or both.
  [ "$(row_for 005-gamma)" = "| 005 | [gamma](archive/005-gamma/story.md) | archived | 2/3 | archived |" ]
  # (2) THE STDERR STREAM'S OWN ORDER: step 7's verdict line is emitted before
  # step 8's, so the sequence is observable without reading the script.
  s7=$(printf '%s\n' "$stderr" | grep -n 'archive-story: status=archived' | head -1 | cut -d: -f1)
  s8=$(printf '%s\n' "$stderr" | grep -n 'archive-story: index=ok' | head -1 | cut -d: -f1)
  [ -n "$s7" ]
  [ -n "$s8" ]
  [ "$s7" -lt "$s8" ]
}

@test "4.2: a regen failure reports regen-failed, never ok, and still exits 0" {
  # The authored case pins that the move stands; this one pins WHAT THE REPORT
  # SAYS about it. `ok` here would be the dangerous value: it would tell every
  # consumer the index agrees with the disk while the row is stale.
  make_story stories 005-delta
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  mkdir -p "$PROJ/.epic/archive"
  chmod 444 "$EPIC_MD"
  chmod 555 "$PROJ/.epic"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-delta
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.index == "regen-failed"' > /dev/null
  # The archive itself COMPLETED — the index never rolls a move back.
  echo "$output" | jq -e '.status == "archived" and .moved == true' > /dev/null
  # The warning reaches stdout too, not only the human on stderr.
  echo "$output" | jq -e '.reason | contains("NOTHING WAS ROLLED BACK")' > /dev/null
  [ -d "$PROJ/.epic/archive/005-delta" ]
  [[ "$stderr" == *"index=regen-failed"* ]]
}

@test "4.2: a refusal and a guard block both keep index skipped, never ok" {
  # `skipped` is NOT a synonym for regen-failed. It means step 8 NEVER RAN, so
  # nothing moved and the index still agrees with the disk — a different fact,
  # and the one that must survive on every path that exits before the move.
  mk_story stories 001-open in-progress
  mk_tasks stories 001-open <<'EOF'
- [ ] 1 - still open
EOF
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/001-open
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused" and .index == "skipped"' > /dev/null
  # ...and a guard block, which exits from further down the same pipeline. A NUL
  # byte is what makes a file non-text for step 2's heuristic (R1.2).
  make_story stories 002-blob
  printf 'a\000b' > "$PROJ/.epic/stories/002-blob/blob.bin"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/002-blob
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .index == "skipped"' > /dev/null
  [ ! -d "$PROJ/.epic/archive/002-blob" ]
}

@test "4.2: a project with no EPIC.md has one created by the archive" {
  # After the move the project still holds exactly one story — the archived one
  # — so the generator's "no stories, stay quiet" branch is unreachable from
  # here and the file IS created. Pinned so the verdict is not re-litigated:
  # index reports `ok`, and the one row points into archive/.
  make_story stories 005-gamma
  [ ! -e "$EPIC_MD" ]
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-gamma
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.index == "ok"' > /dev/null
  [ -f "$EPIC_MD" ]
  [ "$(row_for 005-gamma)" = "| 005 | [gamma](archive/005-gamma/story.md) | archived | 2/3 | archived |" ]
}

@test "4.2: hand-written content outside the markers survives a real archive" {
  # The PARENT TASK's named Risk — clobbering hand-written content — proven end
  # to end through archive-story.sh rather than through the generator alone, on
  # the byte-level shapes a line-based splice destroys: no blank line above the
  # start marker, none below the end marker, and NO FINAL NEWLINE.
  make_story stories 005-gamma
  head_txt='# Program context'$'\n''keep me, byte for byte.'$'\n'
  tail_txt='and me, with no final newline'
  printf '%s<!-- epic:index:start -->\n| stale row |\n<!-- epic:index:end -->\n%s' \
    "$head_txt" "$tail_txt" > "$EPIC_MD"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-gamma
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.index == "ok"' > /dev/null
  printf '%s' "$head_txt" > "$WORK/head.expect"
  head -c "${#head_txt}" "$EPIC_MD" > "$WORK/head.after"
  cmp -s "$WORK/head.expect" "$WORK/head.after"
  printf '%s' "$tail_txt" > "$WORK/tail.expect"
  tail -c "${#tail_txt}" "$EPIC_MD" > "$WORK/tail.after"
  cmp -s "$WORK/tail.expect" "$WORK/tail.after"
  # An off-by-one in either offset duplicates the marker it mis-attributes.
  [ "$(count_marker 'epic:index:start')" -eq 1 ]
  [ "$(count_marker 'epic:index:end')" -eq 1 ]
  idx=$(cat "$EPIC_MD")
  [[ "$idx" != *"stale row"* ]]
  [[ "$idx" == *"archive/005-gamma"* ]]
}

@test "4.2: a missing epic-index.sh is regen-failed, and the archive completes" {
  # An older install, or someone deleted the generator. Two things must hold:
  # the archive must NOT die with an empty stdout (every consumer pipes it into
  # jq), and it must NOT report `skipped` — the move completed, so the index is
  # now stale and saying "step 8 never ran" would be false in the direction that
  # hides it. Verdict: regen-failed, exit 0, the move stands.
  make_story stories 005-gamma
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  cp "$EPIC_MD" "$WORK/epic.before"
  # A copy of the script with NO sibling generator; the repo is never touched.
  mkdir -p "$WORK/bin"
  cp "$ARCHIVE_SH" "$WORK/bin/archive-story.sh"
  [ ! -e "$WORK/bin/epic-index.sh" ]
  run --separate-stderr bash "$WORK/bin/archive-story.sh" .epic/stories/005-gamma
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.index == "regen-failed"' > /dev/null
  echo "$output" | jq -e '.status == "archived" and .moved == true' > /dev/null
  echo "$output" | jq -e '.reason | contains("not there")' > /dev/null
  [ -d "$PROJ/.epic/archive/005-gamma" ]
  # Nothing regenerated it, so the row IS stale — and the report says so rather
  # than pretending the index is current.
  cmp -s "$WORK/epic.before" "$EPIC_MD"
  [[ "$stderr" == *"index=regen-failed"* ]]
}
