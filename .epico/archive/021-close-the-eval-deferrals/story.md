---
story: close-the-eval-deferrals
type: bugfix
scale: full
version: 1
created: 2026-08-29
status: archived
---

# Bugfix - The trigger-eval suite measured the opposite of what it claimed, and a fulfilled deferral had nowhere to go

## Summary

`scripts/run-evals.sh` has never measured skill triggering. Its detector greps
the final-result JSON for a `Skill` tool call that `--output-format json` does
not emit — so it matched only when the skill **failed**, and answered `false`
whenever the skill actually ran. Four further defects kept the suite from
running at all on a subscription-authenticated host. With the instrument fixed,
two trigger queries turn out never to fire, both because a routing mode reached
the cascade without ever reaching the skill `description`. And when the work a
`[~] (deferred: …)` box owes is finally done, no sanctioned operation can close
that box — so stories 013 and 015 cannot reach `done` even once their evals pass.

## Reproduction Steps

1. From a clean checkout, with `epic@lucascouts` installed and enabled, run
   `bash scripts/run-evals.sh --triggers`.
2. Observe every case reporting `claude -p` failure or `triggered=false`: under
   `--bare` the CLI answers `Not logged in · Please run /login` with
   `duration_api_ms: 0`, because `--bare` auth is strictly `ANTHROPIC_API_KEY`
   or `apiKeyHelper` — "OAuth and keychain are never read".
3. Remove `--bare` and re-run. The suite now authenticates, and stops after
   **one** case: `claude -p` inherits the `while read` loop's stdin and consumes
   the remaining queries.
4. Add `</dev/null` and re-run. The suite reaches all cases and every
   `should_trigger` query fails, including `list my stories`.
5. Run one of those queries by hand with `--output-format stream-json`. The
   skill fires: `{"type":"tool_use","name":"Skill","input":{"skill":"epic:epic"}}`.
   Run the same query with `--output-format json` — the format the script uses —
   and no tool call appears anywhere in the payload.
6. Run a query where the skill is offered but **denied** (omit `Skill` from
   `--allowedTools`). The error payload carries `tool_input`, and the script's
   grep matches: the assertion reports `triggered=true` for the one case where
   the skill did not run.
7. In a copy of story 015, run `bash scripts/close-subtask.sh 015 4.1` against
   its `[~] (deferred: …)` sub-task. It exits 1 — `already closed` — and
   `tasks.md` is byte-identical. `REFINE` cannot help: it "never writes a
   checkbox".

## Current Behavior (Defect)

WHEN the suite runs under `--bare` on a subscription-authenticated host THEN
every case fails on authentication, because `--bare` reads neither OAuth nor the
keychain.

WHEN the suite runs without `--bare` while a plugin of the same name is enabled
THEN the run grades the installed copy instead of the working tree, and reports
that verdict as if it came from this repository.

WHEN `claude -p` runs inside the `while read` loop THEN it consumes the loop's
remaining input, so the suite measures one query and reports its outcome with no
denominator — indistinguishable from a suite that ran all 27.

WHEN the skill is invoked but `Skill` is absent from `--allowedTools` THEN the
invocation is denied, and the run is scored as a triggering run.

WHEN the skill triggers and runs successfully THEN the detector answers `false`,
because `--output-format json` emits the final result alone and carries no tool
call to match.

WHEN the run fails outright — network error, timeout, denied permission — THEN
the detector answers `false` and every `should_not_trigger` query is scored as a
pass, having measured nothing.

WHEN a routing mode is added to the cascade without being named in the skill
`description` THEN the skill is never offered for the phrasing that mode
introduced: `stories create --batch <doc>` and `can you create an epic for the
user onboarding flow?` each fire 0 out of 3.

WHEN the work owed by a `[~] (deferred: …)` box is finally done THEN no
operation can record it: `close-subtask.sh` refuses to re-close a closed box,
`REFINE` never writes a checkbox, and reopening is defined by `[ ]` alone — so
the story stays `in-progress` permanently.

## Expected Behavior (Correct)

### R1. The trigger detector measures the invocation, and can report that it measured nothing

- R1.1: WHEN the suite scores a trigger query THE SYSTEM SHALL read the `Skill`
  tool-use event from a `stream-json` transcript, because that is the only
  output format that emits the invocation the query is about
- R1.2: WHEN a transcript carries a `Skill` tool-use event naming `epic:epic`
  THE SYSTEM SHALL report the query as triggered
- R1.3: WHEN a transcript completes without that event THE SYSTEM SHALL report
  the query as not triggered, and SHALL treat the completion itself as evidence
  by requiring the terminal `result` event with `is_error: false`
- R1.4: WHERE a transcript carries no terminal `result` event, or carries one
  reporting an error, THE SYSTEM SHALL report the run as an error distinct from
  both outcomes, and SHALL NOT score it as a pass or a failure
- R1.5: THE SYSTEM SHALL express the detector as a single artefact that reads a
  transcript and emits one of three verdicts, so that one implementation answers
  every caller and can be exercised without spending a model call

### R2. The suite runs what it reports, against the copy it names

- R2.1: WHEN the suite invokes the CLI THE SYSTEM SHALL detach that invocation
  from the enclosing loop's standard input, so that every query in the file is
  measured
- R2.2: WHEN the suite finishes THE SYSTEM SHALL report how many cases and how
  many trigger runs it executed, so that a failure count can be read against its
  denominator
