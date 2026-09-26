#!/usr/bin/env bats
# The checkbox-grammar consumer roster is DATA. This file is the roster's single
# home on the test side: it scans scripts/ and needs no story fixture, so it is
# self-contained.
#
# WHAT IS BEING PINNED, AND WHY IT IS NOT A NUMBER. A prose enumeration of the
# checkbox-grammar consumers cannot fail, so nobody is told when it goes stale.
# Every case below therefore compares a DERIVED set against a DECLARED set. NO
# CASE HERE ASSERTS HOW MANY CONSUMERS THERE ARE — asserting a count would
# recreate, in the very file meant to end the defect, the thing that keeps going
# stale. If a new consumer lands in scripts/, these cases redden and name it;
# nobody edits a number to make them green again, they register the script.
#
# ── THE CONTRACT THESE CASES DRIVE ─────────────────────────────────────────
# The roster and its detection predicate live in ONE sourced shell library:
#
#   tests/lib/checkbox-consumers.sh
#
# sourced by a suite, defining exactly four names:
#
#   CHECKBOX_CONSUMERS=( … )
#       The DECLARED roster: the basename of every script under scripts/ that
#       reads the checkbox grammar. Data, not prose. This is the one place a
#       human edits when a consumer is added.
#
#   CHECKBOX_CONSUMER_EXEMPT=( "name.sh: written reason" … )
#       A script the detection predicate finds but which does not really
#       read the grammar (a false positive) is silenced HERE, and only with a
#       reason after the colon. An entry with no reason is not an exemption.
#       Expected to be empty on the tree as it stands.
#
#   detect_checkbox_consumers <scripts-dir>
#       Prints, one basename per line, every script in <scripts-dir> whose
#       NON-COMMENT body reads the checkbox grammar. Exit 0. This is the
#       derivation — the predicate the tree is scanned with.
#
#   checkbox_roster_diff <scripts-dir>
#       Exit 0 when the detected set equals the declared roster (exemptions
#       absorbed). Otherwise NON-ZERO, printing one line per discrepancy that
#       NAMES THE SCRIPT and says which side it is missing from. "Naming it" is
#       the requirement: a red that says only "the roster disagrees" sends the
#       reader back to counting.
#
# BOTH ARRAYS MUST BE READ AT CALL TIME, not snapshotted when the library is
# sourced. That is a testability requirement, and it is what lets the hostile
# halves below reassign them to drive a case the real tree cannot produce.
#
# EPIC_PLUGIN_ROOT overrides root resolution so this file can run against a
# plugin tree other than the one it sits in.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="${EPIC_PLUGIN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  ROSTER_LIB="$PLUGIN_ROOT/tests/lib/checkbox-consumers.sh"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

# load_roster — source the declared roster, or fail saying it is not there yet.
# Sourced per case rather than in setup() so a case that needs no roster (the
# prose scan) still runs, and so the missing-library red reads plainly.
load_roster() {
  if [ ! -f "$ROSTER_LIB" ]; then
    echo "the declared consumer roster does not exist yet: $ROSTER_LIB"
    return 1
  fi
  # shellcheck disable=SC1090
  source "$ROSTER_LIB"
}

# a_consumer <path> — a script that reads the checkbox grammar in the canonical
# spelling. Any predicate that finds the real consumers finds this one too.
a_consumer() {
  cat > "$1" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
box_re='^[[:space:]]*- \[([ x~])\]'
while IFS= read -r line; do
  [[ "$line" =~ $box_re ]] && printf '%s\n' "${BASH_REMATCH[1]}"
done < "$1"
SH
}

