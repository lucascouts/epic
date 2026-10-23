---
story: preferred-tooling-policy
type: feature
scale: full
version: 1
created: 2026-05-17
status: archived
---

# Implementation Plan - Preferred Tooling Policy

## Overview

The feature is delivered by editing the Epic plugin's Markdown artifacts. Task 1
creates the root policy doc; Task 2 wires detection into triage; Task 3 extends
the Test Advisor (touching three E2E-exclusion sites that must change in lock-step);
Task 4 teaches Run mode the deferred-Red flow; Task 5 updates the design-guide and
executor; Task 6 verifies the cross-artifact contract and syncs release docs.
There is no executable code — every sub-task is verified by Grep and the plugin's
existing `validate`/`bats`/`shellcheck` gates.

## Task List

- [x] 1 - Author the preferred-tooling policy reference
  - _Complexity: Moderate | Tests: None | Risks: copy-paste contradiction from the mcp-integration.md template | Dependencies: None_
  - Objective: Establish a single source-of-truth doc for the tooling policy.

  - [x] 1.1 - Create references/preferred-tooling.md
    - Context:
      - Files: `references/mcp-integration.md` (structural template to mirror)
      - Files: `.epic/stories/003-preferred-tooling-policy/design.md` (priority table + procedures)
    - Objective: Create the policy reference defining tool tiers, detection, and the recommend-and-pause fallback.
    - ToDo:
      - Create `references/preferred-tooling.md` mirroring `references/mcp-integration.md`: `# Preferred Tooling` H1, intro paragraph, `## Priority order` table with columns `# | Tool | Tier | Kind | When to pick`, a `### Hard rules` block, a `## Detection procedure` numbered list, a `## No favorite available` section, and a `## Rules` block.
      - Populate the priority table with the six E2E tools from design.md Data Models (`playwright`/`chrome-devtools` Favorite; `puppeteer`/`selenium`/`browser-use`/`stagehand` Optional) and state that the `When to pick` column is the context rule while the `#` column is only a last-resort tie-break.
      - Document the three detection mechanisms: MCP health-check (`playwright`, `chrome-devtools`, `browser-use`, `stagehand`); manifest inspection for `puppeteer`/`selenium`; skill-list presence for `frontend-design`. GOTCHA — detection passivity: inspect the dependency manifest FIRST; run a version-probe CLI command ONLY when the manifest is inconclusive; never probe unconditionally.
      - Document the `undetermined` outcome (R2.6): WHERE a mechanism cannot run — no dependency manifest present, or the session's skill list is unavailable for `frontend-design` — mark that tool `undetermined` rather than installed, and proceed.
      - Document the recommend-and-pause fallback: when no favorite is available, present an install recommendation with a `[y/n]` install/proceed choice and link to install docs. GOTCHA — headless: in a headless/non-interactive session emit the recommendation as a logged note and proceed; never call `AskUserQuestion` in a headless session.
      - Document optional-tool selection (general rule: favorites first; an optional tool only when already installed AND the context requires it; on a multi-fit tie use the table `#` order and record a one-line justification) and the `frontend-design` skill preference for frontend stories.
      - GOTCHA — Fast mode: do NOT copy mcp-integration.md's "skip in Fast mode" line. State the opposite explicitly: preferred-tooling detection runs in ALL modes including Fast, because it is cheap and the selection annotations matter for E2E sub-tasks.
      - Cross-link `mcp-integration.md` ↔ `preferred-tooling.md` with `[name.md](name.md)` relative links.
    - Validation: `references/preferred-tooling.md` exists; `grep` confirms a `## Priority order` table, a `### Hard rules` block, a `## Detection procedure`, a `## No favorite available` section, and an explicit "runs in Fast" statement.
    - Requirements: R1.1, R1.2, R1.3, R1.4, R2.2, R2.3, R2.4, R2.6, R3.1, R3.2, R3.3, R3.4, R4.1, R4.2, R4.3, R5.1, R5.3
    - Commit: "feat: add preferred-tooling policy reference"

