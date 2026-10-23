---
story: fast-mode-test-first
type: feature
scale: full
version: 1
created: 2026-05-17
status: archived
---

# Implementation Plan - Fast-Mode Test-First Execution with Intent Anchor

## Overview

Update three reference documents to give Fast mode run-time test-first execution and the optional `Acceptance` field, then align four consistency surfaces (SKILL, example, README, ARCHITECTURE), then verify three verify-only surfaces, record the change in the changelog, and run a regression pass. Sequenced so the `Acceptance` field is defined first — the other surfaces reference it — then the plan-time and run-time flow, then the descriptive docs. This story edits markdown only; no executable logic is added, so no sub-task carries a test.

## Task List

- [x] 1 - Fast test-first: behavioral surfaces
  - _Complexity: Moderate | Tests: None | Risks: the Fast flow is described across three reference docs and must stay mutually consistent | Dependencies: None_
  - Objective: Add the run-time test-first flow and the `Acceptance` field to the three reference docs that define Fast-mode behavior

  - [x] 1.1 - Define the Acceptance field in references/tasks.md
    - _Complexity: Simple_
    - Context:
      - Files: `references/tasks.md` (Content Fields table, Tests Field section, Fast Scale Adaptations), `.epic/stories/002-fast-mode-test-first/design.md` (Data Models — the Acceptance field)
    - Objective: Document the optional Fast-only `Acceptance` field and the test-or-Acceptance contract rule
    - ToDo: In `references/tasks.md`, add an `Acceptance` row to the Content Fields table (when to include — Fast-mode sub-task without a test; description — 1-3 observable-behavior statements). Add an "Acceptance Field" subsection: optional, Fast-only, sub-task-level, never on a parent or Commit sub-task, EARS-lite plain statements. In the Fast Scale Adaptations section, state the contract rule — every implementing (non-Commit) Fast sub-task carries either a `Tests` field or an `Acceptance` field.
    - Validation: `references/tasks.md` Content Fields table has an `Acceptance` row; the Fast Scale Adaptations section states the test-or-Acceptance contract rule
    - Requirements: R3.1, R3.4, R3.5

  - [x] 1.2 - Extend Test Advisor Lite in references/phase-gates.md
    - _Complexity: Simple_
    - Context:
      - Files: `references/phase-gates.md` (Test Advisor Lite (Fast mode) section), `.epic/stories/002-fast-mode-test-first/design.md` (Components — phase-gates.md)
    - Objective: Make the Test Advisor Lite checklist require a contract per implementing sub-task and note authoring is run-time
    - ToDo: In `references/phase-gates.md`, in the "Test Advisor Lite (Fast mode)" section, add a 4th check: every implementing (non-Commit) sub-task must end with a `Tests` field or an `Acceptance` field — sub-tasks with no testable logic get an `Acceptance` field. Add a note that Fast, unlike Standard/Full Phase 3, does NOT author tests at plan time — the checklist decides whether a test is needed; test authoring and Red verification happen at run time (cross-reference `run-mode.md`).
    - Validation: `references/phase-gates.md` Test Advisor Lite section states the test-or-Acceptance contract rule and the plan-time vs run-time distinction
    - Requirements: R3, R3.2, R3.3

  - [x] 1.3 - Add run-time test-first ordering to references/run-mode.md
    - _Complexity: Moderate_
    - Context:
      - Files: `references/run-mode.md` (Procedure, Execution Threshold, Task Execution Flow, Executor Prompt Template), `agents/executor.md` (conditional step 5 — read only, MUST NOT be modified), `.epic/stories/002-fast-mode-test-first/design.md` (Architecture, Sequence Diagram, Error Handling)
    - Objective: Give Fast-mode sub-tasks run-time test-first ordering across both execution paths
    - ToDo: In `references/run-mode.md`: (1) in the Task Execution Flow, state that for a Fast-mode sub-task carrying a `Tests` field the test is authored, run, and confirmed failing (Red, for the right reason) before implementation — author then Green then Refactor; (2) in the "Trivial Complexity — Main Agent Inline" path, state the main agent authors the test, confirms Red, then implements and refactors inline (single-author); (3) for Simple+ Fast sub-tasks, state the orchestrator authors the test and confirms Red, then passes it to the Executor as the read-only "Pre-Authored Test" input, reusing the existing Executor protocol unchanged; (4) clarify the materialization step is Standard/Full only (`.draft/authored-tests/`) — Fast writes the authored test directly into the real test tree; (5) add the unexpected-green rule for Fast — revise once, then escalate to the user, never weaken assertions. Do NOT modify `agents/executor.md`.
    - Validation: `references/run-mode.md` describes run-time test-first ordering for Fast on both the inline and Executor paths, the Standard/Full-only materialization scope, and the one-attempt unexpected-green rule; `git diff --quiet agents/executor.md` succeeds
    - Requirements: R1, R1.1, R1.2, R1.3, R2, R2.1, R2.2, R2.3, R4, R4.1, R4.2, R4.3, R4.4, R4.5, R5, R5.1, R5.2, R5.3, R6, R6.1

  - [x] 1.4 - Commit
    - Validation: All 1.1–1.3 validations pass
    - Commit: "feat: add run-time test-first execution and the Acceptance field to Fast mode"

