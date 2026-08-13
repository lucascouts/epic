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
  # NOT `! grep -q`: bash's set -e exempts an inverted command, so a non-last
  # line `!` is a no-op assertion (deviations.yaml, 2.2 test-hygiene discovery).
  [[ "$(cat "$EPIC_MD")" != *"old stale row"* ]]
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
  [[ "$(cat "$EPIC_MD")" != *"stories/005-gamma"* ]]
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

# --- 6.1 Manifest-backed rows for stories no longer on disk (R5.1, R5.4) ---
# design.md:67 says the generator scans stories/ + archive/ + THE MANIFEST. The
# first two were shipped in 4.1; this closes the third. `.epic/archive/` can be
# pruned — the manifest is the permanent record that outlives it, so a story
# recorded there and gone from disk must still get a row, from the numbers
# archive-story.sh DERIVED at move time, and with no link to a directory that
# is not there.
# Each case below was mutation-checked (break the specific line it pins ->
# case red -> restore -> green). Prefixed `6.1:` so they run under
# `bats --filter '^6\.1:'`.

# row_with <cell-text> - the generated row whose Story cell is exactly that.
# row_for cannot see a manifest row: it matches on the link target, and a
# manifest row deliberately has no link.
row_with() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '| '*"| $1 |"*) printf '%s' "$line"; return 0 ;;
    esac
  done < "$EPIC_MD"
  return 1
}

# story_order - the Story cell of every generated row, in file order. link_order
# only sees rows that HAVE a link, so it cannot check where a manifest row sorts.
story_order() {
  local line s out=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '| # | Story '*|'| --- '*) continue ;;
      '| '*' |') ;;
      *) continue ;;
    esac
    s="${line#| }"
    s="${s#*| }"
    s="${s%% |*}"
    out="$out$s "
  done < "$EPIC_MD"
  printf '%s' "$out"
}

# man_start - the manifest, with the header archive-story.sh writes. The comment
# block is reproduced because the parser has to walk past it.
man_start() {
  mkdir -p "$PROJ/.epic/archive"
  cat > "$PROJ/.epic/archive/manifest.yaml" <<'EOF'
# Epic archive manifest — one entry per archived story, appended by
# scripts/archive-story.sh at the moment of the move.
#
# POLICY: Numbers are never recycled. A new story always takes the next highest
# number, even when a lower one now exists only in this file.
archived:
EOF
}

# man_entry <story> <number> <slug> <status> <total> <closed> <deferred>
# One COMPLETE entry in manifest_entry_yaml's exact 16-key shape and indentation.
man_entry() {
  cat >> "$PROJ/.epic/archive/manifest.yaml" <<EOF
  - story: "$1"
    number: "$2"
    slug: "$3"
    type: "feature"
    scale: "standard"
    status: "$4"
    tasks_total: $5
    tasks_closed: $6
    tasks_deferred: $7
    tasks_open: 0
    deferred_items: []
    archived_at: "2026-08-05T10:00:00-03:00"
    pruned:
      logs_kb: 0
      copies_removed: 0
    overrides_used: []
EOF
}

# man_torn <story> <number> <slug> - a LAST entry cut off mid-append. This is
# not a hypothetical: the append lock serializes WRITERS, NOT READERS, and the
# append is one write(2) per line, so a reader running during an archive sees
# exactly this prefix (deviations.yaml, concurrency fix cycle).
#
# THE TEAR POINT IS THE POINT. It is placed AFTER archived_at, so every field
# this renderer reads - number, slug, status and all three counts - is present
# AND well formed. Nothing but the missing `overrides_used` sentinel can reject
# this entry, which is what makes the case a real discriminator: an earlier cut
# (measured) is thrown out by the digits check on tasks_deferred instead, and
# the case then passes with the completeness rule deleted.
man_torn() {
  cat >> "$PROJ/.epic/archive/manifest.yaml" <<EOF
  - story: "$1"
    number: "$2"
    slug: "$3"
    type: "feature"
    scale: "standard"
    status: "done"
    tasks_total: 4
    tasks_closed: 4
    tasks_deferred: 0
    tasks_open: 0
    deferred_items: []
    archived_at: "2026-08-05T10:00:00-03:00"
EOF
}

