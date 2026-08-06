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
#   0  status computable (including integrated: null when no main branch is
#      resolvable — R1.5)
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
local_branch_exists() {
  local rc=0
  git show-ref --verify --quiet "refs/heads/$1" 2>/dev/null || rc=$?
  [[ "$rc" -eq 0 ]]
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

# --- Main-branch resolution (R1.5) ---
# Order: remote HEAD default → local main → local master → none (unknowable).
# MAIN_BRANCH is the short name reported in the JSON; MAIN_REF is the revision
# the evidence queries run against.
MAIN_BRANCH=""
MAIN_REF=""
MAIN_AMBIGUOUS=false

rc=0
ORIGIN_HEAD=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || rc=$?
if [[ "$rc" -eq 0 && -n "$ORIGIN_HEAD" ]]; then
  MAIN_BRANCH="${ORIGIN_HEAD#origin/}"
  # Prefer the local branch of that name (it sees unpushed integration
  # commits); fall back to the remote-tracking ref when the default branch is
  # not checked out locally. Evaluate what is visible, never fail.
  if local_branch_exists "$MAIN_BRANCH"; then
    MAIN_REF="$MAIN_BRANCH"
  else
    MAIN_REF="$ORIGIN_HEAD"
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
  MAIN_REF="$MAIN_BRANCH"
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
  rc=0
  MERGED_BRANCHES=$(git branch -a --merged "$MAIN_REF" --format='%(refname:short)' 2>/dev/null) || rc=$?
  if [[ "$rc" -eq 0 && -n "$MERGED_BRANCHES" ]]; then
    # Herestring, not a pipe: the loop must run in the current shell or the
    # EVIDENCE appends would die with the subshell.
    while IFS= read -r BRANCH_NAME; do
      if [[ "$BRANCH_NAME" =~ $BRANCH_FEAT_RE ]] ||
         [[ -n "$STORY_SLUG" && "$BRANCH_NAME" =~ $BRANCH_SLUG_RE ]]; then
        add_evidence "branch-merged" "$BRANCH_NAME"
      fi
    done <<< "$MERGED_BRANCHES"
  fi

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
# integrated: true iff at least one evidence entry; false when a main branch
# resolved but no evidence was found; null when no main is resolvable (R1.5 —
# unknowable, callers stay quiet).
if [[ -n "$MAIN_BRANCH" ]]; then
  MAIN_JSON="\"$(json_escape "$MAIN_BRANCH")\""
  if [[ "${#EVIDENCE[@]}" -gt 0 ]]; then
    INTEGRATED="true"
  else
    INTEGRATED="false"
  fi
else
  MAIN_JSON="null"
  INTEGRATED="null"
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
