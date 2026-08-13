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

# make_bulky_story <dir-name> [deferred-count]
# A COMPLETE story (no `[ ]` left, status done) whose manifest entry runs to
# MANY LINES: `deferred_items:` gets one line per `[~]` box.
#
# Entry LENGTH IN LINES is what makes the append race reproducible. Bash
# line-buffers stdout, so `printf '%s\n' "$entry" >> file` is one write(2) PER
# LINE, and every one of those is a seam a concurrent archive can cut into.
# make_story's 3-box story is a 15-line entry and only tripped under whole-suite
# contention (1 run in 3); 40 boxes is a ~58-line entry and trips every time.
make_bulky_story() {
  local dir="$PROJ/.epic/stories/$1" n="${2:-40}" i
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

# Story - concurrency fixture
EOF
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-08-01'
    echo '---'
    echo
    echo '## Task List'
    echo '- [x] 1 - The one closed thing'
    for i in $(seq 1 "$n"); do
      echo "- [~] 2.$i - deferred item number $i with a reasonably long title (deferred: waiting on an external actor)"
    done
  } > "$dir/tasks.md"
}

# keep_concurrent_evidence <n-runs> - surface AND preserve everything a failure
# needs. The first version of this test sent all six runs to `> /dev/null 2>&1`,
# so the day it finally went red there was nothing left to diagnose it with: the
# corrupt manifest, every run's verdict and every stderr line died with the temp
# directory, and the bug had to be reproduced from scratch by a separate
# harness. EVERYTHING is copied out of $WORK (teardown deletes it) and the path
# is printed; inline, only the runs that did NOT archive are echoed, because 80
# successful JSON reports in a failure report bury the two that matter.
keep_concurrent_evidence() {
  local n keep verdict shown=0
  keep=$(mktemp -d "${TMPDIR:-/tmp}/archive-conc-evidence.XXXXXX")
  cp -- "$MANIFEST" "$keep/manifest.yaml" 2> /dev/null || true
  for n in $(seq 1 "$1"); do
    cp -- "$WORK/run.$n.out" "$keep/run.$n.out" 2> /dev/null || true
    cp -- "$WORK/run.$n.err" "$keep/run.$n.err" 2> /dev/null || true
    verdict=$(jq -r '.status // "NO-JSON"' < "$WORK/run.$n.out" 2> /dev/null || echo NO-JSON)
    if [ "$verdict" != archived ] && [ "$shown" -lt 5 ]; then
      shown=$((shown + 1))
      echo "--- run $n verdict=$verdict ---"
      cat -- "$WORK/run.$n.out" 2>&1 || true
      echo "--- run $n stderr ---"
      tail -5 -- "$WORK/run.$n.err" 2>&1 || true
    fi
  done
  echo "--- every run's stdout/stderr and the manifest preserved in $keep ---"
}

@test "1.2: concurrent first-runs keep one header and lose no entry" {
  # TWO bugs, one case.
  #
  # (1) `manifest_header > "$MANIFEST_FILE"` used `>`, which TRUNCATES. Two runs
  # could both pass `[[ ! -e ]]`, and the second erased the first run's entry
  # while that first run reported exit 0 and moved its story - the moved-story-
  # without-its-entry state R3.4 exists to make impossible.
  #
  # (2) the append itself was unsynchronized. `printf '%s\n' "$entry" >> file`
  # is NOT one write(2): bash line-buffers, so it is one write PER LINE, and two
  # concurrent archives interleave INSIDE an entry - entry B's keys landing in
  # the middle of entry A's `deferred_items:` list. O_APPEND loses no byte, so
  # the LINE COUNTS SURVIVE: `grep -c '^  - story: '` still reports N and every
  # entry still looks present. That is why this case must PARSE the document.
  #
  # WHY TEN ROUNDS. A collision needs two writers inside their append at the
  # same instant, and the append is ~60us against a spread of arrival times of
  # several ms - so ONE burst is a coin flip, not a proof. Measured against the
  # unfixed code: a single 8-writer burst corrupts about 5-7 times in 10, so ten
  # independent bursts miss with probability ~1e-4 at worst. Bigger entries do
  # NOT help (measured: 200 boxes drops the rate to 2/10, because the longer
  # census de-synchronizes the writers faster than it widens the window), and
  # neither does a FIFO start barrier (5/10). Repetition is what buys the power;
  # the deterministic pin of the mechanism itself is the mutual-exclusion case
  # below. All rounds share ONE manifest, exactly as real archives do, so a
  # single parse at the end catches a corruption from any of them.
  local rounds=10 writers=8 r n idx total=80
  for idx in $(seq 1 "$total"); do
    make_bulky_story "$(printf '%03d-race' "$idx")" 40
  done
  for r in $(seq 1 "$rounds"); do
    for n in $(seq 1 "$writers"); do
      idx=$(((r - 1) * writers + n))
      bash "$ARCHIVE_SH" ".epic/stories/$(printf '%03d-race' "$idx")" --skip-secrets \
        > "$WORK/run.$idx.out" 2> "$WORK/run.$idx.err" &
    done
    wait
  done

  local failed="" archived entries headers yamlerr
  [ -f "$MANIFEST" ] || failed+="no manifest was created; "
  archived=$(ls -1 "$PROJ/.epic/archive" 2> /dev/null | grep -c -- '-race' || true)
  [ "${archived:-0}" -eq "$total" ] || failed+="archived dirs ${archived:-0} != $total; "
  entries=$(grep -c '^  - story: ' "$MANIFEST" 2> /dev/null || true)
  [ "${entries:-0}" -eq "$total" ] || failed+="entry lines ${entries:-0} != $total; "
  headers=$(grep -c '^archived:' "$MANIFEST" 2> /dev/null || true)
  [ "${headers:-0}" -eq 1 ] || failed+="headers ${headers:-0} != 1; "
  # The load-bearing one: a document that PARSES, with N complete entries.
  yamlerr=$(python3 -c '
import sys, yaml
try:
    d = yaml.safe_load(open(sys.argv[1]))
except Exception as e:
    m = getattr(e, "problem_mark", None)
    where = " at line %d" % (m.line + 1) if m else ""
    print("PARSE " + str(e).splitlines()[0] + where)
    raise SystemExit(0)
a = (d or {}).get("archived") or []
if len(a) != int(sys.argv[2]):
    print("COUNT %d != %s" % (len(a), sys.argv[2]))
    raise SystemExit(0)
for e in a:
    if not e.get("archived_at") or not e.get("story"):
        print("INCOMPLETE " + repr(e)[:200])
        raise SystemExit(0)
print("OK")
' "$MANIFEST" "$total" 2>&1 || true)
  [ "$yamlerr" = OK ] || failed+="yaml: $yamlerr; "
  # No lock may survive a run that finished.
  [ ! -e "$PROJ/.epic/archive/.manifest.lock" ] || failed+="a manifest lock was left behind; "

  if [ -n "$failed" ]; then
    echo "CONCURRENCY FAILURE: $failed"
    case "$yamlerr" in
      *"at line "*)
        local ln="${yamlerr##*at line }"
        echo "--- manifest lines $((ln > 20 ? ln - 20 : 1))-$((ln + 5)) ---"
        sed -n "$((ln > 20 ? ln - 20 : 1)),$((ln + 5))p" "$MANIFEST" || true
        ;;
    esac
    keep_concurrent_evidence "$total"
    false
  fi
}

@test "1.2: an archive cannot append while another run holds the manifest lock" {
  # The DETERMINISTIC pin of the mechanism the case above can only pin
  # statistically. Mutual exclusion is not "two writers rarely collide" - it is
  # "while one run holds the lock, no other run writes a byte". So this case
  # takes the lock by hand, exactly the way manifest_append takes it, and
  # watches: with the lock honoured the archive waits and the manifest does not
  # grow; without it the append lands immediately and the assertion below fails
  # on every run, not on some of them.
  make_story 005-excl complete
  mkdir -p "$PROJ/.epic/archive"
  local lock="$PROJ/.epic/archive/.manifest.lock"
  mkdir "$lock"
  : > "$lock/owner.test-holder"
  # A pre-existing manifest, so "did it append?" is a question about SIZE and
  # not about whether the file was created at all.
  printf '%s\n' 'archived:' > "$MANIFEST"
  local before
  before=$(wc -c < "$MANIFEST")
  env EPIC_ARCHIVE_LOCK_TIMEOUT=30 bash "$ARCHIVE_SH" .epic/stories/005-excl \
    > "$WORK/excl.out" 2> "$WORK/excl.err" &
  local archiver=$!
  # Long enough for an unsynchronized append to have happened many times over:
  # the whole critical section is ~1ms.
  sleep 1
  local during
  during=$(wc -c < "$MANIFEST")
  [ "$during" -eq "$before" ] || {
    echo "the manifest grew from $before to $during bytes while the lock was held:"
    diff <(printf '%s\n' 'archived:') "$MANIFEST" || true
    kill "$archiver" 2> /dev/null || true
    wait "$archiver" 2> /dev/null || true
    false
  }
  # The story has not moved either - the append is before the move (R3.4).
  [ -d "$PROJ/.epic/stories/005-excl" ]
  # Release, and it finishes normally.
  rm -f "$lock"/owner.*
  rmdir "$lock"
  wait "$archiver"
  [ -d "$PROJ/.epic/archive/005-excl" ]
  [ "$(grep -c 'story: "005-excl"' "$MANIFEST")" -eq 1 ]
  jq -e '.status == "archived"' < "$WORK/excl.out" > /dev/null
}