@test "6.1: a story only in the manifest keeps its row, with no link at all" {
  # The manifest here is written by the REAL archive-story.sh, so the reader is
  # pinned against the writer's own bytes rather than against a transcription
  # of them: key order, indentation, quoting and the 6-space deferred_items
  # list are all whatever the writer actually emits.
  make_story stories 003-webhooks
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/003-webhooks
  [ "$status" -eq 0 ]
  [ -f "$PROJ/.epic/archive/manifest.yaml" ]
  # ...and then the archived directory is pruned, which is the situation this
  # sub-task exists for. Only the record survives.
  rm -rf "$PROJ/.epic/archive/003-webhooks"
  [ ! -e "$PROJ/.epic/archive/003-webhooks" ]
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  # Number, slug, status and progress are the RECORDED ones. `done` is the
  # story's own frontmatter status at derive time - proof the row was not
  # recomputed, since a row built from disk after step 7 would read `archived`.
  # 2/3 (+1 deferred) is the recorded census, not a recount of files that are
  # gone.
  [ "$(row_with webhooks)" = "| 003 | webhooks | done | 2/3 (+1 deferred) | archived (directory removed) |" ]
  # NO href: R5.1 asks for a link resolving to the story's CURRENT location, and
  # this story has none - a href here would 404 by construction.
  idx=$(cat "$EPIC_MD")
  [[ "$idx" != *"archive/003-webhooks"* ]]
  [[ "$idx" != *"stories/003-webhooks"* ]]
  [[ "$(row_with webhooks)" != *"]("* ]]
}

@test "6.1: a torn trailing entry is skipped and the run still succeeds" {
  # The reader must tolerate a half-written last entry. Blocking on it would
  # hand any concurrent archive the power to break the index; rendering it would
  # publish a row assembled from half a record.
  make_story stories 001-alpha
  man_start
  man_entry 002-beta 002 beta validated 5 4 1
  man_torn 003-cut 003 cut
  run --separate-stderr bash "$INDEX_SH"
  # Not a corrupt manifest, not a failure: exit 0, everything else renders.
  [ "$status" -eq 0 ]
  [ "$(row_with beta)" = "| 002 | beta | validated | 4/5 (+1 deferred) | archived (directory removed) |" ]
  [ "$(row_for 001-alpha)" = "| 001 | [alpha](stories/001-alpha/story.md) | done | 2/3 | active |" ]
  # The torn entry contributes nothing - not a row, not a partial row, not a
  # cell built from the fields that did arrive.
  idx=$(cat "$EPIC_MD")
  [[ "$idx" != *"003-cut"* ]]
  [[ "$idx" != *"| cut |"* ]]
  [[ "$idx" != *"4/4"* ]]
  # A row is not silently swapped for a `| 003 |` shell either.
  [[ "$idx" != *"| 003 |"* ]]
}

@test "6.1: an absent manifest changes nothing" {
  # Two things, because "changes nothing" has two halves: no manifest must not
  # alter any row, and no manifest must be indistinguishable from a manifest
  # with no entries in it.
  make_story stories 001-alpha
  make_story archive 002-beta
  [ ! -e "$PROJ/.epic/archive/manifest.yaml" ]
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 001-alpha)" = "| 001 | [alpha](stories/001-alpha/story.md) | done | 2/3 | active |" ]
  [ "$(row_for 002-beta)" = "| 002 | [beta](archive/002-beta/story.md) | done | 2/3 | archived |" ]
  [[ "$(cat "$EPIC_MD")" != *"directory removed"* ]]
  cp "$EPIC_MD" "$WORK/no-manifest"
  # An entry-less manifest is byte-for-byte the same index.
  man_start
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  cmp -s "$WORK/no-manifest" "$EPIC_MD"
}

