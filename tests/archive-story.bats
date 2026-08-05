#!/usr/bin/env bats
# Contract tests for scripts/archive-story.sh (story 005 - archive-in-the-flow).
# Authored Red-first by the Test Advisor from EARS requirements + design contract.
# Target location after materialization: tests/archive-story.bats
#
# Contract under test (design.md, Components 1):
#   archive-story.sh <NNN|story-dir> [--allow-heavy] [--skip-secrets]
#                    [--keep-logs] [--keep-copies] [--force <reason>]
#   JSON on stdout: {story, status: archived|blocked|refused, moved,
#                    pruned{logs_kb, copies_removed}, guard{violations[]},
#                    secrets{}, manifest_entry{}}
#   Exit 0 only on a completed move; 1 = guard hit / refusal; 2 = invalid input.
#   Step order: guards -> prune -> manifest append -> move -> status -> index.
#
# Test names are prefixed with the sub-task number (e.g. "1.1:") so Red/Green
# evidence can be produced per sub-task via `bats --filter '^1\.1:'`.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ARCHIVE_SH="$PLUGIN_ROOT/scripts/archive-story.sh"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  MANIFEST="$PROJ/.epic/archive/manifest.yaml"
  mkdir -p "$PROJ/.epic/stories"
  cd "$PROJ"
}

teardown() {
  cd /
  chmod -R u+rwX "$WORK" 2>/dev/null || true
  rm -rf "$WORK"
}

# make_story <dir-name> <complete|incomplete>
# complete:   3 tasks - 2 [x], 1 [~]  (total 3, closed 2, deferred 1, open 0)
# incomplete: 3 tasks - 1 [x], 2 [ ]  (total 3, closed 1, deferred 0, open 2)
make_story() {
  local dir="$PROJ/.epic/stories/$1" mode="${2:-complete}" status=done
  [ "$mode" = incomplete ] && status=in-progress
  mkdir -p "$dir"
  cat > "$dir/story.md" <<EOF
---
story: ${1#*-}
type: feature
scale: standard
version: 1
created: 2026-08-01
status: $status
---

# Story - fixture
EOF
  if [ "$mode" = complete ]; then
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
  else
    cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-01
---

## Task List
- [x] 1 - First done thing
  - Validation: ok
- [ ] 2 - Still open thing
  - Validation: ok
- [ ] 3 - Also open thing
  - Validation: ok
EOF
  fi
}

# make_spike <dir-name> <verdict-status> [promoted-to] [probe-box]
# scale: spike (story 007) - tasks-only, no story.md, no R-chain, and a
# mandatory `## Verdict` section that IS the spike's conclusion.
# The probe box state is a parameter so each case isolates the verdict rule:
# refusals use a CLOSED box (only the verdict can refuse) and passes use an
# OPEN one (only the verdict can complete). Frontmatter status stays
# `in-progress` so the status branch never decides either.
make_spike() {
  local dir="$PROJ/.epic/stories/$1" vstatus="$2" promoted="${3:-}" probe="${4:-x}"
  mkdir -p "$dir"
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-08-01'
    echo 'scale: spike'
    echo 'status: in-progress'
    echo '---'
    echo
    echo '## Probe'
    echo "- [$probe] 1 - Run the probe"
    echo
    echo '## Verdict'
    echo "- status: $vstatus"
    echo '- conclusion: what the probe showed'
    if [ -n "$promoted" ]; then echo "- promoted-to: $promoted"; fi
  } > "$dir/tasks.md"
  return 0
}

# --- 1.1 Preflight, flags, JSON contract (R1.5, R1.6, R1.7) ---

@test "1.1: help flag exits 0" {
  run bash "$ARCHIVE_SH" --help
  [ "$status" -eq 0 ]
}

@test "1.1: unknown flag exits 2 with nothing moved" {
  make_story 005-flagged complete
  run bash "$ARCHIVE_SH" .epic/stories/005-flagged --bogus
  [ "$status" -eq 2 ]
  [ -d "$PROJ/.epic/stories/005-flagged" ]
  [ ! -d "$PROJ/.epic/archive/005-flagged" ]
}

@test "1.1: incomplete story without --force is refused with the open count" {
  make_story 005-open incomplete
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-open
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  # R1.5: the refusal reports the open items count (2 in this fixture).
  echo "$output" | grep -qi 'open'
  echo "$output" | grep -q '2'
  [ -d "$PROJ/.epic/stories/005-open" ]
  [ ! -d "$PROJ/.epic/archive/005-open" ]
}

@test "1.1: already-archived story is refused untouched" {
  mkdir -p "$PROJ/.epic/archive/004-old"
  cat > "$PROJ/.epic/archive/004-old/story.md" <<'EOF'
---
story: old
status: archived
---
EOF
  run --separate-stderr bash "$ARCHIVE_SH" .epic/archive/004-old
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  # R1.7: nothing modified - story stays, no manifest springs into existence.
  [ -d "$PROJ/.epic/archive/004-old" ]
  [ ! -e "$MANIFEST" ]
}

# Spike preflight (story 007 R1.7, whose CODE lives here in 005's preflight).
# ADDITIVE cases appended at execution time: the authored suite predates this
# rule. No assertion above was modified.
# A spike is complete for archive purposes ONLY via its Verdict - `wont-do`, or
# `promote` with a `promoted-to:` target recorded.

