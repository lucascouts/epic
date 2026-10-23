---
story: story-state-machine-checkbox-grammar
type: feature
scale: full
version: 2
created: 2026-08-02
last-refined: 2026-08-04
status: archived
history:
  - v1: Initial plan
  - v2: Task 6 added — the second validate-mode pass's findings, and the reopen transition R1.7/R1.8 introduce
---

# Implementation Plan - Story State Machine & Checkbox Grammar

## Overview

Four groups in a load-bearing order: first the parsers learn the new grammar (validate-story, then the other three checkbox consumers with a cross-regression harness), then the human-facing references define the semantics, and only then the engine starts writing states — `hook-task-completed.sh` blocks with exit 2, so a validator that doesn't yet accept `[~]`/`status:` would reject the engine's own writes. Legacy byte-compatibility is pinned by fixture before any engine path changes.

## Task List

- [x] 1 - Grammar and status validation in validate-story.sh
  - _Complexity: Moderate | Tests: Unit (grammar + status suites) | Risks: regression on the 46-test suite just landed in e890d02 | Dependencies: None_
  - Objective: validate-story.sh accepts and validates the `[~]` grammar and the `status:` enum with full legacy tolerance.

  - [x] 1.1 - `[~]` counting and qualifier validation
    - Context:
      - Files: `scripts/validate-story.sh` (regexes at :129, :137, :169, :177 — post-e890d02 state)
    - Objective: `[~]` boxes are counted (closed when terminal, deferred when `deferred:`) and an unqualified `[~]` is an error.
    - ToDo:
      - Extend the box-counting regexes from `\[[ x]\]` to `\[[ x~]\]` where totals are computed; add separate counts: `closed = [x] + terminal [~]`, `deferred = [~] deferred:`.
      - Validate every `[~]` line carries a same-line qualifier matching `(deferred:|waived:|n-a:|superseded-by:)`; on miss, add_error listing the four valid forms and the offending line number.
      - GOTCHA (bash 5.3 + set -u): use plain integer counters incremented in the parse loop — never `${#assoc[@]}` on a possibly-empty associative array (the `REQ_KEYS` pattern from cross-reference.sh:98).
      - Handle read/grep failures with the existing `|| true` + `${VAR:-0}` convention — no new set -e escapes.
    - Tests: Unit · `tests/validate-story-grammar.bats` — the 4 qualifier forms accepted as closed, unqualified/unknown `[~]` errors listing valid forms, `[~]`-only tasks.md parseable, legacy fixture passes
    - Validation: bats suite for 1.1 green; legacy fixture (no `[~]`) produces byte-identical JSON vs pre-change
    - Requirements: R3.1, R3.2, R3.5

  - [x] 1.2 - `status:` enum and consistency checks
    - Context:
      - Files: `scripts/validate-story.sh` (frontmatter parsing at :194-211)
    - Objective: invalid enum values error; absence is silent; lying/diverging status warns.
    - ToDo:
      - Parse `status:` from each artifact's frontmatter with the existing sed/grep pattern; value outside `draft|in-progress|done|validated|superseded|archived` → add_error naming value and enum.
      - Absent field → no error, no warning, no info line (340+ legacy stories; R2.2 is a hard contract).
      - `status: done|validated` while any `[ ]` remains → add_warning "status ahead of checkboxes"; differing values across the story's artifacts → add_warning naming the files.
      - All new messages go through `json_escape()`.
    - Tests: Unit · `tests/validate-story-status.bats` — enum matrix (6 valid + invalid error naming value+enum), absent status silent, ahead-of-checkboxes warning, divergent-artifacts warning
    - Validation: bats matrix (each enum value, `medium`-style invalid, absent, ahead-of-checkboxes, divergent artifacts) green
    - Requirements: R2.1, R2.2, R2.3, R2.4

  - [x] 1.3 - Commit
    - Validation: full bats suite green (all pre-existing 46 + new 1.x tests); shellcheck -S warning clean
    - Commit: "feat(004): validate [~] checkbox grammar and status enum in validate-story"

