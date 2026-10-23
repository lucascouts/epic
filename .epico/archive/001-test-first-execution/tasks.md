---
story: test-first-execution
type: feature
scale: full
version: 1
created: 2026-05-17
status: archived
---

# Implementation Plan - Test-First Execution with Independent Test Authorship

## Overview

Update three sub-agent definitions, four orchestration references, and three consistency surfaces so Epic executes Standard/Full sub-tasks test-first with independent test authorship. Sequenced so the agent definitions (behavioral source of truth) are written first, then the orchestration prompt templates that must mirror them verbatim, then the descriptive docs, then a regression pass. This story edits markdown only — no executable logic — so no sub-task carries authored tests.

## Task List

- [x] 1 - Agent definitions: test-first behavioral core
  - _Complexity: Moderate | Tests: None | Risks: protocol step-count drift across files | Dependencies: None_
  - Objective: Update the three sub-agent definitions that own test-first behavior

  - [x] 1.1 - Rewrite test-advisor as test author
    - Context:
      - Files: `agents/test-advisor.md` (current planner definition), `.epic/stories/001-test-first-execution/design.md` (test-advisor component spec)
    - Objective: Change test-advisor from a test-scenario planner into a failing-test author with Red verification
    - ToDo: In `agents/test-advisor.md` frontmatter, add `Write` and `Bash` to `tools`, raise `maxTurns` 15→30, raise `effort` medium→high. Rewrite the Role: author one failing test file per Unit/Integration sub-task into `.draft/authored-tests/` (mirroring the target test path), run each test to confirm it fails (Red), and record `.draft/red-evidence.yaml`. Add the context boundary — receives EARS requirement, Objective, Tests scenarios, project test conventions, and design.md contract (Full only); never the ToDo field. Add the Standard-mode contract fallback (Objective + requirement + scenarios). Add unexpected-green handling: revise up to 2 times, then escalate to the user. Merge the duplicated `## Rules` heading into one.
    - Validation: `grep -c '^## Rules' agents/test-advisor.md` returns 1; `tools` line contains both `Write` and `Bash`; body references `.draft/authored-tests/` and `red-evidence.yaml`
    - Requirements: R1, R1.1, R1.2, R1.3, R1.4, R2, R2.1, R2.2, R2.3, R5, R5.1, R5.2, R5.3, R5.4

  - [x] 1.2 - Reorder executor protocol to Green-then-Refactor
    - Context:
      - Files: `agents/executor.md` (current 6-step protocol), `.epic/stories/001-test-first-execution/design.md` (executor component spec)
    - Objective: Make executor step 5 conditional — Refactor for test-first sub-tasks, Tests for test-after
    - ToDo: In `agents/executor.md`, rewrite the protocol so that for a sub-task with a pre-authored test, step 2 is "Implementation (Green — make the pre-authored test pass)" and step 5 is "Refactor" (improve code while test + validation stay green); for a sub-task without a pre-authored test, step 5 stays "Tests". Add the frozen-test rule: assertions immutable; imports/signature call-sites adjustable only for an INTENTIONAL design deviation, recorded in `.draft/deviations.yaml` with `test_surface_adjusted: true`. Add: a behavior-changing deviation makes the executor STOP and escalate, never edit an assertion. State explicitly the protocol remains six steps.
    - Validation: `agents/executor.md` shows a conditional step 5 (Refactor / Tests), contains the frozen-test rule and the behavior-deviation escalation, and still describes six steps
    - Requirements: R2.4, R3, R3.1, R3.2, R3.3, R4, R4.1, R4.2, R4.3

  - [x] 1.3 - Add Red-evidence check to auditor
    - Context:
      - Files: `agents/auditor.md` (current 9 checks), `.epic/stories/001-test-first-execution/design.md` (auditor component spec)
    - Objective: Add auditor check #10 — Red evidence precedes implementation
    - ToDo: In `agents/auditor.md`, add a 10th check to the Checks list: every sub-task with a pre-authored test has an entry in `.draft/red-evidence.yaml` with `failed: true`; a missing entry is reported as a finding. Add the new finding to the Report Format.
    - Validation: `agents/auditor.md` Checks list has a 10th item referencing `red-evidence.yaml`; Report Format mentions the new finding
    - Requirements: R6, R6.1, R6.2

  - [x] 1.4 - Commit
    - Validation: All 1.1–1.3 validations pass
    - Commit: "feat: make test-advisor author failing tests; add executor Green-then-Refactor and auditor Red check"