@test "1.2: a stale manifest lock left by a killed run is broken, not inherited" {
  # The append is serialized by a lock directory. A run SIGKILLed inside the
  # critical section cannot release it, and a lock nobody will ever release
  # would wedge every future archive on the machine - the tool blocking forever
  # on a corpse. The break is identity-targeted (see manifest_lock_acquire) and
  # only fires on a marker that has not changed for the whole timeout, so it
  # cannot take a live lock. Timeout shortened here so the case does not sit
  # for the production 30s.
  make_story 005-stale complete
  mkdir -p "$PROJ/.epic/archive/.manifest.lock"
  : > "$PROJ/.epic/archive/.manifest.lock/owner.dead-4242-1"
  run --separate-stderr env EPIC_ARCHIVE_LOCK_TIMEOUT=1 \
    bash "$ARCHIVE_SH" .epic/stories/005-stale
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epic/archive/005-stale" ]
  # It says so, on stderr - breaking somebody's lock is never silent.
  echo "$stderr" | grep -qi 'breaking the manifest lock'
  # ...and the entry really is in there, and the lock is gone again.
  [ "$(grep -c 'story: "005-stale"' "$MANIFEST")" -eq 1 ]
  [ ! -e "$PROJ/.epic/archive/.manifest.lock" ]
}

@test "1.2: a manifest lock that keeps changing hands is waited for, never broken" {
  # The other half of the stale rule, and the one that keeps the break safe: a
  # lock is stale only when ONE identity has held it for the whole timeout. A
  # holder that finishes hands it on to the next run's nonce, which resets the
  # waiter's clock. A timeout measured against elapsed time ALONE would break
  # this busy lock and let a second writer into the middle of an entry.
  #
  # The simulated holder KEEPS THE DIRECTORY the whole time and only rotates the
  # marker inside it - the new marker is created BEFORE the old one is removed,
  # so the directory is never empty and never legitimately breakable. That is
  # the point being isolated: identity changed, ownership did not. (An earlier
  # version of this scaffold let the directory go and then wrote markers into a
  # path that no longer existed, so the "holder" held nothing, every write went
  # to stderr, and the case failed on its own scaffolding - hence the
  # holder-stderr assertion at the end, which turns that into a loud failure
  # rather than a mysterious one.)
  make_story 005-busy complete
  local lock="$PROJ/.epic/archive/.manifest.lock"
  mkdir -p "$PROJ/.epic/archive"
  mkdir "$lock"
  : > "$lock/owner.holder-0"
  # Held for ~2s - TWICE the timeout, so a stale check that ignored identity
  # would certainly fire - while the marker changes every ~0.1s.
  (
    i=1
    while [ "$i" -lt 20 ]; do
      sleep 0.1
      : > "$lock/owner.holder-$i"
      rm -f "$lock/owner.holder-$((i - 1))"
      i=$((i + 1))
    done
    rm -f "$lock"/owner.*
    rmdir "$lock"
  ) 2> "$WORK/holder.err" &
  local holder=$!
  run --separate-stderr env EPIC_ARCHIVE_LOCK_TIMEOUT=1 \
    bash "$ARCHIVE_SH" .epic/stories/005-busy
  wait "$holder" || true
  # The scaffold really did hold the lock for the whole window.
  [ ! -s "$WORK/holder.err" ] || {
    echo "holder scaffold failed:"
    cat "$WORK/holder.err"
    false
  }
  [ "$status" -eq 0 ]
  # It waited for the holder instead of taking the lock away from it...
  [[ "$stderr" != *"breaking the manifest lock"* ]]
  # ...and then did its own append, exactly once.
  [ "$(grep -c 'story: "005-busy"' "$MANIFEST")" -eq 1 ]
  [ -d "$PROJ/.epic/archive/005-busy" ]
  [ ! -e "$lock" ]
}

@test "1.2: a lock path that cannot be a lock is a verdict, not a 30-second wait" {
  # `mkdir` failing is TWO different answers: EEXIST means somebody holds the
  # lock and waiting is right; anything else (a plain file in the way, a
  # read-only archive directory, ENOSPC) means the lock can never appear and
  # waiting only delays the same verdict. Reading every failure as contention
  # costs a full timeout - twice, once for the stale break - before reporting.
  make_story 005-lockfile complete
  mkdir -p "$PROJ/.epic/archive"
  : > "$PROJ/.epic/archive/.manifest.lock"
  local t0=$SECONDS
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-lockfile
  local elapsed=$((SECONDS - t0))
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  # Fail-closed: no entry, nothing moved.
  [ -d "$PROJ/.epic/stories/005-lockfile" ]
  [ ! -d "$PROJ/.epic/archive/005-lockfile" ]
  # Reported at once - the default timeout is 30s, so anything near it means
  # the run sat waiting for a lock that could not exist.
  [ "$elapsed" -lt 10 ]
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
  # NOT `! grep -q …`: bash's set -e exempts a command inverted with `!`, so
  # such an assertion is a NO-OP anywhere but the last line of the body — and
  # one appended line turns even a working one into silence. See the 2.2 block.
  [[ "$(cat "$MANIFEST")" != *closedearly* ]]
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
  # `run` + an explicit status check, not `! grep …` — see the note at the
  # closedearly assertion: an inverted command is exempt from set -e.
  run grep -qa $'[^\r]$' "$arch/story.md"
  [ "$status" -ne 0 ]
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
  [[ "$(cat "$MANIFEST")" != *"giving up"* ]]
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

# ADDITIVE 2.1 cases appended at execution time. Each pins behavior the ToDo
# mandates that the four authored cases above leave unpinned. No assertion above
# was modified, weakened or deleted, and every case below was mutation-checked
# (break the fix -> the case fails).

@test "2.1: every offending file is listed, not just the first" {
  # R1.2 says "list EVERY offending file". A guard that stops at the first one
  # turns a clean-up into a game of whack-a-mole: block, delete, block again.
  make_story 005-many complete
  local story="$PROJ/.epic/stories/005-many"
  yes 'padding line for the weight guard fixture' | head -c 10485761 > "$story/first.txt"
  yes 'padding line for the weight guard fixture' | head -c 10485762 > "$story/second.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-many
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '(.guard.violations | length) == 2' > /dev/null
  echo "$output" | jq -e '[.guard.violations[].file | endswith("first.txt")] | any' > /dev/null
  echo "$output" | jq -e '[.guard.violations[].file | endswith("second.txt")] | any' > /dev/null
  # The human reason carries both too - it is what the orchestrator surfaces.
  echo "$output" | jq -e '.reason | contains("first.txt") and contains("second.txt")' > /dev/null
  [ ! -d "$PROJ/.epic/archive/005-many" ]
}

@test "2.1: each violation carries the offending file's size and its reason" {
  # R1.2 asks for the size AND the reason per offender. As a NUMBER in a field,
  # not a figure a consumer has to fish back out of a prose sentence.
  make_story 005-sized complete
  yes 'padding line for the weight guard fixture' \
    | head -c 10485761 > "$PROJ/.epic/stories/005-sized/big.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-sized
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.guard.violations[0]
    | has("file") and has("size") and has("reason")' > /dev/null
  echo "$output" | jq -e '.guard.violations[0].size == 10485761' > /dev/null
  echo "$output" | jq -e '.guard.violations[0].size | type == "number"' > /dev/null
  echo "$output" | jq -e '.guard.violations[0].reason | test("larger than")' > /dev/null
  # The prose list states the size as well, so a human reading only `reason`
  # learns by how much the file missed.
  echo "$output" | jq -e '.reason | contains("10485761")' > /dev/null
}

@test "2.1: a file inside .draft/ is scanned like any other" {
  # The guard walks the whole story tree: a blob is no lighter for sitting one
  # directory down, and .draft/ is exactly where the corpus put its evidence.
  make_story 005-draftblob complete
  mkdir -p "$PROJ/.epic/stories/005-draftblob/.draft/logs"
  printf 'core\0dump' > "$PROJ/.epic/stories/005-draftblob/.draft/logs/crash.dump"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-draftblob
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked"' > /dev/null
  echo "$output" | jq -e '[.guard.violations[].file
    | endswith(".draft/logs/crash.dump")] | any' > /dev/null
  [ -d "$PROJ/.epic/stories/005-draftblob" ]
  [ ! -d "$PROJ/.epic/archive/005-draftblob" ]
}

@test "2.1: a UTF-16 text artifact is blocked as non-text, with --allow-heavy as the escape" {
  # THE RISK NAMED IN THE PARENT TASK, pinned as a decision rather than left to
  # be rediscovered: a UTF-16 file is real text, and it IS reported as binary,
  # because every ASCII-range character it holds carries a NUL byte.
  # Kept deliberately. A BOM exemption would miss BOM-less UTF-16 anyway AND
  # hand any 2.3 GB blob a two-byte prefix that buys it a free pass - the exact
  # hole this guard exists to close. So the verdict has to EXPLAIN itself, and
  # --allow-heavy is the recorded escape.
  make_story 005-utf16 complete
  python3 -c '
import sys
open(sys.argv[1], "wb").write("# Notes\nplain readable text\n".encode("utf-16-le"))
' "$PROJ/.epic/stories/005-utf16/notes-utf16.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-utf16
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked"' > /dev/null
  echo "$output" | jq -e '[.guard.violations[].file
    | endswith("notes-utf16.md")] | any' > /dev/null
  # The reason names the edge, so nobody has to guess why a text file is binary.
  echo "$output" | jq -e '.guard.violations[0].reason | test("UTF-16")' > /dev/null
  # ...and the documented way out works, recorded as an override.
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-utf16 --allow-heavy
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epic/archive/005-utf16" ]
  grep -q 'allow-heavy' "$MANIFEST"
}

@test "2.1: an empty file and a newline-only file are text, not binary" {
  # `grep -qI .` finds no character on either of them, so reading its exit code
  # as "binary" would block a clean story over an empty placeholder - the guard
  # failing in the direction that costs trust rather than safety.
  make_story 005-emptyish complete
  : > "$PROJ/.epic/stories/005-emptyish/.gitkeep"
  printf '\n\n\n' > "$PROJ/.epic/stories/005-emptyish/blank-lines.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-emptyish
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.guard.violations | length) == 0' > /dev/null
  [ -d "$PROJ/.epic/archive/005-emptyish" ]
}

