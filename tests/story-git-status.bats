#!/usr/bin/env bats
# Unit tests for scripts/story-git-status.sh (story 006 — git-aware lifecycle).
# Authored by the Test Advisor BEFORE implementation (TDD Red phase).
#
# Contract under test (design.md, component 1):
#   story-git-status.sh <NNN|story-dir>  →  JSON on stdout:
#     {story, main_branch, integrated: true|false|null,
#      evidence: [{kind: branch-merged|message-ref, detail}], checked_at}
#   Exit 0 whenever computable (including integrated: null);
#   exit 2 when not a git repo or story not found (callers degrade silently).
#
# Fixtures are real temp git repos (mktemp + git init + commits/branches) —
# no simplified stubs; the script's only dependency IS git.
#
# EPIC_PLUGIN_ROOT overrides root resolution so the draft copy under
# .draft/authored-tests/tests/ can run before materialization into tests/.

setup() {
  PLUGIN_ROOT="${EPIC_PLUGIN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  SCRIPT="$PLUGIN_ROOT/scripts/story-git-status.sh"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

# --- fixture helpers -------------------------------------------------------

# make_repo <dir> <initial-branch>: git repo with one neutral commit and the
# story dir .epic/stories/006-widget-flow inside the worktree.
make_repo() {
  local dir=$1 branch=$2
  mkdir -p "$dir"
  git init -q -b "$branch" "$dir"
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" commit --allow-empty -q -m "chore: initial scaffold"
  mkdir -p "$dir/.epic/stories/006-widget-flow"
  printf -- '---\nstatus: done\n---\n' > "$dir/.epic/stories/006-widget-flow/story.md"
}

# commit_msg <dir> <subject>: empty commit with a controlled subject.
commit_msg() {
  git -C "$1" commit --allow-empty -q -m "$2"
}

# set_origin_head <dir> <branch>: simulate a remote default branch without a
# network remote (refs/remotes/origin/HEAD → refs/remotes/origin/<branch>).
set_origin_head() {
  git -C "$1" update-ref "refs/remotes/origin/$2" HEAD
  git -C "$1" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$2"
}

# run_status <dir>: invoke the script from inside the repo on the fixture story.
run_status() {
  cd "$1"
  run bash "$SCRIPT" .epic/stories/006-widget-flow
}

# =====================================================================
# Task 1.1 — main-branch resolution and JSON skeleton (R1.4, R1.5)
# =====================================================================

@test "1.1 remote HEAD default wins over local main (R1.5)" {
  make_repo "$WORK/r" trunk
  git -C "$WORK/r" branch main          # decoy: remote default must win
  set_origin_head "$WORK/r" trunk
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.main_branch == "trunk"'
}

@test "1.1 falls back to local main when no origin/HEAD (R1.5)" {
  make_repo "$WORK/r" main
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.main_branch == "main"'
}

@test "1.1 falls back to master when no origin/HEAD and no main (R1.5)" {
  make_repo "$WORK/r" master
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.main_branch == "master"'
}

@test "1.1 no resolvable main: integrated null, main_branch null, exit 0 (R1.5)" {
  make_repo "$WORK/r" trunk             # no origin/HEAD, no main, no master
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.integrated == null and .main_branch == null'
}

@test "1.1 both main and master without origin/HEAD: prefer main, flag ambiguity" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" branch master
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.main_branch == "main" and .main_branch_ambiguous == true'
}

@test "1.1 not a git repository: exit 2 so callers degrade silently (R1.4)" {
  mkdir -p "$WORK/plain/.epic/stories/006-widget-flow"
  cd "$WORK/plain"
  run bash "$SCRIPT" .epic/stories/006-widget-flow
  [ "$status" -eq 2 ]
}

@test "1.1 story not found: exit 2" {
  make_repo "$WORK/r" main
  cd "$WORK/r"
  run bash "$SCRIPT" .epic/stories/999-does-not-exist
  [ "$status" -eq 2 ]
}

@test "1.1 contract JSON is valid and complete on the computable path" {
  make_repo "$WORK/r" main
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e \
    'has("story") and has("main_branch") and has("integrated") and has("evidence") and has("checked_at")'
  echo "$output" | jq -e '.evidence | type == "array"'
  echo "$output" | jq -er '.story' | grep -q '006'
}

# =====================================================================
# Task 1.2 — evidence rules: branch-merged and message-ref
# (R1.1, R1.2, R1.3, R1.6)
# =====================================================================

@test "1.2 merged feat/NNN-* branch: integrated true with branch-merged evidence (R1.1)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" branch feat/006-widget-flow   # tip == main tip → fully merged
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.integrated == true'
  echo "$output" | jq -e '.evidence | map(.kind) | index("branch-merged") != null'
}

