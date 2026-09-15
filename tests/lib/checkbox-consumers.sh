#!/usr/bin/env bash
# tests/lib/checkbox-consumers.sh — the checkbox-grammar consumer roster, as
# DATA (story 017: R1.1, R1.2, R1.4).
#
# WHY THIS FILE EXISTS. The roster used to live in prose, in a test header, and
# a sentence cannot fail — so every time a script started reading the grammar,
# the enumeration went stale and nothing turned red. Five successive
# enumerations were wrong that way. Here the roster is an array, and a scan of
# scripts/ is compared against it: when the two disagree the comparison fails
# and NAMES the script, so nobody is sent back to counting.
#
# THE ONE PLACE A HUMAN EDITS is CHECKBOX_CONSUMERS below (or, for a false
# positive, CHECKBOX_CONSUMER_EXEMPT). Nothing else in the tree carries the
# list.
#
# Sourced by a bats suite; safe to source under `set -euo pipefail`. Both
# arrays are read AT CALL TIME by the functions below, never snapshotted when
# this file is sourced — a suite must be able to reassign them between calls to
# drive cases the real tree cannot produce.

# CHECKBOX_CONSUMERS — the DECLARED roster: the basename of every script under
# scripts/ that reads the checkbox grammar (`- [ ]` open, `- [x]` closed,
# `- [~]` closed without the work) as a regex. Sorted, purely so a diff of this
# file reads cleanly. Add a script that starts reading the grammar; drop one
# that stops. Either way checkbox_roster_diff tells you which name to touch.
CHECKBOX_CONSUMERS=(
  archive-story.sh
  close-subtask.sh
  cross-reference.sh
  epic-index.sh
  hook-post-tool-failure.sh
  hook-precompact.sh
  hook-task-completed.sh
  migrate-story.sh
  monitor-stale.sh
  supersede-story.sh
  validate-story.sh
)

# CHECKBOX_CONSUMER_EXEMPT — R1.2. A script the predicate below FINDS but which
# does not really read the grammar (a false positive) is silenced here, and
# only with a written reason after the colon:
#
#   CHECKBOX_CONSUMER_EXEMPT=("name.sh: prints the grammar in its usage text")
#
# An entry with no reason is NOT an exemption: checkbox_roster_diff rejects it
# by name instead of accepting it silently. Without that rule this array
# becomes a second roster — one nobody can audit, because it says nothing about
# why each name is on it. Empty as the tree stands.
CHECKBOX_CONSUMER_EXEMPT=()

# detect_checkbox_consumers <scripts-dir> — the DERIVATION. Prints, one
# basename per line, every *.sh in <scripts-dir> whose NON-COMMENT body reads
# the checkbox grammar. Always exits 0: it reports what it found and does not
# judge it — judging is checkbox_roster_diff's job. Anything it could not scan
# is announced on stderr, so a file that silently drops out of the scan cannot
# pass for a script that simply does not read the grammar.
detect_checkbox_consumers() {
  local dir="${1:-}" f body rc

  # THE PREDICATE, over the ESCAPED-bracket form — `\[` … `\]` as they are
  # written inside a regex literal, which is what "this script reads a
  # checkbox" looks like in source. Every spelling present in the tree must
  # match, and they differ:
  #
  #   \[([ x~])\]        the canonical capture (validate-story.sh, and most)
  #   \[[ x~]\]          no capture group (cross-reference.sh)
  #   \[([x~])\]         closed states only (hook-post-tool-failure.sh)
  #   \[ \]              open box only (monitor-stale.sh) — it asks "is work
  #                      still owed here?", the DELIBERATE EXCEPTION documented
  #                      in that script. Widen this predicate, never the script.
  #   \[)([ x~])(\]      split around the state (close-subtask.sh)
  #
  # `{1,4}` is what spans them: one space, `x~`, ` x~`, and a bracket
  # expression's contents all land inside it. hook-task-completed.sh spells its
  # surrounding whitespace `\s*` rather than `[[:space:]]*` — irrelevant here,
  # because the predicate looks at the box itself, not at what precedes it.
  local box_re='\\\[\(?\[?[ x~]{1,4}\]?\)?\\\]'

  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    printf '%s\n' "detect_checkbox_consumers: not a directory, nothing scanned: '${dir}'" >&2
    return 0
  fi

  # Only *.sh: everything under scripts/ is a .sh, and the roster is a list of
  # script basenames. Scanning every file instead would let a doc that QUOTES
  # the grammar demand an exemption for being documentation.
  for f in "$dir"/*.sh; do
    # Also catches the unmatched glob, which arrives here as a literal path.
    [ -f "$f" ] || continue

    rc=0
    body=''
    # `[ -f ]` says the file EXISTS, not that it OPENS. A bare failed
    # redirection under `set -e` kills the shell with no output at all, and
    # `if ! { …; } < f` reads as success — the `2>` BEFORE the `<`, plus
    # `|| rc=1`, is what makes the failure catchable. Same form as the censuses
    # in scripts/. Whole-line comments are stripped first: scripts in this tree
    # discuss the grammar in prose without reading it there, and a scan that
    # counted those would name innocents.
    { body=$(sed 's/^[[:space:]]*#.*//'); } 2>/dev/null < "$f" || rc=1
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "detect_checkbox_consumers: could not read '$f' — not scanned" >&2
      continue
    fi

    # A here-string, not a pipe: under `set -o pipefail`, `grep -q` exiting on
    # the first match can SIGPIPE the writer and turn a match into status 141.
    if grep -qE "$box_re" <<< "$body"; then
      printf '%s\n' "${f##*/}"
    fi
  done

  return 0
}

