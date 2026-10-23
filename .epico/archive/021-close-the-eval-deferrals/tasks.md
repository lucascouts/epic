---
story: close-the-eval-deferrals
type: bugfix
scale: full
version: 1
created: 2026-08-29
status: archived
---

# Implementation Plan - Close the Eval Deferrals

## Overview

Five task groups in a forced order. The detector is built and proven against
recorded transcripts first, because everything downstream is a claim it has to
score. The harness is repaired around it, then used to capture the pre-edit
trigger roster — the baseline the description work is judged against, and the
one measurement that cannot be taken later. `--fulfill` is independent of both
and can proceed in parallel. The last group spends all three: it runs the evals
stories 013 and 015 deferred and closes their boxes with the operation that did
not exist when they were written.

## Task List

- [x] 1 - The detector, and the fixtures that prove it can fail
  - _Complexity: Simple | Tests: Unit | Risks: a fixture that cannot go red would rebuild the defect this story exists to close | Dependencies: none_
  - Objective: One artefact answers "did the skill fire", with a third answer for "the run did not happen", exercised without spending a model call.

  - [x] 1.1 - Record the transcript fixtures
    - _Complexity: Trivial_
    - Context:
      - Files: `tests/` (suite layout; there is no `tests/fixtures/` yet — this creates it)
    - Objective: Five `stream-json` transcripts on disk, so the detector is testable offline.
    - ToDo: create `tests/fixtures/trigger/`; record `fires.jsonl` (a query that invokes `epic:epic`), `no-fire.jsonl` (a query that does not), `truncated.jsonl` (no terminal `result` event), `errored.jsonl` (`result` with `is_error: true`), and `mutant.jsonl` (a copy of `fires.jsonl` with the skill id changed). Trim each to the events the detector reads — an untrimmed transcript is a 50-line blob nobody will diff. Head each file with a one-line comment naming what it is a fixture *for*.
    - Acceptance: five files exist; `fires.jsonl` contains a `tool_use` event named `Skill` whose `input.skill` is `epic:epic`; `truncated.jsonl` contains no `"type":"result"` line; `mutant.jsonl` differs from `fires.jsonl` in the skill id and nothing else
    - Validation: `command grep -c '"type":"result"' tests/fixtures/trigger/truncated.jsonl` answers 0; `diff <(jq -c 'del(.message.content[]?.input.skill)' fires.jsonl) <(jq -c 'del(.message.content[]?.input.skill)' mutant.jsonl)` is empty
    - Requirements: R1.5

  - [x] 1.2 - `scripts/trigger-detect.sh`
    - _Complexity: Simple_
    - Context:
      - Files: `scripts/next-story-number.sh` (the smallest JSON-on-stdout script — copy its shape), `scripts/close-subtask.sh` (exit-code convention: 2 = malformed call, 1 = the world), `tests/fixtures/trigger/` (from 1.1)
    - Objective: A transcript on stdin becomes one JSON verdict on stdout.
    - ToDo: read stdin; parse each line with `jq -R 'fromjson? // empty'` so a non-JSON line (stderr mixed in) is dropped rather than fatal; emit `{"verdict":"triggered|not-triggered|error","skill":"<id>","runs_completed":<bool>,"reason":"<why, on error>"}`. `triggered` requires a `tool_use` event named `Skill` whose `input.skill` matches the id, inside an `assistant` message. `triggered` and `not-triggered` BOTH require a terminal `{"type":"result","is_error":false}` event; without it, or with `is_error: true`, the verdict is `error` — the distinction the old detector could not make, and the reason a network failure used to score every negative query as a pass. Accept the skill id as `$1`, defaulting to `epic:epic`. `--help` on stderr, exit 2, matching `close-subtask.sh`.
    - Tests: Unit · `tests/trigger-detect.bats` — one case per fixture: `fires` → `triggered`; `no-fire` → `not-triggered`; `truncated` → `error`; `errored` → `error`; `mutant` → `not-triggered` (**the red that proves the assertion can fail** — same transcript, different id, opposite verdict); empty stdin → `error`; a transcript with stderr noise interleaved still scores
    - Validation: `bats tests/trigger-detect.bats` green; `printf '' | bash scripts/trigger-detect.sh | jq -r .verdict` answers `error`; `shellcheck scripts/trigger-detect.sh` clean
    - Requirements: R1.1, R1.2, R1.3, R1.4, R1.5

  - Commit: "fix(021): the trigger detector reads the invocation, and can say it measured nothing"