- [x] 2 - Grammar in the other three checkbox consumers + cross-regression harness
  - _Complexity: Moderate | Tests: Unit + Integration (cross-regression harness) | Risks: the quadruplication — one missed regex reopens the false-clean class | Dependencies: Task 1_
  - Objective: cross-reference, hook-task-completed and monitor-stale agree with validate-story on every count, pinned by a shared fixture.

  - [x] 2.1 - cross-reference.sh accepts `[~]` sub-task headings
    - Context:
      - Files: `scripts/cross-reference.sh` (`task_heading_re` at :101, REQ_KEYS parse loop)
    - Objective: a `[~]` sub-task keeps attributing its `Requirements:` line in the mapping.
    - ToDo:
      - Extend `task_heading_re` to `\[[ x~]\]`; PARSEABLE_TASKS counts `[~]` headings too.
      - No change to orphan/phantom semantics — a deferred sub-task still traces its R-numbers (R4.2).
    - Tests: Unit · `tests/cross-reference-grammar.bats` — `[~]` heading keeps attributing its Requirements in mapping, parseable_tasks counts `[~]`, legacy unchanged
    - Validation: fixture with `- [~] 1.2 (deferred: hw)` + `Requirements: R1.2` maps R1.2 → ["1.2"], status clean
    - Requirements: R4.2

  - [x] 2.2 - hook-task-completed.sh and monitor-stale.sh regex update
    - Context:
      - Files: `scripts/hook-task-completed.sh` (:35 phase-3 detection), `scripts/monitor-stale.sh` (:45 pending regex)
    - Objective: hook recognizes stories whose tasks use `[~]`; staleness counts only `[ ]` as pending.
    - ToDo:
      - hook-task-completed: phase-3 detection regex includes `~` so a story with `[~]` boxes still gets validated on TaskCompleted.
      - monitor-stale: pending remains `\[ \]` ONLY — assert explicitly in a comment that `[~]` is not pending (R4.3); no other behavior change.
    - Tests: Integration · `tests/hook-monitor-grammar.bats` — hook blocks (exit 2) a failing `[~]`-marked story, stale iff `[ ]` present (R4.3 pins)
    - Validation: hook exit codes unchanged on legacy fixture; monitor-stale ignores a story whose only open boxes are `[~]`
    - Requirements: R4.3

  - [x] 2.3 - Cross-regression harness (shared fixture, four consumers)
    - Context:
      - Files: `tests/cross-reference.bats`, `tests/validate-story.bats`, `tests/hook-task-completed.bats` (patterns from e890d02)
    - Objective: one mixed fixture (`[x]`/`[ ]`/`[~]` terminal/deferred) asserted mutually consistent across the four scripts — the atomicity guard as a permanent test.
    - ToDo:
      - New `tests/checkbox-grammar.bats`: build the fixture once in setup, run all four scripts, assert each reports the same open/closed/deferred totals (parse their outputs; monitor-stale via its `find_stale` behavior).
      - Include the legacy fixture asserting byte-identical validate-story and cross-reference JSON vs recorded golden output (R5.1).
    - Tests: Integration · `tests/checkbox-grammar.bats` — one mixed fixture through all four consumers asserting agreement; R5.1 byte-identical legacy goldens
    - Validation: `bats tests/checkbox-grammar.bats` green; intentionally breaking one regex makes it fail (verified once manually, reverted)
    - Requirements: R4.1, R5.1

  - [x] 2.4 - Commit
    - Validation: full bats suite green; shellcheck clean on the three scripts
    - Commit: "feat(004): [~] grammar across all checkbox consumers with cross-regression harness"

