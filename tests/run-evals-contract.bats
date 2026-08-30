#!/usr/bin/env bats
# Contract tests for scripts/run-evals.sh (story 021 — close-the-eval-deferrals).
# Authored by the Test Advisor BEFORE implementation (TDD Red phase).
#
# Contract under test (design.md, Fix Approach 2; R2.1-R2.5):
#   - neither call site passes --bare; both grant Skill; both detach stdin
#   - run_trigger asks for stream-json and delegates the verdict to
#     scripts/trigger-detect.sh — ONE scorer in the tree, not two
#   - the summary reports how many cases and trigger runs executed
#   - EVAL_FILTER selects a subset; EVAL_RUNS repeats it and is validated
#   - an ENABLED plugin of the manifest's own name is a refusal (exit 2), not a
#     silent measurement of the installed copy
#
# WHY MOST OF THIS IS READ, NOT RUN. Executing the suite costs one model call
# per query. These cases pin the invocation the suite would make, which is where
# all four original defects lived: a flag that refuses OAuth, a missing tool
# grant, an inherited stdin, and a scorer reading a format that never carried
# the event. None of those needs an API call to detect — and a test that costs
# money to run is a test nobody runs.
#
# THE CASES THAT DO RUN use a `claude` stub on PATH. They must never reach the
# real CLI: a stub that is bypassed turns this file into a billing surprise, so
# each such case asserts the stub was consulted.
#
# EPIC_PLUGIN_ROOT overrides root resolution so this draft copy can run before
# materialization into tests/ — and so Red can be verified against HEAD rather
# than against an uncommitted working tree.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="${EPIC_PLUGIN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  SCRIPT="$PLUGIN_ROOT/scripts/run-evals.sh"
  WORK=$(mktemp -d)
  BIN="$WORK/bin"; mkdir -p "$BIN"
}

teardown() { rm -rf "$WORK"; }

# A `claude` stub that records every invocation and answers the two subcommands
# the suite uses. $1 = the plugin-list status line to emit.
stub_claude() {
  local status_line="$1"
  cat > "$BIN/claude" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$WORK/calls.log"
case "\$1" in
  plugin) printf '  ❯ epic@lucascouts\n    Status: %s\n' "$status_line" ;;
  -p)     printf '{"type":"result","subtype":"success","is_error":false}\n' ;;
  *)      exit 0 ;;
esac
STUB
  chmod +x "$BIN/claude"
}

# ---------- 2.1: the invocation itself ----------

@test "2.1: neither call site passes --bare — its auth excludes every subscription host" {
  run grep -c -- '--bare' "$SCRIPT"
  [ "$output" = "0" ]
}

@test "2.1: both call sites grant the Skill tool — without it the invocation is denied, and a denial used to score as a trigger" {
  run bash -c "grep -c -- '--allowedTools' '$SCRIPT'"
  local total="$output"
  run bash -c "grep -- '--allowedTools' '$SCRIPT' | grep -c 'Skill'"
  [ "$output" = "$total" ]
}

@test "2.1: both CLI invocations detach stdin — an inherited one made the loop eat its own input" {
  run bash -c "grep -c 'claude -p' '$SCRIPT'"
  local total="$output"
  run bash -c "grep -A6 'claude -p' '$SCRIPT' | grep -c '</dev/null'"
  [ "$output" = "$total" ]
}

@test "2.1: run_trigger asks for stream-json — the only format that emits the tool_use event it scores" {
  run bash -c "sed -n '/^run_trigger()/,/^}/p' '$SCRIPT' | grep -c 'stream-json'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "2.1: the verdict is delegated — run-evals.sh matches no skill id inline, so there is ONE scorer" {
  run bash -c "sed -n '/^run_trigger()/,/^}/p' '$SCRIPT' | grep -c 'trigger-detect.sh'"
  [ "$output" -ge 1 ]
  run bash -c "sed -n '/^run_trigger()/,/^}/p' '$SCRIPT' | grep -c 'epic:epic' || true"
  [ "$output" = "0" ]
}

@test "2.1: run_trigger gives its workdir a git repo, as run_case already does" {
  run bash -c "sed -n '/^run_trigger()/,/^}/p' '$SCRIPT' | grep -c 'git init'"
  [ "$output" -ge 1 ]
}

