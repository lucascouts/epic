#!/usr/bin/env bash
# Runs the eval suite at evals/evals.json and evals/trigger-queries.json
# against the local plugin copy, in `claude`'s print mode. Useful as a
# pre-release smoke test and as a CI gate for SKILL.md description regressions.
#
# Usage:
#   bash scripts/run-evals.sh               # all suites
#   bash scripts/run-evals.sh --cases       # only evals.json cases
#   bash scripts/run-evals.sh --triggers    # only trigger-queries.json
#
#   EVAL_FILTER=<substring> EVAL_RUNS=3 bash scripts/run-evals.sh --triggers
#       Re-measure only the queries containing <substring>, N times each, and
#       report each one as `<query>: <fired>/<runs>` — the numerator is runs in
#       which the skill FIRED, so N/N is healthy above the should_trigger
#       header and 0/N is healthy above should_not_trigger. A trigger eval is
#       probabilistic: one run cannot tell a regression from noise, so a query
#       is qualified by its rate, not by one verdict. EVAL_RUNS must be an
#       integer >= 1; anything else is a usage error (exit 2), never a `seq`
#       that fails quietly into an empty loop and reports a green over no runs.
#
# Requires: jq, claude CLI, plugin-dir-compatible Claude Code.
#
# AN INSTALLED COPY OF THIS PLUGIN IS REFUSED, NOT DOCUMENTED. This is where a
# paragraph used to ask the reader to disable it first. A sentence cannot fail,
# so the ask is now assert_no_plugin_collision below: it runs before the first
# query, it costs nothing, and it names the command that resolves the collision.
#
# THE HERMETIC FLAG IS GONE, DELIBERATELY. That flag — two dashes followed by
# `bare`, intentionally not spelled out anywhere in this file so a contract test
# can assert its absence by literal search — buys hermeticity `--plugin-dir`
# already supplies, and authenticates strictly through ANTHROPIC_API_KEY or
# apiKeyHelper ("OAuth and keychain are never read"). No subscription host
# satisfies that, so every query used to die on credentials before it ran.
#
# BOTH `--allowedTools` lists grant `Skill`. Without that grant the model picks
# the skill and the CLI denies it — and the denial payload is precisely what the
# old inline grep matched, so a denied invocation scored as a fired one.
#
# WHO SCORES A TRIGGER RUN: not this file. `run_trigger` captures the transcript
# and hands it to scripts/trigger-detect.sh, which answers triggered /
# not-triggered / error. ONE scorer in the tree, not two.
#
# Exit codes: 0 = every eval passed AND every run was measured
#             1 = an eval failed, or a run could not be measured at all
#             2 = setup error (bad environment, a malformed EVAL_RUNS, an
#                 enabled plugin of this tree's own name, or a scorer with no
#                 verdict) — the input is wrong, not the world

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || { echo "Error: not in a git repo" >&2; exit 2; })
cd "$ROOT"

command -v claude >/dev/null 2>&1 || { echo "Error: 'claude' CLI not on PATH" >&2; exit 2; }
command -v jq >/dev/null 2>&1     || { echo "Error: 'jq' not on PATH" >&2; exit 2; }

MODE="${1:-all}"
EVAL_FILTER="${EVAL_FILTER:-}"
EVAL_RUNS="${EVAL_RUNS:-1}"

# Validate the run count BEFORE anything runs, and name the variable in the
# message: the caller mistyped an input, so the answer is exit 2, not a suite
# that starts and then behaves oddly.
#
# Left unchecked, `EVAL_RUNS=0` and `EVAL_RUNS=abc` both end as an empty run
# loop — zero queries measured, zero failures counted, "All evals passed."
# printed. That is the same silent-green shape as the inherited stdin this file
# already repaired: a suite that measured nothing must never look like a suite
# that measured everything and liked what it saw.
if ! [[ "$EVAL_RUNS" =~ ^[0-9]+$ ]] || [ "$EVAL_RUNS" -lt 1 ]; then
  echo "Error: EVAL_RUNS must be an integer >= 1 (got: '$EVAL_RUNS')" >&2
  exit 2
fi