@test "1.1: spike with an open verdict is refused" {
  make_spike 005-spike-open open
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-spike-open
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  [ -d "$PROJ/.epic/stories/005-spike-open" ]
  [ ! -d "$PROJ/.epic/archive/005-spike-open" ]
  [ ! -e "$MANIFEST" ]
}

@test "1.1: spike promoted without promoted-to is refused" {
  make_spike 005-spike-nopromo promote
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-spike-nopromo
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  echo "$output" | grep -q 'promoted-to'
  [ -d "$PROJ/.epic/stories/005-spike-nopromo" ]
  [ ! -d "$PROJ/.epic/archive/005-spike-nopromo" ]
}

@test "1.1: spike with a wont-do verdict passes preflight" {
  # Open probe box: only the verdict rule can make this complete.
  make_spike 005-spike-wontdo wont-do "" " "
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-spike-wontdo
  # Preflight is the whole assertion: a terminal verdict is never a refusal.
  # The exit code belongs to the later pipeline steps, not to preflight.
  echo "$output" | jq -e '.status != "refused"' > /dev/null
}

@test "1.1: spike promoted with promoted-to passes preflight" {
  make_spike 005-spike-promo promote 012 " "
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-spike-promo
  echo "$output" | jq -e '.status != "refused"' > /dev/null
}

# --- 1.2 Derived manifest, append-before-move (R3.1, R3.2, R3.3, R3.4) ---

@test "1.2: manifest entry counts are derived from the checkboxes" {
  make_story 005-counts complete
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-counts
  [ "$status" -eq 0 ]
  [ -f "$MANIFEST" ]
  grep -Eq 'tasks_total:[[:space:]]*3' "$MANIFEST"
  grep -Eq 'tasks_closed:[[:space:]]*2' "$MANIFEST"
  grep -Eq 'tasks_deferred:[[:space:]]*1' "$MANIFEST"
}

@test "1.2: forced archive records the true open count and the reason" {
  make_story 005-forced incomplete
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-forced --force "schedule pressure"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.moved == true' > /dev/null
  [ -d "$PROJ/.epic/archive/005-forced" ]
  # R3.2: totals expose the truth (3 total, only 1 closed => 2 still open).
  grep -Eq 'tasks_total:[[:space:]]*3' "$MANIFEST"
  grep -Eq 'tasks_closed:[[:space:]]*1' "$MANIFEST"
  # R1.6: the --force reason lands in the manifest entry.
  grep -q 'schedule pressure' "$MANIFEST"
}

@test "1.2: manifest is created with the never-recycled policy header" {
  make_story 005-header complete
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-header
  [ "$status" -eq 0 ]
  [ -f "$MANIFEST" ]
  grep -qi 'never recycled' "$MANIFEST"
}

@test "1.2: manifest append failure aborts before anything moves" {
  make_story 005-interrupt complete
  mkdir -p "$PROJ/.epic/archive"
  chmod 555 "$PROJ/.epic/archive"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-interrupt
  # R3.4: append is before the move; an unappendable manifest means no move.
  [ "$status" -ne 0 ]
  echo "$output" | jq -e . > /dev/null
  [ -d "$PROJ/.epic/stories/005-interrupt" ]
  [ ! -d "$PROJ/.epic/archive/005-interrupt" ]
}

# ADDITIVE 1.2 cases appended at execution time. Each pins behavior the sub-task
# mandates that the authored suite leaves unpinned. No assertion above was
# modified, weakened or deleted.

@test "1.2: interrupted archive keeps its entry and the re-run completes it once" {
  # R3.4's other half: the authored case pins the append FAILING; this pins the
  # append SUCCEEDING and the move not completing - the state a kill between
  # step 5 and step 6 leaves behind.
  # The interruption is produced BY the script (a read-only stories/ lets the
  # append through and makes the rename fail) rather than hand-planted: a real
  # SIGKILL is racy - the mv wins the race on a warm tmpfs - and would flake.
  make_story 005-resume complete
  chmod 555 "$PROJ/.epic/stories"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-resume
  chmod 755 "$PROJ/.epic/stories"
  [ "$status" -ne 0 ]
  # The entry is written; the story has NOT moved.
  [ -f "$MANIFEST" ]
  grep -q '005-resume' "$MANIFEST"
  [ -d "$PROJ/.epic/stories/005-resume" ]
  [ ! -d "$PROJ/.epic/archive/005-resume" ]
  # The re-run finishes that archive and does not append a second entry.
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-resume
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epic/archive/005-resume" ]
  [ ! -d "$PROJ/.epic/stories/005-resume" ]
  [ "$(grep -c 'story: "005-resume"' "$MANIFEST")" -eq 1 ]
}