@test "6.1: an unreadable manifest renders every other row and exits 0" {
  # The index is a rendering, never a gate: a manifest it cannot open costs the
  # manifest rows and nothing else. fail() here would let one unreadable file
  # take the whole index down.
  make_story stories 001-alpha
  man_start
  man_entry 002-beta 002 beta validated 5 5 0
  chmod 000 "$PROJ/.epic/archive/manifest.yaml"
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 001-alpha)" = "| 001 | [alpha](stories/001-alpha/story.md) | done | 2/3 | active |" ]
  [[ "$(cat "$EPIC_MD")" != *"| beta |"* ]]
}

@test "6.1: a story still on disk always wins over its manifest entry" {
  # An archive that died between the append and the move leaves exactly this:
  # the entry is written FIRST (R3.4), so the story is recorded AND still in
  # stories/. It must render ONCE, from disk, with a working link - never as a
  # second row claiming its directory was removed.
  make_story stories 004-delta
  man_start
  man_entry 004-delta 004 delta validated 9 9 0
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 004-delta)" = "| 004 | [delta](stories/004-delta/story.md) | done | 2/3 | active |" ]
  idx=$(cat "$EPIC_MD")
  [[ "$idx" != *"directory removed"* ]]
  [[ "$idx" != *"9/9"* ]]
  # Identity is checked by NUMBER as well as by directory name: an archived
  # directory renamed on disk still suppresses its entry, because numbers are
  # never recycled (the manifest's own policy header), so the number is the
  # story. Claiming "directory removed" about a directory that is right there
  # is the failure worth ruling out.
  make_story archive 005-renamed
  man_entry 005-original 005 original validated 3 3 0
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 005-renamed)" = "| 005 | [renamed](archive/005-renamed/story.md) | done | 2/3 | archived |" ]
  [[ "$(cat "$EPIC_MD")" != *"| original |"* ]]
  # ...and by NAME as well as by number, which is the half a numbered fixture
  # cannot show (measured: with the name check deleted, the two cases above stay
  # green because the number catches them). A directory that is not NNN-slug is
  # recorded with an EMPTY number - archive-story.sh's derive_entry_fields leaves
  # it empty rather than guessing one - so its name is the only identity there is.
  mkdir -p "$PROJ/.epic/stories/notes-scratch"
  printf 'scratch\n' > "$PROJ/.epic/stories/notes-scratch/README.md"
  man_entry notes-scratch "" notes-scratch done 2 2 0
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for notes-scratch)" = "| — | [notes-scratch](stories/notes-scratch/) | — | — | active |" ]
  idx=$(cat "$EPIC_MD")
  [[ "$idx" != *"| notes-scratch |"* ]]
  [[ "$idx" != *"2/2"* ]]
}

@test "6.1: a recorded value is unescaped, not just stripped of its quotes" {
  # Every manifest scalar was written by archive-story.sh's quote_scalar as ONE
  # double-quoted token whose escapes are the union JSON and YAML decode the
  # same way. Stripping the quotes and stopping would publish the escape itself.
  # Written by the REAL writer, so the escaping under test is its own.
  mk_story stories 006-quoted 'he said "hi" and a back\slash'
  mk_tasks stories 006-quoted <<'EOF'
- [x] 1 - done
EOF
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/006-quoted
  [ "$status" -eq 0 ]
  # The writer really did escape it - without this guard the case would pin
  # nothing whenever the fixture stopped producing an escape at all.
  grep -qF 'status: "he said \"hi\" and a back\\slash"' "$PROJ/.epic/archive/manifest.yaml"
  rm -rf "$PROJ/.epic/archive/006-quoted"
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  # Decoded back to the source text, then re-escaped by md_cell for the table
  # (which doubles the backslash and would escape a pipe or a bracket).
  [ "$(row_with quoted)" = "| 006 | quoted | he said \"hi\" and a back\\\\slash | 1/1 | archived (directory removed) |" ]
}