# The six cases above this comment READ the script. The two below RUN it, with a
# `claude` stub, because "mentions trigger-detect.sh" and "calls it" are not the
# same claim: a guard satisfied by a comment is a guard that cannot fail. Each
# asserts the stub was consulted, so neither can ever reach the real CLI.

@test "2.1: a firing transcript is scored a pass — the delegation is wired, not merely mentioned" {
  cat > "$BIN/claude" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$WORK/calls.log"
case "\$1" in
  plugin) printf '  ❯ epic@lucascouts\n    Status: ✘ disabled\n' ;;
  -p)
    printf '%s\n' '{"type":"assistant","message":{"type":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"epic:epic","args":"plan"}}]}}'
    printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"num_turns":7}'
    ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$BIN/claude"
  cd "$PLUGIN_ROOT"
  # 'Stripe webhook' selects exactly one query, and it is a should_trigger one.
  run env PATH="$BIN:$PATH" EVAL_FILTER='Stripe webhook' bash "$SCRIPT" --triggers
  local suite_status="$status" suite_output="$output"
  [ "$suite_status" -eq 0 ]
  [[ "$suite_output" == *"ran: 0 case(s), 1 trigger(s)"* ]]
  [[ "$suite_output" == *"All evals passed."* ]]
  [[ "$suite_output" != *"FAIL"* ]]
  [[ "$suite_output" != *"ERROR"* ]]
  # The stub answered the query: this case cost no model call.
  run bash -c "grep -c '^-p ' '$WORK/calls.log'"
  [ "$output" -ge 1 ]
}

@test "2.1: a run that produced no transcript is counted as errored, never as a pass" {
  cat > "$BIN/claude" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$WORK/calls.log"
case "\$1" in
  plugin) printf '  ❯ epic@lucascouts\n    Status: ✘ disabled\n' ;;
  # -p answers with nothing at all: the run produced no transcript to score.
  *)      : ;;
esac
STUB
  chmod +x "$BIN/claude"
  cd "$PLUGIN_ROOT"
  run env PATH="$BIN:$PATH" EVAL_FILTER='Stripe webhook' bash "$SCRIPT" --triggers
  local suite_status="$status" suite_output="$output"
  # Reached and attempted — the denominator counts it...
  [[ "$suite_output" == *"ran: 0 case(s), 1 trigger(s)"* ]]
  # ...reported as an ERROR, and never folded into the greens.
  [[ "$suite_output" == *"ERROR"* ]]
  [[ "$suite_output" != *"All evals passed."* ]]
  [ "$suite_status" -eq 1 ]
  run bash -c "grep -c '^-p ' '$WORK/calls.log'"
  [ "$output" -ge 1 ]
}

# ---------- 2.2: denominator, filter, run count ----------

@test "2.2: the summary reports how much was measured, not only how much failed" {
  stub_claude "✘ disabled"
  cd "$PLUGIN_ROOT"
  run env PATH="$BIN:$PATH" EVAL_FILTER=__matches_nothing__ bash "$SCRIPT" --triggers
  [[ "$output" == *"ran: 0 case(s), 0 trigger(s)"* ]]
}

@test "2.2: a filter matching nothing reports a zero denominator — never a bare 'all passed'" {
  stub_claude "✘ disabled"
  cd "$PLUGIN_ROOT"
  run env PATH="$BIN:$PATH" EVAL_FILTER=__matches_nothing__ bash "$SCRIPT" --triggers
  [[ "$output" == *"0 trigger(s)"* ]]
}

@test "2.2: EVAL_RUNS=0 is a usage error naming the variable, not a silent no-op" {
  stub_claude "✘ disabled"
  cd "$PLUGIN_ROOT"
  run env PATH="$BIN:$PATH" EVAL_RUNS=0 bash "$SCRIPT" --triggers
  [ "$status" -eq 2 ]
  [[ "$output" == *"EVAL_RUNS"* ]]
}

@test "2.2: EVAL_RUNS=abc is a usage error, not a seq failure swallowed by set -e" {
  stub_claude "✘ disabled"
  cd "$PLUGIN_ROOT"
  run env PATH="$BIN:$PATH" EVAL_RUNS=abc bash "$SCRIPT" --triggers
  [ "$status" -eq 2 ]
  [[ "$output" == *"EVAL_RUNS"* ]]
}