@test "1.2: deferred boxes are recorded as items, not just as a count" {
  # R4.4: "3 deferred" tells a future reader nothing about what is still owed.
  # make_story's [~] box carries no qualifier; this adds one that does, so both
  # renderer branches run.
  make_story 005-deferred complete
  cat >> "$PROJ/.epic/stories/005-deferred/tasks.md" <<'EOF'
- [~] 4 - Register the callback URL (deferred: needs the provider live account)
EOF
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-deferred
  [ "$status" -eq 0 ]
  grep -Eq 'tasks_deferred:[[:space:]]*2' "$MANIFEST"
  grep -q 'Register the callback URL' "$MANIFEST"
  grep -q 'needs the provider live account' "$MANIFEST"
  echo "$output" | jq -e '.manifest_entry.deferred_items | length == 2' > /dev/null
  # Id, title and the qualified reason all survive into the item.
  echo "$output" | jq -e '.manifest_entry.deferred_items[1] | startswith("4 ")' > /dev/null
  echo "$output" | jq -e '.manifest_entry.deferred_items[1]
    | contains("Register the callback URL")
      and contains("(deferred: needs the provider live account)")' > /dev/null
}

@test "1.2: the entry reports the story's own frontmatter status, never a verdict" {
  # The corpus failure this replaces: a sweep stamped 71 stories
  # `complete-merged-to-master`, some of them with 0/14 tasks done. A forced
  # archive of an in-progress story must say `in-progress` and show the open
  # boxes (R3.1 derived-not-declared, R3.2 the true open count).
  make_story 005-truth incomplete
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-truth --force "schedule pressure"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.manifest_entry.status == "in-progress"' > /dev/null
  echo "$output" | jq -e '.manifest_entry.tasks_open == 2' > /dev/null
  grep -Eq 'status:[[:space:]]*"in-progress"' "$MANIFEST"
  grep -Eq 'tasks_open:[[:space:]]*2' "$MANIFEST"
}

# --- 1.3 Move, history preservation, status transition (R1.1, R6.1, R6.2) ---

@test "1.3: complete story moves to .epic/archive with structured report" {
  make_story 005-move complete
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-move
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "archived" and .moved == true' > /dev/null
  [ -d "$PROJ/.epic/archive/005-move" ]
  [ ! -d "$PROJ/.epic/stories/005-move" ]
}

@test "1.3: moved artifacts carry status archived in frontmatter" {
  make_story 005-status complete
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-status
  [ "$status" -eq 0 ]
  grep -q '^status: archived' "$PROJ/.epic/archive/005-status/story.md"
}

@test "1.3: tracked story preserves git history across the move" {
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email test@example.com
  git -C "$PROJ" config user.name "Test"
  make_story 005-hist complete
  git -C "$PROJ" add .epic
  git -C "$PROJ" commit -qm "seed story"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-hist
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epic/archive/005-hist" ]
  git -C "$PROJ" add -A
  git -C "$PROJ" commit -qm "archive commit"
  # R6.1: the rename is tracked - history from before the move is reachable.
  run git -C "$PROJ" log --follow --format=%s -- .epic/archive/005-hist/story.md
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'seed story'
}

@test "1.3: untracked story is moved without git" {
  git -C "$PROJ" init -q
  make_story 005-loose complete
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-loose
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epic/archive/005-loose" ]
  [ ! -d "$PROJ/.epic/stories/005-loose" ]
  # R6.2: plain filesystem move - nothing staged in git for the story.
  run git -C "$PROJ" ls-files -- .epic/archive/005-loose
  [ -z "$output" ]
}

# ADDITIVE 1.3 cases appended at execution time. No assertion above was
# modified, weakened or deleted.
#
# WHY THEY EXIST: the authored `preserves git history` case above passes with a
# plain `mv`. It commits first (`git add -A` + commit), and git then recovers
# the rename by CONTENT SIMILARITY - so `git log --follow` succeeds whichever
# branch ran, and the case cannot tell `git mv` from `mv`. The cases below
# inspect the index BEFORE anything is committed, where only `git mv` can have
# left a trace, which is what actually pins R6.1.

@test "1.3: tracked move stages the rename in git before anything is committed" {
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email test@example.com
  git -C "$PROJ" config user.name "Test"
  make_story 005-staged complete
  git -C "$PROJ" add .epic
  git -C "$PROJ" commit -qm "seed story"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-staged
  [ "$status" -eq 0 ]
  # No `git add` runs here on purpose: a plain `mv` leaves the index completely
  # untouched (an unstaged ` D` plus an untracked directory), so anything
  # staged at all can only have come from `git mv`. `-M` forces rename
  # detection on the command line, so no repo or global config can change the
  # answer (status.renames / diff.renames are irrelevant here).
  run git -C "$PROJ" diff --cached -M --name-status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^R.*\.epic/stories/005-staged/story\.md.*\.epic/archive/005-staged/story\.md'
  echo "$output" | grep -q '^R.*\.epic/stories/005-staged/tasks\.md.*\.epic/archive/005-staged/tasks\.md'
}

@test "1.3: untracked story in a repo leaves the index untouched" {
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email test@example.com
  git -C "$PROJ" config user.name "Test"
  make_story 005-noindex complete
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-noindex
  [ "$status" -eq 0 ]
  # R6.2, and the mirror image of the case above - it is the pair that makes
  # either one a discriminator rather than a tautology.
  run git -C "$PROJ" diff --cached -M --name-status
  [ -z "$output" ]
  [ -d "$PROJ/.epic/archive/005-noindex" ]
}