- [x] 2 - The harness runs what it reports, against the copy it names
  - _Complexity: Simple | Tests: Unit, Integration | Risks: the plugin guard could refuse a legitimate run; `run_case` has never executed under the new configuration | Dependencies: Task 1_
  - Objective: `run-evals.sh` is executable on a subscription host, measures every query, delegates scoring, and refuses to grade the wrong copy.

  - [x] 2.1 - Rebuild the invocation and delegate the verdict
    - _Complexity: Simple_
    - Context:
      - Files: `scripts/run-evals.sh` (the working tree already carries an unplanned repair of this — treat it as a draft to be re-derived under this plan, not as done work), `scripts/trigger-detect.sh` (from 1.2)
    - Objective: Every query is measured, and scored by the detector rather than by an inline grep.
    - ToDo: drop `--bare` from both call sites (its auth is strictly `ANTHROPIC_API_KEY`/`apiKeyHelper`, which no subscription host satisfies, and the hermeticity it sells is already supplied by `--plugin-dir`); add `Skill` to both `--allowedTools` lists (without it the skill is chosen and then denied, and the denial used to score as a trigger); redirect the CLI's stdin from `/dev/null` at both call sites (inherited stdin made the loop consume its own input and measure one query of 27); switch `run_trigger` to `--output-format stream-json --verbose` and pipe the transcript into `trigger-detect.sh`; map the three verdicts — `triggered`/`not-triggered` compare against expectation, `error` is reported as ERROR and counted apart from pass and fail. Give `run_trigger` a `git init`ed workdir, as `run_case` already has.
    - Tests: Unit · `tests/run-evals-contract.bats` — filter `^2.1:`: PIN that neither call site passes `--bare`; that both grant `Skill`; that both redirect stdin; that `run_trigger` requests `stream-json`; that the scoring path invokes `trigger-detect.sh` rather than matching a skill id inline (one scorer, not two)
    - Validation: `bats tests/run-evals-contract.bats` green; `command grep -c -- '--bare' scripts/run-evals.sh` answers 0; `shellcheck scripts/run-evals.sh` clean
    - Requirements: R2.1, R2.4

  - [x] 2.2 - Denominator, filter, run count, and per-query rate
    - _Complexity: Simple_
    - Context:
      - Files: `scripts/run-evals.sh`
    - Objective: A result can be read against how much was measured.
    - ToDo: count cases and trigger runs, and print `ran: N case(s), M trigger(s)` before the verdict — a failure count with no denominator reads identically whether the suite ran everything or stopped at the first query, which is exactly how the stdin defect stayed invisible. Accept `EVAL_FILTER` (substring) and `EVAL_RUNS` (integer ≥ 1, validated — a non-integer is a usage error, not a silent `seq` failure); report each query's rate over its runs (`query: 2/3`) rather than one line per failure. Use `if/then` for the filter rather than `[[ … ]] && continue`, which survives `set -e` only by the AND-list exception.
    - Tests: Unit · `tests/run-evals-contract.bats` — filter `^2.2:`: PIN that the summary line carries both counters; that `EVAL_RUNS=0` and `EVAL_RUNS=abc` exit 2 naming the variable; that a filter matching no query reports a zero denominator rather than "all passed"
    - Validation: `bats tests/run-evals-contract.bats` green; `EVAL_FILTER=__none__ bash scripts/run-evals.sh --triggers` prints `ran: 0 case(s), 0 trigger(s)`
    - Requirements: R2.2, R2.5

  - [x] 2.3 - Refuse to grade the wrong copy
    - _Complexity: Simple_
    - Context:
      - Files: `scripts/run-evals.sh`, `.claude-plugin/plugin.json` (the `name` field is the authority — do not hardcode `epic`)
    - Objective: A run that would measure the installed plugin stops instead, and says how to fix it.
    - ToDo: read the plugin name from the manifest; ask `claude plugin list`; when a plugin of that name is **enabled**, exit 2 naming `claude plugin disable <name>` and the reason — `--plugin-dir` does not outrank an enabled plugin of the same name, so the run would grade the cache. When the CLI's answer cannot be parsed, warn and proceed: an unverifiable state is not the same as a known-bad one, and refusing on it would make the suite hostage to an output format. Move the header prose about disabling from comment to code — a sentence cannot fail.
    - Tests: Unit · `tests/run-evals-contract.bats` — filter `^2.3:`: PIN with a stubbed `claude` on PATH that an enabled same-name plugin exits 2 and names the disable command; that a disabled one proceeds; that an unparseable listing warns and proceeds; that the name comes from the manifest (rename it in a fixture and the message follows)
    - Validation: `bats tests/run-evals-contract.bats` green; with the plugin enabled, `bash scripts/run-evals.sh --triggers` exits 2 without making a single model call
    - Requirements: R2.3

  - [x] 2.4 - Exercise `run_case` once
    - _Complexity: Trivial_
    - Context:
      - Files: `scripts/run-evals.sh` (`run_case`), `evals/evals.json` (6 cases)
    - Objective: `run_case` stops being "changed and never executed".
    - ToDo: run `bash scripts/run-evals.sh --cases` with the plugin disabled, and record the outcome verbatim in the report — including which of the 6 cases passed. Fix only what that run proves broken; do not tune the cases themselves (out of scope).
    - Acceptance: the 6 cases execute and each reports PASS or a named FAIL; no case dies on authentication or on a denied `Skill`; the summary reports `ran: 6 case(s)`
    - Validation: `bash scripts/run-evals.sh --cases` output pasted into the sub-task report, with its exit code
    - Requirements: R2.1, R2.4

  - Commit: "fix(021): the eval suite runs on a subscription host, and reports its denominator"