@test "2.1: a blocked story leaves no manifest entry and no archive directory" {
  # The step order, asserted from the outside: the guard runs BEFORE the append
  # (step 5) and the move (step 6). A blocked story that had already been
  # written into the permanent record would be a record of an archive that
  # never happened - and .epic/archive/ is deliberately hard to repair.
  make_story 005-nowrite complete
  printf 'ab\0cd' > "$PROJ/.epic/stories/005-nowrite/blob.dat"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-nowrite
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | jq -e '.manifest_entry == {}' > /dev/null
  [ ! -e "$MANIFEST" ]
  [ ! -d "$PROJ/.epic/archive" ]
  [ -f "$PROJ/.epic/stories/005-nowrite/story.md" ]
  [ -f "$PROJ/.epic/stories/005-nowrite/blob.dat" ]
}

@test "2.1: a file the guard cannot read is a reported verdict, not a silent abort" {
  # `[[ -f ]]` says a file EXISTS, not that it opens. A `grep` that fails on an
  # unreadable file exits 2, and taking that for "no match, therefore text"
  # would clear a file nobody inspected; letting it abort under `set -e` would
  # end the run with zero bytes on stdout, which the output contract promises
  # never happens. Fail closed, with JSON, naming the file.
  make_story 005-opaque complete
  printf 'plain readable text\n' > "$PROJ/.epic/stories/005-opaque/opaque.txt"
  chmod 000 "$PROJ/.epic/stories/005-opaque/opaque.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-opaque
  # `|| true`: if the guard ever stops blocking, the story is MOVED and this
  # path is gone - and the case must then fail on its assertion, not die here
  # on the fixture cleanup. (teardown chmods the whole work tree anyway.)
  chmod 644 "$PROJ/.epic/stories/005-opaque/opaque.txt" 2> /dev/null || true
  [ "$status" -eq 1 ]
  [ -n "$output" ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | jq -e '[.guard.violations[].file | endswith("opaque.txt")] | any' > /dev/null
  echo "$output" | jq -e '.guard.violations[0].reason | test("cannot be read")' > /dev/null
  [ -d "$PROJ/.epic/stories/005-opaque" ]
  [ ! -d "$PROJ/.epic/archive/005-opaque" ]
}

@test "2.1: a tree the guard cannot fully enumerate blocks instead of passing" {
  # The quiet way for a guard to fail is to pass on a tree it never saw: a
  # directory it cannot descend into makes `find` exit non-zero AFTER printing
  # the files it did reach, and a scan that reads only the output would clear a
  # story on the strength of a partial list. Same rule as everywhere else here -
  # what the guard cannot see, it cannot clear.
  make_story 005-locked complete
  mkdir -p "$PROJ/.epic/stories/005-locked/.draft/locked"
  printf 'ab\0cd' > "$PROJ/.epic/stories/005-locked/.draft/locked/hidden.dat"
  chmod 000 "$PROJ/.epic/stories/005-locked/.draft/locked"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-locked
  chmod 755 "$PROJ/.epic/stories/005-locked/.draft/locked" 2> /dev/null || true
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | jq -e '[.guard.violations[].reason
    | test("cannot enumerate")] | any' > /dev/null
  [ -d "$PROJ/.epic/stories/005-locked" ]
  [ ! -d "$PROJ/.epic/archive/005-locked" ]
}

@test "2.1: a 2 GB-class binary is blocked with the offender and its size listed" {
  # story.md's success metric, in the shape the corpus actually produced: zeo-002
  # archived a 2.3 GB binary. The fixture is sparse, so it costs no disk - and
  # the guard must not have to READ it to refuse it (size first, then text).
  make_story 005-zeo complete
  truncate -s 2469606195 "$PROJ/.epic/stories/005-zeo/vendor-blob.bin"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-zeo
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked"' > /dev/null
  echo "$output" | jq -e '.guard.violations[0].size == 2469606195' > /dev/null
  echo "$output" | grep -q 'vendor-blob.bin'
  # It is refused for its WEIGHT, and that assertion is what makes this case a
  # discriminator: a sparse file is all NUL bytes, so a guard that read it first
  # would block it as "non-text" and look just as correct while the 10 MB rule
  # sat broken. The size test runs first precisely so 2.3 GB is never read.
  echo "$output" | jq -e '.guard.violations[0].reason | test("larger than")' > /dev/null
  [ -d "$PROJ/.epic/stories/005-zeo" ]
  [ ! -d "$PROJ/.epic/archive/005-zeo" ]
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

# ADDITIVE 2.2 cases appended at execution time. Each pins behavior the ToDo
# mandates that the three authored cases above leave unpinned. No assertion
# above was modified, weakened or deleted, and every case below was
# mutation-checked (break the fix -> the case fails).

# gl_shim_path <exit-code> - a PATH directory mirroring /usr/bin with a FAKE
# `gitleaks` that exits with the given code and writes NO report. Same mirroring
# trick the 1.2 clock case uses; a shim is the only honest way to produce a scan
# failure, since the real binary cannot be made to fail on demand.
#
# The shim's diagnostic is deliberately NASTY - ANSI escapes (which gitleaks
# really does emit, even into a pipe), a double quote, DEL and a C1 byte. That
# text is external data spliced into the JSON `secrets.error`, so it exercises
# the union escaper on the one path where arbitrary bytes from another program
# reach this script's output.
gl_shim_path() {
  local code="$1" dir="$WORK/glshim-$1" t
  mkdir -p "$dir"
  for t in /usr/bin/*; do ln -s "$t" "$dir/${t##*/}" 2> /dev/null || true; done
  # rm first: writing THROUGH the symlink would try to overwrite /usr/bin/gitleaks.
  rm -f "$dir/gitleaks"
  {
    echo '#!/bin/sh'
    printf 'printf %s >&2\n' "'FTL \\033[1mboom\\033[0m \"quoted\" del=\\177 c1=\\302\\206\\n'"
    printf 'exit %s\n' "$code"
  } > "$dir/gitleaks"
  chmod +x "$dir/gitleaks"
  printf '%s' "$dir"
}

@test "2.2: a scan that exits neither 0 nor 1 blocks instead of passing" {
  # THE difference between "scanned and clean" and "never actually scanned".
  # A scanner that RAN and could not answer is a guard hit like any other -
  # only an ABSENT scanner is the documented degradation (R1.8). Collapsing the
  # two turns every broken gitleaks on every machine into a silent free pass.
  make_story 005-scanfail complete
  local p
  p=$(gl_shim_path 7)
  run --separate-stderr env PATH="$p" bash "$ARCHIVE_SH" .epic/stories/005-scanfail
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  # Not a clean scan, and not findings either - the report says which.
  echo "$output" | jq -e '.secrets.scanned == false' > /dev/null
  echo "$output" | jq -e '.secrets.findings == null' > /dev/null
  echo "$output" | jq -e '.secrets.error | test("exited 7")' > /dev/null
  echo "$output" | jq -e '.reason | test("FAILED")' > /dev/null
  # The size census runs BEFORE the scan, so this one is a real measurement
  # (no oversized file in the fixture) rather than the untaken-count null below.
  echo "$output" | jq -e '.secrets.unscanned_files == 0' > /dev/null
  # The scanner's own diagnostic is arbitrary bytes from another program spliced
  # into a JSON string. stdout must still parse, and round-trip what went in.
  echo "$output" | jq -e . > /dev/null
  echo "$output" | jq -e '.secrets.error | contains("[1mboom")' > /dev/null
  echo "$output" | jq -e '.secrets.error | contains("\"quoted\"")' > /dev/null
  echo "$output" | jq -e '.secrets.error | contains("del=")' > /dev/null
  echo "$output" | jq -e '.secrets.error | contains("c1=")' > /dev/null
  # Fail-closed: nothing moved, nothing recorded.
  [ -d "$PROJ/.epic/stories/005-scanfail" ]
  [ ! -d "$PROJ/.epic/archive/005-scanfail" ]
  [ ! -e "$MANIFEST" ]
}

@test "2.2: gitleaks' own fatal exit 1 is a scan failure, not a findings count" {
  # gitleaks exits 1 for FINDINGS *and* for its own fatal errors - an
  # unparseable config, an unwritable report path, a target that does not exist.
  # So the exit code alone cannot tell "found something" from "never looked",
  # and the naive reading of `--exit-code 1` reports a scan that never ran as
  # `findings: 0`. The REPORT is the discriminator: gitleaks writes it only
  # after a scan that actually ran.
  make_story 005-fatal complete
  local p
  p=$(gl_shim_path 1)
  run --separate-stderr env PATH="$p" bash "$ARCHIVE_SH" .epic/stories/005-fatal
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | jq -e '.secrets.scanned == false' > /dev/null
  # The one assertion that matters: it is NOT reported as a clean scan.
  echo "$output" | jq -e '.secrets.findings == null' > /dev/null
  echo "$output" | jq -e '.secrets.error | test("without writing a readable JSON report")' > /dev/null
  [ -d "$PROJ/.epic/stories/005-fatal" ]
  [ ! -e "$MANIFEST" ]
  # No report survives this path, so none is named: pointing an operator at a
  # file the run has just deleted is the same mistake as a false "nothing moved".
  echo "$output" | jq -e '.secrets.report == null' > /dev/null
  echo "$output" | jq -e '.secrets.error | test("/tmp/") | not' > /dev/null
}

@test "2.2: exit 0 without a report is a scanner that answered without looking" {
  # The mirror of the exit-1 fatal above, and the branch no shim reached until
  # now: a CLEAN exit is trusted only when a report proves a scan happened.
  # gitleaks writes the report after the scan, so exit 0 with nothing on disk
  # is an answer with no scan behind it — which must not become `findings: 0`.
  # Found by the orchestrator: mutating this check away left every existing
  # 2.2 case green, so the branch was implemented but pinned by nothing.
  make_story 005-noreport complete
  local p
  p=$(gl_shim_path 0)
  run --separate-stderr env PATH="$p" bash "$ARCHIVE_SH" .epic/stories/005-noreport
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | jq -e '.secrets.scanned == false' > /dev/null
  # The assertion that carries the whole case: a scan that did not happen is
  # never reported as a scan that found nothing.
  echo "$output" | jq -e '.secrets.findings == null' > /dev/null
  echo "$output" | jq -e '.secrets.error | test("exited 0 but wrote no readable JSON report")' > /dev/null
  # No surviving report, so none is named (same rule as the exit-1 fatal case).
  echo "$output" | jq -e '.secrets.report == null' > /dev/null
  # Fail-closed: the guard precedes the append and the move.
  [ -d "$PROJ/.epic/stories/005-noreport" ]
  [ ! -d "$PROJ/.epic/archive/005-noreport" ]
  [ ! -e "$MANIFEST" ]
}