# Read ONE plugin's state out of a `claude plugin list` answer on stdin, and
# print exactly one word: enabled | disabled | absent | unknown.
#
# The listing is a BLOCK per plugin — a `❯ <name>@<marketplace>` header
# followed by indented `Field: value` lines — so a `Status:` line means nothing
# on its own. `grep enabled` over the whole answer would refuse whenever ANY
# OTHER plugin is enabled, and a normal host has a dozen. Every status is
# therefore attributed to the header above it, and only ours is read.
#
# The header is recognised by its `<name>@` token, not by the `❯` glyph: a
# cosmetic change to the bullet must not silently switch the guard off. What it
# cannot parse it calls `unknown` — never `disabled`, which would be a claim.
plugin_state() {
  local want="$1"
  awk -v want="$want" '
    # A header carries no "Field:" separator, which is what keeps a line of
    # prose ("gibberish that is not a listing") from being read as an entry.
    index($0, ":") == 0 {
      for (i = 1; i <= NF; i++) {
        at = index($i, "@")
        if (at > 1) {
          saw_entry = 1
          mine = (substr($i, 1, at - 1) == want)
          if (mine) found = 1
          next
        }
      }
    }

    mine && $1 == "Status:" {
      if (index($0, "disabled") > 0)     dis = 1
      else if (index($0, "enabled") > 0) en = 1
    }

    END {
      if (!saw_entry) { print "unknown";  exit }  # not a listing we understand
      if (!found)     { print "absent";   exit }  # a listing; we are not in it
      if (en)         { print "enabled";  exit }  # user + project scope: any
      if (dis)        { print "disabled"; exit }  # enabled block decides
      print "unknown"                             # our block, no status read
    }
  '
}

# Refuse to grade the wrong copy.
#
# `--plugin-dir` does NOT outrank an enabled plugin of the same name: the
# installed copy wins resolution and the suite measures the cache instead of
# this working tree — a green that says nothing about the code under review.
#
# The name comes from the MANIFEST, never from a literal: renaming the plugin
# has to move the guard with it, not leave it watching a name that no longer
# exists. And an answer that cannot be parsed is treated as "cannot verify",
# not as "known bad": refusing on an unreadable listing would make the whole
# suite hostage to the CLI's output format.
assert_no_plugin_collision() {
  local manifest="$ROOT/.claude-plugin/plugin.json"
  local name="" listing="" state="" invocation="bash scripts/run-evals.sh"
  if [ "$MODE" != "all" ]; then invocation="$invocation $MODE"; fi

  if [ -f "$manifest" ]; then
    name=$(jq -r '.name // ""' "$manifest" 2>/dev/null) || name=""
  fi
  if [ -z "$name" ]; then
    echo "Warning: could not read .name from $manifest — the installed-copy check was skipped." >&2
    return 0
  fi

  # stdin detached, as on every other CLI call in this file, and a `|| ` guard
  # because under `set -e` a CLI that exits non-zero here would kill the suite
  # on a question that is only advisory.
  listing=$(claude plugin list </dev/null 2>/dev/null) || listing=""
  state=$(printf '%s\n' "$listing" | plugin_state "$name") || state="unknown"

  # The remedy is spelled once: the refusal and the cannot-verify warning are
  # written for different readers, but they must never name different commands.
  local fix="claude plugin disable $name"

  case "$state" in
    enabled)
      cat >&2 <<EOF
Error: the plugin '$name' is ENABLED on this host, so this run would grade the
installed copy instead of this working tree. Disable it, measure, put it back:

  $fix && $invocation
  claude plugin enable $name

--plugin-dir does not outrank an enabled plugin of the same name: the installed
copy wins resolution and the suite reads the cache. Measured: with the plugin
disabled and no --plugin-dir, no skill event appears at all; adding
--plugin-dir brings this tree's skill back. That pair is what makes a run
attributable, and it is why this is a refusal rather than a warning.
EOF
      exit 2
      ;;
    disabled)
      echo "-- plugin check: '$name' is installed but disabled — this run grades the working tree."
      ;;
    absent)
      echo "-- plugin check: no installed plugin named '$name' — nothing outranks --plugin-dir."
      ;;
    *)
      echo "Warning: could not read 'claude plugin list' — proceeding UNVERIFIED. If '$name' is enabled on this host, run '$fix' first or this run grades the installed copy." >&2
      ;;
  esac
}

# Here, and not later: before the counters, before the temp dir, before the
# first query. A refusal that arrives after a model call has already cost what
# it exists to save.
assert_no_plugin_collision

FAILURES=0
TRIGGER_ERRORS=0
CASES_RUN=0
TRIGGERS_RUN=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