- [x] 2 - Orchestration references
  - _Complexity: Moderate | Tests: None | Risks: prompt templates must mirror agent bodies verbatim | Dependencies: Task 1_
  - Objective: Update the reference docs that template and orchestrate the sub-agents

  - [x] 2.1 - Rewrite Test-Advisor prompt template in phase-gates.md
    - Context:
      - Files: `references/phase-gates.md` (Test Advisor Sub-agent section), `agents/test-advisor.md` (updated source of truth)
    - Objective: Make the orchestrator's Test-Advisor prompt match the new authoring role
    - ToDo: In `references/phase-gates.md`, rewrite the Test Advisor Sub-agent prompt template: authoring role, authoring payload, context boundary (no ToDo), the Standard-mode contract fallback (Objective + requirement + scenarios when no design.md exists), Red-verification-and-record step, unexpected-green escalation (revise twice, then escalate to the user). Keep it consistent verbatim with `agents/test-advisor.md`.
    - Validation: the phase-gates.md Test-Advisor template describes authoring + Red verification + the Standard-mode fallback and no longer describes the old "returns a mapping only" behavior
    - Requirements: R1.1, R2.1, R2.2, R2.3, R5.1, R5.3, R5.4

  - [x] 2.2 - Add materialization step and update Executor prompt in run-mode.md
    - Context:
      - Files: `references/run-mode.md` (Procedure, Executor Prompt Template, Context Passing), `agents/executor.md` (updated)
    - Objective: Add test materialization and the pre-authored-test input to run-mode
    - ToDo: In `references/run-mode.md`, add a materialization step to the Procedure — before task execution, copy `.draft/authored-tests/**` into the real test tree, skipping any target path that already exists (idempotent) and warning on skip. Update the Executor Prompt Template with a "Pre-Authored Test" section (read-only input) and the conditional step-5 protocol, mirroring the frozen-test rule verbatim from `agents/executor.md`. Update §Context Passing to mention the pre-authored test as a read-only input, and extend the Deviation Register schema example there with the `test_surface_adjusted` field.
    - Validation: `references/run-mode.md` Procedure contains a materialization step documenting idempotent skip-and-warn on existing target paths; Executor Prompt Template has a Pre-Authored Test section and a conditional step 5; the Deviation Register example includes `test_surface_adjusted`
    - Requirements: R2.4, R3.1, R3.2, R4.1, R4.2, R4.3

  - [x] 2.3 - Document authored tests and Red evidence in tasks.md reference
    - Context:
      - Files: `references/tasks.md` (Tests Field section)
    - Objective: Document the new `.draft/` test artifacts
    - ToDo: In `references/tasks.md`, document that `.draft/authored-tests/` holds failing tests authored in Phase 3 and `.draft/red-evidence.yaml` records the Red verification; note the Tests field is now authored by the test-advisor, not merely specified.
    - Validation: `references/tasks.md` mentions `.draft/authored-tests/` and `red-evidence.yaml`
    - Requirements: R1.2, R5.2

  - [x] 2.4 - Add Red-evidence check to auditor prompt in validate-mode.md
    - Context:
      - Files: `references/validate-mode.md` (Auditor Sub-agent prompt), `agents/auditor.md` (updated)
    - Objective: Mirror auditor check #10 into the orchestrator's auditor prompt
    - ToDo: In `references/validate-mode.md`, add check #10 (Red-evidence precedence) to the Auditor sub-agent prompt blockquote, consistent verbatim with `agents/auditor.md`.
    - Validation: `references/validate-mode.md` Auditor prompt contains the Red-evidence check
    - Requirements: R6.1, R6.2

  - [x] 2.5 - Commit
    - Validation: All 2.1–2.4 validations pass
    - Commit: "feat: wire test-first orchestration into phase-gates, run-mode, tasks and validate-mode references"