- R2.3: WHERE a plugin whose name collides with the working tree's is enabled
  THE SYSTEM SHALL refuse to run and SHALL name the command that resolves the
  collision, because `--plugin-dir` does not outrank an enabled plugin and a run
  in that state grades the wrong copy
- R2.4: THE SYSTEM SHALL authenticate through the host's ordinary session, and
  SHALL grant the `Skill` tool, so that an invocation the query is written to
  measure is neither refused for credentials nor denied for permission
- R2.5: WHERE a caller names a subset of queries and a run count THE SYSTEM
  SHALL measure only that subset, that many times, and SHALL report each query's
  trigger rate over its runs, because a probabilistic assertion is qualified by
  a rate and not by a single verdict

### R3. A routing mode is reachable only if the description announces it

- R3.1: WHEN a routing mode is present in the skill's cascade THE SYSTEM SHALL
  name that mode's vocabulary in the skill `description`, so that the skill is
  offered for the phrasings the mode introduced
- R3.2: THE SYSTEM SHALL state at least one affirmative example for each mode
  the trigger set exercises, rather than naming a term only inside a negation
- R3.3: WHEN the cascade and the description disagree about which modes exist
  THE SYSTEM SHALL fail a check that names the unannounced mode, so that the
  divergence is reported by the suite rather than discovered by a user
- R3.4: WHEN the description is rewritten THE SYSTEM SHALL report each affected
  query's trigger rate before and after the edit, over a stated number of runs

### R4. A deferral that has been fulfilled can be closed as fulfilled

- R4.1: WHEN the work owed by a `[~] (deferred: …)` box is done THE SYSTEM SHALL
  close that box as `[x]` through the same script that writes every other
  checkbox
- R4.2: WHEN such a box is closed THE SYSTEM SHALL retain the original
  deferral reason alongside the evidence that discharged it, because `.epic/` is
  untracked in this project and a reason dropped from the line is destroyed
- R4.3: WHERE a box carries a terminal qualifier (`waived:`, `n-a:`,
  `superseded-by:`) or is already `[x]` THE SYSTEM SHALL refuse, because those
  states record a decision rather than an outstanding debt
- R4.4: WHEN such a close leaves no `[ ]` and no deferred `[~]` in the story THE
  SYSTEM SHALL write `status: done` in the same invocation, by the census the
  status transition table already defines

## Unchanged Behavior (Regression Prevention)

WHEN the trigger suite runs against an unmodified description THEN the system
SHALL CONTINUE TO report as triggering every query that triggers today — the 22
of 27 that passed the first honest run, measured again before the description
is touched.

WHEN `close-subtask.sh` is called on a `[ ]` box, a group header with open
children, an archived story, a duplicate box id, or with a malformed `--tilde`
argument THEN the system SHALL CONTINUE TO refuse exactly as it does today, with
the same exit codes and the same JSON-on-stdout contract.

WHEN any existing test in `tests/` runs THEN the system SHALL CONTINUE TO pass:
569 cases are green at `5e8406b`, and no existing case may be renamed or removed
to accommodate this work.

WHEN a story artefact is validated THEN the system SHALL CONTINUE TO produce the
same errors and warnings for every story that exists today — the checkbox
grammar gains a way to close a deferral, not a new box state.

WHEN the skill is invoked with any phrasing the description already covers THEN
the system SHALL CONTINUE TO route to the same mode, because the description
gains vocabulary rather than losing any.

## Success Metrics

- The detector answers correctly on five versioned transcripts, including one
  where the skill id is mutated — the red that proves the assertion can fail
- `stories create --batch <doc>` and `can you create an epic for X` rise from
  0/3 to a stated rate over 5 runs, reported before and after
- The full trigger suite is measured once before and once after the description
  edit, and no query that passed before fails after
- Stories 013 and 015 reach `status: done` through `close-subtask.sh`, with
  every previously deferred box reading its original reason and its discharge
- `bats tests/` green, `shellcheck` clean on every script touched

## Constraints

- `close-subtask.sh` remains the only writer of the checkbox grammar (story
  010). The new operation is a path through that script, never a second writer
- Exit-code semantics of both scripts are contract: `2` means the command line
  is malformed, `1` means the world must change. A refusal emits its JSON; a
  usage error emits none
- `--bare` may not return. Its hermeticity is already supplied by
  `--plugin-dir`, and its auth model excludes every subscription host
- The four checkbox qualifiers stay four. This story adds a transition between
  states, not a fifth state
- No test may be weakened to accommodate a change; a test that must change is
  re-proven red first
- Trigger measurements are probabilistic: any claim about a query's behaviour
  carries the number of runs it rests on

## Out of Scope

- Converting the suite to `claude plugin eval` case files. The runner answers
  `plugin eval is currently in early access` and exits 1 on this host; writing
  cases that cannot be executed is the defect this story exists to close, one
  level up. Revisit when the gate lifts — `--ablation` and `--runs` would then
  replace much of R1 and R2
- The three trigger queries that fire intermittently (1/3 and 2/3). They are
  measured and recorded, not tuned: distinguishing a weak description from
  ordinary sampling variance needs a run budget this story does not spend
- Any change to `evals/evals.json` case content. `run_case` is repaired and
  exercised, but the cases themselves are left as they are
- Retroactive repair of stories 013 and 015 beyond closing their boxes. What
  those stories shipped stays shipped; this story gives their deferrals a way to
  close honestly