@test "2.2: the absent-scanner note says WHAT was skipped, not just the scanner's name" {
  # The authored case greps stdout+stderr for 'gitleaks' - which the constant
  # `"scanner": "gitleaks"` key satisfies ON ITS OWN, so it cannot tell a real
  # note from no note at all (mutation-checked: strip both notes and it still
  # reports ok). R1.8 asks for the SKIPPED SCAN to be noted, so that is what
  # this pins, in both registers.
  mkdir "$WORK/nobin2"
  local t
  for t in /usr/bin/*; do ln -s "$t" "$WORK/nobin2/${t##*/}" 2> /dev/null || true; done
  rm -f "$WORK/nobin2/gitleaks"
  make_story 005-nonote complete
  run --separate-stderr env PATH="$WORK/nobin2" bash "$ARCHIVE_SH" .epic/stories/005-nonote
  [ "$status" -eq 0 ]
  # Structurally on stdout, where the orchestrator's jq can see it...
  echo "$output" | jq -e '.secrets.scanned == false' > /dev/null
  echo "$output" | jq -e '.secrets.skipped == "gitleaks not installed"' > /dev/null
  echo "$output" | jq -e '.secrets.findings == null' > /dev/null
  # ...and in prose on stderr, in the guard's key=value shape, for the human.
  echo "$stderr" | grep -q 'guard=secrets verdict=skipped'
  echo "$stderr" | grep -q 'reason=gitleaks-not-installed'
  echo "$stderr" | grep -q 'UNSCANNED'
}

@test "2.2: a clean story reports a scan that RAN, and silence still means not-run" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # `secrets: {}` used to be the only value there was, so every consumer had to
  # read silence as safety. A clean archive must now say so POSITIVELY...
  make_story 005-clean complete
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-clean
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.secrets.scanned == true' > /dev/null
  echo "$output" | jq -e '.secrets.findings == 0' > /dev/null
  echo "$output" | jq -e '.secrets.skipped == null and .secrets.error == null' > /dev/null
  # ...and `{}` keeps its own meaning, which is the other half of the pair: a
  # story blocked at step 2 never reaches the scanner, so it must not read as
  # clean either.
  make_story 005-cleanbin complete
  printf 'ab\0cd' > "$PROJ/.epic/stories/005-cleanbin/blob.dat"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-cleanbin
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.secrets == {}' > /dev/null
}

@test "2.2: --skip-secrets on a story that really holds a secret archives, and the skip shows" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # R1.4 on the path that actually exercises the override: the authored case
  # asserts the exit code and the manifest, but a skip that LOOKS like a clean
  # scan in the report is worse than no scan at all.
  make_story 005-leakskip complete
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' \
    > "$PROJ/.epic/stories/005-leakskip/notes-creds.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-leakskip --skip-secrets
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epic/archive/005-leakskip" ]
  echo "$output" | jq -e '.secrets.scanned == false' > /dev/null
  echo "$output" | jq -e '.secrets.findings == null' > /dev/null
  echo "$output" | jq -e '.secrets.skipped == "--skip-secrets"' > /dev/null
  # Nothing was measured on this path, so no count claims to be one.
  echo "$output" | jq -e '.secrets.unscanned_files == null' > /dev/null
  # R1.4: recorded in the entry, on stdout and in the permanent record.
  echo "$output" | jq -e '.manifest_entry.overrides_used | index("skip-secrets") != null' > /dev/null
  grep -q 'skip-secrets' "$MANIFEST"
  # Archive does not scrub: the file travels as it is...
  grep -q 'AKIAQWERTYUIOPASDFGH' "$PROJ/.epic/archive/005-leakskip/notes-creds.md"
  # ...but the secret is never copied into the manifest. (`[[ != ]]` rather than
  # `! grep`: see the note in the no-secret-material case - a `!` that is not
  # the last line of the body can never fail a bats test.)
  [[ "$(cat "$MANIFEST")" != *AKIAQWERTYUIOPASDFGH* ]]
}

@test "2.2: the findings count is the real count, not a boolean" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # R1.3 says "reporting the findings count". A guard that answers 1 for any
  # number of leaks tells the operator nothing about the size of the clean-up.
  make_story 005-two complete
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' \
    > "$PROJ/.epic/stories/005-two/creds-a.md"
  printf 'aws_access_key_id = "AKIAZXCVBNMASDFGHJKL"\n' \
    > "$PROJ/.epic/stories/005-two/creds-b.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-two
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.secrets.findings == 2' > /dev/null
  echo "$output" | jq -e '.secrets.findings | type == "number"' > /dev/null
  # The human reason carries the count too - it is what the orchestrator surfaces.
  echo "$output" | jq -e '.reason | contains("2 secret")' > /dev/null
}

@test "2.2: no secret material reaches stdout, stderr or the permanent record" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # A guard that quotes the leak into its own diagnostics copies it into every
  # log that captures the run - CI output, shell history, an orchestrator
  # transcript. The count and the report PATH are what leave this process.
  make_story 005-quiet complete
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' \
    > "$PROJ/.epic/stories/005-quiet/notes-creds.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-quiet
  [ "$status" -eq 1 ]
  # `[[ != ]]`, NOT `! grep -q ...`: bash exempts a `!`-inverted command from
  # `set -e`, so a `! cmd` anywhere but the LAST line of a bats test body is a
  # no-op that can never fail the case. Mutation-checked - with the secret
  # deliberately spliced into the block reason, the `!` form still reported ok.
  [[ "$output" != *AKIAQWERTYUIOPASDFGH* ]]
  [[ "$stderr" != *AKIAQWERTYUIOPASDFGH* ]]
  [ ! -e "$MANIFEST" ]
  # The report path IS reported, so the operator can go and read it.
  echo "$output" | jq -e '.secrets.report | test("gitleaks-report.json")' > /dev/null
}

@test "2.2: a story blocked on secrets leaves no manifest entry and no archive directory" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # The step order, asserted from the outside: the secrets guard runs BEFORE the
  # prune (step 4), the append (step 5) and the move (step 6). A blocked story
  # already written into the permanent record would be a record of an archive
  # that never happened, under a tree that is deliberately hard to repair.
  make_story 005-order complete
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' \
    > "$PROJ/.epic/stories/005-order/notes-creds.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-order
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | jq -e '.manifest_entry == {}' > /dev/null
  [ ! -e "$MANIFEST" ]
  [ ! -d "$PROJ/.epic/archive" ]
  [ -f "$PROJ/.epic/stories/005-order/notes-creds.md" ]
  [ -f "$PROJ/.epic/stories/005-order/story.md" ]
}