- [x] 3 - The description announces every mode the cascade routes
  - _Complexity: Moderate | Tests: Unit | Risks: a longer description may dilute triggering for phrasings that work today — the one Medium risk in the design, and it grew when Phase 3 measured six absent modes rather than two | Dependencies: Task 2_
  - Objective: `--batch` and `migrate` become reachable by the phrasings they introduced, without any query that fires today ceasing to fire.

  - [x] 3.1 - Capture the pre-edit roster
    - _Complexity: Trivial_
    - Context:
      - Files: `evals/trigger-queries.json` (27 queries), `scripts/run-evals.sh` (repaired by Task 2)
    - Objective: The baseline exists before the thing it measures is touched — it cannot be captured afterwards.
    - ToDo: with the plugin disabled, run the full trigger suite once and record the per-query verdict as a roster in the sub-task report. This is the comparison set for 3.4 and the evidence for Unchanged Behavior item 1. Take it BEFORE any edit to `SKILL.md`.
    - Acceptance: 27 queries measured, each with its verdict; the roster names which queries fire and which do not; `ran:` reports 27
    - Validation: the roster pasted into the sub-task report, with the run's exit code and denominator
    - Requirements: R3.4

  - [x] 3.2 - The lint, proven red against today's description
    - _Complexity: Simple_
    - Context:
      - Files: `skills/epic/SKILL.md` (the routing cascade block and the `description` field), `tests/consumer-roster.bats` (the declared-table-plus-scan shape this follows)
    - Objective: A mode present in the cascade and absent from the description turns a test red.
    - ToDo: `tests/skill-description-coverage.bats` holds a declared table of `cascade arm → required description term(s)`. It fails on **either** side of a divergence: a declared term missing from the `description`, or a cascade arm absent from the table. A table checking only the first half goes stale exactly as the description did. Prove it red on the description as it stands — it must name `batch` and `migrate` — before 3.3 changes anything.
    - Tests: Unit · `tests/skill-description-coverage.bats` — the suite IS the deliverable; its red against the current `SKILL.md` is its Red evidence, and a case with a fixture description missing a declared term is the mutant proving it can fail
    - Validation: `bats tests/skill-description-coverage.bats` FAILS against `SKILL.md` at HEAD, naming `batch` and `migrate`; output pasted into the report
    - Requirements: R3.3

  - [x] 3.3 - Rewrite the description
    - _Complexity: Simple_
    - Context:
      - Files: `skills/epic/SKILL.md` (`description`), `references/batch-create.md` and `references/migrate-mode.md` (the vocabulary each mode actually uses)
    - Objective: Every routed mode is named, and no term appears only inside a negation.
    - ToDo: add the vocabulary of the **six** modes the lint names — `init`, `migrate`, `batch`, `archive`, `supersede`, `teams` (measured in Phase 3 against `SKILL.md` at `5e8406b`, not the two the trigger evals could see); replace the lone negated occurrence of "epic" with at least one affirmative example ("create an epic for X"). Keep the addition as short as the coverage allows — length is the mechanism of the dilution risk, so every added clause must earn a mode. **Only `batch` and `migrate` have a trigger query to prove them**; for the other four the lint is the whole of the evidence, and that limit is stated in the report rather than left implied. Do not touch the cascade.
    - Tests: Unit · `tests/skill-description-coverage.bats` — the suite from 3.2 turns green; no new case, the same case flipping colour
    - Validation: `bats tests/skill-description-coverage.bats` green; `git diff --stat skills/epic/SKILL.md` touches the description only
    - Requirements: R3.1, R3.2
    - Dependencies: 3.2 (its red is this sub-task's Red evidence)

  - [x] 3.4 - Measure the change, both directions
    - _Complexity: Trivial_
    - Context:
      - Files: `evals/trigger-queries.json`, `scripts/run-evals.sh`
    - Objective: The gain is stated with its denominator, and the regression risk is checked rather than assumed.
    - ToDo: re-measure the two 0/3 queries with `EVAL_RUNS=5`, and the full suite once. Report the two rates against 3.1's roster, query by query. A query that fired in 3.1 and does not fire now BLOCKS the group — revise 3.3 or revert it; a dilution that trades two gains for one loss is not a fix.
    - Acceptance: both target queries report a rate over 5 runs, before and after; the full-suite roster is compared against 3.1 query by query; any regression is named rather than averaged away; the four modes with no trigger query are reported as covered by the lint alone, never counted as measured
    - Validation: both rates and the roster diff pasted into the report, with run counts
    - Requirements: R3.4

  - Commit: "fix(021): a routed mode is announced by the description, and a lint says so"

- [x] 4 - A deferral that was fulfilled can be closed as fulfilled
  - _Complexity: Moderate | Tests: Unit | Risks: writing a qualifier token onto a closed box would make seven readers score it as deferred | Dependencies: none_
  - Objective: `close-subtask.sh` gains the one transition out of `[~] (deferred: …)`, without becoming a way to erase a decision.

  - [x] 4.1 - `--fulfill` in the one writer
    - _Complexity: Moderate_
    - Context:
      - Files: `scripts/close-subtask.sh` (the `--tilde` parse arm, the stowaway guard at the qualifier check, the already-closed refusal, and the census/stamp path every close shares), `tests/lib/checkbox-consumers.sh` (the 11 declared readers of the grammar)
    - Objective: A `[~] (deferred: …)` box becomes `[x]` carrying both the debt and its discharge.
    - ToDo: add `--fulfill "<evidence>"`. It resolves and locates the box exactly as every other path does, then requires the located box to be `[~]` with a `deferred:` qualifier — a terminal qualifier or an `[x]` is a refusal naming the state found, because those record a decision rather than an outstanding debt. Rewrite the line as `- [x] N.N - <title> (fulfilled: <evidence>; original deferral — <reason>)`, carrying the original reason with its `deferred:` token removed. **The shape is forced by measurement, not by taste:** the canonical regex `(^|[^[:alnum:]_-])deferred:` — shared by all seven scripts that read the grammar in code — matches `(was deferred: …)`, so that spelling would have seven readers score a closed box as deferred and the story would never reach `done`. When the preserved reason itself carries a qualifier token, refuse and name it, as the stowaway guard already does for `--tilde` (measured: all five real reasons in 013 and 015 are clean, so this refuses none of them). Reuse the existing census and `status:` stamp untouched.
    - Tests: Unit · `tests/close-subtask-fulfill.bats` — fulfils a `deferred:` box and the line reads both halves; the rewritten line does NOT match the canonical qualifier regex (the assertion the whole shape exists for, and it goes red against the `was deferred:` spelling); refuses on `waived:`, on `n-a:`, on `superseded-by:`, and on `[x]`, each naming the state; refuses when the preserved reason carries a token; a gate box fulfils by `gate:<prefix>` as well as a sub-task by `N.N`; the census writes `done` when the fulfilled box was the last deferral; `--fulfill` with no argument is exit 2
    - Validation: `bats tests/close-subtask-fulfill.bats` green; `bats tests/close-subtask.bats tests/close-subtask-transaction.bats tests/close-subtask-roundtrip.bats` green and unedited; `shellcheck scripts/close-subtask.sh` clean
    - Requirements: R4.1, R4.2, R4.3, R4.4

  - [x] 4.2 - Say it where the grammar is defined
    - _Complexity: Trivial_
    - Context:
      - Files: `references/tasks.md` (Checkbox Grammar, Completion), `references/run-mode.md` (the close-call table), `ARCHITECTURE.md` (script inventory)
    - Objective: The one exit from a deferral is documented where a reader of the grammar will meet it.
    - ToDo: `tasks.md` gains the transition — a `[~] (deferred:)` is the only closed state that can be reopened into `[x]`, and only through `--fulfill`; state that a terminal qualifier cannot. `run-mode.md` gains a `fulfill` row beside `close` and `close-tilde`. `ARCHITECTURE.md` registers `scripts/trigger-detect.sh` and the new flag. Say the line shape once, in `tasks.md`, and have the others point at it.
    - Acceptance: the transition is stated in `references/tasks.md`; `run-mode.md`'s call table carries the row; `ARCHITECTURE.md` lists the new script; the line shape is defined in exactly one file
    - Validation: `command grep -c 'fulfill' references/tasks.md references/run-mode.md ARCHITECTURE.md` each ≥ 1; `bash scripts/validate-story.sh` on every story in `.epic/` reports the same JSON as before the change
    - Requirements: R4.1

  - Commit: "fix(021): a fulfilled deferral closes through the one writer, carrying its debt and its discharge"

- [x] 5 - Spend it: close what 013 and 015 deferred
  - _Complexity: Simple | Tests: Integration | Risks: the deferred evals may still fail, in which case the boxes stay open and this group reports that instead | Dependencies: Task 2, Task 3, Task 4_
  - Objective: The five deferred boxes are settled by measurement — closed if their evals pass, left open with a fresh reason if they do not.

  - [x] 5.1 - Run the deferred evals and settle the boxes
    - _Complexity: Simple_
    - Context:
      - Files: `.epic/stories/013-quick-create/tasks.md` (sub-task 3.2 and two gates), `.epic/stories/015-migrate-commit-field/tasks.md` (sub-task 4.1 and one gate), `scripts/close-subtask.sh` (`--fulfill`, from 4.1)
    - Objective: Each of the five boxes reaches the state its evidence supports.
    - ToDo: with the plugin disabled, run the trigger evals each deferral names. For every box whose eval passes, close it with `--fulfill` carrying the measurement as evidence. For any that still fails, leave it `[~]` and rewrite its reason to what is now true — the old reason cites `claude plugin eval` as the supported path, which is measurably wrong on this host (`early access`, exit 1). Report both sets. **Do not close a box whose eval did not pass**: this story exists because a gate was ticked against evidence that did not exist.
    - Tests: Integration · `tests/close-subtask-fulfill.bats` — filter `^5.1:`: PIN against a fixture copy of a real deferred story that the fulfilled box carries its evidence and its original reason, and that the story's `status:` reaches `done` only when no deferral remains
    - Validation: `bash scripts/validate-story.sh` on 013 and 015 reports no new error; `bash scripts/epic-index.sh` renders each story's progress and status; the eval output for each box pasted into the report
    - Requirements: R4.1, R4.2, R4.4

  - Commit: "fix(021): settle the deferrals of 013 and 015 against measurement"

## Quality Gates

- [x] All acceptance criteria validated (R1.1-R4.4 each behind a passing test, a recorded measurement, or grep-verifiable reference copy)
- [x] All task validations pass
- [x] All tests written and passing (full `bats tests/` green; case count = 569 baseline + the cases tasks 1, 2, 3 and 4 add; no existing case renamed or removed)
- [x] Every new assertion proven capable of failing — the detector against the mutant fixture, the description lint against today's `SKILL.md`, the `--fulfill` line shape against the `was deferred:` spelling; each red observed and reported, never argued
- [~] The description change is measured in both directions against a roster captured before the edit, and no query that fired in 3.1 fails in 3.4 (waived: the clause compares against the 2026-08-30 roster, and a same-day counterfactual measured the UNCHANGED old description (md5 0ef39c4c, that exact anchor) at 2/5 on the very query the clause fired for, against 3/3 for the same bytes thirteen days earlier. It fails identically for a tree carrying no edit, so it measures the calendar rather than the diff. The maintainer accepted the same-day comparator, under which the edit reads 1/5 against 2/5, p about 1.0. The gate's first half is satisfied; its second half is reported FAILED with its cause named, never ticked — see .draft/roster-after.md)
- [~] Code integrated (one scorer, not two: `run-evals.sh` matches no skill id inline; `close-subtask.sh` remains the only writer of the checkbox grammar) (waived: the first clause holds, pinned by run-evals-contract case 5 — run-evals.sh matches no skill id inline, so there is one scorer. The second clause has one documented exception. Sub-task 5.1 rewrote three deferral REASONS in story 013 by hand, because no script path exists to restate one — close-subtask.sh refuses an already-closed box, --tilde opens nothing, and --fulfill discharges a debt rather than restating it. No box STATE was written by hand. All three remain closed exactly as they were, each carrying exactly one qualifier token, and validate-story.sh reports 0 errors on 013. A restate path is the follow-up this exposes)
- [x] Error handling implemented (the third verdict distinguishes "did not fire" from "did not run"; the plugin guard refuses rather than measuring the wrong copy; `--fulfill` refuses on every state that is not an outstanding deferral)
