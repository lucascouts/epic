#!/usr/bin/env bash
# Read-only git integration status for a single epic story.
#
# Usage: story-git-status.sh <NNN|story-dir>
#   <story-dir>  a story directory path (e.g. .epic/stories/006-widget-flow)
#   <NNN>        a bare story number, resolved as .epic/stories/NNN-* relative
#                to the current working directory
#
# Output: one JSON object on stdout —
#   {story, main_branch, integrated: true|false|null,
#    evidence: [{kind: branch-merged|message-ref, detail}], checked_at}
#
# Exit codes:
#   0  status computable (including integrated: null when no main branch
#      REVISION is queryable — R1.5. The NAME can still be knowable there, and
#      is still reported as main_branch; see the JSON emission block)
#   2  not a git repository or story not found — callers degrade silently, a
#      non-git workspace is legal (R1.4)
#
# Governing principle: evaluate git live, store nothing. This script writes NO
# files, ever. Every git call is guarded with `|| rc=$?` so an expected git
# failure never trips `set -e` (wave-0 convention), and git stderr is silenced
# so the stdout JSON is the only thing consumers ever see.

set -euo pipefail

# --- String quoting (R1.7) --------------------------------------------------
# `evidence[].detail` carries a commit subject — the rawest externally-authored
# string this plugin ever handles. A control character is perfectly legal in a
# commit message, and RFC 8259 §7 forbids U+0000-U+001F raw inside a JSON
# string, so a single 0x0C in a matching subject makes the WHOLE document
# unparseable while the script still exits 0 — an undefined caller path, because
# R1.4's degrade-silently contract only covers exit 2.
#
# So this uses the full C0/C1 `\uXXXX` table proven in scripts/archive-story.sh,
# not the lighter validate-story.sh variant (which covers only \ " \n \r \t).
# The producer stays dependency-free: consumers parse with jq, this emitter must
# never need it.
#
# Table scope: everything in U+0000-U+001F and U+007F-U+009F that has no short
# form here. C1 characters are matched as their UTF-8 pair (0xC2 0x80-0x9F),
# which is byte-identical whether bash runs in a UTF-8 locale (one character) or
# in C (two bytes) — the substitution is locale-independent either way. NUL needs
# no entry: a bash string cannot hold one.
#
# ONE-LINE DELTA vs archive-story.sh: its loop list excludes 8 and 12 because
# THAT script also has the short forms \b and \f. This one keeps only \ " \n \r
# \t, so 8 and 12 MUST stay in the list below and are emitted as \u0008 / \u000c.
# Copying archive-story.sh's list unchanged would leave 0x0C unescaped — exactly
# the bug this table exists to close.
JSON_ESC_RAW=()   # needle: the literal byte sequence to replace
JSON_ESC_REP=()   # replacement: its \uXXXX form
# The `printf -v needle "$needle"` pair below is a TWO-STAGE printf and the
# variable-as-format is the point of it: stage 1 builds the literal text `\x1b`,
# stage 2 makes printf interpret that escape into the byte itself. Writing the
# byte directly is not an option — it is what we are trying to produce.
# shellcheck disable=SC2059
_json_escape_table() {
  local i needle rep
  # C0 minus the three with a short escape (\t \n \r = 9 10 13), plus DEL (127).
  for i in 1 2 3 4 5 6 7 8 11 12 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 127; do
    printf -v needle '\\x%02x' "$i"
    printf -v needle "$needle"
    printf -v rep '\\u%04x' "$i"
    JSON_ESC_RAW+=("$needle")
    JSON_ESC_REP+=("$rep")
  done
  # C1: U+0080-U+009F, as their UTF-8 pair.
  for ((i = 128; i <= 159; i++)); do
    printf -v needle '\\xc2\\x%02x' "$i"
    printf -v needle "$needle"
    printf -v rep '\\u%04x' "$i"
    JSON_ESC_RAW+=("$needle")
    JSON_ESC_REP+=("$rep")
  done
}
_json_escape_table
unset -f _json_escape_table