@test "6.1: manifest rows sort among the disk rows and regen stays a no-op" {
  # R5.4 has to keep holding with manifest rows in play, and manifest rows have
  # to take their place on the SAME number axis as disk rows - a manifest row
  # appended after the sort would order by where it was read, not by its number.
  # Mixed widths on purpose: a lexicographic sort puts 010 and 100 before 2.
  mk_story stories 010-jay draft
  mk_tasks stories 010-jay <<'EOF'
- [x] 1 - done
EOF
  mk_story archive 100-century archived
  mk_tasks archive 100-century <<'EOF'
- [x] 1 - done
EOF
  man_start
  man_entry 2-two 2 two validated 1 1 0
  man_entry 009-india 009 india validated 4 2 2
  man_entry 99-nines 99 nines done 3 3 0
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(story_order)" = "two india [jay](stories/010-jay/story.md) nines [century](archive/100-century/story.md) " ]
  cp "$EPIC_MD" "$WORK/snap"
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  # Second regeneration with no state change: zero diff (R5.4).
  cmp -s "$WORK/snap" "$EPIC_MD"
}

# --- 6.2 Spike rows render the Verdict status (R5.1) ---
# design.md:67: "`scale: spike` rows render the Verdict status (007)". A spike
# has no lifecycle status to show — its conclusion lives in a `## Verdict`
# section, and the index must state THAT. The grammar is archive-story.sh's
# parse_verdict verbatim; only the aggregation differs (preflight decides
# completion, this renders).
# Each case below was mutation-checked against the specific line it pins
# (break -> that case red -> restore -> green). Prefixed `6.2:` so they run
# under `bats --filter '^6\.2:'`.

# spike_story <area> <dir> [status] - story.md for a `scale: spike` story,
# carrying a lifecycle status on purpose: the verdict must win over it.
spike_story() {
  local dir="$PROJ/.epic/$1/$2"
  mkdir -p "$dir"
  {
    echo '---'
    echo "story: ${2#*-}"
    echo 'type: spike'
    echo 'scale: spike'
    echo 'version: 1'
    echo 'created: 2026-08-01'
    if [ -n "${3:-}" ]; then echo "status: $3"; fi
    echo '---'
    echo
    echo '# Spike - fixture'
  } > "$dir/story.md"
}

# spike_tasks <area> <dir> - tasks.md declaring `scale: spike` in its OWN
# frontmatter plus one closed probe box; the `## Verdict` section, when the case
# wants one, is read from stdin. A spike commonly has no story.md at all, so the
# scale has to be readable from here: status_cell reads the row's story.md and
# falls back to tasks.md, which is its own registered exception to the shared
# scale rule - see scripts/epic-index.sh at status_cell for why it keeps that
# precedence while every reader that GATES something resolves scale from
# tasks.md.
spike_tasks() {
  local dir="$PROJ/.epic/$1/$2"
  mkdir -p "$dir"
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-08-01'
    echo 'scale: spike'
    echo '---'
    echo
    echo '## Probe'
    echo '- [x] 1 - ran the probe'
    cat
  } > "$dir/tasks.md"
}

@test "6.2: a spike renders its Verdict where a lifecycle status would go" {
  # The fixture carries `status: in-progress` in its frontmatter. A spike's
  # boxes are probe steps and its status is not its conclusion (007 R1.7), so
  # the Verdict must REPLACE it, not sit next to it.
  spike_story stories 001-probe in-progress
  spike_tasks stories 001-probe <<'EOF'

## Verdict
- status: wont-do
- conclusion: the API cannot do it; not worth a story
EOF
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 001-probe)" = "| 001 | [probe](stories/001-probe/story.md) | wont-do | 1/1 | active |" ]
  # The lifecycle status is not rendered anywhere - not appended, not a fallback.
  [[ "$(cat "$EPIC_MD")" != *"in-progress"* ]]
}