- [x] 2 - Wire detection into triage
  - _Complexity: Moderate | Tests: None | Risks: SKILL.md is large — edits must land in the correct sections | Dependencies: Task 1_
  - Objective: Make triage run detection, surface the result, and persist the decision.

  - [x] 2.1 - Extend SKILL.md triage with preferred-tooling detection
    - Context:
      - Files: `skills/epic/SKILL.md` (Triage Protocol, MCP Integration subsection, triage proposal block)
      - Files: `references/preferred-tooling.md` (procedure to reference — created in 1.1)
    - Objective: Add the triage detection step, the reference subsection, and the proposal line.
    - ToDo:
      - In `skills/epic/SKILL.md`, add a `### Preferred Tooling` subsection next to the existing `### MCP Integration` subsection, pointing to `references/preferred-tooling.md`.
      - Add triage step **7b "Detect preferred tooling"** immediately after step 7 (Health-check candidate MCPs) in the Triage Protocol numbered list; state it runs in all modes (unlike MCP detection, which Fast skips).
      - Add a `> - Tooling:` line to the triage proposal block (after `> - MCPs:`) reporting detected tools, the resolved E2E/frontend selection, and any favorite-absent recommendation.
      - Specify the selection outcome the step produces: WHEN a favorite is available, select it; WHEN the user proceeds without installing, select the best installed optional tool that fits the task context (per `references/preferred-tooling.md`); WHEN no favorite and no fitting optional tool exist, record `none — no E2E tooling available` in design.md's `## Tooling Decisions` block AND as a story Constraint.
      - State that the recommendation/pause happens at triage only, and that the resolved decision is written to design.md's `## Tooling Decisions` block and annotated in tasks.md — executor and Test Advisor consume it without re-detecting.
      - GOTCHA — headless: the favorite-absent pause reuses the Runtime dependency precheck's interactive/headless signal (`TaskCreate` present = interactive); in a headless session emit a logged note instead of pausing.
    - Validation: `grep` of `skills/epic/SKILL.md` shows the `### Preferred Tooling` subsection, the step `7b`, the `> - Tooling:` proposal line, and the post-"proceed" / no-tool-fits selection outcome.
    - Requirements: R2.1, R2.5, R3.3, R3.5, R4.1, R5.1, R6.1, R6.2
    - Commit: "feat: wire preferred-tooling detection into triage"

- [x] 3 - Extend the Test Advisor for E2E authorship
  - _Complexity: Moderate | Tests: None | Risks: the E2E-exclusion wording is duplicated across three files — all must change identically | Dependencies: Task 1_
  - Objective: Let the Test Advisor author E2E tests with Red deferred to Run mode.

  - [x] 3.1 - Update agents/test-advisor.md for E2E authorship
    - Context:
      - Files: `agents/test-advisor.md` (current E2E exclusion at lines ~21, ~24, ~114, ~120-121; red-evidence schema)
      - Files: `.epic/stories/003-preferred-tooling-policy/design.md` (C3 + red-evidence schema)
    - Objective: Allow E2E test authorship with a deferred-Red evidence shape.
    - ToDo:
      - Edit `agents/test-advisor.md` so the agent authors `Unit`, `Integration`, AND `E2E` test files. Update every E2E-exclusion mention (lines ~21, ~24, ~114, ~120-121) — no line may still say the agent never authors E2E.
      - For an `E2E` sub-task: author the test file under `.draft/authored-tests/` using the story's selected E2E tool, but DEFER Red verification to Run mode (do not run the test in Phase 3).
      - Add the deferred-Red rule: write a `red-evidence.yaml` entry with `red_deferred: true` (new field) and a `tool:` field, OMITTING `failed`/`reason`/`command`. GOTCHA — do NOT write `failed: false`: Run mode reads `failed: false` as a broken-test error.
      - Extend the "Inputs Expected" section to include the story's selected E2E tool (read from design.md `## Tooling Decisions`).
      - Leave Unit/Integration behavior unchanged — still authored and Red-verified during Phase 3.
    - Validation: `grep` of `agents/test-advisor.md` shows no remaining "never author ... E2E" text and shows the deferred-Red rule with `red_deferred`.
    - Requirements: R7.1, R7.2, R7.4

  - [x] 3.2 - Update references/phase-gates.md Test Advisor prompt
    - Context:
      - Files: `references/phase-gates.md` (Test Advisor sub-agent prompt, lines ~158, ~175, ~183-189)
      - Files: `agents/test-advisor.md` (the wording finalized in 3.1 — must match)
    - Objective: Align the Test Advisor sub-agent prompt with E2E authorship and deferred Red.
    - ToDo:
      - Edit the Test Advisor sub-agent prompt in `references/phase-gates.md` so it instructs authoring E2E test files too, with Red deferred to Run mode. The E2E rule wording MUST be identical to the wording 3.1 placed in `agents/test-advisor.md`.
      - Update the Red-evidence instruction in the prompt to describe the `red_deferred: true` entry shape for E2E.
    - Validation: `grep` of `references/phase-gates.md` Test Advisor section matches the new E2E-authorship wording from 3.1.
    - Requirements: R7.1, R7.2, R7.4

  - [x] 3.3 - Update references/tasks.md Tests-field note
    - Context:
      - Files: `references/tasks.md` (Tests-field note, lines ~121-127)
      - Files: `agents/test-advisor.md` (wording from 3.1)
    - Objective: Update the Tests-field documentation so E2E is described as authored.
    - ToDo:
      - Edit the Tests-field note in `references/tasks.md` so it states E2E tests are authored at plan time (Red deferred), consistent with the wording from 3.1 and 3.2 — remove any implication that E2E is exclusively test-after.
      - Add the E2E annotation grammar to the Tests-field note — `` E2E · `tool` · `path/to/test` — scenarios `` — so the framework has a persistent producer-side spec for the E2E sub-task annotation (the format Task 6.1 verifies). Document that the `tool` segment is the selected E2E tool from design.md `## Tooling Decisions`.
    - Validation: `grep` of `references/tasks.md` Tests-field note reflects E2E authoring, matches 3.1/3.2, and shows the `E2E · tool · path` annotation grammar.
    - Requirements: R7.1, R7.4, R6.2

  - [x] 3.4 - Commit
    - Validation: `grep` across `agents/test-advisor.md`, `references/phase-gates.md`, and `references/tasks.md` shows identical E2E-authorship wording and no remaining E2E-exclusion text; 3.1-3.3 validations pass.
    - Commit: "feat: extend Test Advisor to author E2E tests with deferred Red"