# checkbox_roster_diff <scripts-dir> — the COMPARISON. Exit 0 when the derived
# set equals the declared roster, exemptions absorbed. Otherwise non-zero, with
# one line per discrepancy on stdout that NAMES the script and says which side
# it is missing from. Naming is the requirement (R1.1): a red that says only
# "the roster disagrees" sends the reader back to counting, which is the whole
# defect this file exists to end.
#
# Both arrays are read here, at call time, straight out of the environment.
checkbox_roster_diff() {
  local dir="${1:-}" detected entry name reason rc=0
  local -a detected_names=()
  # Membership is asked of a set, not scanned for in a nested loop. Three
  # portability notes, all house rules from scripts/: `${arr[@]+"${arr[@]}"}`
  # rather than plain `"${arr[@]}"` (expanding an EMPTY array that way aborts
  # under `set -u` on bash < 4.4); `${map[$k]:-}` for the miss-safe lookup; and
  # never `${#map[@]}` on an associative array, which this tree has measured
  # tripping `set -u`.
  local -A declared=() exempt=() derived=()

  # stdout only — detect_checkbox_consumers' stderr flows past, so a file it
  # could not scan is still announced to whoever ran this.
  detected=$(detect_checkbox_consumers "$dir")
  if [ -n "$detected" ]; then
    mapfile -t detected_names <<< "$detected"
  fi
  for entry in ${detected_names[@]+"${detected_names[@]}"}; do
    derived["$entry"]=1
  done
  for entry in ${CHECKBOX_CONSUMERS[@]+"${CHECKBOX_CONSUMERS[@]}"}; do
    [ -n "$entry" ] || continue
    declared["$entry"]=1
  done

  # --- The exemption list is validated before it is trusted (R1.2) ----------
  for entry in ${CHECKBOX_CONSUMER_EXEMPT[@]+"${CHECKBOX_CONSUMER_EXEMPT[@]}"}; do
    name="${entry%%:*}"
    reason="${entry#*:}"
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    # No colon, no name before it, or nothing but whitespace after it: a bare
    # name explains nothing, so it silences nothing.
    if [[ "$entry" != *:* ]] || [ -z "$name" ] || [ -z "${reason//[[:space:]]/}" ]; then
      printf '%s\n' "exemption rejected: '$entry' carries no written reason — an exemption is spelled \"name.sh: why it is not really a consumer\", and a bare name is a second roster nobody can audit (R1.2)"
      rc=1
      continue
    fi
    exempt["$name"]=1
  done

  # --- Found by the scan, on neither list: missing from the DECLARED side ---
  for name in ${detected_names[@]+"${detected_names[@]}"}; do
    if [ -n "${declared[$name]:-}" ] || [ -n "${exempt[$name]:-}" ]; then
      continue
    fi
    printf '%s\n' "$name: the scan of '$dir' finds it reading the checkbox grammar, but it is on neither list — MISSING FROM THE DECLARED ROSTER. Add it to CHECKBOX_CONSUMERS in tests/lib/checkbox-consumers.sh, or, if it only looks like a reader, exempt it there with a written reason."
    rc=1
  done

  # --- Declared, never found: missing from the DERIVED side -----------------
  for name in ${CHECKBOX_CONSUMERS[@]+"${CHECKBOX_CONSUMERS[@]}"}; do
    if [ -z "${derived[$name]:-}" ]; then
      printf '%s\n' "$name: CHECKBOX_CONSUMERS declares it, but the scan of '$dir' does not find it reading the checkbox grammar — MISSING FROM THE DERIVED SET. Either it stopped reading the grammar (drop it from the roster), or its spelling of the box changed and the predicate in tests/lib/checkbox-consumers.sh no longer covers it (widen the predicate)."
      rc=1
    fi
  done

  return "$rc"
}
