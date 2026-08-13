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

# =====================================================================
# Task 8.2 — the resolved main name is a function of the ref alone (R1.5, R1.12)
# =====================================================================
# `git symbolic-ref --short` renders the AMBIGUITY-AWARE spelling: the answer
# depends on which OTHER refs happen to exist. Add one decoy ref that also
# claims the short name "origin/main" and refs/remotes/origin/HEAD stops
# rendering as "origin/main" and starts rendering as "remotes/origin/main" —
# a string the fixed `${x#origin/}` strip cannot touch, so the reported
# main_branch becomes "remotes/origin/main" and the revision every evidence
# query runs against silently moves from the LOCAL main to the remote-tracking
# ref. That second effect is why this is the only defect in five reviews that
# changes `integrated`: an unpushed integration merge lives on local main and
# vanishes from the query. Hostile half first (agents/test-advisor.md), and
# the decoy is authored in BOTH of its reachable spellings — a branch and a
# tag — because the trigger is "another ref claims the name", not "another
# branch does".
#
# make_decoyed_repo <dir>: origin/HEAD → origin/main, plus a local main
# carrying an unpushed --no-ff merge of the story branch. Everything except
# the decoy ref itself, which each case adds in its own spelling.
make_decoyed_repo() {
  local dir=$1
  make_repo "$dir" main
  git -C "$dir" remote add origin https://example.invalid/widget.git
  # origin/main is pinned at the initial commit BEFORE the merge exists, so
  # the integration commit below is genuinely unpushed.
  set_origin_head "$dir" main
  git -C "$dir" checkout -q -b feat/006-widget-flow
  commit_msg "$dir" "wip: the widget, subject carrying no story token"
  git -C "$dir" checkout -q main
  git -C "$dir" merge -q --no-ff -m "chore: integrate the branch" feat/006-widget-flow
}

@test "8.2 a decoy BRANCH named origin/<default> changes neither the name nor integrated (R1.5, R1.12)" {
  make_decoyed_repo "$WORK/r"
  git -C "$WORK/r" branch origin/main        # refs/heads/origin/main — the decoy
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  # The name comes from refs/remotes/origin/HEAD's own path, so an unrelated
  # ref cannot move it.
  echo "$output" | jq -e '.main_branch == "main"'
  # And because the name is right, the revision is right: the merge that only
  # ever landed on LOCAL main still counts (R1.11).
  echo "$output" | jq -e '.integrated == true'
}

@test "8.2 a decoy TAG named origin/<default> changes neither the name nor integrated (R1.5, R1.12)" {
  make_decoyed_repo "$WORK/r"
  git -C "$WORK/r" tag origin/main           # refs/tags/origin/main — same claim, other namespace
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.main_branch == "main"'
  echo "$output" | jq -e '.integrated == true'
}

# =====================================================================
# Task 8.3 — uniqueness over the RENDERED set, not the short names (R1.10)
# =====================================================================
# 7.3 asked the right question of the wrong set. Its fix compares SHORT names,
# and escalates a colliding pair to the qualified spelling — but that spelling
# is a string the fix itself invented, and nothing asked what could collide
# with IT. A third branch whose PLAIN short name already reads
# "remotes/origin/feat/006-widget-flow" is byte-identical to what the colliding
# pair escalates to, and it had no collision of its own to escalate. The
# guarantee holds at two and breaks at three: R1.10 constrains the details a
# consumer reads, so the predicate belongs on the rendered set.
# This is the derived-value half of the hostile-half rule
# (agents/test-advisor.md) — hostile case first, converse second.

@test "8.3 three branches colliding pairwise get three distinct details (R1.10)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" remote add origin https://example.invalid/widget.git
  # Three genuinely different branches. Their short names are, in order:
  #   origin/feat/…  ·  remotes/origin/feat/…  ·  origin/feat/…
  # so 1 and 3 collide while 2 does not — and 2's PLAIN name is exactly what
  # the qualified spelling of 3 renders as.
  git -C "$WORK/r" branch origin/feat/006-widget-flow                          # refs/heads/origin/…
  git -C "$WORK/r" branch remotes/origin/feat/006-widget-flow                  # refs/heads/remotes/origin/…
  git -C "$WORK/r" update-ref refs/remotes/origin/feat/006-widget-flow HEAD    # refs/remotes/origin/…
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  # All three survive identity dedup — no two of them are the same branch.
  [ "$(branch_merged_count)" -eq 3 ]
  # The guarantee as a consumer observes it, asked of the whole set rather than
  # of any pair: three entries, three distinct details.
  echo "$output" | jq -e \
    '[.evidence[] | select(.kind == "branch-merged").detail] | (unique | length) == length'
}

@test "8.3 three branches with distinct short names all keep them (R1.10)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" remote add origin https://example.invalid/widget.git
  git -C "$WORK/r" branch feat/006-widget-flow
  git -C "$WORK/r" branch chore/006-widget-flow
  git -C "$WORK/r" branch origin/feat/006-widget-flow
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  [ "$(branch_merged_count)" -eq 3 ]
  # The converse of case 1, and the reason the predicate must stay CONDITIONAL:
  # escalating whenever the set has more than one member would rewrite the
  # detail of every ordinary multi-branch repository. Nothing collides here,
  # so nothing moves.
  echo "$output" | jq -e \
    '[.evidence[] | select(.kind == "branch-merged").detail] | sort == ["chore/006-widget-flow", "feat/006-widget-flow", "origin/feat/006-widget-flow"]'
}