@test "6.2: a promote verdict names the story it was promoted to" {
  # No story.md at all on the spikes here: that is the shape archive-story.sh
  # documents (a spike is tasks-only), so the scale itself must be readable from
  # tasks.md or the row silently renders as a lifecycle story.
  mk_story stories 012-successor draft
  mk_tasks stories 012-successor <<'EOF'
- [x] 1 - done
EOF
  spike_tasks stories 002-oauth <<'EOF'

## Verdict
- status: promote
- conclusion: worth doing
- promoted-to: 012
EOF
  # A target that resolves nowhere is SHOWN, not hidden - the `superseded by MMM
  # (missing)` idiom, for the same reason: a dangling pointer is exactly what a
  # reader needs to be told about.
  spike_tasks stories 003-mesh <<'EOF'

## Verdict
- status: promote
- promoted-to: 042
EOF
  # The template ships `promoted-to: NNN` unfilled. It must NOT render as a
  # target: parse_verdict requires a leading DIGIT, which is what "the target is
  # recorded" means (fail-closed, same as preflight).
  spike_tasks stories 004-bare <<'EOF'

## Verdict
- status: promote
- promoted-to: NNN
EOF
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 002-oauth)" = "| 002 | [oauth](stories/002-oauth/) | promote to 012 | 1/1 | active |" ]
  [ "$(row_for 003-mesh)" = "| 003 | [mesh](stories/003-mesh/) | promote to 042 (missing) | 1/1 | active |" ]
  [ "$(row_for 004-bare)" = "| 004 | [bare](stories/004-bare/) | promote | 1/1 | active |" ]
  [[ "$(cat "$EPIC_MD")" != *"NNN"* ]]
  # R5.4 still holds with spike rows in play.
  cp "$EPIC_MD" "$WORK/snap"
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  cmp -s "$WORK/snap" "$EPIC_MD"
}

@test "6.2: a spike with no readable Verdict renders the em dash" {
  # Absent is absent. The em dash is the SAME one a story with no `status:`
  # renders - never the frontmatter status, never an invented `open`.
  spike_story stories 001-running in-progress
  spike_tasks stories 001-running </dev/null
  # A Verdict section that exists but records no status: still no verdict.
  spike_story stories 002-empty in-progress
  spike_tasks stories 002-empty <<'EOF'

## Verdict
- conclusion: still measuring
EOF
  # A `status:` OUTSIDE the section is not the verdict either - the section ends
  # at the next heading, which is what keeps a stray key from being read as one.
  spike_story stories 003-scoped in-progress
  spike_tasks stories 003-scoped <<'EOF'

## Verdict
- conclusion: still measuring

## Notes
- status: promote
- promoted-to: 012
EOF
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 001-running)" = "| 001 | [running](stories/001-running/story.md) | — | 1/1 | active |" ]
  [ "$(row_for 002-empty)" = "| 002 | [empty](stories/002-empty/story.md) | — | 1/1 | active |" ]
  [ "$(row_for 003-scoped)" = "| 003 | [scoped](stories/003-scoped/story.md) | — | 1/1 | active |" ]
  idx=$(cat "$EPIC_MD")
  [[ "$idx" != *"in-progress"* ]]
  [[ "$idx" != *"promote"* ]]
}

# --- 3.3 Post-supersede rendering (story 006, R3.7) ---
# The 4.1 supersede cases above pinned the renderer's contract FORWARD, before
# any writer for the companion key existed. Story 006's supersede op is that
# writer, and these cases pin the FULL artifact shape it leaves behind
# (supersede-mode.md, Closure + Walkthrough): `status: superseded` plus
# `superseded-by: MMM` in EVERY artifact's frontmatter — tasks.md included,
# which the renderer must ignore for status — and every open box closed as a
# terminal `[~] (superseded-by: MMM)`, which progress folds into closed, never
# into deferred. Both were mutation-checked against a copy of the script with
# the pointer rendering removed (both red) and with the `(missing)` suffix
# removed (the second red). Prefixed `3.3:` for `bats --filter '^3\.3:'`.