- [x] 2 - Consistency surfaces
  - _Complexity: Simple | Tests: None | Risks: a stale Fast-mode description left behind on a surface not in this list | Dependencies: Task 1_
  - Objective: Align the descriptive and example surfaces with Fast-mode test-first

  - [x] 2.1 - Update skills/epic/SKILL.md
    - Context:
      - Files: `skills/epic/SKILL.md` (Adaptive Modes table, Gotchas, Triage gotcha on Fast upgrade)
    - Objective: SKILL.md reflects Fast as test-first and keeps the Fast→Standard upgrade guidance explicit
    - ToDo: In `skills/epic/SKILL.md`, update the Gotchas list and any Fast-mode description so Fast is described as test-first with the `Acceptance` field; ensure the guidance to upgrade Fast→Standard when a change needs traceability or design docs is explicit.
    - Validation: `skills/epic/SKILL.md` describes Fast as test-first and retains explicit Fast→Standard upgrade guidance
    - Requirements: R6.2, R7, R7.1

  - [x] 2.2 - Update assets/examples/fast-feature.md
    - Context:
      - Files: `assets/examples/fast-feature.md` (current Fast example)
    - Objective: The Fast example shows a test-first sub-task and an `Acceptance` field
    - ToDo: In `assets/examples/fast-feature.md`, update the example `tasks.md` so at least one sub-task shows a `Tests` field (test-first) and at least one structural sub-task shows an `Acceptance` field with 1-3 observable-behavior bullets.
    - Validation: `assets/examples/fast-feature.md` contains both a `Tests` field and an `Acceptance` field example
    - Requirements: R7.1

  - [x] 2.3 - Update README.md
    - Context:
      - Files: `README.md` (Design Principles, mode descriptions, "test-first" prose)
    - Objective: README no longer presents test-first as Standard/Full only
    - ToDo: In `README.md`, update the mode descriptions and Design Principles so test-first is described as applying to Fast as well (run-time, single-author for Fast); mention the `Acceptance` field for Fast sub-tasks without a test.
    - Validation: `README.md` has no prose restricting test-first to Standard/Full; the `Acceptance` field is mentioned
    - Requirements: R7.1, R7.2

  - [x] 2.4 - Update ARCHITECTURE.md
    - Context:
      - Files: `ARCHITECTURE.md` (Validation layers, scale-adaptive section, Fast-mode references)
    - Objective: ARCHITECTURE reflects Fast-mode run-time test-first
    - ToDo: In `ARCHITECTURE.md`, update the scale-adaptive and Validation-layers sections to note Fast-mode run-time test-first ordering and the `Acceptance` field as the Fast intent anchor; note the Executor is reused unchanged.
    - Validation: `ARCHITECTURE.md` describes Fast-mode test-first and the `Acceptance` field, and states the Executor is reused unchanged
    - Requirements: R7.1, R7.2

  - [x] 2.5 - Commit
    - Validation: All 2.1–2.4 validations pass
    - Commit: "docs: align SKILL, example, README and ARCHITECTURE with Fast-mode test-first"