- [x] 3 - Semantics in references and LIST rendering
  - _Complexity: Simple | Tests: None (doc contract; covered at script level by 1.x/2.x) | Risks: contract text drifting from parser behavior | Dependencies: Task 2_
  - Objective: the human-facing contract (grammar table, completion definition, progress rendering) matches what the parsers now do.

  - [x] 3.1 - Grammar and completion contract in references + SKILL
    - Context:
      - Files: `references/tasks.md` (checkbox rules §Structure/§Rules), `skills/epic/SKILL.md` (frontmatter spec :455-482, completion definition), `references/run-mode.md` (:112 marking step), `references/validate-mode.md` (:77 completion def)
    - Objective: one written definition — complete = no `[ ]`; done = all `[x]`/terminal `[~]`; done-except-external = only-deferred remaining — plus the `[~]` qualifier table and the `status:` field spec.
    - ToDo:
      - Add the `[~]` qualifier table (4 forms, terminal column) to references/tasks.md; update the checkbox rule (`- [ ]`/`- [x]`/`- [~]`).
      - Add `status:` to the frontmatter spec in SKILL.md (enum, engine-written note, same-value-across-artifacts rule), plus the optional companion `superseded-by: MMM` (written only by the supersede operation — story 006; consumed by the index — story 005).
      - Update the completion wording in run-mode.md and validate-mode.md to the single definition above.
    - Tests: None — markdown contract text; the documented grammar/completion behavior is executably covered by 1.1 and 2.3
    - Validation: grep confirms no remaining "all checkboxes [x]"-style stale definition in references/ or SKILL.md
    - Requirements: R3.1, R3.3

  - [x] 3.2 - LIST progress and computed conditions
    - Context:
      - Files: `references/list-mode.md` (:9 progress, :74 archive gate)
    - Objective: LIST renders closed/total (+D deferred), the persisted status column, and computed annotations.
    - ToDo:
      - Progress formula = closed/total with deferred count suffix when >0; status column shows the frontmatter value ("—" when absent — legacy stays quiet).
      - Computed annotations: `done-except-external (N deferred)` when only-deferred remain (a `blocked` annotation is out of scope for this story).
      - Archive-gate wording (:74) updated to the new completion definition (forward-consistency with story 005).
    - Tests: None — rendering instructions. ~~Counting semantics covered at script level by 1.1 and 2.3's only-deferred scenario~~ — **corrected by 5.4**: 2.3 had no only-deferred scenario when this was written. It does now (`tests/checkbox-grammar.bats`), and `done-except-external` stays a doc-level condition computed by LIST/validate-mode, not a script output.
    - Validation: rendering example in list-mode.md matches a fixture story processed by the scripts — **corrected by 5.4**: no script emits `done-except-external` or `Gates: C/T`, so only the underlying census was ever machine-checkable. The census the example rests on is now asserted directly.
    - Requirements: R3.4, R3.5

  - [x] 3.3 - Commit
    - Validation: validate-story.sh passes on both stories 004-007 themselves (dogfood check)
    - Commit: "docs(004): [~] grammar, status field and completion semantics in references"