run_case() {
  local id="$1" prompt="$2"
  local workdir="$TMP/$id"
  mkdir -p "$workdir"

  echo ">> eval case: $id"
  CASES_RUN=$((CASES_RUN + 1))

  ( cd "$workdir" && git init -q && git commit --allow-empty -qm initial 2>/dev/null ) || true

  local output
  if ! output=$(
    cd "$workdir" && \
    claude -p "$prompt" \
      --plugin-dir "$ROOT" \
      --allowedTools "Read,Write,Glob,Grep,Bash,Agent,Skill,EnterWorktree,ExitWorktree,TodoWrite" \
      --output-format json \
      </dev/null 2>&1
  ); then
    echo "  FAIL: the print-mode invocation returned non-zero"
    echo "$output" | head -20 | sed 's/^/    /'
    FAILURES=$((FAILURES + 1))
    return
  fi

  # Assertion: Epic should have created .epic/stories/ for Create-mode cases.
  if [[ "$id" != "ambiguous-input" ]]; then
    if ! find "$workdir/.epic/stories" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -q .; then
      echo "  FAIL: no story directory created"
      FAILURES=$((FAILURES + 1))
      return
    fi
    # Every Epic story must have tasks.md.
    if ! find "$workdir/.epic/stories" -mindepth 2 -maxdepth 2 -name tasks.md 2>/dev/null | grep -q .; then
      echo "  FAIL: tasks.md missing"
      FAILURES=$((FAILURES + 1))
      return
    fi
    # Validate the story artifact. Capture the real exit status: `$?` right
    # after `if ! cmd` reads the negated status (always 0) — dead code.
    local story_dir rc=0
    story_dir=$(find "$workdir/.epic/stories" -mindepth 1 -maxdepth 1 -type d | head -1)
    bash "$ROOT/scripts/validate-story.sh" "$story_dir" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 1 ]; then
      echo "  FAIL: validate-story.sh reported errors"
      FAILURES=$((FAILURES + 1))
      return
    fi
  fi

  echo "  PASS"
}

