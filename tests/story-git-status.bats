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
