#!/usr/bin/env bats
# Story 007, sub-task 5.1 — spike is exempt wherever Fast is exempt (R1.1),
# and Run mode reaches the promote offer by pointer, not by restatement (R1.6).
#
# Contract under test (doc-contract suite, same shape as
# tests/hook-monitor-grammar.bats — the surface here is agent-executed prose,
# so the assertions pin BLOCKS, never sentences):
#
#   R1.1 — a spike story has no `.draft/` either, so every scale-scoped clause
#          that exempts Fast from `.draft/`-dependent machinery must name spike
#          alongside it:
#            C1  run-mode.md step 7 (materialization) exemption
#            C2  run-mode.md step 7 converse-guard exemption
#            C3  run-mode.md run-time test-first ordering section, including
#                its Trivial and Simple+ sub-sections
#            C4  context-discovery.md Completeness Checklist scale scoping
#   R1.6 — run-mode.md carries a LINK to the promote offer that list-mode.md
#          defines (`## Spike Lifecycle`), in the same define-once/reuse shape
#          the Archive offer uses, and does NOT restate its mechanics.
#
# Assertion discipline: each case extracts a block by a structural anchor
# (heading, numbered step, paragraph landmark) and then asserts the word
# `spike` is present in it, case-insensitively. No case requires the
# implementer to reproduce a sentence verbatim — a correct rewrite of the
# prose must stay green, since prose that cannot be rewritten is the defect
# this story exists to stop.
#
# Note on awk patterns: they are passed as strings, so they carry NO backslash
# escapes (gawk strips `\.`/`\+` with a warning and the pattern silently stops
# matching). Literal punctuation is written as a bracket class: `[.]`, `[+]`.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUN_MODE="$PLUGIN_ROOT/references/run-mode.md"
  CONTEXT_DISCOVERY="$PLUGIN_ROOT/references/context-discovery.md"
  [ -f "$RUN_MODE" ]
  [ -f "$CONTEXT_DISCOVERY" ]
}

# --- block extractors -------------------------------------------------------

# Lines from the first line matching ERE $1 up to (not including) the next
# line matching ERE $2, from file $3.
section_between() {
  awk -v start="$1" -v stop="$2" '
    !inb && $0 ~ start { inb = 1; print; next }
    inb  && $0 ~ stop  { exit }
    inb                { print }
  ' "$3"
}

# --- assertions -------------------------------------------------------------

# First 25 lines of a block, so a failure message stays readable.
show_block() {
  printf '%s\n' "$1" | head -25
}

# $1 = label, $2 = block. The block must exist (guards against anchor drift)
# and must name spike somewhere inside it.
assert_names_spike() {
  local label=$1 block=$2
  if [ -z "$block" ]; then
    echo "anchor drift: extracted no block for $label"
    return 1
  fi
  if ! grep -qi 'spike' <<< "$block"; then
    echo "$label: block never names spike. Block was:"
    show_block "$block"
    return 1
  fi
}

# Tolerant variant for blocks whose scale scoping may legitimately move
# elsewhere: naming Fast without naming spike is the failure; naming neither
# is fine (the scoping now lives in the section that owns it).
assert_no_fast_only_scoping() {
  local label=$1 block=$2
  if [ -z "$block" ]; then
    echo "anchor drift: extracted no block for $label"
    return 1
  fi
  if grep -qi 'fast' <<< "$block" && ! grep -qi 'spike' <<< "$block"; then
    echo "$label: scopes on Fast but never names spike. Block was:"
    show_block "$block"
    return 1
  fi
}

# Assert file $2 does NOT match ERE $1. (A bare `! grep` is exempt from bats'
# errexit trap and would never fail the test.)
refute_grep_file() {
  if grep -qiE "$1" "$2"; then
    echo "did not expect /$1/ in $2:"
    grep -inE "$1" "$2"
    return 1
  fi
}

# --- C1: materialization exemption ------------------------------------------

@test "C1 R1.1: run-mode step 7 exempts spike from materialization, not Fast alone" {
  block=$(section_between '^[0-9]+[.] .*Materialize pre-authored tests' 'checks the converse' "$RUN_MODE")
  assert_names_spike "run-mode.md step 7 (materialize)" "$block"
}

# --- C2: converse-guard exemption -------------------------------------------

@test "C2 R1.1: run-mode step 7's converse guard exempts spike, not Fast alone" {
  block=$(section_between 'checks the converse' '^[0-9]+[.] ' "$RUN_MODE")
  assert_names_spike "run-mode.md step 7 (converse guard)" "$block"
}

# --- C3: run-time test-first ordering ---------------------------------------

@test "C3a R1.1: run-mode's run-time test-first ordering section is scoped to spike too" {
  block=$(section_between '^### Run-time test-first ordering' '^### Trivial Complexity' "$RUN_MODE")
  assert_names_spike "run-mode.md run-time test-first ordering" "$block"
}

@test "C3b R1.1: the Trivial Complexity sub-section carries no Fast-only scale scoping" {
  block=$(section_between '^### Trivial Complexity' '^### Simple[+] Complexity' "$RUN_MODE")
  assert_no_fast_only_scoping "run-mode.md Trivial Complexity" "$block"
}

@test "C3c R1.1: the Simple+ Complexity sub-section carries no Fast-only scale scoping" {
  block=$(section_between '^### Simple[+] Complexity' '^### Status Transitions' "$RUN_MODE")
  assert_no_fast_only_scoping "run-mode.md Simple+ Complexity" "$block"
}

# --- C4: completeness checklist scale scoping -------------------------------

@test "C4 R1.1: context-discovery's Completeness Checklist names spike beside fast scale" {
  block=$(section_between '^## Completeness Checklist' '^## ' "$CONTEXT_DISCOVERY")
  assert_names_spike "context-discovery.md Completeness Checklist" "$block"
}

# --- C5: promote offer is pointed at, never restated ------------------------

@test "C5a R1.6: run-mode links to list-mode.md's promote offer definition" {
  # Define once, reuse: a markdown link into list-mode.md's spike/promote
  # definition, the same shape run-mode.md uses for the Archive offer
  # (validate-mode.md#archive-offer). Any anchor is accepted as long as the
  # linking line is about the spike promote offer.
  if ! grep -oiE '[]]\([^)]*list-mode[.]md#[^)]*\)' "$RUN_MODE" | grep -qiE 'spike|promote'; then
    echo "run-mode.md carries no markdown link into list-mode.md's spike/promote definition"
    grep -inE 'list-mode[.]md' "$RUN_MODE" || echo "(run-mode.md never mentions list-mode.md)"
    return 1
  fi
}

@test "C5b R1.6: run-mode does not restate the promote offer's promoted-to write" {
  # Green pin: the offer's mechanics — including writing `promoted-to: NNN`
  # back into the Verdict — are defined once in list-mode.md. Run mode must
  # gain a pointer, never a second spelling of the procedure.
  refute_grep_file 'promoted-to' "$RUN_MODE"
}