@test "1.2 unmerged story branch is not integration evidence (R1.1)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" checkout -q -b feat/006-widget-flow
  commit_msg "$WORK/r" "wip: widget work in progress"   # ahead of main, no 006 token
  git -C "$WORK/r" checkout -q main
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.integrated == false'
}

@test "1.2 conventional type(NNN): subject on main: message-ref evidence (R1.2)" {
  make_repo "$WORK/r" main
  commit_msg "$WORK/r" "feat(006): add the widget flow"
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.integrated == true'
  echo "$output" | jq -e '.evidence | map(.kind) | index("message-ref") != null'
}

@test "1.2 NNN-slug token in a subject on main: message-ref evidence (R1.2)" {
  make_repo "$WORK/r" main
  commit_msg "$WORK/r" "merge story 006-widget-flow into main"
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.integrated == true'
}

@test "1.2 unpadded delimited form fix(6): matches story 006" {
  make_repo "$WORK/r" main
  commit_msg "$WORK/r" "fix(6): correct widget rounding"
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.integrated == true'
}

@test "1.2 bare undelimited number is NEVER evidence (R1.3)" {
  make_repo "$WORK/r" main
  commit_msg "$WORK/r" "discussed 006 during standup"   # bare padded token
  commit_msg "$WORK/r" "bump build to 1006"             # substring, no boundary
  commit_msg "$WORK/r" "retry 6 times before failing"   # bare unpadded token
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.integrated == false'
  echo "$output" | jq -e '.evidence == []'
}

@test "1.2 history rewrite is reflected live: deleted branch flips to false (R1.6)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" branch feat/006-widget-flow
  cd "$WORK/r"
  run bash "$SCRIPT" .epic/stories/006-widget-flow
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.integrated == true'
  git branch -D feat/006-widget-flow >/dev/null
  run bash "$SCRIPT" .epic/stories/006-widget-flow
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.integrated == false'
}

@test "1.2 evaluation writes no state files into the worktree (R1.6, no-storage rule)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" branch feat/006-widget-flow
  before=$(cd "$WORK/r" && find . -path ./.git -prune -o -type f -print | sort)
  porcelain_before=$(git -C "$WORK/r" status --porcelain)
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  after=$(cd "$WORK/r" && find . -path ./.git -prune -o -type f -print | sort)
  [ "$before" = "$after" ]
  # Delta, not absolute emptiness: make_repo itself leaves story.md untracked,
  # so an empty-porcelain assertion is unsatisfiable on hosts with no global
  # ignore for .epic. What the no-storage rule owns is that the SCRIPT changes
  # nothing — tracked or untracked — between the two snapshots.
  porcelain_after=$(git -C "$WORK/r" status --porcelain)
  [ "$porcelain_before" = "$porcelain_after" ]   # no artifact was modified
}

# =====================================================================
# Task 4.1 — full C0/C1 escaping in json_escape (R1.7)
# =====================================================================
# A control character is legal in a commit message and RFC 8259 forbids it raw
# inside a JSON string, so a single one in a matching subject used to make the
# whole document unparseable while the script still exited 0. Both cases assert
# the pair that matters: the document PARSES, and the escaped detail DECODES
# back to the original bytes (escaping must not be lossy).
# --cleanup=verbatim is required: git's default whitespace cleanup is otherwise
# free to strip or rewrite the very byte under test.

@test "4.1 raw form feed in a matching subject stays parseable JSON (R1.7)" {
  make_repo "$WORK/r" main
  subject=$(printf 'feat(006): weird\x0cchar')
  git -C "$WORK/r" commit --allow-empty -q --cleanup=verbatim -m "$subject" 2>/dev/null
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e .
  decoded=$(echo "$output" | jq -er '.evidence[] | select(.kind=="message-ref") | .detail')
  [ "$decoded" = "$subject" ]
}

@test "4.1 raw ESC in a matching subject stays parseable JSON (R1.7)" {
  make_repo "$WORK/r" main
  subject=$(printf 'feat(006): esc\x1b[31mred')
  git -C "$WORK/r" commit --allow-empty -q --cleanup=verbatim -m "$subject" 2>/dev/null
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e .
  decoded=$(echo "$output" | jq -er '.evidence[] | select(.kind=="message-ref") | .detail')
  [ "$decoded" = "$subject" ]
}

# =====================================================================
# Task 5.1 — evidence uniqueness (R1.8)
# =====================================================================
# The duplicate these cases pin is not one rule firing twice:
# feat/006-widget-flow matches the anchored ^feat/0*006- pattern while
# origin/feat/006-widget-flow matches only the /0*006-<slug> pattern, so the
# pair reaches the loop through two different rules.