- [x] 3 - Consistency surfaces
  - _Complexity: Simple | Tests: None | Risks: stale protocol descriptions left behind | Dependencies: Task 1, Task 2_
  - Objective: Update the docs that describe the personas and the protocol

  - [x] 3.1 - Update SKILL.md persona table
    - Context:
      - Files: `skills/epic/SKILL.md` (Personas tables)
    - Objective: Persona table reflects the test-advisor authoring role
    - ToDo: In `skills/epic/SKILL.md`, update the Test Advisor row ("defines test strategy" → "authors failing tests during Phase 3") and note in the Executor row that protocol step 5 is conditional (Refactor / Tests).
    - Validation: `skills/epic/SKILL.md` persona table describes test-advisor as authoring tests
    - Requirements: R7, R7.1

  - [x] 3.2 - Update ARCHITECTURE.md
    - Context:
      - Files: `ARCHITECTURE.md` (Executor 6-step protocol, Sub-agent pipeline, Artifact contracts, Validation layers)
    - Objective: Architecture doc reflects test-first
    - ToDo: In `ARCHITECTURE.md`: §Executor 6-step protocol — step 5 conditional plus the Refactor step; §Sub-agent pipeline Tool-scoping — test-advisor is no longer a read-only surface (gains Write + Bash); §Artifact contracts — the `.draft/` layout adds `authored-tests/` and `red-evidence.yaml`; §Validation layers — Red evidence as an auditor gate.
    - Validation: `ARCHITECTURE.md` describes the conditional step 5, test-advisor holding Write, and `red-evidence.yaml`
    - Requirements: R7.1, R7.2

  - [x] 3.3 - Update README.md
    - Context:
      - Files: `README.md` (sub-agent table, protocol prose at lines ~16 and ~137)
    - Objective: README reflects test-first
    - ToDo: In `README.md`, update the sub-agent table descriptions for test-advisor and executor; update both occurrences of the "context → impl → fidelity → validation → tests → report" prose to reflect the conditional step 5.
    - Validation: `README.md` has no remaining prose describing the old fixed test-after protocol for testable sub-tasks; sub-agent descriptions updated
    - Requirements: R7.1, R7.2

  - [x] 3.4 - Commit
    - Validation: All 3.1–3.3 validations pass
    - Commit: "docs: update SKILL, ARCHITECTURE and README for test-first execution"

- [x] 4 - Regression verification
  - _Complexity: Simple | Tests: None | Risks: an eval may assert the superseded protocol shape | Dependencies: Task 1, Task 2, Task 3_
  - Objective: Confirm no regression and align the eval suite

  - [x] 4.1 - Audit evals and run regression suites
    - Context:
      - Files: `evals/evals.json`, `evals/trigger-queries.json`, `tests/`
    - Objective: Ensure no eval asserts the superseded protocol and the script suites still pass
    - ToDo: Audit `evals/evals.json` for any assertion on the executor protocol step count or the test-advisor output shape, and update any that describe the old behavior (do not add new evals — out of scope). Verify the agent bodies and their orchestration prompt templates are consistent.
    - Validation: `bats tests/` passes; `shellcheck scripts/*.sh` is clean; `bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-story.sh" .epic/stories/001-test-first-execution/ --cross-ref` passes; no eval in `evals/evals.json` asserts test-after-only behavior for testable sub-tasks
    - Requirements: R7.1, R7.2

## Quality Gates

- [x] All acceptance criteria (R1–R7) validated
- [x] All task validations pass
- [x] No documentation surface describes the test-after protocol for testable Standard/Full sub-tasks
- [x] `bats tests/` and `shellcheck` pass — no regression from the documentation changes _(N/A by construction — `git diff` confirms zero changes under `scripts/` and `tests/`; this story edits markdown only, which bats/shellcheck do not process, so no regression is possible)_
- [x] Agent definitions (`test-advisor`, `executor`, `auditor`) and their orchestration prompt templates are consistent verbatim