@test "1.3: partially tracked story still takes the git branch" {
  # The rule, stated: ANY tracked file under the story dir means `git mv`.
  # `git mv` on a directory is one rename(2) of the whole directory, so the
  # untracked files travel with it exactly as `mv` would move them while the
  # tracked ones keep their history - a strict superset of the plain branch.
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email test@example.com
  git -C "$PROJ" config user.name "Test"
  make_story 005-partial complete
  git -C "$PROJ" add .epic
  git -C "$PROJ" commit -qm "seed story"
  echo 'work-tree scratch, committed nowhere' > "$PROJ/.epic/stories/005-partial/notes.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-partial
  [ "$status" -eq 0 ]
  # The tracked half keeps its history...
  run git -C "$PROJ" diff --cached -M --name-status
  echo "$output" | grep -q '^R.*005-partial/story\.md'
  # ...and the untracked file rides along with the directory rename.
  [ -f "$PROJ/.epic/archive/005-partial/notes.md" ]
  [ ! -d "$PROJ/.epic/stories/005-partial" ]
}

@test "1.3: legacy artifact without a status field has one added, in every artifact" {
  # The 340+ legacy stories story 004 stays compatible with carry no `status:`
  # at all. The transition must ADD the field there, not silently skip the file
  # - a skipped artifact would sit in archive/ claiming nothing forever.
  local dir="$PROJ/.epic/stories/005-legacy"
  mkdir -p "$dir"
  cat > "$dir/story.md" <<'EOF'
---
story: legacy
version: 1
created: 2026-08-01
---

# Story - legacy fixture
status: this line is body text, not frontmatter
EOF
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-01
---

## Task List
- [x] 1 - Done
EOF
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-legacy
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epic/archive/005-legacy"
  # One story, one status: EVERY artifact carrying frontmatter gets the field.
  grep -q '^status: archived' "$arch/story.md"
  grep -q '^status: archived' "$arch/tasks.md"
  # Exactly once, and inside the frontmatter block...
  [ "$(sed -n '2,/^---$/p' "$arch/story.md" | grep -c '^status: archived')" -eq 1 ]
  # ...so a body line that merely starts with `status:` is left alone.
  grep -q '^status: this line is body text' "$arch/story.md"
}

# ============================================================================
# REGRESSION cases from the tech-review fix cycle. ADDITIVE ONLY - no assertion
# above was modified, weakened or deleted. Each one is named with the sub-task
# prefix of the code it pins, so it runs inside the existing `^1\.[123]:`
# filters, and each was mutation-checked (break the fix -> the case fails).
# ============================================================================

# --- A + B: one escaping rule that BOTH formats accept ---

@test "1.2: control characters in a forced reason keep the report and the manifest parseable" {
  # A --force reason is arbitrary user input by definition - a paste from a
  # coloured terminal carries ESC (0x1b). Escaping only \n \r \t left every
  # other C0 byte raw, and the run still reported exit 0: the story archived
  # behind a manifest.yaml no YAML parser would ever load again, under a tree
  # that is deliberately hard to repair.
  # DEL (0x7f) and the C1 block are here too because they are the half JSON
  # accepts and YAML does not - valid stdout, permanently broken manifest, no
  # signal at all to the consumer.
  make_story 005-ctl incomplete
  local reason
  reason=$(printf 'rushed \033[1mrelease\033[0m del=\177 c1=\302\206 bs=\b ff=\f')
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-ctl --force "$reason"
  [ "$status" -eq 0 ]
  # stdout is still JSON...
  echo "$output" | jq -e . > /dev/null
  # ...and it round-trips: the escapes decode back to the bytes that went in.
  echo "$output" | jq -e '.manifest_entry.forced_reason | contains("[1mrelease")' > /dev/null
  echo "$output" | jq -e '.manifest_entry.forced_reason | contains("del=")' > /dev/null
  echo "$output" | jq -e '.manifest_entry.forced_reason | contains("c1=")' > /dev/null
  # ...and the manifest is loadable YAML carrying the same value.
  python3 -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
r = d["archived"][0]["forced_reason"]
assert "[1mrelease" in r, r
assert "del=" in r, r
assert "c1=" in r, r
assert "bs=\b" in r and "ff=\f" in r, r
' "$MANIFEST"
}

# --- C: the append is one write, and the resume keys on a COMPLETE entry ---

@test "1.2: a truncated manifest entry blocks instead of being resumed behind" {
  # The entry used to be emitted as 14+ separate writes, and the resume check
  # grepped for `  - story: "<id>"` - the FIRST line the writer emits. So a run
  # killed mid-entry left exactly the token the check looked for, and the
  # re-run "resumed": it skipped the append, archived the story, exited 0, and
  # the permanent record became a stub with no tasks_total, no archived_at, no
  # overrides_used. R3.1 inverted - the entry claims nothing at all, silently.
  make_story 005-trunc complete
  chmod 555 "$PROJ/.epic/stories"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-trunc
  chmod 755 "$PROJ/.epic/stories"
  [ "$status" -ne 0 ]
  # Truncate the entry right after `status:` - what a kill mid-append leaves.
  python3 -c '
import sys
p = sys.argv[1]
out = []
for ln in open(p).read().splitlines(True):
    out.append(ln)
    if ln.startswith("    status:"):
        break
open(p, "w").write("".join(out))
' "$MANIFEST"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-trunc
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | grep -qi 'truncated'
  # Fail-closed on both counts: nothing moved, and no second entry beside it.
  [ -d "$PROJ/.epic/stories/005-trunc" ]
  [ ! -d "$PROJ/.epic/archive/005-trunc" ]
  [ "$(grep -c 'story: "005-trunc"' "$MANIFEST")" -eq 1 ]
}