- [x] 4 - Engine-written status transitions
  - _Complexity: Moderate | Tests: None (orchestrator instructions; receiving side covered by 1.2) | Risks: hook loops; legacy stories mid-run | Dependencies: Task 1, Task 2 (parsers must accept what the engine writes)_
  - Objective: CREATE/RUN/VALIDATE write the four transitions they own, via Edit, tolerantly on legacy stories.

  - [x] 4.1 - CREATE writes `status: draft`
    - Context:
      - Files: `skills/epic/SKILL.md` (Output Rules frontmatter block :455-467)
    - Objective: new stories are born with `status: draft` in every artifact.
    - ToDo:
      - Add `status: draft` to the creation frontmatter template; note it applies to new stories only (no retro-writes).
    - Tests: None — frontmatter template edit; `status: draft` acceptance covered by 1.2's enum matrix
    - Validation: frontmatter template in SKILL.md includes status; validate-story accepts it
    - Requirements: R1.1

  - [x] 4.2 - RUN transitions (`in-progress`, `done`) with legacy add-on-touch
    - Context:
      - Files: `references/run-mode.md` (sub-task marking step :112, session end)
    - Objective: run-mode instructs the orchestrator to update status at first marking and at completion.
    - ToDo:
      - After marking a sub-task: if story status is absent or `draft` → set `in-progress`; if the marking leaves no `[ ]` and no deferred `[~]` → set `done`.
      - GOTCHA: write via `Edit` on the frontmatter line — the PostToolUse validate hook matches `Write` only (hooks/hooks.json:5); `Write` would re-trigger validation on every transition.
      - Legacy story (no `status:` field): Edit ADDS the field with the observed state; never write states the run did not observe (R1.6).
      - Same value written to every artifact of the story that has frontmatter (R1.5) — story.md/design.md/tasks.md when present.
    - Tests: None — orchestrator instructions (Edit-based transitions); every value written validates clean via 1.2
    - Validation: dry-run walkthrough in run-mode.md example shows both transitions; validate-story emits no warning after each write
    - Requirements: R1.2, R1.3, R1.5, R1.6

  - [x] 4.3 - VALIDATE transition (`validated`)
    - Context:
      - Files: `references/validate-mode.md` (final steps :77-81)
    - Objective: a passing validation persists `validated`.
    - ToDo:
      - On Validator+Auditor pass: set `status: validated` (same Edit mechanism, all artifacts); on fail, leave status untouched.
      - Ordering contract at the validate pass point: 006's integration warning runs first, THEN this status write, THEN 005's archive offer — which is why the offer's condition is `done|validated`.
    - Tests: None — orchestrator instructions; `validated` acceptance and no-false-ahead-warning covered by 1.2
    - Validation: validate-mode.md procedure includes the write; ahead-of-checkboxes warning logic (1.2) does not fire after a legitimate pass
    - Requirements: R1.4

  - [x] 4.4 - Commit
    - Validation: full bats suite green; stories 004-007 re-validated clean
    - Commit: "feat(004): engine-written status transitions in create/run/validate"