# copy_scripts — a writable duplicate of scripts/, so a case can add a script
# to the tree it scans without touching the repository.
copy_scripts() {
  mkdir -p "$WORK/scripts"
  cp "$PLUGIN_ROOT"/scripts/*.sh "$WORK/scripts/"
}

# --- The roster is derived and compared ------------------------------------

@test "the declared roster and a scan of scripts/ agree — and both are non-empty" {
  load_roster

  # The non-emptiness pair is not decoration. Two ways to make a comparison
  # green while measuring nothing are an empty roster and a predicate that
  # finds nothing; asserting both sides carry entries kills both, without
  # anyone writing what the number is.
  [ "${#CHECKBOX_CONSUMERS[@]}" -gt 0 ]

  run detect_checkbox_consumers "$PLUGIN_ROOT/scripts"
  [ "$status" -eq 0 ]
  [ -n "$output" ]

  # Same set, same size — the derivation IS the assertion.
  detected=$(printf '%s\n' "$output" | sort)
  declared=$(printf '%s\n' "${CHECKBOX_CONSUMERS[@]}" | sort)
  [ "$detected" = "$declared" ]

  # Every declared name is a script that actually exists.
  for s in "${CHECKBOX_CONSUMERS[@]}"; do
    [ -f "$PLUGIN_ROOT/scripts/$s" ]
  done

  # And the comparison agrees with itself through its own entry point.
  run checkbox_roster_diff "$PLUGIN_ROOT/scripts"
  [ "$status" -eq 0 ]
}

@test "an unregistered consumer reddens the derivation, and the red names it" {
  load_roster
  copy_scripts
  a_consumer "$WORK/scripts/zz-unregistered.sh"

  run checkbox_roster_diff "$WORK/scripts"
  [ "$status" -ne 0 ]
  # Naming is the point: the reader must be told WHICH script to register.
  echo "$output" | grep -qF 'zz-unregistered.sh'
}

@test "an exemption silences a detected script only when it carries a reason" {
  load_roster
  copy_scripts
  # Stands in for a false positive — a script the predicate finds that does not
  # really read the grammar. What a test can observe is the MECHANISM, so the
  # fixture is one every predicate detects.
  a_consumer "$WORK/scripts/zz-lookalike.sh"

  # Neither declared nor exempt: fails, and says which script.
  run checkbox_roster_diff "$WORK/scripts"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF 'zz-lookalike.sh'

  # Exempt WITH a written reason: absorbed, the derivation is green again.
  CHECKBOX_CONSUMER_EXEMPT=("zz-lookalike.sh: prints the grammar in its usage text, never reads a box")
  run checkbox_roster_diff "$WORK/scripts"
  [ "$status" -eq 0 ]

  # Exempt with NO reason is not an exemption. A bare name is how an exemption
  # list becomes a second, unexplained roster.
  CHECKBOX_CONSUMER_EXEMPT=("zz-lookalike.sh")
  run checkbox_roster_diff "$WORK/scripts"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF 'zz-lookalike.sh'
}

# --- The predicate is pinned against the roster ----------------------------

@test "the predicate finds every declared consumer ON ITS OWN" {
  load_roster

  # THE ANTI-NARROWING PIN. A predicate that stops matching a spelling makes
  # the derivation above green by finding nothing on both sides at once. Here
  # each declared consumer is scanned ALONE, so a predicate narrowed to any
  # subset reddens naming the consumer it can no longer see. This is also what
  # keeps the two awkward spellings in the tree covered without naming them
  # here: whatever the roster declares must be findable, one at a time.
  for s in "${CHECKBOX_CONSUMERS[@]}"; do
    rm -rf "$WORK/solo"
    mkdir -p "$WORK/solo"
    cp "$PLUGIN_ROOT/scripts/$s" "$WORK/solo/$s"

    run detect_checkbox_consumers "$WORK/solo"
    [ "$status" -eq 0 ]
    if [ "$output" != "$s" ]; then
      echo "the predicate no longer finds the declared consumer '$s' (found: '${output:-nothing}')"
      return 1
    fi
  done
}

@test "a declared consumer the predicate cannot find is a failure, named" {
  load_roster
  copy_scripts

  # The same narrowing seen from the roster's side: a name on the list that the
  # scan does not produce must redden, not be quietly dropped.
  CHECKBOX_CONSUMERS+=("zz-phantom.sh")
  run checkbox_roster_diff "$WORK/scripts"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF 'zz-phantom.sh'
}

@test "a script that only DISCUSSES the grammar in comments is not a consumer" {
  load_roster
  mkdir -p "$WORK/talk"
  cat > "$WORK/talk/zz-commentary.sh" <<'SH'
#!/usr/bin/env bash
# The checkbox grammar is '^[[:space:]]*- \[([ x~])\]' — `- [ ]` open, `- [x]`
# closed, `- [~]` closed without the work. This script explains it and reads
# nothing: whole-line comments are stripped before detection, because scripts
# in the tree discuss the grammar exactly like this.
set -euo pipefail
printf 'nothing to see\n'
SH

  run detect_checkbox_consumers "$WORK/talk"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- The count stays out of the prose --------------------------------------

@test "no file under tests/ or scripts/ states a count of grammar consumers" {
  # THE SHAPE THE SCAN MATCHES: a cardinal number determining "consumer(s)" in the checkbox/grammar/roster sense — `the <N> checkbox
  # consumers`, with <N> spelled out or in digits. (The shape is written with a
  # placeholder rather than quoted verbatim on purpose: a quotation of the
  # sentence being banned is itself the banned sentence, and this file is under
  # tests/, so the scan below would flag its own documentation.) The two arms
  # are deliberately narrow. A broader arm (any cardinal near any "consumer")
  # flags sentences that are true or about something else entirely — "it has
  # two consumers" of a variable, "the one consumer that would write to it".
  # A linter that reddens on true sentences gets disabled, so this one catches
  # only the sentence shape that goes stale.
  #
  # ORDINALS ARE NOT COUNTS and are not matched.
  cardinal='one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|[0-9]+'

  run grep -rniE \
    -e "($cardinal)[[:space:]]+(checkbox|checkbox-grammar|grammar|roster)[[:space:]-]*consumers?" \
    -e "($cardinal)[[:space:]]+consumers?[[:space:]]+of[[:space:]]+(the[[:space:]]+)?(checkbox|grammar)" \
    "$PLUGIN_ROOT/tests" "$PLUGIN_ROOT/scripts"
  if [ "$status" -eq 0 ]; then
    echo "a consumer count is still asserted in prose:"
    echo "$output"
    return 1
  fi
  [ -z "$output" ]
}