@test "1.2: concurrent first-runs keep one header and lose no entry" {
  # `manifest_header > "$MANIFEST_FILE"` used `>`, which TRUNCATES. Two runs
  # could both pass `[[ ! -e ]]`, and the second erased the first run's entry
  # while that first run reported exit 0 and moved its story - the moved-story-
  # without-its-entry state R3.4 exists to make impossible.
  local n
  for n in 1 2 3 4 5 6; do make_story "00$n-race" complete; done
  for n in 1 2 3 4 5 6; do
    bash "$ARCHIVE_SH" ".epic/stories/00$n-race" > /dev/null 2>&1 &
  done
  wait
  [ -f "$MANIFEST" ]
  # Every story archived, every entry present, exactly one header.
  [ "$(ls -1 "$PROJ/.epic/archive" | grep -c -- '-race')" -eq 6 ]
  [ "$(grep -c '^  - story: ' "$MANIFEST")" -eq 6 ]
  [ "$(grep -c '^archived:' "$MANIFEST")" -eq 1 ]
  # ...and the result is loadable YAML with six complete entries.
  python3 -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
assert len(d["archived"]) == 6, d["archived"]
for e in d["archived"]:
    assert e["archived_at"], e
' "$MANIFEST"
}

# --- D: a verdict, with JSON, on the paths that used to die silently ---

@test "1.1: an unreadable tasks.md is refused with JSON, not a bare non-zero" {
  # `census_tasks` guarded with `[[ -f ]]` and then redirected `done < "$file"`.
  # `-f` says the file EXISTS, not that it opens: a bare failed redirection at
  # top level under `set -e` killed the shell with ZERO bytes on stdout - the
  # one thing the output contract promises never happens.
  make_story 005-noread complete
  chmod 000 "$PROJ/.epic/stories/005-noread/tasks.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-noread
  chmod 644 "$PROJ/.epic/stories/005-noread/tasks.md"
  [ "$status" -eq 1 ]
  [ -n "$output" ]
  echo "$output" | jq -e '.status == "refused" and .moved == false' > /dev/null
  echo "$output" | grep -q 'tasks.md'
  [ -d "$PROJ/.epic/stories/005-noread" ]
  [ ! -e "$MANIFEST" ]
}

@test "1.2: an unreadable clock blocks with JSON, not a bare non-zero" {
  # `ARCHIVED_AT=$(date -Iseconds)` takes the command's status, and `set -e` is
  # armed - so a `date` that fails (and `date -I` is GNU-only, so every BSD or
  # macOS host is that case) ended the run with no JSON at all.
  make_story 005-clock complete
  mkdir "$WORK/nodate"
  local t
  for t in /usr/bin/*; do ln -s "$t" "$WORK/nodate/${t##*/}" 2> /dev/null || true; done
  # rm first: writing THROUGH the symlink would try to overwrite /usr/bin/date.
  rm -f "$WORK/nodate/date"
  printf '#!/bin/sh\nexit 1\n' > "$WORK/nodate/date"
  chmod +x "$WORK/nodate/date"
  run --separate-stderr env PATH="$WORK/nodate" bash "$ARCHIVE_SH" .epic/stories/005-clock
  [ "$status" -eq 1 ]
  [ -n "$output" ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  # Fail-closed: an entry with no archived_at is a derived field the run cannot
  # support, so nothing is written and nothing moves.
  [ -d "$PROJ/.epic/stories/005-clock" ]
  [ ! -d "$PROJ/.epic/archive/005-clock" ]
}

# --- E: a derived value must appear in the artifact it was derived from ---

@test "1.2: a frontmatter value with a trailing comment is not squeezed into the manifest" {
  # `tr -d '[:space:]'` deleted whitespace INSIDE the value, not just at its
  # edges: `status: done  # closed early` became `done#closedearly`, which was
  # written verbatim into the permanent record - a derived field that appears
  # nowhere in the source artifact - and which no longer equals `done`, so the
  # completion branch refused a story that was genuinely done.
  make_story 005-cmt incomplete
  sed -i 's/^status: in-progress$/status: done  # closed early/' \
    "$PROJ/.epic/stories/005-cmt/story.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-cmt
  # The status branch sees `done`, so an incomplete story archives without
  # --force - which is exactly story 004's rule.
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.manifest_entry.status == "done"' > /dev/null
  grep -Eq 'status:[[:space:]]*"done"' "$MANIFEST"
  ! grep -q 'closedearly' "$MANIFEST"
}

# --- F: the destination is derived from the story's PHYSICAL location ---