- [x] 5 - Remediation of the validate-mode findings (2026-08-04)
  - _Complexity: Simple | Tests: Unit (hook-precompact census) | Risks: none — additive coverage plus contract corrections | Dependencies: Task 4_
  - Objective: close the coverage and criterion-fidelity gaps the Validator + Auditor pass surfaced. The mechanism is sound; what is missing is pinning and honest bookkeeping.

  - [x] 5.1 - CI runs the whole `tests/` directory (G1)
    - Context:
      - Files: `.github/workflows/shell.yml` (:33)
    - Objective: every suite in `tests/` runs in the only automated runner, including the cross-regression harness.
    - ToDo:
      - Replace the hand-maintained three-file list with `bats tests/`, with a comment stating why an enumerated list is the wrong shape here.
    - Tests: None — CI configuration; the suites it runs are themselves the tests
    - Validation: every suite in `tests/` executes in the `bats` job, verified locally with `act -j bats` — **corrected by 6.7**: this line read "the 9 suites (70 tests)"; at 5.8 the real figures were 10 and 79, and Task 6 took the tests to 84. The count is not the invariant and never was — "no suite is left out" is, which is why the fix was `bats tests/` and not a longer list
    - Requirements: R4.1
    - _Applied during the validate-mode pass of 2026-08-04, outside the Executor protocol — a one-line config fix to a failing quality gate._

  - [x] 5.2 - One definition for dependency satisfaction (G5)
    - Context:
      - Files: `references/tasks.md` (new `### Dependency Satisfaction`), `references/run-mode.md` (:13, Parallel Execution intro, Detection step 2, step 4 prompt)
    - Objective: kill the contradiction between "all dependencies are **complete**" and "a `deferred:` dep is **not** satisfied" — two readings of the same field four lines apart.
    - ToDo:
      - Define **satisfied** once in `references/tasks.md`, alongside Completion: every box `[x]` or terminal `[~]`; a `[~] (deferred: …)` dependency is not satisfied.
      - State that this is the ONLY place terminal and deferred `[~]` diverge, and name the intended asymmetry (a `done-except-external` story has nothing pending, yet a task depending on a deferred box still waits).
      - Point all four `run-mode.md` sites at that definition instead of restating it.
    - Tests: None — contract text; no script reads `Dependencies`
    - Validation: no remaining use of "complete"/"uncompleted" for dependency state in `run-mode.md`
    - Requirements: R3.3
    - _Applied during the validate-mode pass of 2026-08-04, outside the Executor protocol._

  - [x] 5.3 - `hook-precompact.sh` coverage and the corrected consumer count (G2)
    - Context:
      - Files: `scripts/hook-precompact.sh` (:61-74), `.epic/stories/004-story-state-machine-checkbox-grammar/design.md` (:78)
    - Objective: the one script that actually *renders* R3.5 progress stops being the one with no regression pin.
    - ToDo:
      - New `tests/hook-precompact-grammar.bats`: mixed fixture → `3/5 completed (+1 deferred)`; no-deferred fixture → no `(+N deferred)` suffix; legacy fixture → byte-identical to pre-change output; a line carrying both `deferred:` and a terminal qualifier counts as deferred.
      - Add the script to the cross-regression harness in `tests/checkbox-grammar.bats` so the consumers agree five ways, not four.
      - Correct `design.md:78` — "6 regex places across 4 scripts" is factually wrong; it is 7 across 5.
      - Consider replacing the `grep | grep -cv` precedence pipeline (:63-64) with the census-loop form used in `validate-story.sh:163-166` — today it is a second independent implementation of the same rule, which is the drift class this story exists to close.
    - Tests: Unit · `tests/hook-precompact-grammar.bats` — census matrix; harness extended to five consumers
    - Validation: full bats suite green; reverting `hook-precompact.sh`'s `[ x~]` class makes the new suite fail
    - Requirements: R3.5, R4.1

  - [x] 5.4 - Executable coverage for the completion conditions (G3)
    - Context:
      - Files: `tests/checkbox-grammar.bats`, `.epic/stories/004-story-state-machine-checkbox-grammar/tasks.md` (:117-118 — the false coverage claims)
    - Objective: R3.3 (`complete`) and R3.4 (`done-except-external`) stop being doc-only assertions.
    - ToDo:
      - Add an **only-deferred** scenario to the harness: a fixture with zero `[ ]`, ≥1 `[~] (deferred: …)` — assert the census yields the `done-except-external` triple, that monitor-stale does not flag it, and that `status: validated` on it raises no ahead-of-checkboxes warning.
      - `grep -rn "done-except-external" scripts/` currently returns nothing: decide explicitly whether the condition stays doc-only (LIST/validate-mode compute it inline) or gets a script helper — and write the decision down either way.
      - Correct the two false validation claims in task 3.2: "covered at script level by 2.3's only-deferred scenario" describes a scenario that did not exist.
    - Tests: Unit · extends `tests/checkbox-grammar.bats` with the only-deferred fixture
    - Validation: the new scenario fails if the terminal/deferred split is collapsed
    - Requirements: R3.3, R3.4

  - [x] 5.5 - Register the unrecorded criterion deviations and the reopen gap (G4, G7)
    - Context:
      - Files: `.epic/stories/004-story-state-machine-checkbox-grammar/.draft/deviations.yaml`, `references/validate-mode.md` (:95-96), `references/run-mode.md` (Status Transitions rules 2 and 3)
    - Objective: every place the implementation narrowed or extended an acceptance criterion is in the register, not only in prose.
    - ToDo:
      - **U1** — `validate-mode.md:95-96` adds a "no `[ ]` remains" precondition to R1.4, which the criterion does not carry. Well-argued in-line (writing `validated` with an open box would trip R2.3), but it is a criterion narrowing.
      - **U2** — `run-mode.md` rule 4 lets a first marking that also completes the story write `done` directly, so R1.2's `in-progress` is skipped.
      - **U3** — `run-mode.md` allows `validated → done`, an edge `design.md`'s state diagram does not draw.
      - **G7 (new, found by dogfooding this very remediation)** — the transition table fires **only after a marking**. *Adding* open boxes to a `done` story is not a marking, so no rule covers **reopening**: rule 2 requires `absent or draft`, rule 3 says write nothing, and the story would keep `status: done` with `[ ]` open — exactly the R2.3 lie the field exists to expose. Closing this needs a real `done → in-progress` edge, which means amending the criteria (Refine on this story) or a follow-up story. **Do not invent the rule silently.**
      - Either record each as a deviation, or amend R1.2/R1.4 — decide per item rather than in bulk.
    - Tests: None — register and contract bookkeeping
    - Validation: every criterion-narrowing decision in `run-mode.md`/`validate-mode.md` traces to a register entry or an amended criterion
    - Requirements: R1.2, R1.4

  - [x] 5.6 - Write down the R4.1 ↔ R5.1 resolution (G6)
    - Context:
      - Files: `.epic/stories/004-story-state-machine-checkbox-grammar/design.md` (§3), `tests/checkbox-grammar.bats`
    - Objective: the tension between "the four tools **report** consistent totals" (R4.1) and "legacy output byte-identical" (R5.1) is resolved on paper, not just in practice.
    - ToDo:
      - Record that `validate-story.sh` deliberately emits no count key — adding one would break R5.1 — so the harness asserts *agreement on which boxes exist*, not the equal open/closed/deferred triples task 2.3 literally specified.
      - Note that the hook and monitor expose only exit codes, so their "agreement" is structural by construction.
    - Tests: None — design rationale
    - Validation: a reader of R4.1 can tell what the harness does and does not prove
    - Requirements: R4.1, R5.1

  - [x] 5.7 - Align `agents/validator.md` with `validate-mode.md`
    - Context:
      - Files: `agents/validator.md` (:20), `references/validate-mode.md` (:21-33)
    - Objective: the persona file stops being one grammar revision behind the prompt that drives it.
    - ToDo:
      - `agents/validator.md:20` still reads "For each completed task and sub-task (marked `[x]`)", while `validate-mode.md` now passes a "Closed without work" list of `[~]` boxes and asks for a SKIP verdict naming the qualifier. Mirror that.
      - Sweep the other `agents/*.md` for the same drift — the file was missing from task 3.1's list, which is why it was missed.
    - Tests: None — agent instruction text
    - Validation: no `agents/*.md` describes checkbox states the current grammar does not have
    - Requirements: R3.1

  - [x] 5.8 - Commit
    - Validation: full bats suite green; `act -j bats` green; stories 003-007 validate clean
    - Commit: "fix(004): close the coverage and contract gaps found by validate-mode"