- [x] 4 - Run-mode deferred Red for E2E
  - _Complexity: Moderate | Tests: None | Risks: must not alter the Executor's test-first branching | Dependencies: Task 3_
  - Objective: Teach Run mode to confirm the deferred Red for E2E sub-tasks.

  - [x] 4.1 - Update references/run-mode.md for deferred E2E Red
    - Context:
      - Files: `references/run-mode.md` (task-execution flow, authored-test materialization)
      - Files: `agents/executor.md` (test-first vs test-after branching — must stay unchanged)
    - Objective: Document the orchestrator-owned deferred-Red confirmation for E2E.
    - ToDo:
      - Edit `references/run-mode.md` so the task-execution/materialization flow includes: for an E2E sub-task whose pre-authored test carries `red_deferred: true`, the orchestrator runs the test and confirms it FAILS (Red) BEFORE spawning the Executor, then confirms it PASSES (Green) after the Executor completes. If the deferred Red does not fail as expected, STOP and escalate.
      - GOTCHA — the Executor's test-first step 2/5 branching stays UNCHANGED: the orchestrator owns the deferred Red check; the Executor still treats a present pre-authored test as a test-first sub-task.
      - GOTCHA — a `red_deferred: true` entry legitimately omits `failed`/`reason`/`command`. Run mode MUST distinguish an absent `failed` key (deferred E2E test, valid) from `failed: false` (broken test — blocks Phase 3). Document that Run mode does not treat a missing `failed` key on a `red_deferred` entry as missing or invalid Red evidence.
    - Validation: `grep` of `references/run-mode.md` describes the deferred-Red confirmation for E2E sub-tasks and the orchestrator ownership.
    - Requirements: R7.3
    - Commit: "feat: confirm deferred E2E Red in Run mode"