# branch_merged_count: how many branch-merged entries the last run emitted.
branch_merged_count() {
  echo "$output" | jq '[.evidence[] | select(.kind == "branch-merged")] | length'
}

@test "5.1 one branch under both a local and a remote-tracking ref is one entry (R1.8)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" remote add origin https://example.invalid/widget.git
  git -C "$WORK/r" branch feat/006-widget-flow
  git -C "$WORK/r" update-ref refs/remotes/origin/feat/006-widget-flow HEAD
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.integrated == true'
  [ "$(branch_merged_count)" -eq 1 ]
  # The survivor names the local branch, not the remote-tracking ref.
  echo "$output" | jq -e '[.evidence[] | select(.kind == "branch-merged")][0].detail == "feat/006-widget-flow"'
}

@test "5.1 two genuinely distinct merged branches still yield two entries (R1.8)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" branch feat/006-widget-flow
  git -C "$WORK/r" branch feat/006-widget-flow-followup
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  [ "$(branch_merged_count)" -eq 2 ]
}

@test "5.1 the remote list comes from git, not a hardcoded origin (R1.8)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" remote add upstream https://example.invalid/widget.git
  git -C "$WORK/r" branch feat/006-widget-flow
  git -C "$WORK/r" update-ref refs/remotes/upstream/feat/006-widget-flow HEAD
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  [ "$(branch_merged_count)" -eq 1 ]
}

@test "5.1 a local branch literally named origin/... is not stripped without that remote (R1.8)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" branch feat/006-widget-flow
  git -C "$WORK/r" branch origin/feat/006-widget-flow   # no remote named origin
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  [ "$(branch_merged_count)" -eq 2 ]
}

# =====================================================================
# Task 6.1/6.2 — the two predicates R1.8 actually rests on
# =====================================================================
# Authored from the amended R1.8 text BEFORE the fix, and confirmed Red:
# "one merged branch ... a single evidence entry, and the reported detail
# SHALL name a ref that is itself merged into the main branch".
# Task 5.1's case 4 covered only the benign half of its own rule (a name
# collision with NO such remote); these cover the hostile halves.

@test "6.1 a local branch named origin/... IS kept when that remote exists (R1.8)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" remote add origin https://example.invalid/widget.git
  git -C "$WORK/r" branch feat/006-widget-flow
  git -C "$WORK/r" branch origin/feat/006-widget-flow   # a real, distinct local branch
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  # Two distinct branches: only their SHORT names collide, their refs do not.
  [ "$(branch_merged_count)" -eq 2 ]
}

@test "6.1 the same branch name on two remotes at different tips stays two (R1.8)" {
  make_repo "$WORK/r" main
  commit_msg "$WORK/r" "chore: a second commit so two distinct merged tips exist"
  git -C "$WORK/r" remote add origin https://example.invalid/widget.git
  git -C "$WORK/r" remote add fork https://example.invalid/fork.git
  git -C "$WORK/r" update-ref refs/remotes/origin/feat/006-widget-flow HEAD
  git -C "$WORK/r" update-ref refs/remotes/fork/feat/006-widget-flow HEAD~1
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  # Same name, different commits, both merged — one is not the other's mirror.
  [ "$(branch_merged_count)" -eq 2 ]
}

@test "6.2 an unmerged local branch is never named as branch-merged evidence (R1.8)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" remote add origin https://example.invalid/widget.git
  git -C "$WORK/r" update-ref refs/remotes/origin/feat/006-widget-flow HEAD
  git -C "$WORK/r" checkout -q -b feat/006-widget-flow
  commit_msg "$WORK/r" "wip: diverged, never merged back"
  git -C "$WORK/r" checkout -q main
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  [ "$(branch_merged_count)" -eq 1 ]
  # The merged ref is the remote one. Preferring the local short name here
  # would name a branch that never reached main.
  echo "$output" | jq -e '[.evidence[] | select(.kind == "branch-merged")][0].detail == "origin/feat/006-widget-flow"'
}

# =====================================================================
# Task 7.2 — the same-branch predicate (R1.9)
# =====================================================================
# R1.8 and R1.9 are converses: R1.8 forbids reporting one branch twice, R1.9
# forbids reporting two branches once. Authored from R1.9's text BEFORE the
# fix, hostile case first (agents/test-advisor.md, Hostile-half rule).
# A shared NAME is not a shared branch. Collapsing requires the
# remote-tracking ref to be that branch's mirror — its configured upstream OR
# the same commit — and NEITHER disjunct is the rule on its own: same-object
# alone splits a local branch legitimately ahead of its upstream (case 2),
# name alone swallows a second remote sitting at a different tip (case 1).