- [x] 6 - Remediation of the second validate-mode pass (2026-08-04)
  - _Complexity: Moderate | Tests: Unit (sixth consumer + census observability) | Risks: the reopen rule touches the one field the engine writes — a wrong rule here manufactures the very lie the field exists to expose | Dependencies: Task 5_
  - Objective: close the reopen gap with a real state-machine edge (R1.7, R1.8), pin the sixth checkbox consumer, and make the terminal/deferred split observable wherever the contract claims it is.

  - [x] 6.1 - The reopen transition (`done`/`validated` → `in-progress`)
    - Context:
      - Files: `references/run-mode.md` (Status Transitions table), `references/refine-mode.md` (procedure), `skills/epic/SKILL.md` (Lifecycle Status — the writers table and the "Refine does not write `status:`" line)
    - Objective: a story that gains an open `[ ]` after reaching `done` or `validated` returns to `in-progress`, written by whichever mode observed it.
    - ToDo:
      - Add the rule to run-mode.md's transition table: `status` is `done` or `validated` and a `[ ]` remains after the census → write `in-progress`. Order it so it cannot shadow rule 1 — a marking that re-completes the story still writes `done`.
      - Amend `skills/epic/SKILL.md`: REFINE becomes a writer for **this transition only** (R1.8) and for no other value. Today the file states the opposite outright, which is why this Refine deliberately left `status: done` standing rather than inventing the write.
      - Add the census step to `references/refine-mode.md`'s procedure, after the merged tasks.md is written.
      - GOTCHA: the `Edit`-not-`Write` mechanism is defined once in run-mode.md — link it, never restate it.
    - Tests: None — orchestrator instructions; the receiving side (`in-progress` accepted, warning cleared) is covered by 1.2
    - Validation: story 004 is its own fixture — it currently reads `status: done` with open `[ ]` boxes and `validate-story.sh` warns "ahead of checkboxes"; after this sub-task a census writes `in-progress` and the warning clears
    - Requirements: R1.7, R1.8

  - [x] 6.2 - SKILL.md's `done` row contradicts R1.3
    - Context:
      - Files: `skills/epic/SKILL.md` (Lifecycle Status writers table)
    - Objective: the field spec stops licensing `done` on a story that still owes deferred work.
    - ToDo:
      - The row reads "`done` | RUN — when the story is complete (no `[ ]` remains)". In this story's own vocabulary "complete" includes `done-except-external`, while R1.3 and run-mode.md rule 1 require no `[ ]` **and** no deferred `[~]`. Point at run-mode's rule instead of paraphrasing it.
      - Sweep SKILL.md and references/ for any other paraphrase of the completion condition that drops the deferred clause.
    - Tests: None — contract text
    - Validation: `references/tasks.md` is the only file that defines completion in its own words; every other site links to it
    - Requirements: R1.3

  - [x] 6.3 - The false "everywhere else" sentence
    - Context:
      - Files: `references/tasks.md` (`### Dependency Satisfaction`)
    - Objective: the section written to kill a contradiction stops carrying one.
    - ToDo:
      - It claims dependency satisfaction is "the **only** place where terminal and deferred `[~]` diverge. Everywhere else — completion, progress, staleness, the `closed` count — both are closed." Three of the four named are false: `closed` excludes deferred, progress renders it apart, and a deferred box blocks `done`.
      - Rewrite naming what genuinely treats them alike (staleness, and the bare "no `[ ]` remains" predicate) and what does not.
    - Tests: None — contract text
    - Validation: every claim in the rewritten sentence traces to the counting rules stated above it in the same file
    - Requirements: R3.3, R3.6

  - [x] 6.4 - The sixth checkbox consumer
    - Context:
      - Files: `scripts/hook-post-tool-failure.sh` (the mid-run guard), `tests/checkbox-grammar.bats`
    - Objective: the one checkbox consumer no enumeration ever caught joins the grammar and the harness.
    - ToDo:
      - The guard requires one `[x]` and one `[ ]`. A story mid-run whose closed boxes are all terminal `[~]` reads as not-mid-run, so the executor Step-4 reminder is silently suppressed on a Bash failure. Closed is `[x]` + terminal `[~]`, per the single definition.
      - Add the script to `tests/checkbox-grammar.bats` so the consumers agree six ways, not five.
    - Tests: Unit · extends `tests/checkbox-grammar.bats` — a mid-run story whose closed boxes are all `[~]` still triggers the reminder; legacy behavior unchanged
    - Validation: reverting the guard's grammar fails the new scenario
    - Requirements: R4.1

  - [x] 6.5 - The unobservable split and the second census implementation
    - Context:
      - Files: `scripts/validate-story.sh` (the census loop), `scripts/hook-precompact.sh` (`DONE_T` pipeline)
    - Objective: the terminal/deferred distinction is either observable or gone, and one rule has exactly one implementation.
    - ToDo:
      - `BOX_CLOSED` and `BOX_DEFERRED` are only ever consumed as a sum: swapping the terminal branch to `BOX_DEFERRED` leaves all 79 tests green. Decide explicitly — give the split an observable consumer, or collapse it to one counter and delete the comments claiming a distinction the code does not make. Write the decision down either way.
      - Replace the `grep | grep -cv` precedence pipeline in `hook-precompact.sh` with the census-loop form. It is a second independent implementation of the qualifier rule and the two already disagree: on `- [~]waived: …` (no space after the box) validate-story counts terminal-closed while hook-precompact counts neither.
      - Add that malformed shape to the harness so the disagreement cannot come back.
    - Tests: Unit · extends `tests/checkbox-grammar.bats` and `tests/hook-precompact-grammar.bats`
    - Validation: the mutation that survives today — terminal → deferred in validate-story's census — is killed, or the counter it mutates no longer exists
    - Requirements: R3.5, R4.1

  - [x] 6.6 - R3.6 behind the dependency rule
    - Context:
      - Files: `references/tasks.md` (`### Dependency Satisfaction`), `.draft/deviations.yaml` (the 3.1 entry)
    - Objective: the dependency rule stops being an unowned normative addition.
    - ToDo:
      - The rule was written during 3.1/5.2 with no acceptance criterion behind it — its own deviation entry closes with "it is a NEW rule, flagged for review". R3.6 now covers it: cite the criterion at the definition site and retire the flag, recording that the review happened and its outcome was a criterion.
    - Tests: None — contract text
    - Validation: cross-reference.sh maps R3.6 to this sub-task with no orphan
    - Requirements: R3.6

  - [x] 6.7 - Register bookkeeping
    - Context:
      - Files: `.draft/deviations.yaml`, `.draft/red-evidence.yaml`, this file (5.1's counts), `design.md`
    - Objective: no register entry describes a state the repository no longer has.
    - ToDo:
      - red-evidence: add entries for 5.3 and 5.4 recording honestly that both suites were written green-first as regression pins (`failed: false`, with the reason). `tests/hook-precompact-grammar.bats` already says so in its header; the contract is better served by an accurate record than by a missing one.
      - deviations: four entries are stale — the hook-precompact entry still says "NO dedicated test covers it" (5.3 added seven); the 3.1 entry cites `run-mode.md:432`, which 5.2 moved; the reopen entry says "5.5 owns closing it" (Task 6 does); discovery 1 says story 003 was "left untouched" (its `[~]` was qualified and 003 validates clean).
      - 5.1's Validation records "9 suites (70 tests)"; the real figures are 10 and 79.
    - Tests: None — register bookkeeping
    - Requirements: R4.1

  - [x] 6.8 - Commit
    - Validation: full bats suite green; `shellcheck -S warning` clean; stories 001-007 validate clean; story 004 reads `status: in-progress` with no ahead-of-checkboxes warning
    - Commit: "fix(004): close the reopen gap and the findings of the second validate pass"

## Quality Gates

Reopened at v2 — Task 6 added unimplemented criteria (R1.7, R1.8, R3.6), so the settlement
these gates recorded no longer held. Re-settled at the close of Task 6 (2026-08-04), each
with the evidence that settles it.

- [x] All acceptance criteria validated (R1.1–R5.1 traced by cross-reference.sh) — 22/22 traced, 0 orphans, 0 phantoms; R1.7/R1.8 implemented by 6.1, R3.6 by 6.3 and 6.6
- [x] All task validations pass — every sub-task's Validation command was executed and reported; stories 001-007 all validate 0 errors / 0 warnings
- [x] All tests written and passing (cross-regression harness included) — 84 tests across 10 suites, green locally and in the CI `bats` job mirrored with `act -j bats`; shellcheck clean at CI strictness
- [x] Code integrated (no orphaned implementations) — the sixth consumer joined the harness, and the terminal/deferred split lost its consumer-less copy: `validate-story.sh` no longer implements it, leaving the two that observably act on it — `hook-precompact.sh` renders it, `hook-post-tool-failure.sh` gates on it — both pinned by `tests/checkbox-grammar.bats`
- [x] Error handling implemented (legacy tolerance paths exercised) — R5.1 goldens still byte-identical, R2.2 (absent `status:`) still silent, and the new census guards a missing tasks.md before reading it