# One trigger run: capture a transcript, then let the scorer say what it means.
# Returns 0 = the verdict matched the expectation, 1 = it did not, 2 = the run
# was not measurable at all (neither a pass nor a failure).
run_trigger() {
  local phrase="$1" expect_trigger="$2" run_no="${3:-1}"
  local workdir
  workdir="$TMP/trigger-$(printf '%s' "$phrase" | tr -cd 'a-zA-Z0-9' | head -c 30)-r$run_no"
  mkdir -p "$workdir"
  TRIGGERS_RUN=$((TRIGGERS_RUN + 1))

  # A git repo, exactly as run_case gets one: the skill reads workspace state on
  # entry, and a directory outside a repo is not the shape any query was written
  # against.
  ( cd "$workdir" && git init -q && git commit --allow-empty -qm initial 2>/dev/null ) || true

  local cli_err="$workdir/cli-stderr.log"
  local scorer_err="$workdir/scorer-stderr.log"

  # THREE deliberate details on this invocation, each one a repaired defect:
  #
  # `</dev/null` — this function runs inside a `while read` loop, and with an
  # inherited stdin the CLI swallowed the remaining queries: 27 queries in the
  # file, one measured, and no denominator printed to reveal it.
  #
  # stderr to a FILE, not `2>&1` — a stderr write with no trailing newline glues
  # itself onto the next event line. The scorer drops that unparseable line, and
  # when the casualty is the terminal `result` the verdict flips to `error`: a
  # false statement about a run that finished fine. A pure JSONL transcript
  # cannot be corrupted that way.
  #
  # `stream-json` — the only format that emits the tool_use event at all;
  # `--output-format json` returns the final result alone, which is why the old
  # scorer could only ever match the skill's failure payload.
  # The brace group makes the guard's scope explicit: a failed `cd` OR a
  # failed `claude` both land on `|| true`, so neither aborts the suite under
  # `set -e`. Written as a bare `A && B || C` chain, shellcheck 0.9 (the CI
  # runner's) reads it as a mistaken if/else and fails the lint (SC2015).
  local output
  output=$(
    { cd "$workdir" &&
      claude -p "$phrase" \
        --plugin-dir "$ROOT" \
        --allowedTools "Read,Glob,Grep,Agent,Skill" \
        --output-format stream-json --verbose \
        </dev/null 2>"$cli_err"; } || true
  )

  # The transcript is piped in EXPLICITLY. The scorer reads stdin whole, so
  # calling it with an inherited stdin inside this loop would reproduce, in
  # miniature, the very defect the redirect above removes.
  #
  # The `||` guard is not decoration: under `set -euo pipefail` a non-zero exit
  # inside `$( )` aborts THIS SCRIPT, not this function, so a scorer that
  # refuses (no parser, malformed call) would kill the suite mid-loop.
  local verdict_json=""
  verdict_json=$(
    printf '%s\n' "$output" | bash "$ROOT/scripts/trigger-detect.sh" 2>"$scorer_err"
  ) || verdict_json=""

  # `//` is safe on `reason`, a string. It must NEVER be used on the scorer's
  # `runs_completed`, which is `false` on exactly the verdict that matters:
  # `//` yields its right-hand side for `false` as well as `null`, so it would
  # mask an unmeasured run as a measured one.
  local verdict="" reason=""
  if [ -n "$verdict_json" ]; then
    verdict=$(printf '%s\n' "$verdict_json" | jq -r '.verdict // ""') || verdict=""
    reason=$(printf '%s\n' "$verdict_json" | jq -r '.reason // ""')  || reason=""
  fi

  # Branch on the VALUE, never on the scorer's exit status: all three verdicts
  # exit 0, because the scorer cannot know which one the caller expected —
  # "did not fire" is the desired answer for 12 of these 27 queries.
  local observed=""
  case "$verdict" in
    triggered)     observed=true  ;;
    not-triggered) observed=false ;;
    error)
      # Neither a pass nor a failure: nothing was measured. Counted on its own
      # so no green can be built on a run that never happened.
      echo "  ERROR trigger [run $run_no]: '$phrase' — ${reason:-the scorer gave no reason}"
      if [ -s "$cli_err" ]; then
        head -3 "$cli_err" | sed 's/^/      cli stderr: /'
      fi
      TRIGGER_ERRORS=$((TRIGGER_ERRORS + 1))
      return 2
      ;;
    *)
      # Not a query result at all: the scorer was called wrong, or could not
      # run. It would answer identically for every query, so the suite stops
      # here rather than printing 27 invented outcomes.
      echo "Error: scripts/trigger-detect.sh gave no usable verdict (got: '$verdict')" >&2
      if [ -s "$scorer_err" ]; then sed 's/^/  /' "$scorer_err" >&2; fi
      exit 2
      ;;
  esac

  if [ "$observed" = "$expect_trigger" ]; then
    return 0
  fi

  # Nothing is printed here on purpose. A missed expectation is reported once
  # per QUERY, as a rate, by measure_query below: with EVAL_RUNS=3 a line per
  # failed run says "FAIL" three times without ever saying "of how many", which
  # is the same unreadable shape as a failure count with no denominator.
  FAILURES=$((FAILURES + 1))
  return 1
}

# Is this query in the subset the caller asked for? An empty filter selects
# everything.
#
# Written as a predicate consumed by `if`, and deliberately NOT as the
# `[[ … ]] && continue` one-liner it replaces. That AND-list form is exempt from
# `set -e` only while the test is not the last command of the list — the moment
# it is negated, extended, or lifted into a function like this one, a query that
# simply does not match returns 1 and kills the whole suite. A construct that is
# correct only by an exception to the shell's error handling is a trap.
query_selected() {
  local phrase="$1"
  if [ -z "$EVAL_FILTER" ]; then
    return 0
  fi
  if [[ "$phrase" == *"$EVAL_FILTER"* ]]; then
    return 0
  fi
  return 1
}