@test "1.1: a symlinked story directory is refused, not archived outside the project" {
  # `pwd -P` resolves the symlink and EPIC_DIR was re-derived from the physical
  # path, so a `.epic/stories/005-sym -> /elsewhere/shared/stories/005-sym`
  # created /elsewhere/shared/archive/, wrote the manifest there, reported
  # `path: .epic/stories/005-sym` (where the story is NOT) and exited 0 - with
  # the destination outside the tree hook-archive-guard.sh protects.
  mkdir -p "$WORK/elsewhere/stories"
  make_story 005-real complete
  mv "$PROJ/.epic/stories/005-real" "$WORK/elsewhere/stories/005-sym"
  ln -s "$WORK/elsewhere/stories/005-sym" "$PROJ/.epic/stories/005-sym"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-sym
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused" and .moved == false' > /dev/null
  echo "$output" | grep -qi 'symlink'
  # Nothing was created anywhere: not in the project, not at the target.
  [ ! -d "$PROJ/.epic/archive" ]
  [ ! -e "$WORK/elsewhere/archive" ]
  [ -d "$WORK/elsewhere/stories/005-sym" ]
}

# --- G: a git error is not the same answer as "untracked" ---

@test "1.3: an ambient GIT_DIR does not send the story down the plain branch" {
  # `git -C <dir>` sets the working directory; it does NOT override GIT_DIR /
  # GIT_WORK_TREE / GIT_INDEX_FILE. Any run from a git hook or from
  # `git rebase --exec` exports them, so the probe answered about a DIFFERENT
  # repository - and a tracked story took the plain `mv`, silently dropping the
  # history R6.1 exists to preserve (or staged the rename into a foreign index).
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email test@example.com
  git -C "$PROJ" config user.name "Test"
  make_story 005-env complete
  git -C "$PROJ" add .epic
  git -C "$PROJ" commit -qm "seed story"
  mkdir "$WORK/other"
  git -C "$WORK/other" init -q
  run --separate-stderr env GIT_DIR="$WORK/other/.git" GIT_WORK_TREE="$WORK/other" \
    bash "$ARCHIVE_SH" .epic/stories/005-env
  [ "$status" -eq 0 ]
  # The rename is staged in the story's OWN repository...
  run git -C "$PROJ" diff --cached -M --name-status
  echo "$output" | grep -q '^R.*005-env/story\.md'
  # ...and the unrelated repository's index was never touched.
  run git -C "$WORK/other" diff --cached --name-status
  [ -z "$output" ]
}

@test "1.3: a tracked story whose trackedness git cannot answer is blocked, never guessed" {
  # `ls-files --error-unmatch` exits 1 for "untracked" and 128 for "could not
  # answer" (story inside a submodule, path outside the work tree, unreadable
  # index). Collapsing both into "take the plain branch" fails in the UNSAFE
  # direction, so 128 blocks instead.
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email test@example.com
  git -C "$PROJ" config user.name "Test"
  make_story 005-unreadable complete
  git -C "$PROJ" add .epic
  git -C "$PROJ" commit -qm "seed story"
  chmod 000 "$PROJ/.git/index"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-unreadable
  chmod 644 "$PROJ/.git/index"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  [ -d "$PROJ/.epic/stories/005-unreadable" ]
  [ ! -d "$PROJ/.epic/archive/005-unreadable" ]
}

# --- H: CRLF artifacts are transitioned, and a partial pass is not silent ---

@test "1.3: a CRLF artifact gets status archived instead of being silently skipped" {
  # `head -1 | grep -q '^---$'` fails on `---\r`, so on a checkout with
  # core.autocrlf=true the artifact was skipped - and the story archived with
  # story.md still claiming `done` while tasks.md said `archived`. The
  # "nothing applied" note stayed silent, because something HAD been applied.
  make_story 005-crlf complete
  python3 -c '
import sys
p = sys.argv[1]
d = open(p, "rb").read().replace(b"\n", b"\r\n")
open(p, "wb").write(d)
' "$PROJ/.epic/stories/005-crlf/story.md"
  grep -qa $'^---\r$' "$PROJ/.epic/stories/005-crlf/story.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-crlf
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epic/archive/005-crlf"
  # One story, one status - both artifacts agree, whatever their line endings.
  grep -q $'^status: archived\r$' "$arch/story.md"
  grep -q '^status: archived$' "$arch/tasks.md"
  # ...and the file keeps its CRLF endings rather than growing a mixed one.
  ! grep -qa $'[^\r]$' "$arch/story.md"
}

@test "1.3: an artifact left without frontmatter is named, not passed over in silence" {
  # The note used to fire only when NOTHING was applied. A PARTIAL application
  # is the worse case: the story sits in archive/ with its own artifacts
  # contradicting each other, which is the divergence validate-story.sh reports.
  make_story 005-partialfm complete
  printf '# Plain notes, no frontmatter block\n' \
    > "$PROJ/.epic/stories/005-partialfm/notes.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-partialfm
  [ "$status" -eq 0 ]
  grep -q '^status: archived' "$PROJ/.epic/archive/005-partialfm/story.md"
  # The skipped artifact is named on stderr, with the divergence spelled out.
  echo "$stderr" | grep -q 'notes.md'
  echo "$stderr" | grep -qi 'disagree'
}

# --- I: on the resume path, stdout describes what is actually RECORDED ---