# =====================================================================
# Task 8.4 — an ambiguous remote split does not collapse (R1.9, R1.13)
# =====================================================================
# Deciding WHICH remote a refs/remotes/… ref belongs to is not "the first path
# segment": git accepts a remote name containing a slash. With remotes "a" and
# "a/b", the ref refs/remotes/a/b/feat/006-widget-flow is genuinely ambiguous —
# branch feat/006-widget-flow of remote "a/b", or branch b/feat/006-widget-flow
# of remote "a"? — and taking the first configured match is a GUESS. Guess
# wrong and both collapse predicates can hold against a branch that is not the
# one in hand, so a real branch disappears from the evidence. The rule is
# therefore not a better guess but NO guess.
# `git remote add` refuses this pair in either order ("subset of existing
# remote"), so the topology only ever arrives from a hand-written config —
# which is exactly what add_nested_remotes writes.

# add_nested_remotes <dir>: configure remotes "a" and "a/b", the pair whose
# names make a remote-tracking refname ambiguous.
add_nested_remotes() {
  cat >> "$1/.git/config" <<'EOF'
[remote "a"]
	url = https://example.invalid/a.git
	fetch = +refs/heads/*:refs/remotes/a/*
[remote "a/b"]
	url = https://example.invalid/ab.git
	fetch = +refs/heads/*:refs/remotes/a/b/*
EOF
}

@test "8.4 an ambiguous remote split keeps both branches (R1.9, R1.13)" {
  make_repo "$WORK/r" main
  add_nested_remotes "$WORK/r"
  # Branch feat/006-widget-flow of remote "a/b" …
  git -C "$WORK/r" update-ref refs/remotes/a/b/feat/006-widget-flow HEAD
  # … and an unrelated LOCAL branch that the wrong reading names instead.
  git -C "$WORK/r" branch b/feat/006-widget-flow
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  # Read as branch b/feat/… of remote "a", both collapse predicates hold —
  # merged, same object — and the remote's own branch vanishes. Two branches
  # are two entries.
  [ "$(branch_merged_count)" -eq 2 ]
  echo "$output" | jq -e \
    '[.evidence[] | select(.kind == "branch-merged").detail] | sort == ["a/b/feat/006-widget-flow", "b/feat/006-widget-flow"]'
}

@test "8.4 an unambiguous split still collapses its pair (R1.8)" {
  make_repo "$WORK/r" main
  add_nested_remotes "$WORK/r"
  # Same nested-remote config, but only ONE of the two names prefixes this
  # ref: "a" does, "a/b" does not. Nothing is ambiguous, so the collapse must
  # still fire — the refusal is scoped to the ambiguity, not to the topology.
  git -C "$WORK/r" update-ref refs/remotes/a/c/feat/006-widget-flow HEAD
  git -C "$WORK/r" branch c/feat/006-widget-flow
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  # The converse guard: refusing whenever more than one remote is CONFIGURED —
  # rather than whenever more than one is a PREFIX — would split this pair and
  # re-break R1.8.
  [ "$(branch_merged_count)" -eq 1 ]
  echo "$output" | jq -e '[.evidence[] | select(.kind == "branch-merged")][0].detail == "c/feat/006-widget-flow"'
}

# =====================================================================
# Task 8.6 — a name that resolves over a revision that does not (R1.5)
# =====================================================================
# `integrated: false` is a POSITIVE claim: a main branch resolved, evidence was
# sought, none was found. `null` is the absence of a claim. The two gates that
# decide this branch on different variables — evidence is sought when MAIN_REF
# is non-empty, but the true/false-vs-null choice is made on MAIN_BRANCH — and
# 8.2 made MAIN_REF a full refname at every assignment without ever asking
# whether that refname RESOLVES. `git symbolic-ref` reads its stored target
# without requiring the target to exist (measured: rc 0 either way, with and
# without --short, so this predates 8.2), so a pruned origin/main leaves the
# name knowable and the revision empty. Both queries then fail into their own
# guards and the empty evidence list is emitted as a finding.
# references/validate-mode.md:138 states the rule this breaks verbatim, in the
# paragraph that opens `Exit 2 from the detector`:
# "Not computable" must never dress up as a finding
# This is 8.1's derived-value question asked of 8.2's own output — hostile half
# first, then the converse that keeps honest negatives honest.

@test "8.6 a dangling origin/HEAD is not computable, not a negative (R1.5)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" remote add origin https://example.invalid/widget.git
  set_origin_head "$WORK/r" main
  git -C "$WORK/r" branch -m main trunk        # no local main to prefer instead
  git -C "$WORK/r" update-ref -d refs/remotes/origin/main   # what --prune leaves behind
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  # The NAME is still knowable — origin/HEAD's own path says so.
  echo "$output" | jq -e '.main_branch == "main"'
  # The INTEGRATION is not: nothing was queried, so nothing may be claimed.
  echo "$output" | jq -e '.integrated == null'
}

@test "8.6 a resolvable main with no evidence is still a negative (R1.5)" {
  make_repo "$WORK/r" main
  git -C "$WORK/r" remote add origin https://example.invalid/widget.git
  set_origin_head "$WORK/r" main
  run_status "$WORK/r"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.main_branch == "main"'
  # The converse guard: the revision resolves and the queries ran, so "no
  # evidence" is a measured negative and must NOT be softened into null.
  echo "$output" | jq -e '.integrated == false'
  echo "$output" | jq -e '.evidence == []'
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