- [x] 5 - design-guide and executor updates
  - _Complexity: Simple | Tests: None | Risks: None | Dependencies: Task 1_
  - Objective: Surface tooling decisions in the design template and the executor.

  - [x] 5.1 - Update references/design-guide.md testing strategy
    - Context:
      - Files: `references/design-guide.md` (Testing Strategy template, lines ~94-98)
      - Files: `.epic/stories/003-preferred-tooling-policy/design.md` (Tooling Decisions block format)
    - Objective: Add a tool annotation and a Tooling Decisions block to the design template.
    - ToDo:
      - Edit the Testing Strategy template in `references/design-guide.md` so the E2E line includes the selected-tool annotation.
      - Add a `## Tooling Decisions` block to the design document template, with the format from design.md Data Models (E2E tool, Frontend aid, Recommendation surfaced).
    - Validation: `grep` of `references/design-guide.md` shows the E2E tool annotation and the `## Tooling Decisions` block.
    - Requirements: R6.1

  - [x] 5.2 - Update agents/executor.md for frontend-design and E2E pre-authored test
    - Context:
      - Files: `agents/executor.md` (Step 1/2 context, test-first vs test-after table)
    - Objective: Note the frontend-design designation and the not-yet-Red E2E pre-authored test.
    - ToDo:
      - Edit `agents/executor.md` to note that when a frontend sub-task designates the `frontend-design` skill (per design.md Tooling Decisions / the sub-task ToDo), the Executor uses that skill during Step 2 Implementation.
      - Add a note that an E2E sub-task may carry a pre-authored test whose Red was deferred and already confirmed by the orchestrator before spawn — the Executor treats it as a normal test-first sub-task and MUST NOT re-author or re-verify it.
    - Validation: `grep` of `agents/executor.md` references `frontend-design` usage and the orchestrator-confirmed deferred-Red E2E test.
    - Requirements: R5.2, R6.3, R7.3

  - [x] 5.3 - Commit
    - Validation: 5.1 and 5.2 validations pass.
    - Commit: "feat: document tooling decisions in design-guide and executor"

- [x] 6 - Cross-artifact verification and release-sync docs
  - _Complexity: Simple | Tests: None | Risks: None | Dependencies: Task 2, Task 3, Task 4, Task 5_
  - Objective: Verify the persisted-decision contract and sync release docs.

  - [x] 6.1 - Verify the persisted-decision contract
    - Context:
      - Files: `skills/epic/SKILL.md` (producer of the Tooling Decisions block)
      - Files: `references/design-guide.md`, `agents/test-advisor.md`, `agents/executor.md` (consumers)
    - Objective: Confirm the producer/consumer data contract for the tooling decision is consistent.
    - ToDo:
      - Cross-read the `## Tooling Decisions` block format produced/described in `skills/epic/SKILL.md` and `references/design-guide.md` against how `agents/test-advisor.md` and `agents/executor.md` reference the selected tool. Verify field names (`E2E tool`, `Frontend aid`) and the tasks.md E2E/frontend annotation format match on both sides. If any consumer references a field the producer does not write, fix the mismatch in the offending file.
    - Validation: cross-read confirms identical field names and annotation format across producer and consumers; no consumer references an unproduced field.
    - Requirements: R6.3

  - [x] 6.2 - Update CHANGELOG.md, README.md, ARCHITECTURE.md
    - Context:
      - Files: `CHANGELOG.md`, `README.md`, `ARCHITECTURE.md` (release-sync convention)
    - Objective: Reflect the new reference doc and the extended Test Advisor scope.
    - ToDo:
      - Add a `CHANGELOG.md` entry describing the preferred-tooling policy and the extended Test Advisor E2E authorship.
      - Update `README.md` to mention `references/preferred-tooling.md` and the E2E-authoring capability in the relevant feature/sub-agent table.
      - Update `ARCHITECTURE.md` to note the new reference doc and the Test Advisor scope change.
    - Validation: `grep` shows `CHANGELOG.md`, `README.md`, and `ARCHITECTURE.md` all mention preferred-tooling.

  - [x] 6.3 - Commit
    - Validation: `bash scripts/validate-story.sh .epic/stories/003-preferred-tooling-policy` and `bash scripts/cross-reference.sh .epic/stories/003-preferred-tooling-policy` pass; `bats tests/` and `shellcheck` show no regression.
    - Commit: "docs: changelog, README and ARCHITECTURE for preferred-tooling policy"

## Quality Gates

- [x] All acceptance criteria validated
- [x] All task validations pass
- [x] The three E2E-exclusion sites (`test-advisor.md`, `phase-gates.md`, `tasks.md`) read identically
- [x] `references/preferred-tooling.md` is cross-linked from `SKILL.md`
- [x] Producer/consumer contract for the Tooling Decisions block verified (Task 6.1)
- [x] `validate-story.sh` and `cross-reference.sh` pass
- [~] `bats tests/` and `shellcheck` show no regression (n-a: story modified zero `.sh`/`.bats`/test files — Markdown-only, so a shell regression is structurally impossible)