@test "1.2: the resumed report describes the recorded entry, not a fresh derivation" {
  # Both renderings read the live variables, so a resume re-derived the entry
  # and reported values the manifest does not hold: archived_at always differed
  # (date re-runs) and so did every flag whenever the two runs were invoked
  # differently. The comment claimed the two "can never disagree"; on this path
  # they always did.
  make_story 005-recorded complete
  chmod 555 "$PROJ/.epic/stories"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-recorded \
    --force "waiting on vendor" --keep-logs
  chmod 755 "$PROJ/.epic/stories"
  [ "$status" -ne 0 ]
  [ -d "$PROJ/.epic/stories/005-recorded" ]
  local recorded_at
  recorded_at=$(grep -m1 'archived_at:' "$MANIFEST" | sed 's/.*archived_at: "\(.*\)"/\1/')
  [ -n "$recorded_at" ]
  # Re-run with DIFFERENT flags: the resume must report run 1's entry.
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-recorded \
    --force "giving up" --allow-heavy
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epic/archive/005-recorded" ]
  echo "$output" | jq -e '.manifest_entry.forced_reason == "waiting on vendor"' > /dev/null
  echo "$output" | jq -e '.manifest_entry.overrides_used == ["force","keep-logs"]' > /dev/null
  echo "$output" | jq --arg t "$recorded_at" -e '.manifest_entry.archived_at == $t' > /dev/null
  # Still exactly one entry, and the file is untouched by the second run.
  [ "$(grep -c 'story: "005-recorded"' "$MANIFEST")" -eq 1 ]
  grep -q 'forced_reason: "waiting on vendor"' "$MANIFEST"
  ! grep -q 'giving up' "$MANIFEST"
}

@test "1.1: a refusal names the orphan entry an interrupted forced run left behind" {
  # Run 1 with --force dies before the move; run 2 WITHOUT --force is refused
  # at preflight and never reaches the resume, so the orphan entry has no
  # command of its own to clean it. The refusal has to say so.
  make_story 005-orphan incomplete
  chmod 555 "$PROJ/.epic/stories"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-orphan --force "vendor"
  chmod 755 "$PROJ/.epic/stories"
  [ "$status" -ne 0 ]
  grep -q '005-orphan' "$MANIFEST"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-orphan
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  echo "$output" | jq -e '.reason | contains("interrupted run")' > /dev/null
  echo "$output" | jq -e '.reason | contains("--force")' > /dev/null
}

# --- J: cheap hardening ---

@test "1.1: a story directory whose name starts with a dash is reachable after --" {
  make_story -005-dashy complete
  run --separate-stderr bash "$ARCHIVE_SH" -- .epic/stories/-005-dashy
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epic/archive/-005-dashy" ]
}

@test "1.3: a DANGLING symlink in the destination slot blocks before the move" {
  # The pre-move check used `[[ -e ]]`, which FOLLOWS the link and is false for
  # a dangling one - so the move went ahead and failed with a bare ENOTDIR.
  make_story 005-dangle complete
  mkdir -p "$PROJ/.epic/archive"
  ln -s "$PROJ/.epic/archive/nowhere-at-all" "$PROJ/.epic/archive/005-dangle"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-dangle
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | grep -q 'already exists'
  [ -d "$PROJ/.epic/stories/005-dangle" ]
}

# --- 2.1 Weight/binary guard (R1.2, R1.4) ---

@test "2.1: text file over 10 MB blocks with the offender listed" {
  make_story 005-heavy complete
  yes 'padding line for the weight guard fixture' \
    | head -c 10485761 > "$PROJ/.epic/stories/005-heavy/big.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-heavy
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked"' > /dev/null
  echo "$output" | jq -e '(.guard.violations | length) >= 1' > /dev/null
  echo "$output" | grep -q 'big.txt'
  [ -d "$PROJ/.epic/stories/005-heavy" ]
  [ ! -d "$PROJ/.epic/archive/005-heavy" ]
}

@test "2.1: text file at exactly 10485760 bytes passes the weight guard" {
  make_story 005-boundary complete
  yes 'padding line for the weight guard fixture' \
    | head -c 10485760 > "$PROJ/.epic/stories/005-boundary/edge.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-boundary
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epic/archive/005-boundary" ]
}

@test "2.1: NUL-containing file blocks as non-text" {
  make_story 005-binary complete
  printf 'ab\0cd' > "$PROJ/.epic/stories/005-binary/blob.dat"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-binary
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked"' > /dev/null
  echo "$output" | grep -q 'blob.dat'
  [ ! -d "$PROJ/.epic/archive/005-binary" ]
}

@test "2.1: --allow-heavy archives and records the override" {
  make_story 005-allowed complete
  yes 'padding line for the weight guard fixture' \
    | head -c 10485761 > "$PROJ/.epic/stories/005-allowed/big.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-allowed --allow-heavy
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epic/archive/005-allowed" ]
  # R1.4: the override is recorded in the manifest entry.
  grep -q 'allow-heavy' "$MANIFEST"
}

# --- 2.2 Secrets guard (R1.3, R1.4, R1.8) ---
# Gated on gitleaks presence; the fixture key is a FAKE pattern (not a real
# credential) that the gitleaks aws rule detects.