@test "2.2: the filter is applied with if/then, not an AND-list that survives set -e by exception" {
  # Assert the feature EXISTS before asserting how it is written: "contains no
  # AND-list" is vacuously true of a script with no filter at all, and this case
  # passed against HEAD for exactly that reason until the first clause was added.
  run bash -c "grep -c 'EVAL_FILTER' '$SCRIPT'"
  [ "$output" -ge 2 ]
  run bash -c "grep -c 'EVAL_FILTER.*&& continue' '$SCRIPT' || true"
  [ "$output" = "0" ]
}

# The two cases below pin the PER-QUERY RATE, which nothing else in this file
# reaches: EVAL_RUNS is only worth having if the repeated runs are reported as a
# rate, and a rate is the one form in which "fired 1 of 3 times" is sayable at
# all. Both RUN the suite behind a stub and assert the stub was consulted, so
# neither can reach the real CLI.
#
# Each asserts the QUERY's own line, never a bare `: N/M` — the section header
# carries `(healthy: 0/2)`, so a substring test on the rate alone would be
# satisfied by the header and would hold with no query line printed at all.

@test "2.2: a query is reported once as a rate over its runs, not once per failed run" {
  cat > "$BIN/claude" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$WORK/calls.log"
case "\$1" in
  plugin) printf '  ❯ epic@lucascouts\n    Status: ✘ disabled\n' ;;
  -p)
    # Fires on odd-numbered calls only. Two consecutive calls always hold
    # exactly one odd, so this is 1-of-2 wherever the run pair starts — the
    # rate survives a later guard that consults the stub before the queries.
    if [ \$(( \$(wc -l < "$WORK/calls.log") % 2 )) -eq 1 ]; then
      printf '%s\n' '{"type":"assistant","message":{"type":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"epic:epic","args":"plan"}}]}}'
    fi
    printf '%s\n' '{"type":"result","subtype":"success","is_error":false}'
    ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$BIN/claude"
  cd "$PLUGIN_ROOT"
  run env PATH="$BIN:$PATH" EVAL_FILTER='Stripe webhook' EVAL_RUNS=2 bash "$SCRIPT" --triggers
  local suite_status="$status" suite_output="$output"
  # EVAL_RUNS is honoured: one query, and the denominator counts RUNS.
  [[ "$suite_output" == *"ran: 0 case(s), 2 trigger(s)"* ]]
  # The query appears once, carrying its rate — not once per run that missed.
  [[ "$suite_output" == *"audit log: 1/2"* ]]
  # The rate is for reading, not for grading: a run that missed still fails.
  [ "$suite_status" -eq 1 ]
  run bash -c "grep -c '^-p ' '$WORK/calls.log'"
  [ "$output" = "2" ]
}

@test "2.2: the rate counts runs that FIRED in both groups — a quiet should_not_trigger query reads 0/N and passes" {
  stub_claude "✘ disabled"
  cd "$PLUGIN_ROOT"
  # 'regex' selects exactly one query, and it is a should_not_trigger one. The
  # stub answers with a terminal result and no Skill event: it never fires.
  run env PATH="$BIN:$PATH" EVAL_FILTER=regex EVAL_RUNS=2 bash "$SCRIPT" --triggers
  local suite_status="$status" suite_output="$output"
  [ "$suite_status" -eq 0 ]
  [[ "$suite_output" == *"ran: 0 case(s), 2 trigger(s)"* ]]
  # 0/2 IS this query's pass. A numerator of "runs that matched the
  # expectation" would print 2/2 here and make the two groups unreadable
  # against each other.
  [[ "$suite_output" == *"regex do?: 0/2"* ]]
  # ...and 0/2 only reads as a pass because the section names its direction.
  [[ "$suite_output" == *"should_not_trigger"* ]]
  run bash -c "grep -c '^-p ' '$WORK/calls.log'"
  [ "$output" = "2" ]
}

# ---------- 2.3: refuse to grade the wrong copy ----------

@test "2.3: an ENABLED plugin of the same name is a refusal — --plugin-dir does not outrank it" {
  stub_claude "✔ enabled"
  cd "$PLUGIN_ROOT"
  run env PATH="$BIN:$PATH" bash "$SCRIPT" --triggers
  [ "$status" -eq 2 ]
  [[ "$output" == *"disable"* ]]
}

@test "2.3: the refusal names the command that resolves it" {
  stub_claude "✔ enabled"
  cd "$PLUGIN_ROOT"
  run env PATH="$BIN:$PATH" bash "$SCRIPT" --triggers
  [[ "$output" == *"claude plugin disable"* ]]
}