- [x] 3 - Verification, changelog and regression
  - _Complexity: Simple | Tests: None | Risks: a verify-only surface is actually stale and the change is missed | Dependencies: Task 1, Task 2_
  - Objective: Verify the remaining surfaces, record the change, and confirm no regression

  - [x] 3.1 - Verify the verify-only surfaces
    - Context:
      - Files: `PURPOSE.md`, `output-styles/epic.md`, `evals/evals.json`
    - Objective: Confirm the three verify-only surfaces are consistent; update only if stale
    - ToDo: Grep `PURPOSE.md`, `output-styles/epic.md`, and `evals/evals.json` for any description of Fast-mode test handling. If a surface describes the superseded Fast test-after behavior, update it to match the new behavior; if it does not mention Fast test handling, leave it unchanged and state that in the report.
    - Validation: none of `PURPOSE.md`, `output-styles/epic.md`, `evals/evals.json` describes Fast-mode test-after; the `fast-feature` eval case does not contradict the new behavior
    - Requirements: R7.1

  - [x] 3.2 - Add CHANGELOG entry
    - Context:
      - Files: `CHANGELOG.md` (Unreleased section)
    - Objective: Record the Fast-mode test-first capability
    - ToDo: In `CHANGELOG.md`, add an `[Unreleased]` entry under Added describing Fast-mode run-time test-first execution and the optional `Acceptance` field, noting Standard/Full are unchanged and `agents/executor.md` is reused unmodified.
    - Validation: `CHANGELOG.md` `[Unreleased]` section describes the Fast-mode test-first capability
    - Requirements: R7.1

  - [x] 3.3 - Regression and consistency check
    - Context:
      - Files: `tests/`, `scripts/`, `agents/executor.md`, `references/phase-gates.md`, `references/run-mode.md`, `references/tasks.md`, `skills/epic/SKILL.md`
    - Objective: Confirm no regression and that the Fast flow is described identically across surfaces
    - ToDo: Run `bats tests/` and `shellcheck scripts/*.sh` — both must pass. Run `validate-story.sh` and `cross-reference.sh` on this story. Confirm `git diff` shows no change under `scripts/` and no change to `agents/executor.md`. Confirm the Fast test-first flow is described consistently across `phase-gates.md`, `run-mode.md`, `references/tasks.md`, and `SKILL.md`.
    - Validation: `bats tests/` passes; `shellcheck scripts/*.sh` is clean; `git diff --quiet agents/executor.md scripts/` succeeds; the Fast flow descriptions are mutually consistent
    - Requirements: R7.1, R7.2

  - [x] 3.4 - Commit
    - Validation: All 3.1–3.3 validations pass
    - Commit: "docs: changelog and regression check for Fast-mode test-first"

## Quality Gates

- [x] All acceptance criteria (R1–R7) validated
- [x] All task validations pass
- [x] No documentation surface describes Fast-mode test-after for sub-tasks that need a test
- [x] `agents/executor.md` and `scripts/` have an empty diff for this story
- [x] The Fast test-first flow is described identically across `phase-gates.md`, `run-mode.md`, `references/tasks.md` and `SKILL.md`
- [x] `bats tests/` and `shellcheck` pass — no regression from the documentation changes. _Settled 2026-08-11 at `dec2003`, not at story time: `bats`/`shellcheck` were absent from PATH when this story ran and the gate was left open rather than ticked on the argument alone. Both are installed now, and both were executed:_

  ```
  $ shellcheck scripts/*.sh bin/*        → exit 0
  $ bats tests/                          → exit 0 · ok: 386 · not ok: 0
  ```

  _The run is a superset, not an isolation: it proves the tree is green today, six stories later, rather than attributing that green to this story alone. The attribution rests on the gate above — `agents/executor.md` and `scripts/` have an empty diff for this story — so there is no code path through which these documentation changes could have regressed either command._