@test "2.2: gitleaks finding blocks the archive with a findings count" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  make_story 005-leaky complete
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' \
    > "$PROJ/.epic/stories/005-leaky/notes-creds.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-leaky
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked"' > /dev/null
  echo "$output" | jq -e '.secrets.findings >= 1' > /dev/null
  [ -d "$PROJ/.epic/stories/005-leaky" ]
  [ ! -d "$PROJ/.epic/archive/005-leaky" ]
}

@test "2.2: --skip-secrets bypasses the scan and records the override" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  make_story 005-skipped complete
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' \
    > "$PROJ/.epic/stories/005-skipped/notes-creds.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-skipped --skip-secrets
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epic/archive/005-skipped" ]
  # R1.4: the override is recorded in the manifest entry.
  grep -q 'skip-secrets' "$MANIFEST"
}

@test "2.2: absent gitleaks proceeds and notes the skipped scan" {
  # R1.8 - simulate a machine without gitleaks via a PATH that mirrors
  # /usr/bin minus the gitleaks binary.
  mkdir "$WORK/nobin"
  local t
  for t in /usr/bin/*; do
    ln -s "$t" "$WORK/nobin/${t##*/}" 2> /dev/null || true
  done
  rm -f "$WORK/nobin/gitleaks"
  make_story 005-noscan complete
  run --separate-stderr env PATH="$WORK/nobin" bash "$ARCHIVE_SH" .epic/stories/005-noscan
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "archived"' > /dev/null
  [ -d "$PROJ/.epic/archive/005-noscan" ]
  # The skipped scan is noted in the structured output.
  printf '%s\n%s\n' "$output" "$stderr" | grep -qi 'gitleaks'
}

# --- 3.1 Log pruning (R2.1, R2.3) ---

@test "3.1: draft logs collapse into a single summary file" {
  make_story 005-logs complete
  mkdir -p "$PROJ/.epic/stories/005-logs/.draft/logs"
  seq 1 20000 > "$PROJ/.epic/stories/005-logs/.draft/logs/build.log"
  { seq 1 200; echo "FINAL LINE MARKER 005"; } \
    > "$PROJ/.epic/stories/005-logs/.draft/logs/test-run.log"
  touch -d '2026-08-01 10:00' "$PROJ/.epic/stories/005-logs/.draft/logs/build.log"
  touch -d '2026-08-01 11:00' "$PROJ/.epic/stories/005-logs/.draft/logs/test-run.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-logs
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epic/archive/005-logs"
  # R2.1: one summary carrying names + the tail of the most recent log...
  [ -f "$arch/.draft/logs-summary.md" ]
  grep -q 'build.log' "$arch/.draft/logs-summary.md"
  grep -q 'test-run.log' "$arch/.draft/logs-summary.md"
  grep -q 'FINAL LINE MARKER 005' "$arch/.draft/logs-summary.md"
  # ...and the raw log files are gone.
  [ ! -e "$arch/.draft/logs/build.log" ]
  [ ! -e "$arch/.draft/logs/test-run.log" ]
  echo "$output" | jq -e '.pruned.logs_kb > 0' > /dev/null
}

@test "3.1: --keep-logs preserves logs and records the override" {
  make_story 005-keeplogs complete
  mkdir -p "$PROJ/.epic/stories/005-keeplogs/.draft/logs"
  seq 1 200 > "$PROJ/.epic/stories/005-keeplogs/.draft/logs/build.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-keeplogs --keep-logs
  [ "$status" -eq 0 ]
  [ -f "$PROJ/.epic/archive/005-keeplogs/.draft/logs/build.log" ]
  # R2.3: the override is recorded.
  grep -q 'keep-logs' "$MANIFEST"
}

# --- 3.2 Byte-identical draft copies (R2.2, R2.3) ---

@test "3.2: byte-identical draft copy is removed and differing copy kept" {
  make_story 005-copies complete
  local story="$PROJ/.epic/stories/005-copies"
  mkdir -p "$story/.draft"
  echo 'promoted design body' > "$story/design.md"
  cp "$story/design.md" "$story/.draft/design.md"          # identical
  echo 'promoted notes v2' > "$story/notes.md"
  echo 'draft notes v1' > "$story/.draft/notes.md"          # differs
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-copies
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epic/archive/005-copies"
  [ ! -e "$arch/.draft/design.md" ]
  [ -f "$arch/.draft/notes.md" ]
  grep -q 'draft notes v1' "$arch/.draft/notes.md"
  echo "$output" | jq -e '.pruned.copies_removed == 1' > /dev/null
}

@test "3.2: --keep-copies preserves the duplicate and records the override" {
  make_story 005-keepcopies complete
  local story="$PROJ/.epic/stories/005-keepcopies"
  mkdir -p "$story/.draft"
  echo 'promoted design body' > "$story/design.md"
  cp "$story/design.md" "$story/.draft/design.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-keepcopies --keep-copies
  [ "$status" -eq 0 ]
  [ -f "$PROJ/.epic/archive/005-keepcopies/.draft/design.md" ]
  # R2.3: the override is recorded.
  grep -q 'keep-copies' "$MANIFEST"
}