@test "3.3: a story the supersede op closed renders superseded by MMM" {
  # NNN exactly as steps 2-3 leave it, MMM present in stories/. The fixture is
  # the walkthrough's: one [x] survivor, three boxes closed by the op.
  mk_story stories 042-legacy-import superseded 'superseded-by: 051'
  mk_tasks stories 042-legacy-import <<'EOF'
---
version: 1
created: 2026-05-14
status: superseded
superseded-by: 051
---

## Task List
- [x] 1.1 - Parse the legacy CSV export
- [~] 2.1 - Map legacy fields to the new schema (superseded-by: 051)
- [~] 2.2 - Validate mapped rows (superseded-by: 051)
- [~] 3.1 - Import against the live feed (superseded-by: 051)
EOF
  mk_story stories 051-modern-import in-progress
  mk_tasks stories 051-modern-import <<'EOF'
- [ ] 1 - rebuild the import on the v2 bulk endpoint
EOF
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  # Status from story.md's companion key; 4/4 because `superseded-by:` is a
  # TERMINAL qualifier (an op-closed box is settled, not owed).
  [ "$(row_for 042-legacy-import)" = "| 042 | [legacy-import](stories/042-legacy-import/story.md) | superseded by 051 | 4/4 | active |" ]
  # The pair in tasks.md's own frontmatter leaks nowhere: no deferred count,
  # and the op's 3.1 closure REPLACED any `deferred:` (a line carrying both
  # would stay owed, because deferred: wins the census).
  [[ "$(cat "$EPIC_MD")" != *"deferred"* ]]
}

@test "3.3: a superseded story whose successor left the project renders missing" {
  # Same post-op shape, but MMM has no directory anywhere - neither stories/
  # nor archive/. The dangling pointer is surfaced, never an error (exit 0).
  mk_story stories 007-dead superseded 'superseded-by: 099'
  mk_tasks stories 007-dead <<'EOF'
---
version: 1
created: 2026-05-14
status: superseded
superseded-by: 099
---

## Task List
- [x] 1 - done before the supersede
- [~] 2 - remapped away (superseded-by: 099)
EOF
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 007-dead)" = "| 007 | [dead](stories/007-dead/story.md) | superseded by 099 (missing) | 2/2 | active |" ]
}

@test "6.2: a non-spike story is untouched by the Verdict rule" {
  # The regression this sub-task could have shipped: reading a Verdict from a
  # story that is not a spike. All three rows below carry one and none may show
  # it - their status column is the lifecycle status, byte for byte what it was
  # before this rule existed.
  mk_story stories 001-alpha done
  mk_tasks stories 001-alpha <<'EOF'
- [x] 1 - done
## Verdict
- status: wont-do
- promoted-to: 012
EOF
  # No `scale:` key at all - the 340+ legacy stories that predate the field.
  mkdir -p "$PROJ/.epic/stories/002-legacy"
  {
    echo '---'
    echo 'story: legacy'
    echo 'status: validated'
    echo '---'
    echo
    echo '# Story'
  } > "$PROJ/.epic/stories/002-legacy/story.md"
  mk_tasks stories 002-legacy <<'EOF'
- [x] 1 - done
## Verdict
- status: promote
- promoted-to: 012
EOF
  # status_cell keeps its own precedence: the row's story.md decides the scale
  # lookup and tasks.md is a FALLBACK for the tasks-only scales, not an override
  # that can turn a standard story into a spike. That is a deliberate, registered
  # exception to the shared scale rule - see scripts/epic-index.sh at status_cell.
  mk_story stories 003-precedence done
  spike_tasks stories 003-precedence <<'EOF'

## Verdict
- status: wont-do
EOF
  run --separate-stderr bash "$INDEX_SH"
  [ "$status" -eq 0 ]
  [ "$(row_for 001-alpha)" = "| 001 | [alpha](stories/001-alpha/story.md) | done | 1/1 | active |" ]
  [ "$(row_for 002-legacy)" = "| 002 | [legacy](stories/002-legacy/story.md) | validated | 1/1 | active |" ]
  [ "$(row_for 003-precedence)" = "| 003 | [precedence](stories/003-precedence/story.md) | done | 1/1 | active |" ]
  idx=$(cat "$EPIC_MD")
  [[ "$idx" != *"wont-do"* ]]
  [[ "$idx" != *"promote"* ]]
}