# Measure ONE query across EVAL_RUNS runs and report its trigger rate.
#
# The numerator is runs in which the skill FIRED — the same meaning in both
# groups, so the two sections can be read with one rule. What differs is the
# healthy value, and each section header states it: N/N where the skill should
# fire, 0/N where it should not.
#
# A rate, not a verdict, because the measurement is probabilistic: 3/3 and 1/3
# are both "it fires" and only the denominator separates a regression from
# noise. The exit code stays strict — every run that missed its expectation
# still fails the suite — so the rate adds reading, it does not soften grading.
#
# A run the scorer could not measure is in the DENOMINATOR but in neither
# outcome, and the count is stated on the line. Folding it in silently would
# re-tell the exact lie this suite exists to stop: "did not fire" and "did not
# run" are not the same answer.
measure_query() {
  local phrase="$1" expect_trigger="$2"
  local r rc fired=0 unmeasured=0 note=""

  for (( r = 1; r <= EVAL_RUNS; r++ )); do
    # The `|| rc=$?` guard is mandatory under `set -e`: run_trigger returns
    # non-zero for a missed expectation (1) and for an unmeasured run (2), and
    # an unguarded call would abort the suite on the first one instead of
    # scoring it. `exit 2` from inside run_trigger still stops everything —
    # that path is a broken scorer, not a query result.
    rc=0
    run_trigger "$phrase" "$expect_trigger" "$r" || rc=$?

    # rc is relative to the EXPECTATION; the rate is about what was OBSERVED.
    # Matching a should-not-trigger query means the skill stayed quiet, so the
    # observation is recovered from the pair (rc, expectation), never from rc
    # alone.
    case "$rc" in
      0) if [ "$expect_trigger" = true  ]; then fired=$(( fired + 1 )); fi ;;
      1) if [ "$expect_trigger" = false ]; then fired=$(( fired + 1 )); fi ;;
      *) unmeasured=$(( unmeasured + 1 )) ;;
    esac
  done

  if [ "$unmeasured" -gt 0 ]; then
    note=" [$unmeasured unmeasured — see above]"
  fi
  printf -- '  %s: %d/%d%s\n' "$phrase" "$fired" "$EVAL_RUNS" "$note"
}

# Measure one group of trigger-queries.json — the two differ only in which
# answer is the right one.
#
# $1 is BOTH the JSON key and the printed section label, deliberately: they are
# one fact, and two copies of a fact drift. The header states the healthy rate
# for the group, so `0/3` never has to be remembered as a pass.
measure_group() {
  local group="$1" expect_trigger="$2"
  local healthy="0/$EVAL_RUNS"
  if [ "$expect_trigger" = true ]; then
    healthy="$EVAL_RUNS/$EVAL_RUNS"
  fi

  printf -- '-- %s — rate = runs that fired (healthy: %s) --\n' "$group" "$healthy"

  # Process substitution, not a pipe: the right side of a pipe runs in a
  # subshell, so the FAILURES increments below it never reach this shell and
  # the suite exits 0 no matter what it measured.
  while read -r phrase; do
    if query_selected "$phrase"; then
      measure_query "$phrase" "$expect_trigger"
    fi
  done < <(jq -r --arg g "$group" '.[$g][]' evals/trigger-queries.json)
}

# Feed the loop via process substitution, not a pipe: the right side of a pipe
# runs in a subshell, so FAILURES increments there never reached the parent and
# the suite always exited 0 ("All evals passed"). Same trap, same fix, inside
# measure_group.
if [[ "$MODE" == "all" || "$MODE" == "--cases" ]]; then
  echo "=== evals/evals.json ==="
  while read -r case_json; do
    id=$(echo "$case_json" | jq -r '.id')
    prompt=$(echo "$case_json" | jq -r '.prompt')
    run_case "$id" "$prompt"
  done < <(jq -c '.test_cases[]' evals/evals.json)
fi

if [[ "$MODE" == "all" || "$MODE" == "--triggers" ]]; then
  echo
  echo "=== evals/trigger-queries.json ==="
  measure_group should_trigger     true
  measure_group should_not_trigger false
fi

echo
# Report the denominator, not just the failures: "5 failed" cannot be read
# without knowing 5 of how many, and a suite that silently stops early (as this
# one did while the CLI inherited the loop's stdin) reads identical to one
# that ran everything.
echo "ran: $CASES_RUN case(s), $TRIGGERS_RUN trigger(s)"
if [ "$TRIGGER_ERRORS" -gt 0 ]; then
  echo "$TRIGGER_ERRORS trigger run(s) were NOT measured — see the ERROR lines above."
fi
if [ "$FAILURES" -eq 0 ] && [ "$TRIGGER_ERRORS" -eq 0 ]; then
  echo "All evals passed."
  exit 0
elif [ "$FAILURES" -eq 0 ]; then
  # No failure, but not a pass either: an unmeasured run is the one outcome the
  # old suite reported as a green, and reporting it as one again is the defect.
  echo "0 eval(s) failed, but $TRIGGER_ERRORS run(s) went unmeasured."
  exit 1
else
  echo "$FAILURES eval(s) failed."
  exit 1
fi