@test "2.2: the scan report lives outside the project and never rides into the archive" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # gitleaks' JSON report holds the MATCHED SECRET, the file and the line. Two
  # places it must never be: world-readable in a shared temp directory, and
  # inside the story - where it would travel into .epic/archive/ with the move
  # and become a permanent copy of exactly what the guard just objected to.
  make_story 005-reportpath complete
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' \
    > "$PROJ/.epic/stories/005-reportpath/notes-creds.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-reportpath
  [ "$status" -eq 1 ]
  local rp
  rp=$(echo "$output" | jq -r '.secrets.report')
  [ -n "$rp" ] && [ "$rp" != "null" ]
  [[ "$rp" != "$PROJ"/* ]]
  [ -f "$rp" ]
  grep -q 'AKIAQWERTYUIOPASDFGH' "$rp"
  [ "$(stat -c %a "$rp")" = "600" ]
  [ "$(stat -c %a "$(dirname "$rp")")" = "700" ]
  rm -rf "$(dirname "$rp")"
  # A CLEAN scan keeps nothing: `[]` is not evidence, and nothing gitleaks-shaped
  # may end up in the archived story.
  make_story 005-reportgone complete
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-reportgone
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.secrets.report == null' > /dev/null
  [ -z "$(find "$PROJ/.epic/archive/005-reportgone" -name '*gitleaks*' -print -quit)" ]
}

@test "2.2: a file over the scanner's size limit is reported as unscanned, not as clean" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # PINNED AS A DECISION, not left to be rediscovered: --max-target-megabytes 15
  # makes gitleaks skip any file over 15,000,000 bytes (decimal MB, probed
  # exactly: 15000000 is scanned, 15000001 is not) WITHOUT saying so - it exits
  # 0 and reports "no leaks found". A scanner that silently skips the biggest
  # file in the tree while reporting clean is the exact failure R1.3 exists to
  # prevent. Step 2 blocks anything over 10 MB, so only --allow-heavy can bring
  # a file this size to the scanner at all - and when it does, the archive says
  # what the pass does NOT cover.
  make_story 005-toobig complete
  {
    printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n'
    head -c 15000001 /dev/zero | tr '\0' 'a'
  } > "$PROJ/.epic/stories/005-toobig/huge-notes.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-toobig --allow-heavy
  [ "$status" -eq 0 ]
  # The scan passes with a plaintext key sitting in the story...
  echo "$output" | jq -e '.secrets.scanned == true and .secrets.findings == 0' > /dev/null
  # ...so it must not be allowed to imply the file was looked at.
  echo "$output" | jq -e '.secrets.unscanned_files == 1' > /dev/null
  echo "$stderr" | grep -q 'huge-notes.md'
  echo "$stderr" | grep -qi 'skips'
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

# ADDITIVE 3.1 cases appended at execution time. Each pins behavior the ToDo
# mandates that the two authored cases leave unpinned. No authored assertion was
# modified, weakened or deleted, and every case below was mutation-checked
# (break the fix -> the case fails).
#
# NOTE ON THE AUTHORED PAIR: `3.1: --keep-logs preserves logs and records the
# override` was ALREADY GREEN before this sub-task, because nothing pruned at
# all - it could not tell "the flag was honoured" from "the feature does not
# exist". It only becomes a discriminator now that the prune exists, which is
# why `--keep-logs writes no summary at all` sits beside it.

# make_log_story <dir-name> [lines] - a COMPLETE story with .draft/logs/build.log
make_log_story() {
  local dir="$PROJ/.epic/stories/$1"
  make_story "$1" complete
  mkdir -p "$dir/.draft/logs"
  seq 1 "${2:-500}" > "$dir/.draft/logs/build.log"
}

@test "3.1: a story blocked by the weight guard keeps every log file" {
  # THE STEP ORDER, asserted from outside the script. Prune is the FIRST
  # destructive step in the pipeline, so it must be unreachable on any path that
  # can still return `blocked`. A prune that ran before the guards would collapse
  # these logs and THEN refuse the archive - evidence destroyed for a story that
  # was never archived at all, and nothing left to re-run against.
  make_log_story 005-blockedlogs 2000
  local story="$PROJ/.epic/stories/005-blockedlogs"
  yes 'padding line for the weight guard fixture' | head -c 10485761 > "$story/big.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-blockedlogs
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  # The logs are untouched, byte for byte, and no summary was written...
  [ -f "$story/.draft/logs/build.log" ]
  [ "$(wc -l < "$story/.draft/logs/build.log")" -eq 2000 ]
  [ ! -e "$story/.draft/logs-summary.md" ]
  echo "$output" | jq -e '.pruned.logs_kb == 0' > /dev/null
  # ...and the prune never announced itself at all. (`[[ != ]]`, not `! grep`:
  # an inverted command is exempt from set -e - see the 2.2 discovery.)
  [[ "$stderr" != *"prune=logs"* ]]
}

@test "3.1: a story blocked by the secrets guard keeps every log file" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # The same assertion against the OTHER guard, because the two block from
  # different steps and only running both proves the prune sits after each.
  make_log_story 005-leakylogs 2000
  local story="$PROJ/.epic/stories/005-leakylogs"
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' > "$story/notes-creds.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-leakylogs
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  [ -f "$story/.draft/logs/build.log" ]
  [ "$(wc -l < "$story/.draft/logs/build.log")" -eq 2000 ]
  [ ! -e "$story/.draft/logs-summary.md" ]
  [[ "$stderr" != *"prune=logs"* ]]
}

@test "3.1: the prune reports itself after both guards, never before" {
  # The other half of the pair: the two cases above prove the prune does not run
  # when a guard blocks; this proves that when it DOES run, it runs last. All
  # three verdicts are key=value lines on stderr, so the ORDER is readable
  # without parsing prose - and `guards_passed=true` is the script's own
  # sequence assertion, stated where a test can see it.
  make_log_story 005-order31 500
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-order31
  [ "$status" -eq 0 ]
  local weight secrets prune
  weight=$(echo "$stderr" | grep -n 'guard=weight-binary' | head -1 | cut -d: -f1)
  secrets=$(echo "$stderr" | grep -n 'guard=secrets' | head -1 | cut -d: -f1)
  prune=$(echo "$stderr" | grep -n 'prune=logs' | head -1 | cut -d: -f1)
  [ -n "$weight" ]
  [ -n "$secrets" ]
  [ -n "$prune" ]
  [ "$prune" -gt "$weight" ]
  [ "$prune" -gt "$secrets" ]
  echo "$stderr" | grep -q 'prune=logs verdict=pruned.*guards_passed=true'
}

@test "3.1: logs_kb measures what was actually freed, not a constant" {
  # The sub-task's Validation criterion is "pruned.logs_kb ~ freed size". A
  # constant, a boolean or a file count would satisfy the authored `> 0` just as
  # well, so this asserts the EXACT arithmetic on two fixtures whose log sizes
  # differ by two orders of magnitude. Rounded UP, deliberately: integer division
  # reports 0 for anything under a kilobyte, and `logs_kb: 0` already means
  # "nothing was freed".
  make_story 005-kbsmall complete
  mkdir -p "$PROJ/.epic/stories/005-kbsmall/.draft/logs"
  head -c 30000 /dev/zero | tr '\0' 'a' \
    > "$PROJ/.epic/stories/005-kbsmall/.draft/logs/small.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-kbsmall
  [ "$status" -eq 0 ]
  # ceil(30000 / 1024) == 30
  echo "$output" | jq -e '.pruned.logs_kb == 30' > /dev/null

  make_story 005-kbbig complete
  mkdir -p "$PROJ/.epic/stories/005-kbbig/.draft/logs"
  head -c 3000000 /dev/zero | tr '\0' 'a' \
    > "$PROJ/.epic/stories/005-kbbig/.draft/logs/big.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-kbbig
  [ "$status" -eq 0 ]
  # ceil(3000000 / 1024) == 2930
  echo "$output" | jq -e '.pruned.logs_kb == 2930' > /dev/null
  # ...and the measurement reaches the permanent record, not just stdout.
  grep -Eq 'logs_kb:[[:space:]]*2930' "$MANIFEST"
}

@test "3.1: the summary records each log's size and last-modified time, not just its name" {
  # R2.1 asks for the NAME, the SIZE and the LAST-MODIFIED TIME of every log.
  # The authored case greps for the two names only - which a summary listing
  # nothing but names would satisfy exactly as well.
  make_story 005-facts complete
  local d="$PROJ/.epic/stories/005-facts/.draft/logs"
  mkdir -p "$d"
  head -c 4096 /dev/zero | tr '\0' 'x' > "$d/first.log"
  head -c 8192 /dev/zero | tr '\0' 'y' > "$d/second.log"
  touch -d '2026-08-01 10:00' "$d/first.log"
  touch -d '2026-08-02 11:30' "$d/second.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-facts
  [ "$status" -eq 0 ]
  local s="$PROJ/.epic/archive/005-facts/.draft/logs-summary.md"
  [ -f "$s" ]
  grep -q 'size_bytes: 4096' "$s"
  grep -q 'size_bytes: 8192' "$s"
  # `touch -d` and `stat %y` both speak local time, so the two agree whatever
  # TZ the machine running the suite is set to.
  grep -q '2026-08-01 10:00' "$s"
  grep -q '2026-08-02 11:30' "$s"
}

@test "3.1: a single log collapses, and its own tail is the one recorded" {
  # The degenerate case of "the most recently modified log": one file, which is
  # both the newest and the oldest. It must not crash and must not skip the tail.
  make_story 005-onelog complete
  local d="$PROJ/.epic/stories/005-onelog/.draft/logs"
  mkdir -p "$d"
  { seq 1 100; echo 'ONLY LOG MARKER'; } > "$d/only.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-onelog
  [ "$status" -eq 0 ]
  local s="$PROJ/.epic/archive/005-onelog/.draft/logs-summary.md"
  [ -f "$s" ]
  grep -q 'only.log' "$s"
  grep -q 'ONLY LOG MARKER' "$s"
  [ ! -e "$PROJ/.epic/archive/005-onelog/.draft/logs/only.log" ]
  echo "$output" | jq -e '.pruned.logs_kb > 0' > /dev/null
}

@test "3.1: an empty logs directory produces no summary and reports no prune" {
  # DECIDED, not left to chance: with no log files there is nothing to record and
  # nothing to replace, so NO summary is written - a file listing zero logs and
  # holding no tail would be a permanent record of nothing. It must also not
  # crash, and must not report a prune that did not happen.
  make_story 005-emptylogs complete
  mkdir -p "$PROJ/.epic/stories/005-emptylogs/.draft/logs"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-emptylogs
  [ "$status" -eq 0 ]
  [ ! -e "$PROJ/.epic/archive/005-emptylogs/.draft/logs-summary.md" ]
  echo "$output" | jq -e '.pruned.logs_kb == 0' > /dev/null
  echo "$stderr" | grep -q 'prune=logs verdict=none'
}

@test "3.1: a log that cannot be read is reported and kept, never deleted unrecorded" {
  # A file whose evidence could not be captured must not be destroyed by the step
  # whose whole purpose is to preserve that evidence. And it must be a REPORTED
  # verdict with JSON on stdout: a bare `set -e` abort would end the run with
  # zero bytes on stdout, which the output contract promises never happens.
  # --allow-heavy is needed to reach step 4 at all - the weight/binary guard
  # blocks an unreadable file first (2.1), which is the step order doing its job.
  make_story 005-unreadlog complete
  local d="$PROJ/.epic/stories/005-unreadlog/.draft/logs"
  mkdir -p "$d"
  { seq 1 50; echo 'OLDER READABLE MARKER'; } > "$d/older.log"
  { seq 1 50; echo 'NEWER UNREADABLE MARKER'; } > "$d/newer.log"
  touch -d '2026-08-01 10:00' "$d/older.log"
  touch -d '2026-08-01 12:00' "$d/newer.log"
  chmod 000 "$d/newer.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-unreadlog --allow-heavy
  # `|| true` on both: whichever side of the move the file ended on, the fixture
  # cleanup must not kill the case before its assertions run.
  chmod 644 "$d/newer.log" 2> /dev/null || true
  chmod 644 "$PROJ/.epic/archive/005-unreadlog/.draft/logs/newer.log" 2> /dev/null || true
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  echo "$output" | jq -e '.status == "archived"' > /dev/null
  local arch="$PROJ/.epic/archive/005-unreadlog"
  # The readable log collapsed...
  [ ! -e "$arch/.draft/logs/older.log" ]
  # ...and the one whose tail could not be read is still there, untouched.
  [ -f "$arch/.draft/logs/newer.log" ]
  grep -q 'NEWER UNREADABLE MARKER' "$arch/.draft/logs/newer.log"
  # The summary names it and says why, and stderr carries the same verdict.
  grep -q 'newer.log' "$arch/.draft/logs-summary.md"
  grep -q 'could not be read' "$arch/.draft/logs-summary.md"
  echo "$stderr" | grep -q 'prune=logs verdict=partial'
}

@test "3.1: a log name with a quote, a space and a newline lands intact in the summary" {
  # A file name is arbitrary bytes, and it reaches the summary as CONTENT - so it
  # goes through quote_scalar, the one escaper whose output BOTH JSON and YAML
  # decode the same way, and never through some second rule invented for this
  # file. It is also why the log list is a YAML block and not a markdown table:
  # a name holding `|` would silently grow a column there.
  make_story 005-oddname complete
  local d="$PROJ/.epic/stories/005-oddname/.draft/logs"
  mkdir -p "$d"
  local odd
  odd=$(printf 'we"ird na\nme.log')
  { seq 1 20; echo 'ODD NAME MARKER'; } > "$d/$odd"
  printf 'plain\n' > "$d/plain.log"
  touch -d '2026-08-01 10:00' "$d/plain.log"
  touch -d '2026-08-01 12:00' "$d/$odd"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-oddname
  [ "$status" -eq 0 ]
  local s="$PROJ/.epic/archive/005-oddname/.draft/logs-summary.md"
  [ -f "$s" ]
  # One line, escaped exactly as both formats decode it.
  grep -qF 'name: "we\"ird na\nme.log"' "$s"
  # ...and it round-trips: the block still PARSES as YAML and gives back the
  # bytes that went in. A grep alone would pass on an escape that is merely
  # present; this fails on one that is merely plausible.
  python3 -c '
import sys, yaml
txt = open(sys.argv[1]).read()
block = txt.split("~~~yaml\n", 1)[1].split("\n~~~", 1)[0]
names = [e["name"] for e in yaml.safe_load(block)["logs"]]
assert sys.argv[2] in names, (sys.argv[2], names)
' "$s" "$odd"
  # The odd-named log is the newest, so the tail is its own - and it is gone.
  grep -q 'ODD NAME MARKER' "$s"
  [ ! -e "$PROJ/.epic/archive/005-oddname/.draft/logs/$odd" ]
}

@test "3.1: --keep-logs writes no summary at all" {
  # The authored --keep-logs case passed BEFORE this sub-task existed, because
  # nothing pruned - so it cannot tell "the flag was honoured" from "the feature
  # is missing". This is the half that can: the flag means keep the logs INSTEAD
  # of collapsing them, so a run that wrote a summary AND kept the logs would be
  # honouring neither reading.
  make_log_story 005-keepnosum 500
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-keepnosum --keep-logs
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epic/archive/005-keepnosum"
  [ -f "$arch/.draft/logs/build.log" ]
  [ "$(wc -l < "$arch/.draft/logs/build.log")" -eq 500 ]
  [ ! -e "$arch/.draft/logs-summary.md" ]
  echo "$output" | jq -e '.pruned.logs_kb == 0' > /dev/null
  echo "$stderr" | grep -q 'prune=logs verdict=skipped reason=--keep-logs'
}

@test "3.1: an existing logs-summary.md is never overwritten" {
  # The summary is the artifact this step produces, so one already sitting there
  # was written by a hand or by an interrupted run. Replacing a document about
  # the logs with a generated one - and then deleting the logs it described - is
  # exactly the quiet loss this step exists to end. Fail-safe: skip, keep the
  # logs, and say so.
  make_log_story 005-hassum 300
  printf '# Hand-written notes about these logs\n' \
    > "$PROJ/.epic/stories/005-hassum/.draft/logs-summary.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-hassum
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epic/archive/005-hassum"
  grep -q 'Hand-written notes' "$arch/.draft/logs-summary.md"
  [ -f "$arch/.draft/logs/build.log" ]
  echo "$output" | jq -e '.pruned.logs_kb == 0' > /dev/null
  echo "$stderr" | grep -q 'prune=logs verdict=skipped reason=summary-exists'
}

# --- 3.1 THE CREDENTIAL DECISION (the hand-off sub-task 2.2 recorded) ---
# Step 3 scans `.draft/logs/*` as they are, and the summary is written
# AFTERWARDS - so no guard ever looks at it, and 40 lines of arbitrary log
# output enter the archive unscanned. ACCEPTED, deliberately: the prune only
# ever REMOVES, so every byte of that tail was already in the story when
# gitleaks read it and would have travelled into the archive verbatim under
# --keep-logs. Collapsing a log cannot introduce a credential the archive was
# not already about to receive - it can only reduce one, and re-scanning would
# re-read a strict subset (or, where nothing was scanned, scan exactly what the
# operator chose not to scan). Blocking is worse still: the verdict would land
# AFTER a destructive step, which is what the step order forbids.
# What is NOT accepted is silence about the guarantee. These two cases pin that.

@test "3.1: an unscanned story says so in the summary it leaves behind" {
  make_log_story 005-provenance 300
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-provenance --skip-secrets
  [ "$status" -eq 0 ]
  local s="$PROJ/.epic/archive/005-provenance/.draft/logs-summary.md"
  [ -f "$s" ]
  grep -q 'secrets_scan:' "$s"
  grep -q 'NOT SCANNED' "$s"
  grep -q 'skip-secrets' "$s"
}

@test "3.1: a scanned story records the scan, and the two summaries differ" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # The pair is what makes either half a discriminator rather than a constant:
  # in a permanent record, "scanned and clean" and "nobody looked" must not be
  # the same sentence.
  make_log_story 005-prov-scanned 300
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-prov-scanned
  [ "$status" -eq 0 ]
  make_log_story 005-prov-unscanned 300
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-prov-unscanned --skip-secrets
  [ "$status" -eq 0 ]
  local a b
  a=$(grep 'secrets_scan:' "$PROJ/.epic/archive/005-prov-scanned/.draft/logs-summary.md")
  b=$(grep 'secrets_scan:' "$PROJ/.epic/archive/005-prov-unscanned/.draft/logs-summary.md")
  [[ "$a" == *"scanned by gitleaks"* ]]
  [[ "$b" == *"NOT SCANNED"* ]]
  [[ "$a" != "$b" ]]
}

@test "3.1: a log too big for the scanner is recorded as unscanned in its own summary" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # THE one case where `scanned: true, findings: 0` genuinely does NOT cover the
  # tail: gitleaks silently skips any file over --max-target-megabytes (2.2's
  # measured residual - no report entry, no exit code, `INF no leaks found`).
  # Step 2 blocks anything over 10 MB, so only --allow-heavy brings a log this
  # size to the scanner at all; when it does, the summary refuses to let a clean
  # verdict stand for lines nothing ever looked at.
  make_story 005-bigunscanned complete
  local d="$PROJ/.epic/stories/005-bigunscanned/.draft/logs"
  mkdir -p "$d"
  { head -c 15000001 /dev/zero | tr '\0' 'a'; echo; echo 'HUGE LOG MARKER'; } > "$d/huge.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-bigunscanned --allow-heavy
  [ "$status" -eq 0 ]
  local s="$PROJ/.epic/archive/005-bigunscanned/.draft/logs-summary.md"
  [ -f "$s" ]
  grep -q 'HUGE LOG MARKER' "$s"
  # The scan reported clean, with the file never opened...
  echo "$output" | jq -e '.secrets.scanned == true and .secrets.findings == 0' > /dev/null
  echo "$output" | jq -e '.secrets.unscanned_files == 1' > /dev/null
  # ...and the summary says exactly that, in the artifact that outlives the run.
  grep -q 'NOT scanned' "$s"
  grep -q '15000000-byte limit' "$s"
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

# ADDITIVE 3.2 cases appended at execution time. Each pins behavior the ToDo
# mandates that the two authored cases leave unpinned, and every one was
# mutation-checked (break the fix -> the case fails, restore -> it passes). No
# authored assertion was modified, weakened or deleted.
#
# NOTE ON THE AUTHORED PAIR: `3.2: --keep-copies preserves the duplicate` was
# ALREADY GREEN before this sub-task, vacuously - nothing pruned, so it could not
# tell "the flag was honoured" from "the feature does not exist". It becomes a
# real discriminator now that the prune exists, which is the point of keeping it
# untouched.

# make_copy_story <dir-name> - a COMPLETE story with an empty .draft/ ready for
# the fixture's own files. Echoes nothing; the caller writes the pairs it needs.
make_copy_story() {
  make_story "$1" complete
  mkdir -p "$PROJ/.epic/stories/$1/.draft"
}

@test "3.2: a story blocked by the weight guard keeps every .draft copy" {
  # THE STEP ORDER, asserted from outside the script, for the COPIES half. 3.1
  # pinned it for the logs half only, and step 4 is destructive on both: a copies
  # prune that ran before the guards would delete files for a story that is then
  # refused - and unlike the logs half it writes no summary, so the only record
  # that the file ever existed would be gone with it.
  make_copy_story 005-blockedcopies
  local story="$PROJ/.epic/stories/005-blockedcopies"
  echo 'promoted design body' > "$story/design.md"
  cp "$story/design.md" "$story/.draft/design.md"
  yes 'padding line for the weight guard fixture' | head -c 10485761 > "$story/big.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-blockedcopies
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  # The exact copy is still exactly where it was...
  [ -f "$story/.draft/design.md" ]
  grep -q 'promoted design body' "$story/.draft/design.md"
  echo "$output" | jq -e '.pruned.copies_removed == 0' > /dev/null
  # ...and the copies prune never announced itself at all. (`[[ != ]]`, not
  # `! grep`: an inverted command is exempt from set -e - see the 2.2 discovery.)
  [[ "$stderr" != *"prune=copies"* ]]
}

@test "3.2: the copies prune reports itself after both guards and after the logs prune" {
  # The other half of the pair: the case above proves the copies prune does not
  # run when a guard blocks; this proves that when it DOES run, it runs last -
  # after both guards AND after the logs half, which is the order the summary it
  # must not delete depends on. All four verdicts are key=value lines on stderr,
  # so the ORDER is readable without parsing prose, and `guards_passed=true` is
  # the script's own sequence assertion stated where a test can see it.
  make_copy_story 005-order32
  local story="$PROJ/.epic/stories/005-order32"
  mkdir -p "$story/.draft/logs"
  seq 1 500 > "$story/.draft/logs/build.log"
  echo 'promoted design body' > "$story/design.md"
  cp "$story/design.md" "$story/.draft/design.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-order32
  [ "$status" -eq 0 ]
  local weight secrets logs copies
  weight=$(echo "$stderr" | grep -n 'guard=weight-binary' | head -1 | cut -d: -f1)
  secrets=$(echo "$stderr" | grep -n 'guard=secrets' | head -1 | cut -d: -f1)
  logs=$(echo "$stderr" | grep -n 'prune=logs' | head -1 | cut -d: -f1)
  copies=$(echo "$stderr" | grep -n 'prune=copies' | head -1 | cut -d: -f1)
  [ -n "$weight" ]
  [ -n "$secrets" ]
  [ -n "$logs" ]
  [ -n "$copies" ]
  [ "$copies" -gt "$weight" ]
  [ "$copies" -gt "$secrets" ]
  [ "$copies" -gt "$logs" ]
  echo "$stderr" | grep -q 'prune=copies verdict=pruned.*guards_passed=true'
}

@test "3.2: a near-duplicate survives - one byte, one newline, or the same length" {
  # THE load-bearing word of R2.2 is "byte-identical". A near-duplicate is a
  # DIFFERENT DOCUMENT - usually the working draft the promoted artifact grew out
  # of, which is exactly what a reader opens .draft/ for. Three shapes, because
  # the plausible wrong implementations each miss a different one: comparing
  # sizes passes the two same-length pairs, and comparing "the first line" or a
  # trimmed form passes the trailing-newline pair.
  make_copy_story 005-near
  local story="$PROJ/.epic/stories/005-near" d="$PROJ/.epic/stories/005-near/.draft"
  printf 'duplicate detection\n' > "$story/onebyte.md"
  printf 'duplicate detectiom\n' > "$d/onebyte.md"        # one byte changed
  printf 'trailing newline matters\n' > "$story/newline.md"
  printf 'trailing newline matters' > "$d/newline.md"     # one byte shorter
  printf 'AAAA\n' > "$story/samesize.md"
  printf 'BBBB\n' > "$d/samesize.md"                      # same length, other bytes
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-near
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epic/archive/005-near"
  [ -f "$arch/.draft/onebyte.md" ]
  [ -f "$arch/.draft/newline.md" ]
  [ -f "$arch/.draft/samesize.md" ]
  grep -q 'detectiom' "$arch/.draft/onebyte.md"
  [ "$(cat "$arch/.draft/samesize.md")" = 'BBBB' ]
  # The trailing newline is the difference, so it must still be absent.
  [ "$(wc -c < "$arch/.draft/newline.md")" -eq 24 ]
  echo "$output" | jq -e '.pruned.copies_removed == 0' > /dev/null
  # `clean` and not `none`: every draft file WAS compared and none matched.
  echo "$stderr" | grep -q 'prune=copies verdict=clean files_seen=3 compared=3 removed=0'
}

@test "3.2: identical bytes are a duplicate whatever the permissions and the mtime say" {
  # R2.2 is about CONTENT. A copy someone chmod'ed or touched is still a copy,
  # and metadata equality is neither necessary nor sufficient for it - which is
  # why the comparison is cmp on the bytes and not a stat-based shortcut.
  make_copy_story 005-meta
  local story="$PROJ/.epic/stories/005-meta"
  printf 'promoted body, byte for byte\n' > "$story/design.md"
  cp "$story/design.md" "$story/.draft/design.md"
  chmod 600 "$story/.draft/design.md"
  chmod 644 "$story/design.md"
  touch -d '2020-01-01 00:00' "$story/.draft/design.md"
  touch -d '2026-08-01 12:00' "$story/design.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-meta
  [ "$status" -eq 0 ]
  [ ! -e "$PROJ/.epic/archive/005-meta/.draft/design.md" ]
  [ -f "$PROJ/.epic/archive/005-meta/design.md" ]
  echo "$output" | jq -e '.pruned.copies_removed == 1' > /dev/null
}

@test "3.2: copies_removed is a real count, not a boolean" {
  # The authored case removes exactly one copy, so a boolean, a constant 1 or a
  # "did anything happen" flag satisfies it identically. Three copies is what
  # tells a count from a flag - and the number has to reach the PERMANENT record,
  # not just stdout.
  make_copy_story 005-three
  local story="$PROJ/.epic/stories/005-three" f
  for f in design research plan; do
    printf 'promoted %s body\n' "$f" > "$story/$f.md"
    cp "$story/$f.md" "$story/.draft/$f.md"
  done
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-three
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epic/archive/005-three"
  for f in design research plan; do
    [ ! -e "$arch/.draft/$f.md" ]
    [ -f "$arch/$f.md" ]
  done
  echo "$output" | jq -e '.pruned.copies_removed == 3' > /dev/null
  grep -Eq 'copies_removed:[[:space:]]*3' "$MANIFEST"
}

@test "3.2: a .draft file with no promoted sibling is never touched" {
  # This is MOST of .draft/, and it is the failure mode that would hurt worst:
  # "prune the drafts" read as "empty .draft/" destroys the working notes the
  # archive exists to keep. A file that is a copy of nothing can never be a
  # duplicate of anything.
  make_copy_story 005-orphan
  local story="$PROJ/.epic/stories/005-orphan"
  printf 'scratch thinking nobody promoted\n' > "$story/.draft/scratch.md"
  printf 'raw interview notes\n' > "$story/.draft/interview.txt"
  printf 'promoted design body\n' > "$story/design.md"
  cp "$story/design.md" "$story/.draft/design.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-orphan
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epic/archive/005-orphan"
  [ -f "$arch/.draft/scratch.md" ]
  grep -q 'scratch thinking' "$arch/.draft/scratch.md"
  [ -f "$arch/.draft/interview.txt" ]
  # ...while the one that IS an exact copy went, so this is not "nothing ran".
  [ ! -e "$arch/.draft/design.md" ]
  echo "$output" | jq -e '.pruned.copies_removed == 1' > /dev/null
  # 3 files seen, only 1 of them had a promoted artifact to compare against.
  echo "$stderr" | grep -q 'prune=copies verdict=pruned files_seen=3 compared=1 removed=1'
}

@test "3.2: a nested draft copy pairs by relative path, never by basename" {
  # THE RULE, pinned in both directions, because getting it wrong deletes a file
  # that was never a duplicate. `.draft/<rel>` pairs with `<story>/<rel>`:
  #   .draft/adr/002.md vs a top-level 002.md  -> NOT a pair (different document
  #                                               that happens to share a name)
  #   .draft/adr/003.md vs adr/003.md          -> a pair, and an exact copy
  # Both fixtures are byte-identical to their would-be partner, so only the
  # PAIRING decides the outcome.
  make_copy_story 005-nested
  local story="$PROJ/.epic/stories/005-nested"
  mkdir -p "$story/.draft/adr" "$story/adr"
  printf 'same bytes, unrelated documents\n' > "$story/002.md"
  printf 'same bytes, unrelated documents\n' > "$story/.draft/adr/002.md"
  printf 'promoted adr three\n' > "$story/adr/003.md"
  cp "$story/adr/003.md" "$story/.draft/adr/003.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-nested
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epic/archive/005-nested"
  [ -f "$arch/.draft/adr/002.md" ]
  grep -q 'unrelated documents' "$arch/.draft/adr/002.md"
  [ ! -e "$arch/.draft/adr/003.md" ]
  [ -f "$arch/adr/003.md" ]
  echo "$output" | jq -e '.pruned.copies_removed == 1' > /dev/null
}

@test "3.2: a draft copy that cannot be read is kept, never assumed identical" {
  # 3.1's rule for the logs half, and it matters more here: `[[ -f ]]` says a
  # file EXISTS, not that it opens, and reading an unreadable file as a duplicate
  # deletes the one copy nobody was able to check. cmp answers 0/1/>1 and only 0
  # deletes. --allow-heavy is needed to reach step 4 at all - the weight/binary
  # guard blocks an unreadable file first (2.1), which is the step order working.
  make_copy_story 005-unreadcopy
  local story="$PROJ/.epic/stories/005-unreadcopy"
  printf 'promoted design body\n' > "$story/design.md"
  cp "$story/design.md" "$story/.draft/design.md"
  chmod 000 "$story/.draft/design.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-unreadcopy --allow-heavy
  # `|| true` on both: whichever side of the move the file ended on, the fixture
  # cleanup must not kill the case before its assertions run.
  chmod 644 "$story/.draft/design.md" 2> /dev/null || true
  chmod 644 "$PROJ/.epic/archive/005-unreadcopy/.draft/design.md" 2> /dev/null || true
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  echo "$output" | jq -e '.status == "archived"' > /dev/null
  local arch="$PROJ/.epic/archive/005-unreadcopy"
  [ -f "$arch/.draft/design.md" ]
  grep -q 'promoted design body' "$arch/.draft/design.md"
  echo "$output" | jq -e '.pruned.copies_removed == 0' > /dev/null
  # Reported, not silent: the file is named with the reason it was left.
  echo "$stderr" | grep -q 'prune=copies verdict=partial'
  echo "$stderr" | grep -q 'design.md'
}

@test "3.2: a draft file whose promoted counterpart is a directory is not a duplicate" {
  # A type mismatch is not a comparison. Both directions: a draft FILE whose
  # promoted path is a DIRECTORY (cmp against a directory is an error, and an
  # error is never "equal"), and a draft DIRECTORY whose promoted path is a FILE
  # (nothing under it maps to anything, so nothing is a candidate).
  make_copy_story 005-typemix
  local story="$PROJ/.epic/stories/005-typemix"
  mkdir -p "$story/adr.md" "$story/.draft/notes.md"
  printf 'promoted adr collection\n' > "$story/adr.md/index.md"
  printf 'draft file where a directory was promoted\n' > "$story/.draft/adr.md"
  printf 'promoted notes body\n' > "$story/notes.md"
  printf 'draft directory where a file was promoted\n' > "$story/.draft/notes.md/inner.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-typemix
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epic/archive/005-typemix"
  [ -f "$arch/.draft/adr.md" ]
  [ -f "$arch/.draft/notes.md/inner.md" ]
  [ -f "$arch/adr.md/index.md" ]
  [ -f "$arch/notes.md" ]
  echo "$output" | jq -e '.pruned.copies_removed == 0' > /dev/null
  # `clean`, not `partial`: a type mismatch is not even a comparison, so nothing
  # was compared and nothing failed to compare.
  echo "$stderr" | grep -q 'prune=copies verdict=clean files_seen=2 compared=0 removed=0'
}

@test "3.2: a symlinked draft copy is left as a link, never deleted" {
  # cmp FOLLOWS symlinks, so a link to the promoted artifact reads as
  # "identical". It is left alone anyway: it holds no bytes of its own, so
  # R2.2's "remove the copy" has nothing to remove, and a symlink is how someone
  # deliberately wrote down "same file". Two layers keep it safe - `find -type f`
  # never enumerates it, and the loop tests -L again - and only removing BOTH
  # changes the outcome.
  make_copy_story 005-linkcopy
  local story="$PROJ/.epic/stories/005-linkcopy"
  printf 'promoted design body\n' > "$story/design.md"
  ln -s ../design.md "$story/.draft/design.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-linkcopy
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epic/archive/005-linkcopy"
  [ -L "$arch/.draft/design.md" ]
  # ...and it still resolves: -f follows the link.
  [ -f "$arch/.draft/design.md" ]
  echo "$output" | jq -e '.pruned.copies_removed == 0' > /dev/null
}

@test "3.2: a promoted artifact that is a symlink into .draft is never made to dangle" {
  # THE dangerous direction. cmp follows the promoted link, so the pair reads as
  # byte-identical - and deleting the .draft file would leave the promoted
  # artifact pointing at nothing. A removal of a redundant duplicate would have
  # become the destruction of the story's only copy.
  make_copy_story 005-linkpromoted
  local story="$PROJ/.epic/stories/005-linkpromoted"
  printf 'the only copy of this text\n' > "$story/.draft/design.md"
  ln -s .draft/design.md "$story/design.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-linkpromoted
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epic/archive/005-linkpromoted"
  [ -f "$arch/.draft/design.md" ]
  # -f on the link is FALSE when it dangles, so this is the no-dangle assertion.
  [ -L "$arch/design.md" ]
  [ -f "$arch/design.md" ]
  grep -q 'the only copy of this text' "$arch/design.md"
  echo "$output" | jq -e '.pruned.copies_removed == 0' > /dev/null
}

@test "3.2: the generated logs summary is not deleted by the copies half" {
  # Step 4 runs the logs half FIRST, so .draft/logs-summary.md exists by the time
  # the copies half enumerates the subtree. It has no promoted sibling, so it is
  # inert - and it must stay that way, because it is now the ONLY record of logs
  # this same step deleted moments earlier.
  make_copy_story 005-summarysafe
  local story="$PROJ/.epic/stories/005-summarysafe"
  mkdir -p "$story/.draft/logs"
  { seq 1 300; echo 'SUMMARY SAFE MARKER'; } > "$story/.draft/logs/build.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/005-summarysafe
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epic/archive/005-summarysafe"
  [ -f "$arch/.draft/logs-summary.md" ]
  grep -q 'SUMMARY SAFE MARKER' "$arch/.draft/logs-summary.md"
  [ ! -e "$arch/.draft/logs/build.log" ]
  echo "$output" | jq -e '.pruned.logs_kb > 0 and .pruned.copies_removed == 0' > /dev/null
  # The copies half DID look at it and decided it was not a copy of anything.
  echo "$stderr" | grep -q 'prune=copies verdict=clean files_seen=1 compared=0 removed=0'
}

# --- 4.2 The superseded preflight state (story 006, R3.6) ---
# `superseded` is the third word in assess_completion's status alternation, and
# it is the one story 006's supersede op depends on: its step 5 offers the
# archive by DELEGATING to this script, so the offer is only honest if
# `superseded` clears the completion gate here. That word shipped with zero
# coverage - this section is it. Prefixed `4.2:` for `bats --filter '^4\.2:'`.
#
# TWO cases, because one cannot do both jobs:
#   - the canonical post-supersede shape has every box closed, so BOX_OPEN is 0
#     and the LATER `elif [[ "$BOX_OPEN" -eq 0 ]]` branch would carry it even
#     with `superseded` deleted from the alternation. It pins the realistic
#     artifact, not the word.
#   - the second keeps one box open, so the status branch is the ONLY thing
#     that can complete it. That is the mutation guard: deleting `superseded`
#     turns it red (verified - the archive is refused with the open count).
# The interrupted shape is no longer one supersede can WRITE: supersede-mode.md
# step 3 was reordered to close-then-flip, so the status write is the commit
# point and an interruption leaves the story visibly unfinished instead. Its
# Interrupted-Run Recovery says that shape "did not come from this command" -
# but that is a claim about the WRITER, and this gate is a READER. The shape
# still arrives: a hand-edited frontmatter, an artifact predating the op.
# Archive must accept it because assess_completion takes the status OR the
# boxes, never both (story 004) - a `status:` naming a completion state carries
# the story through whatever the boxes say. The reorder therefore did not make
# this case dead, and the guard riding on it stays.

# make_superseded_story <dir-name> <MMM> [leftover-open-box]
# The artifacts as the supersede op leaves them (references/supersede-mode.md,
# Closure + Walkthrough): `status: superseded` plus the machine-readable
# `superseded-by: MMM` companion in EVERY artifact with frontmatter, and every
# open sub-task closed on its own line as a terminal `[~] ... (superseded-by:
# MMM)` - story 004's checkbox grammar, verbatim.
# A non-empty third argument leaves box 3.1 OPEN - the status-written,
# closures-unfinished shape described above, however it came to be written.
make_superseded_story() {
  local dir="$PROJ/.epic/stories/$1" by="$2" leftover="${3:-}"
  mkdir -p "$dir"
  {
    echo '---'
    echo "story: ${1#*-}"
    echo 'type: feature'
    echo 'scale: standard'
    echo 'version: 1'
    echo 'created: 2026-05-14'
    echo 'status: superseded'
    echo "superseded-by: $by"
    echo '---'
    echo
    echo '# Story - superseded fixture'
  } > "$dir/story.md"
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-05-14'
    echo 'status: superseded'
    echo "superseded-by: $by"
    echo '---'
    echo
    echo '## Task List'
    echo '- [x] 1.1 - Parse the legacy CSV export'
    echo "- [~] 2.1 - Map legacy fields to the new schema (superseded-by: $by)"
    echo "- [~] 2.2 - Validate mapped rows (superseded-by: $by)"
    if [ -n "$leftover" ]; then
      echo '- [ ] 3.1 - Import against the live feed'
    else
      echo "- [~] 3.1 - Import against the live feed (superseded-by: $by)"
    fi
  } > "$dir/tasks.md"
  return 0
}

@test "4.2: a superseded story clears the completion gate and archives" {
  # The walkthrough's own fixture: 042 superseded by 051, one [x] survivor and
  # three boxes the op closed. What the step-5 offer actually hands this script.
  make_superseded_story 042-legacy-import 051
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/042-legacy-import
  # A REAL archive, not merely a run that did not crash.
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "archived" and .moved == true' > /dev/null
  [ -d "$PROJ/.epic/archive/042-legacy-import" ]
  [ ! -d "$PROJ/.epic/stories/042-legacy-import" ]
  # The entry records the story's OWN pre-archive status, so the manifest says
  # what the story was when it was archived, never a verdict this script coined.
  [ -f "$MANIFEST" ]
  grep -q 'story: "042-legacy-import"' "$MANIFEST"
  grep -Eq 'status:[[:space:]]*"superseded"' "$MANIFEST"
  echo "$output" | jq -e '.manifest_entry.status == "superseded"' > /dev/null
  # 4 boxes, none open: `superseded-by:` is terminal, so nothing stays owed.
  echo "$output" | jq -e '.tasks == {total: 4, closed: 1, deferred: 3, open: 0}' > /dev/null
  # The terminal qualifier survives verbatim into the recorded items, which is
  # what tells a future reader these were remapped, not abandoned.
  echo "$output" | jq -e '.manifest_entry.deferred_items | length == 3' > /dev/null
  echo "$output" | jq -e '.manifest_entry.deferred_items[0]
    | contains("Map legacy fields to the new schema")
      and contains("(superseded-by: 051)")' > /dev/null
  grep -q 'superseded-by: 051' "$MANIFEST"
}

@test "4.2: status superseded archives a story whose closures were interrupted" {
  # THE MUTATION GUARD. One box is still `[ ]`, so BOX_OPEN is 1 and every other
  # branch of assess_completion refuses: only `FM_STATUS == "superseded"` can
  # complete this. Drop that word from the alternation and this case goes red
  # with "1 task checkbox(es) still open".
  make_superseded_story 043-interrupted 051 leftover-open-box
  run --separate-stderr bash "$ARCHIVE_SH" .epic/stories/043-interrupted
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "archived" and .moved == true' > /dev/null
  [ -d "$PROJ/.epic/archive/043-interrupted" ]
  [ ! -d "$PROJ/.epic/stories/043-interrupted" ]
  [ -f "$MANIFEST" ]
  grep -q 'story: "043-interrupted"' "$MANIFEST"
  grep -Eq 'status:[[:space:]]*"superseded"' "$MANIFEST"
  # The open box is REAL and recorded as such - the archive does not launder it.
  echo "$output" | jq -e '.tasks == {total: 4, closed: 1, deferred: 2, open: 1}' > /dev/null
  grep -Eq 'tasks_open:[[:space:]]*1' "$MANIFEST"
  # ...and no escape hatch was used: --force would have recorded both a
  # `force` override and a `forced_reason`, so their absence proves the status
  # branch alone carried this through the gate.
  echo "$output" | jq -e '.manifest_entry.overrides_used == []' > /dev/null
  echo "$output" | jq -e '.manifest_entry | has("forced_reason") | not' > /dev/null
}