@test "2.3: the refusal costs no model call — it fires before the first query" {
  stub_claude "✔ enabled"
  cd "$PLUGIN_ROOT"
  run env PATH="$BIN:$PATH" bash "$SCRIPT" --triggers
  run bash -c "grep -c '^-p' '$WORK/calls.log' || true"
  [ "$output" = "0" ]
}

@test "2.3: a DISABLED plugin proceeds — the guard blocks the collision, not the suite" {
  stub_claude "✘ disabled"
  cd "$PLUGIN_ROOT"
  run env PATH="$BIN:$PATH" EVAL_FILTER=__matches_nothing__ bash "$SCRIPT" --triggers
  [ "$status" -ne 2 ]
  # A script with NO guard also "proceeds". Assert the guard ran: the stub must
  # have been asked. Without this clause the case passed against HEAD, scoring
  # the absence of the feature as the feature working.
  run bash -c "grep -c '^plugin' '$WORK/calls.log' || true"
  [ "$output" -ge 1 ]
}

@test "2.3: an unparseable plugin listing warns and proceeds — unverifiable is not known-bad" {
  cat > "$BIN/claude" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  plugin) echo "gibberish that is not a listing" ;;
  -p)     printf '{"type":"result","subtype":"success","is_error":false}\n' ;;
esac
STUB
  chmod +x "$BIN/claude"
  cd "$PLUGIN_ROOT"
  run env PATH="$BIN:$PATH" EVAL_FILTER=__matches_nothing__ bash "$SCRIPT" --triggers
  [ "$status" -ne 2 ]
  [[ "$output" == *"warn"* || "$output" == *"Warn"* || "$output" == *"could not"* ]]
}

@test "2.3: the plugin name comes from the manifest, never hardcoded" {
  run bash -c "grep -c 'plugin.json' '$SCRIPT'"
  [ "$output" -ge 1 ]
}

# The case above is satisfied by a script that merely MENTIONS plugin.json — in
# a comment, say. The two below spend a fixture to ask the stronger question the
# plan asks for, from both directions: rename the plugin and the REFUSAL must
# rename with it, and a DIFFERENT installed plugin must not be read as a
# collision. A hardcoded name fails the first; a `grep enabled` over the whole
# listing fails the second.

# A throwaway repo whose manifest carries $1 as the plugin name. run-evals.sh
# resolves its root with `git rev-parse`, so running it from here is what makes
# this manifest the one it reads. Only what the guard can reach is copied in:
# the guard fires before the first query, and trigger-queries.json is all the
# path after it needs.
renamed_fixture() {
  local repo="$WORK/fixture"
  mkdir -p "$repo/.claude-plugin" "$repo/evals"
  jq --arg n "$1" '.name = $n' "$PLUGIN_ROOT/.claude-plugin/plugin.json" > "$repo/.claude-plugin/plugin.json"
  cp "$PLUGIN_ROOT/evals/trigger-queries.json" "$repo/evals/trigger-queries.json"
  git -C "$repo" init -q
  printf '%s\n' "$repo"
}

@test "2.3: the refusal names the MANIFEST's plugin — rename it and the command renames with it" {
  local repo; repo=$(renamed_fixture renamed-plugin)
  cat > "$BIN/claude" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$WORK/calls.log"
case "\$1" in
  plugin) printf '  ❯ renamed-plugin@somewhere\n    Status: ✔ enabled\n' ;;
  *)      exit 0 ;;
esac
STUB
  chmod +x "$BIN/claude"
  cd "$repo"
  run env PATH="$BIN:$PATH" EVAL_FILTER=__matches_nothing__ bash "$SCRIPT" --triggers
  [ "$status" -eq 2 ]
  [[ "$output" == *"claude plugin disable renamed-plugin"* ]]
}

@test "2.3: a different installed plugin is not a collision — the name is compared, and the Status read under it" {
  local repo; repo=$(renamed_fixture renamed-plugin)
  # The listing offers epic@lucascouts, ENABLED. It is not this manifest's name,
  # so it outranks nothing here and the suite must proceed.
  stub_claude "✔ enabled"
  cd "$repo"
  run env PATH="$BIN:$PATH" EVAL_FILTER=__matches_nothing__ bash "$SCRIPT" --triggers
  [ "$status" -ne 2 ]
  run bash -c "grep -c '^plugin' '$WORK/calls.log' || true"
  [ "$output" -ge 1 ]
}