json_escape() {
  local s="$1" i
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  for i in "${!JSON_ESC_RAW[@]}"; do
    s=${s//"${JSON_ESC_RAW[i]}"/"${JSON_ESC_REP[i]}"}
  done
  printf '%s' "$s"
}

# Escape a literal string for interpolation into a POSIX ERE ([[ =~ ]]).
# Story slugs are normally [a-z0-9-], but the slug comes from an arbitrary
# directory name, so metacharacters must not silently widen the match.
regex_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//./\\.}
  s=${s//\*/\\*}
  s=${s//+/\\+}
  s=${s//\?/\\?}
  s=${s//\[/\\[}
  s=${s//\]/\\]}
  s=${s//\(/\\(}
  s=${s//\)/\\)}
  s=${s//\{/\\{}
  s=${s//^/\\^}
  s=${s//|/\\|}
  # NB: } and $ must be escaped in the replacement too — an unescaped } would
  # end the parameter expansion early and leak a literal } into the pattern.
  s=${s//\}/\\\}}
  s=${s//\$/\\\$}
  printf '%s' "$s"
}

# add_evidence <kind> <detail>: append one evidence entry (a single-line JSON
# object) to the global EVIDENCE array.
add_evidence() {
  EVIDENCE+=("{\"kind\": \"$1\", \"detail\": \"$(json_escape "$2")\"}")
}

# local_branch_exists <name>: succeeds when refs/heads/<name> exists. The git
# call stays guarded so set -e never aborts; only used inside if conditions.
# SCOPE: main-branch resolution ONLY. Existence is deliberately NOT the
# predicate anywhere in evidence collection — a branch can exist and never have
# reached main (R1.8); mergedness is what evidence means. See ref_is_merged.
local_branch_exists() {
  local rc=0
  git show-ref --verify --quiet "refs/heads/$1" 2>/dev/null || rc=$?
  [[ "$rc" -eq 0 ]]
}

# ref_short_name <full-ref>: the name a reader knows a ref by —
# refs/heads/x → x, refs/remotes/origin/x → origin/x. Derived here instead of
# asking git for %(refname:short) because that rendering is ambiguity-aware and
# therefore unstable: when refs/heads/origin/x and refs/remotes/origin/x
# coexist git renders them "heads/origin/x" and "remotes/origin/x", and
# refs/remotes/origin/HEAD collapses to a bare "origin". The match patterns need
# one predictable spelling, and one `git branch` call must stay enough.
# THIS SPELLING IS THE MATCHER'S INPUT AND MUST STAY PLAIN. BRANCH_FEAT_RE is
# anchored (^feat/0*NNN-), so handing it git's disambiguated "heads/feat/NNN-x"
# instead would fail the anchor and drop the branch out of evidence altogether —
# a silent false negative, not a cosmetic one. Disambiguation is therefore
# confined to the EMITTED DETAIL, where this is only the FIRST of three rungs:
# see ref_qualified_name, ref_spelling and render_branch_details.
ref_short_name() {
  local ref="$1"
  case "$ref" in
    refs/heads/*)   printf '%s' "${ref#refs/heads/}" ;;
    refs/remotes/*) printf '%s' "${ref#refs/remotes/}" ;;
    # Anything else — git emits a "(HEAD detached at ...)" pseudo-entry — is
    # passed through untouched; it matches no evidence pattern either way.
    *)              printf '%s' "$ref" ;;
  esac
}

# ref_qualified_name <full-ref>: the longer spelling git falls back to when the
# short one is ambiguous — refs/heads/origin/x → heads/origin/x,
# refs/remotes/origin/x → remotes/origin/x. Measured on git 2.55: with both of
# those refs present, %(refname:short) renders exactly those two strings, and
# stripping "refs/" reproduces them.
# Derived here rather than asked of git for the same reason ref_short_name is —
# git's answer depends on which OTHER refs happen to exist, so it would move
# under a ref this run never looked at. A prefix strip is deterministic, needs
# no git call, and this file already holds every ref it cares about.
# NOT a spelling that can be assumed free: a local branch may be literally named
# remotes/origin/x, whose PLAIN short name is this string. Escalating to it is
# therefore never the end of the question — see render_branch_details.
ref_qualified_name() {
  local ref="$1"
  case "$ref" in
    refs/*) printf '%s' "${ref#refs/}" ;;
    # Same passthrough as ref_short_name: a non-refs/ string is not a ref name
    # and there is nothing to qualify.
    *)      printf '%s' "$ref" ;;
  esac
}

# ref_is_merged <full-ref>: succeeds when <full-ref> is in the merged set
# enumerated for this run. MEMBERSHIP, not existence (R1.8) — the two diverge
# exactly when a local branch was pushed, then rewritten locally: the ref
# exists, only its remote-tracking counterpart ever reached main.
# NB: ${arr+"${arr[@]}"} — under `set -u` an empty array must not be expanded
# bare. The guard yields nothing when the array is empty and quoted elements
# otherwise.
ref_is_merged() {
  local ref="$1" merged
  for merged in ${MERGED_REFS+"${MERGED_REFS[@]}"}; do
    [[ "$merged" == "$ref" ]] && return 0
  done
  return 1
}

# ref_object <full-ref>: the object <full-ref> resolves to, or nothing when it
# resolves to nothing. TOTAL — it always exits 0, because it is read through a
# command substitution in an assignment, where a non-zero status WOULD trip
# `set -e`. `--verify --quiet` is what makes a missing ref an ordinary empty
# answer (rc 1, no stderr) instead of a fatal.
# Full refnames only: they stay unambiguous even when refs/heads/origin/x and
# refs/remotes/origin/x coexist — the same reason this file never asks git for a
# short name. See ref_short_name.
ref_object() {
  local rc=0 oid=""
  oid=$(git rev-parse --verify --quiet "$1" 2>/dev/null) || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    printf '%s' "$oid"
  fi
  return 0
}

# refs_same_object <ref-a> <ref-b>: succeeds when both refs resolve AND land on
# the same object. The -n guard is not redundant: two refs that both resolve to
# nothing are not "the same object", they are two absent refs. Objects are
# compared raw, never peeled with ^{commit} — a branch ref is a commit already,
# and peeling would only add a failure mode.
refs_same_object() {
  local oid_a oid_b
  oid_a=$(ref_object "$1")
  oid_b=$(ref_object "$2")
  [[ -n "$oid_a" && "$oid_a" == "$oid_b" ]]
}

# ref_mirrors_branch <remote-tracking-ref> <local-ref>: succeeds when the
# remote-tracking ref really is <local-ref>'s mirror, and not a different branch
# that merely shares its name (R1.9). A shared name is NECESSARY and not
# SUFFICIENT; this is the missing conjunct that made fork/x at another tip
# vanish into refs/heads/x.
# GOTCHA — BOTH disjuncts are load-bearing, and each one alone is a defect:
#   * same-object alone: a local branch legitimately AHEAD of its own upstream
#     sits at a different commit, so it would split into two evidence entries —
#     re-breaking R1.8, the converse defect.
#   * upstream alone: a fresh clone or a fixture can have identical tips with no
#     branch.<x>.remote configured at all, and that pair would split too.
# R1.8 and R1.9 are converses; a one-sided predicate here just trades one defect
# for the other. Three consecutive reviews found the bug at exactly this spot —
# do not "simplify" this back into a single test.
# `@{upstream}` needs the SHORT branch name (measured: refs/heads/x@{upstream}
# resolves to nothing) and prints the upstream's FULL refname, directly
# comparable to the ref in hand. Under `--verify --quiet` every failure mode —
# no upstream, no such branch, an upstream whose ref is gone, a name git reads
# as an option — is the same rc 1 with empty stdout, so an unreadable upstream
# fails CLOSED: it can only refuse a collapse, never invent one.
ref_mirrors_branch() {
  local remote_ref="$1" local_ref="$2" upstream="" rc=0
  upstream=$(git rev-parse --verify --quiet --symbolic-full-name \
    "${local_ref#refs/heads/}@{upstream}" 2>/dev/null) || rc=$?
  if [[ "$rc" -eq 0 && "$upstream" == "$remote_ref" ]]; then
    return 0
  fi
  refs_same_object "$local_ref" "$remote_ref"
}

# branch_identity <full-ref>: the key deciding whether two refs denote the same
# branch (R1.8, R1.9). Identity comes from the FULL refname, never the short
# one:
#   refs/heads/x            → itself
#   refs/remotes/<remote>/x → refs/heads/x when BOTH hold: that local ref is
#                             itself in the merged set, AND the remote-tracking
#                             ref is genuinely its mirror (ref_mirrors_branch);
#                             otherwise itself
# refs/heads/x paired with its own remote-tracking ref is the ONLY collapse, so
# a local branch literally named "origin/x" stays distinct from
# refs/remotes/origin/x (their short names are identical, their refs are not),
# and one branch name on two remotes at two different tips stays two branches —
# the name matching is only half the predicate (R1.9).
# Returning a key that is always a MERGED ref is what lets the caller name the
# evidence from the key alone.
# The remote list is read from git, never a hardcoded "origin", and the split of
# refs/remotes/<remote>/<branch> is not simply "the first path segment": git
# accepts a remote name containing a slash, so refs/remotes/a/b/x may be branch
# x of remote "a/b" — or branch b/x of remote "a", when both names are
# configured. WHERE MORE THAN ONE CONFIGURED NAME FITS THERE IS NO SPLIT TO
# MAKE, AND THIS REFUSES TO INVENT ONE (R1.13): the ref keeps its own identity.
branch_identity() {
  # fits         how many configured remote names fit this ref
  # split_remote the one that fits, meaningful only when fits is exactly 1
  local ref="$1" rest remote fits=0 split_remote="" local_ref
  # A local branch is always its own identity — nothing collapses INTO a
  # remote-tracking ref, only the other way round.
  if [[ "$ref" != refs/remotes/* ]]; then
    printf '%s' "$ref"
    return 0
  fi
  rest="${ref#refs/remotes/}"
  # COUNT the remotes that fit, THEN decide. The first fit cannot settle it, and
  # this loop used to stop at it — a GUESS, under a comment asserting the guess
  # was harmless: "the collapse needs BOTH predicates … at worst one extra
  # evidence entry, never a missing one".
  #
  # MEASURED FALSE, which is why neither that comment nor the `break` is still
  # here. With remotes "a" and "a/b" configured, refs/remotes/a/b/feat/NNN-x is
  # read as branch b/feat/NNN-x of remote "a"; let that local branch exist, be
  # merged and sit at the same object and BOTH predicates hold — the collapse
  # fires and branch feat/NNN-x of remote "a/b" disappears from the evidence
  # entirely. A wrong guess does lose a branch.
  #
  # So the rule is not a better guess but NO GUESS: exactly one fit collapses,
  # more than one keeps the ref's own identity (R1.13). THE DIRECTION IS WHAT
  # MAKES THIS SAFE rather than merely different — refusing a collapse can only
  # ever ADD an evidence entry, never remove one, and `integrated` is
  # existential so it is untouched either way. That is what turns "never a
  # missing one" from an assertion into a fact.
  #
  # THE FIT IS TESTED AS "<name>/" and must stay that way: a remote named "ab"
  # does not own refs/remotes/a/b/x, and a bare-name test would count it as a
  # second fit and refuse a collapse nothing was ambiguous about.
  #
  # The scan is pure string work over a list `git remote` already produced, so
  # counting every fit instead of stopping at one costs no git call — one
  # comparison per remote. `git remote add` refuses the colliding pair in either
  # order ("subset of existing remote"), so the topology only ever arrives from
  # a hand-written config; that is why the class is cheap to remove, not a
  # reason to leave it open.
  for remote in ${REMOTES+"${REMOTES[@]}"}; do
    if [[ "$rest" == "$remote/"* ]]; then
      # Assignment, not (( fits++ )): a post-increment whose OLD value is 0
      # returns status 1 and would trip `set -e` on the very first fit.
      fits=$(( fits + 1 ))
      split_remote="$remote"
    fi
  done
  # -ne 1, not -gt 1, and both excluded counts mean the same thing here: with no
  # fit there is no split to make (a remote-tracking ref of a remote this repo
  # does not configure), and with several there is no split worth guessing at.
  # Either way the ref is already its own identity.
  if [[ "$fits" -ne 1 ]]; then
    printf '%s' "$ref"
    return 0
  fi
  local_ref="refs/heads/${rest#"$split_remote"/}"
  # The split is settled; now both rules must hold, cheapest first:
  #   1. the local counterpart is itself MERGED — membership, never existence,
  #      or the detail could name a branch that never reached main;
  #   2. and it is the same BRANCH, not merely the same name (R1.9).
  # && short-circuits, so a remote-only branch costs no extra git call.
  if ref_is_merged "$local_ref" && ref_mirrors_branch "$ref" "$local_ref"; then
    printf '%s' "$local_ref"
    return 0
  fi
  printf '%s' "$ref"
}

# branch_already_seen <key>: succeeds when <key> — a branch identity, see
# branch_identity — was already selected as a surviving identity in this run.
# SELECTED, not yet emitted: SEEN_BRANCHES is filled by the first pass and only
# rendered into evidence by the second, so that the second can ask its question
# of the whole survivor set at once (R1.10, see render_branch_details).
# Keeping SEEN_BRANCHES duplicate-free is also what makes the escalation there
# terminate: distinct entries are distinct FULL refnames.
# Linear scan — the list is one entry per matching branch, never a size where a
# hash would pay for itself.
branch_already_seen() {
  local key="$1" seen
  for seen in ${SEEN_BRANCHES+"${SEEN_BRANCHES[@]}"}; do
    [[ "$seen" == "$key" ]] && return 0
  done
  return 1
}

# The three spellings one identity can be reported under, in escalation order:
#   rung 0  short      refs/heads/origin/x → origin/x
#   rung 1  qualified  refs/heads/origin/x → heads/origin/x
#   rung 2  full       refs/heads/origin/x → refs/heads/origin/x
# EVERY RUNG RENDERS THE KEY AND NOTHING ELSE — that is what keeps rule 2
# (R1.8: the reported detail must name a ref that is itself merged) true however
# far a detail escalates. branch_identity only ever returns a ref of the merged
# set, and none of these three spellings can name a different ref.
# Rung 2 is the refname itself, and refnames are unique by construction; that
# single fact is the whole termination argument for render_branch_details.
DETAIL_RUNG_MAX=2

# ref_spelling <full-ref> <rung>: <full-ref> written at that rung.
# TOTAL — it is read through a command substitution in an assignment, where a
# non-zero status would trip `set -e`.
ref_spelling() {
  case "$2" in
    0) ref_short_name "$1" ;;
    1) ref_qualified_name "$1" ;;
    # Rung 2 and any value above it: the key verbatim. There is nothing longer
    # to escalate to, and nothing left that could need disambiguating.
    *) printf '%s' "$1" ;;
  esac
  return 0
}

# render_branch_details: fills BRANCH_DETAILS — index-parallel to SEEN_BRANCHES
# — with the string each surviving identity is reported under, such that no two
# entries of the emitted document arrive byte-identical (R1.10). Bash has no
# nested arrays; parallel indexed arrays are the idiom this file already uses.
#
# THE PREDICATE IS THE RENDERED SET, NEVER THE SHORT NAMES, and that is the
# whole reason this is a whole-set pass instead of a per-key call. Asking "does
# another survivor share my SHORT name?", escalating the pair that does, and
# emitting the longer spelling asks nothing about whether THAT spelling was
# free. Measured on git 2.55 with three merged branches —
# refs/heads/origin/feat/NNN-x, refs/heads/remotes/origin/feat/NNN-x and
# refs/remotes/origin/feat/NNN-x: the first and third collide on the short name
# origin/feat/NNN-x and escalate to heads/origin/… and remotes/origin/…, and
# remotes/origin/… is byte-identical to the PLAIN short name of the second,
# which had no collision of its own to escalate. Three entries, two distinct
# details. R1.10 constrains what the document says, so the question has to be
# asked of what the document says — a predicate over anything else is a
# predicate over the wrong thing.
#
# CONDITIONAL, and this is the half that is easy to lose. Escalating whenever
# the set holds more than one member would be simpler and would rewrite the
# detail of every ordinary multi-branch repository — "feat/NNN-x" becoming
# "heads/feat/NNN-x" for consumers that never had an ambiguity to resolve. Only
# a collision earns a longer spelling.
#
# TERMINATION IS FREE, which is why there is no iteration cap and none is
# needed. Each round escalates at least one entry: a colliding group cannot
# consist solely of entries already at DETAIL_RUNG_MAX, because that rung
# renders the key and the keys are distinct full refnames (branch_already_seen
# keeps SEEN_BRANCHES duplicate-free). Rungs never decrease and are capped, so
# the sum of rungs strictly increases every round towards 2n and the loop
# reaches a fixed point where no two details are equal.
# THE LOOP STILL DOES NOT TRUST THAT ARGUMENT, and the exit condition is
# "nothing escalated this round" rather than "nothing collides this round" for
# one reason: the two differ only when a colliding entry has no rung left, which
# the paragraph above proves impossible — and if that proof were ever falsified
# (a future change letting a duplicate key into SEEN_BRANCHES), the collides
# form would spin forever while this one stops. A duplicate detail is a
# cosmetic defect; a hang inside a script hooks and agents call is not. The
# strictly cheaper failure mode is the one worth being wrong into.
#
# DETECT, THEN ESCALATE — two phases per round, and the split is load-bearing
# for exactly the reason the SELECT/RENDER split below is: escalating in place
# while scanning would compare later entries against details that have already
# moved, and could only ever disambiguate the second member of each pair.
#
# Pure string work — no git call, so nothing here can fail or need guarding.
render_branch_details() {
  local n i j escalated
  local -a rungs=() colliding=()
  n=${#SEEN_BRANCHES[@]}
  BRANCH_DETAILS=()
  for ((i = 0; i < n; i++)); do
    rungs[i]=0
    BRANCH_DETAILS[i]=$(ref_spelling "${SEEN_BRANCHES[i]}" 0)
  done
  while :; do
    # Phase 1 — DETECT, over one frozen snapshot of the whole rendered set.
    for ((i = 0; i < n; i++)); do
      colliding[i]=false
      for ((j = 0; j < n; j++)); do
        if [[ "$i" -ne "$j" && "${BRANCH_DETAILS[i]}" == "${BRANCH_DETAILS[j]}" ]]; then
          colliding[i]=true
          break
        fi
      done
    done
    # Phase 2 — ESCALATE every entry that snapshot found colliding. A newly
    # rendered detail may collide with an entry that did NOT collide before
    # (the exact defect this function exists to close); the next round sees it,
    # because detection always re-reads the whole set.
    escalated=false
    for ((i = 0; i < n; i++)); do
      if [[ "${colliding[i]}" == true && "${rungs[i]}" -lt "$DETAIL_RUNG_MAX" ]]; then
        # Assignment, not (( rungs[i]++ )): a post-increment whose OLD value is
        # 0 returns status 1 and would trip `set -e` on the very first
        # escalation.
        rungs[i]=$(( rungs[i] + 1 ))
        BRANCH_DETAILS[i]=$(ref_spelling "${SEEN_BRANCHES[i]}" "${rungs[i]}")
        escalated=true
      fi
    done
    if [[ "$escalated" != true ]]; then
      break
    fi
  done
  return 0
}

# --- Input ---
STORY_ARG="${1:-}"
if [[ -z "$STORY_ARG" ]]; then
  echo "Usage: story-git-status.sh <NNN|story-dir>" >&2
  exit 2
fi

# --- Workspace check (R1.4) ---
# Not a git repository → exit 2 with nothing on stdout, so callers degrade
# silently (no annotation, no warning downstream).
rc=0
IN_TREE=$(git rev-parse --is-inside-work-tree 2>/dev/null) || rc=$?
if [[ "$rc" -ne 0 || "$IN_TREE" != "true" ]]; then
  echo "story-git-status: not a git repository: $PWD" >&2
  exit 2
fi

# --- Story resolution ---
STORY_DIR=""
if [[ -d "$STORY_ARG" ]]; then
  STORY_DIR="$STORY_ARG"
elif [[ "$STORY_ARG" =~ ^[0-9]+$ ]]; then
  # Bare number: first match of .epic/stories/NNN-* under the cwd. Without
  # nullglob an unmatched pattern stays literal and fails the -d test below.
  for CANDIDATE in .epic/stories/"$STORY_ARG"-*/; do
    if [[ -d "$CANDIDATE" ]]; then
      STORY_DIR="${CANDIDATE%/}"
      break
    fi
  done
fi

if [[ -z "$STORY_DIR" ]]; then
  echo "story-git-status: story not found: $STORY_ARG" >&2
  exit 2
fi

STORY_NAME=$(basename "$STORY_DIR")

# --- Story token extraction ---
# Story dirs follow NNN-slug. The capture strips the zero padding (006 → 6) so
# the evidence regexes can accept every delimited padded form via a leading
# `0*` while bare numbers, prose mentions and substrings such as 1006 never
# match (R1.3). A dir name without a numeric prefix yields no tokens, which
# simply means no number-based evidence can ever be found — never an error.
STORY_NUM=""
STORY_SLUG=""
if [[ "$STORY_NAME" =~ ^0*([0-9]+)-(.+)$ ]]; then
  STORY_NUM="${BASH_REMATCH[1]}"
  STORY_SLUG="${BASH_REMATCH[2]}"
elif [[ "$STORY_NAME" =~ ^0*([0-9]+)$ ]]; then
  STORY_NUM="${BASH_REMATCH[1]}"
fi

# --- Main-branch resolution (R1.5, R1.11, R1.12) ---
# Order: remote HEAD default → local main → local master → none (unknowable).
# THE NAME AND THE REVISION ARE TWO DIFFERENT ANSWERS, and conflating them is
# exactly what R1.12 forbids:
#   MAIN_BRANCH — the NAME: a BARE branch name, reported as main_branch in the
#                 JSON and interpolated into callers' warning text;
#   MAIN_REF    — the REVISION the evidence queries run against: always a FULL
#                 refname, never a bare name — at EVERY assignment below, on
#                 the remote path and on the local fallback alike.
MAIN_BRANCH=""
MAIN_REF=""
MAIN_AMBIGUOUS=false

# Read the FULL ref and strip a LITERAL prefix. Asking git to shorten it is
# forbidden here (R1.12): git's short rendering is AMBIGUITY-AWARE, so it is a
# function of the whole ref store rather than of this ref alone, and it moves
# under refs this run never looked at. Measured on git 2.55 — add ONE unrelated
# ref that also claims the name "origin/main" (refs/heads/origin/main or
# refs/tags/origin/main; both reproduce it) and the shortened answer stops being
# "origin/main" and becomes "remotes/origin/main". A fixed ${x#origin/} strip
# then misses, and the corrupted string becomes BOTH the reported name AND the
# revision probed — so an integration merge sitting on the local main drops out
# of every query and `integrated` flips on a ref nothing here ever consulted.
# The full path is deterministic and the strip costs no second git call.
# Same lesson, other call site: see ref_short_name.
rc=0
ORIGIN_HEAD_REF=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null) || rc=$?
# The guard and the strip carry the SAME literal prefix and must move together.
# `?*` requires at least one character after it, so an empty or unexpected
# target (a hand-written symbolic-ref pointing outside refs/remotes/origin/ —
# git's own porcelain, clone and `remote set-head`, never writes one) falls
# through to the local fallback below. Stripping a prefix that is not there
# would otherwise leave the whole path standing and report it as the name.
if [[ "$rc" -eq 0 && "$ORIGIN_HEAD_REF" == refs/remotes/origin/?* ]]; then
  MAIN_BRANCH="${ORIGIN_HEAD_REF#refs/remotes/origin/}"
  # Prefer the local branch of that name — it is the one that sees unpushed
  # integration commits (R1.11); fall back to the remote-tracking ref when the
  # default branch is not checked out locally. Evaluate what is visible, never
  # fail. local_branch_exists takes the BARE name and builds refs/heads/ itself,
  # so it must not be handed a full refname.
  if local_branch_exists "$MAIN_BRANCH"; then
    MAIN_REF="refs/heads/$MAIN_BRANCH"
  else
    MAIN_REF="$ORIGIN_HEAD_REF"
  fi
else
  HAS_MAIN=false
  HAS_MASTER=false
  if local_branch_exists main; then
    HAS_MAIN=true
  fi
  if local_branch_exists master; then
    HAS_MASTER=true
  fi

  if [[ "$HAS_MAIN" == true && "$HAS_MASTER" == true ]]; then
    # Both local candidates and no remote default to settle it: prefer main,
    # but surface the ambiguity to consumers.
    MAIN_BRANCH="main"
    MAIN_AMBIGUOUS=true
  elif [[ "$HAS_MAIN" == true ]]; then
    MAIN_BRANCH="main"
  elif [[ "$HAS_MASTER" == true ]]; then
    MAIN_BRANCH="master"
  fi
  # A FULL refname here too — the identical ambiguity, one layer down. A bare
  # "main" in a repository that ALSO holds a tag named main resolves to the TAG:
  # gitrevisions checks refs/tags/<name> before refs/heads/<name>. Measured on
  # git 2.55: `git log main` warns "refname 'main' is ambiguous" on stderr —
  # which this script silences — and then reports the tag's history, so a
  # commit made on the branch afterwards silently vanishes from the evidence.
  # The two candidates above are branches BY CONSTRUCTION (local_branch_exists
  # is what selected them), so refs/heads/ is the right prefix with nothing
  # re-asked of git. Empty stays empty: no main resolved means no revision to
  # query, which is R1.5's unknowable case.
  if [[ -n "$MAIN_BRANCH" ]]; then
    MAIN_REF="refs/heads/$MAIN_BRANCH"
  fi
fi

# A NAME THAT RESOLVES IS NOT A REVISION THAT RESOLVES, and this is where that
# distinction stops being a comment above and becomes a check. `git symbolic-ref`
# reads the target STORED in refs/remotes/origin/HEAD without requiring that
# target to exist, and exits 0 either way — measured on git 2.55, identically
# with and without `--short`, so the gap predates the R1.12 work above rather
# than being introduced by it. A `git fetch --prune` that removes
# refs/remotes/origin/main leaves the symref still pointing at it, so with no
# local `main` to prefer, the NAME resolves to `main` while the REVISION names
# nothing at all.
# Both evidence queries then fail — `fatal: malformed object name` and
# `fatal: bad revision`, rc 128, measured — and both are swallowed by their own
# `|| rc=$?` guards. The guards are right: a query that cannot run must never
# abort the run. What is wrong is calling the empty evidence list they leave
# behind a FINDING. R1.5 and references/validate-mode.md require the opposite,
# the latter verbatim: not computable must never dress up as a finding.
# ONE GATE AFTER THE WHOLE BLOCK, NOT ONE PER ARM, and the placement is the
# point. The defect closed here has exactly the shape of a per-assignment
# discipline: every MAIN_REF assignment above was checked to be SPELLED as a
# full refname and not one was ever checked to RESOLVE. A rule applied at each
# assignment is a rule a newly added arm can silently skip; applied here, the
# invariant "MAIN_REF non-empty ⇒ MAIN_REF resolves" holds whichever arm
# assigned it, and the emission gate below can rest on it.
# The local-fallback arm is believed redundant here, and this deliberately does
# not rely on that belief. Measured on git 2.55: `show-ref --verify --quiet`
# (what local_branch_exists asks) is the STRICTER of the two — on a ref whose
# object is missing it exits 128 while `rev-parse --verify --quiet` prints the
# name and exits 0, and on a dangling symref inside refs/heads both refuse. One
# cheap call buys independence from that measurement continuing to hold.
# THE PREDICATE'S OWN LIMIT, measured and named rather than assumed away:
# `rev-parse --verify --quiet` accepts a ref whose OBJECT is missing — it prints
# the stored name and exits 0 — so a ref hand-written at a nonexistent object
# still passes this gate, still fails both queries, and still lands on `false`.
# That state is one `git update-ref` REFUSES to create (rc 128, "nonexistent
# object") and `git fsck` reports as "invalid sha1 pointer": a corrupt
# repository, where every other git consumer is equally broken. It is out of
# contract in the same sense entry 18's hand-written symref shape is, and
# closing it would need a peeled `^{commit}` probe — a different call shape with
# failure modes of its own. Recorded in .draft/deviations.yaml, not fixed here.
# `[[ ]]` short-circuits `&&`, so the command substitution never runs — and
# ref_object never sees an empty ref — when nothing resolved a name at all.
if [[ -n "$MAIN_REF" && -z "$(ref_object "$MAIN_REF")" ]]; then
  MAIN_REF=""
fi

# --- Evidence collection (R1.1, R1.2, R1.3, R1.6) ---
# Either kind flips integrated on its own; both are reported when both hold.
# GOTCHA: feat/NNN-slug is an emergent convention documented nowhere — both
# evidence kinds are first-class and a branch is NEVER required (a squash
# merge whose subject carries the token is enough). Every invocation
# re-queries git — no caching, no state files — so history rewrites are
# reflected on the very next call (R1.6). Both git queries stay guarded: on a
# shallow clone or detached HEAD we evaluate whatever history is visible and
# never fail.
EVIDENCE=()
if [[ -n "$MAIN_REF" && -n "$STORY_NUM" ]]; then
  SLUG_RE=""
  if [[ -n "$STORY_SLUG" ]]; then
    SLUG_RE=$(regex_escape "$STORY_SLUG")
  fi

  # Rule 1 — branch-merged (R1.1): a branch matching feat/NNN-* or
  # */NNN-<slug>* whose tip is already reachable from main.
  BRANCH_FEAT_RE="^feat/0*${STORY_NUM}-"
  BRANCH_SLUG_RE="/0*${STORY_NUM}-${SLUG_RE}"

  # Evidence uniqueness (R1.8): one merged branch is one piece of evidence,
  # however many refs point at it, AND the reported detail must name a ref that
  # is itself merged. The duplicate is NOT one rule firing twice —
  # feat/NNN-slug matches the anchored BRANCH_FEAT_RE while
  # origin/feat/NNN-slug matches only BRANCH_SLUG_RE, so the pair arrives
  # through different branches of the || below and no guard inside either one
  # can see it. Dedupe over the accumulated refs instead, keyed on the FULL
  # refname (branch_identity): the short name cannot tell a local branch named
  # "origin/x" from the remote-tracking ref of "x", and collapsing those two
  # loses a real branch. That same blindness returns at the output edge — two
  # survivors rendered by short name alone arrive byte-identical — so the
  # RENDERED set is swept for equal details and the colliding ones spelled apart
  # until none are (R1.10, see render_branch_details).
  REMOTES=()
  rc=0
  REMOTES_RAW=$(git remote 2>/dev/null) || rc=$?
  if [[ "$rc" -eq 0 && -n "$REMOTES_RAW" ]]; then
    while IFS= read -r REMOTE_NAME; do
      [[ -n "$REMOTE_NAME" ]] && REMOTES+=("$REMOTE_NAME")
    done <<< "$REMOTES_RAW"
  fi
  # The surviving identities, in the order they were selected. Two jobs, one
  # array: the dedupe ledger the first pass tests against, and the render list
  # the second pass walks.
  SEEN_BRANCHES=()

  # Enumerate FULL refnames. The whole set is collected before any of it is
  # judged, because branch_identity asks whether ANOTHER ref (the local
  # counterpart of a remote-tracking one) is in the merged set — a question the
  # ref in hand cannot answer.
  MERGED_REFS=()
  rc=0
  MERGED_RAW=$(git branch -a --merged "$MAIN_REF" --format='%(refname)' 2>/dev/null) || rc=$?
  if [[ "$rc" -eq 0 && -n "$MERGED_RAW" ]]; then
    # Herestring, not a pipe: the loop must run in the current shell or the
    # array append would die with the subshell.
    while IFS= read -r MERGED_REF; do
      [[ -n "$MERGED_REF" ]] && MERGED_REFS+=("$MERGED_REF")
    done <<< "$MERGED_RAW"
  fi

  # SELECT, then RENDER — two passes, and the split is load-bearing (R1.10).
  # "Does another survivor render this same detail?" is unanswerable at the
  # moment the FIRST of a colliding pair is reached: the second has not been
  # seen yet. Emitting inside the selection loop can therefore only ever
  # disambiguate the second of the two. The survivor set is a function of
  # MERGED_REFS and the match patterns, both fully determined before either
  # pass, so settling it first costs nothing and makes the question answerable.
  # Pass order is preserved end to end: SEEN_BRANCHES is appended in
  # MERGED_REFS order, BRANCH_DETAILS is index-parallel to it, and evidence is
  # emitted in that same order.
  for BRANCH_REF in ${MERGED_REFS+"${MERGED_REFS[@]}"}; do
    # The matcher gets the PLAIN short name, always. Its patterns are anchored
    # at ^feat/ and would not survive a qualified spelling — see ref_short_name.
    BRANCH_NAME=$(ref_short_name "$BRANCH_REF")
    if [[ "$BRANCH_NAME" =~ $BRANCH_FEAT_RE ]] ||
       [[ -n "$STORY_SLUG" && "$BRANCH_NAME" =~ $BRANCH_SLUG_RE ]]; then
      BRANCH_KEY=$(branch_identity "$BRANCH_REF")
      if ! branch_already_seen "$BRANCH_KEY"; then
        SEEN_BRANCHES+=("$BRANCH_KEY")
      fi
    fi
  done

  # Every detail is named from its KEY, which branch_identity guarantees is a
  # ref of the merged set: the local branch's own name only when that local
  # branch really merged, otherwise the ref as git named it. Existence is the
  # wrong question — a local feat/NNN-x that diverged and never merged must not
  # be named merely because its remote-tracking counterpart reached main.
  # render_branch_details only ever RENDERS those keys, at whichever rung it
  # takes to tell them apart, so WHICH ref gets named is settled entirely above
  # and R1.8 is untouched by R1.10.
  render_branch_details
  for BRANCH_DETAIL in ${BRANCH_DETAILS+"${BRANCH_DETAILS[@]}"}; do
    add_evidence "branch-merged" "$BRANCH_DETAIL"
  done

  # Rule 2 — message-ref (R1.2): a commit subject reachable from main carrying
  # the story number as a delimited token ONLY — \(0*NNN\) (conventional
  # type(NNN):) or a word-bounded 0*NNN-<slug>. A bare undelimited number and
  # substrings such as 1006 never count (R1.3). The rule is existential, so
  # the first (most recent) matching subject is reported as the detail.
  MSG_CONV_RE="\\(0*${STORY_NUM}\\)"
  MSG_SLUG_RE="(^|[^[:alnum:]_])0*${STORY_NUM}-${SLUG_RE}"
  rc=0
  SUBJECTS=$(git log "$MAIN_REF" --format=%s -- 2>/dev/null) || rc=$?
  if [[ "$rc" -eq 0 && -n "$SUBJECTS" ]]; then
    while IFS= read -r SUBJECT; do
      if [[ "$SUBJECT" =~ $MSG_CONV_RE ]] ||
         [[ -n "$STORY_SLUG" && "$SUBJECT" =~ $MSG_SLUG_RE ]]; then
        add_evidence "message-ref" "$SUBJECT"
        break
      fi
    done <<< "$SUBJECTS"
  fi
fi

# --- JSON emission ---
# TWO FIELDS, TWO QUESTIONS, TWO GATES — and keying both on one variable is the
# defect this shape exists to prevent:
#   main_branch — the NAME, gated on MAIN_BRANCH. Reported whenever a name
#                 resolved, INCLUDING when its revision did not: the name really
#                 is knowable there, and withholding it would understate what
#                 was measured just as surely as `false` overstates it.
#   integrated  — the CLAIM, gated on MAIN_REF, the revision the queries
#                 actually ran against (R1.5, R1.11).
#     true   at least one evidence entry — the queries ran and found something;
#     false  the queries RAN and found nothing. A positive claim, and consumers
#            treat it as one: validate appends a warning naming the missing
#            evidence kinds (references/validate-mode.md);
#     null   no queryable revision, so nothing was ever asked and nothing may be
#            claimed — unknowable, and callers stay quiet.
# The `false` arm is reachable ONLY through a MAIN_REF the gate above proved
# resolves — that is what turns "the queries ran" from a hope into a fact.
# ONE CAVEAT, NAMED RATHER THAN GLOSSED: the evidence gate also requires
# STORY_NUM, so a story directory carrying no numeric prefix reports `false`
# with no query having run. That stays a true negative rather than a dressed-up
# unknown, and the difference is DERIVABILITY: both evidence rules are defined
# in terms of the story number, so with no number "no evidence exists" follows
# without asking git — whereas with no revision the evidence may well exist and
# simply could not be looked at.
# The converse pairing — main_branch null with integrated true or false — stays
# unreachable by construction, not by a second test: MAIN_REF is assigned on no
# arm that leaves MAIN_BRANCH empty, so MAIN_REF non-empty implies MAIN_BRANCH
# non-empty.
if [[ -n "$MAIN_BRANCH" ]]; then
  MAIN_JSON="\"$(json_escape "$MAIN_BRANCH")\""
else
  MAIN_JSON="null"
fi

if [[ -z "$MAIN_REF" ]]; then
  INTEGRATED="null"
elif [[ "${#EVIDENCE[@]}" -gt 0 ]]; then
  INTEGRATED="true"
else
  INTEGRATED="false"
fi

CHECKED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "{"
echo "  \"story\": \"$(json_escape "$STORY_NAME")\","
echo "  \"main_branch\": $MAIN_JSON,"
if [[ "$MAIN_AMBIGUOUS" == true ]]; then
  echo "  \"main_branch_ambiguous\": true,"
fi
echo "  \"integrated\": $INTEGRATED,"
if [[ "${#EVIDENCE[@]}" -eq 0 ]]; then
  echo "  \"evidence\": [],"
else
  echo "  \"evidence\": ["
  EVIDENCE_LAST=$(( ${#EVIDENCE[@]} - 1 ))
  for ((i = 0; i <= EVIDENCE_LAST; i++)); do
    SEP=","
    if [[ "$i" -eq "$EVIDENCE_LAST" ]]; then
      SEP=""
    fi
    echo "    ${EVIDENCE[i]}$SEP"
  done
  echo "  ],"
fi
echo "  \"checked_at\": \"$CHECKED_AT\""
echo "}"

exit 0