@test "7.2 a second remote at a different tip is its own entry (R1.9)" {
  make_repo "$WORK/r" main
  commit_msg "$WORK/r" "chore: a second commit so two distinct merged tips exist"
  git -C "$WORK/r" remote add origin https://example.invalid/widget.git
  git -C "$WORK/r" remote add fork https://example.invalid/fork.git
  git -C "$WORK/r" branch feat/006-widget-flow                                # local @A
  git -C "$WORK/r" update-ref refs/remotes/origin/feat/006-widget-flow HEAD   # @A — the local branch's mirror
  git -C "$WORK/r" update-ref refs/remotes/fork/feat/006-widget-flow HEAD~1   # @B — a different branch, also merged
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  # origin/x sits on the local branch's own commit and folds into it; fork/x is
  # neither its upstream nor at its commit, so it survives as its own entry.
  [ "$(branch_merged_count)" -eq 2 ]
  echo "$output" | jq -e \
    '[.evidence[] | select(.kind == "branch-merged").detail] | sort == ["feat/006-widget-flow", "fork/feat/006-widget-flow"]'
}

@test "7.2 a local branch ahead of its own upstream stays one entry (R1.8)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" remote add origin https://example.invalid/widget.git
  git -C "$WORK/r" update-ref refs/remotes/origin/feat/006-widget-flow HEAD   # the pushed tip
  git -C "$WORK/r" checkout -q -b feat/006-widget-flow
  commit_msg "$WORK/r" "chore: local work not pushed yet"                     # local moves ahead
  git -C "$WORK/r" branch --set-upstream-to=origin/feat/006-widget-flow \
    feat/006-widget-flow >/dev/null 2>&1
  git -C "$WORK/r" checkout -q main
  git -C "$WORK/r" merge -q --no-ff -m "chore: integrate the branch" feat/006-widget-flow
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  # The converse of case 1: the two objects DIFFER, so a same-object-only
  # predicate would split one branch into two and re-break R1.8. The upstream
  # link is what says they are one branch.
  [ "$(branch_merged_count)" -eq 1 ]
  echo "$output" | jq -e '[.evidence[] | select(.kind == "branch-merged")][0].detail == "feat/006-widget-flow"'
}

# =====================================================================
# Task 7.3 — distinguishable details (R1.10)
# =====================================================================
# Identity is computed from the FULL refname; the detail is then rendered as
# the SHORT name, which throws that distinction away again. A guarantee the
# consumer cannot observe is not a guarantee: two entries denoting different
# branches must not arrive byte-identical. Hostile case first — the collision
# — then the converse: disambiguation fires ON COLLISION ONLY, so a lone
# identity keeps the plain short name every other case already asserts.

@test "7.3 two identities that share a short name get distinguishable details (R1.10)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" remote add origin https://example.invalid/widget.git
  git -C "$WORK/r" branch origin/feat/006-widget-flow            # a real LOCAL branch, literally named that
  git -C "$WORK/r" update-ref refs/remotes/origin/feat/006-widget-flow HEAD
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  [ "$(branch_merged_count)" -eq 2 ]
  # The guarantee as a consumer observes it: distinct entries, distinct details.
  echo "$output" | jq -e \
    '[.evidence[] | select(.kind == "branch-merged").detail] | (unique | length) == length'
  # Spelled the way git itself disambiguates the same pair.
  echo "$output" | jq -e \
    '[.evidence[] | select(.kind == "branch-merged").detail] | sort == ["heads/origin/feat/006-widget-flow", "remotes/origin/feat/006-widget-flow"]'
}

@test "7.3 a lone identity keeps its plain short name (R1.10)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" remote add origin https://example.invalid/widget.git
  git -C "$WORK/r" branch origin/feat/006-widget-flow            # same spelling, but nothing to collide with
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  [ "$(branch_merged_count)" -eq 1 ]
  # Not "heads/origin/...": disambiguating unconditionally would rewrite the
  # detail of every ordinary case and move assertions this fix must not touch.
  echo "$output" | jq -e '[.evidence[] | select(.kind == "branch-merged")][0].detail == "origin/feat/006-widget-flow"'
}

# When the branch exists ONLY as a remote-tracking ref, deduping must not
# invent a local branch that was never there — the detail keeps the ref name.
@test "5.1 a remote-only merged branch keeps its ref name in the detail (R1.8)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" remote add origin https://example.invalid/widget.git
  git -C "$WORK/r" update-ref refs/remotes/origin/feat/006-widget-flow HEAD
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  [ "$(branch_merged_count)" -eq 1 ]
  echo "$output" | jq -e '[.evidence[] | select(.kind == "branch-merged")][0].detail == "origin/feat/006-widget-flow"'
}
