---
story: preferred-tooling-policy
type: feature
scale: full
version: 1
created: 2026-05-17
status: archived
---

# Story - Preferred Tooling Policy

## Introduction

Epic currently has no awareness of which end-to-end (E2E) testing tools or
frontend-implementation aids exist on the user's system — task descriptions
name test types abstractly and the executor improvises. This feature gives the
plugin an explicit, opinionated **preferred-tooling policy**: it knows a small
set of favorite tools, detects what is actually installed, recommends the
favorites when they are missing, and otherwise selects an available tool that
fits the task. The result is consistent, predictable E2E and frontend tooling
across stories instead of per-run guesswork.

## Requirements

### R1. E2E Tooling Tiers

**User Story:** As an Epic user, I want the plugin to have a fixed opinion on
which E2E tools are preferred, so that E2E sub-tasks use consistent tooling
instead of an arbitrary choice per run.

#### Acceptance Criteria

- R1.1: THE SYSTEM SHALL recognize `playwright` and `chrome-devtools` as favorite E2E testing tools
- R1.2: THE SYSTEM SHALL recognize `browser-use`, `selenium`, `puppeteer`, and `stagehand` as optional E2E testing tools
- R1.3: WHEN a story involves E2E testing AND more than one E2E tool is available THE SYSTEM SHALL prefer a favorite tool over an optional tool
- R1.4: THE SYSTEM SHALL treat the favorite and optional tier lists as the single source of truth referenced by every persona that selects an E2E tool

### R2. Preferred-Tooling Detection

**User Story:** As an Epic user, I want the plugin to know which preferred
tools are actually installed, so that it never recommends a tool it cannot use.

#### Acceptance Criteria

- R2.1: WHEN triage runs THE SYSTEM SHALL detect the availability of every favorite and optional preferred tool
- R2.2: WHERE a preferred tool is an MCP server THE SYSTEM SHALL determine availability via a minimal health-check call
- R2.3: WHERE a preferred tool is a library or CLI THE SYSTEM SHALL determine availability by inspecting the project's dependency manifest, and WHERE the manifest is inconclusive THE SYSTEM SHALL run a version-probe command
- R2.4: WHERE a preferred tool is a Claude Code skill THE SYSTEM SHALL determine availability by its presence in the session's available-skills list
- R2.5: THE SYSTEM SHALL run preferred-tooling detection in all modes, including Fast mode
- R2.6: WHEN a detection mechanism cannot run THE SYSTEM SHALL mark that tool as undetermined rather than installed and proceed

### R3. Favorite-Absent Recommendation

**User Story:** As an Epic user, I want to be told when a favorite tool is
missing and be given the choice to install it, so that I am never silently
downgraded to a lesser tool.

#### Acceptance Criteria

- R3.1: WHEN a story requires E2E testing AND no favorite E2E tool is available THE SYSTEM SHALL present a recommendation to install a favorite and pause, awaiting the user's decision to install or to proceed
- R3.2: WHEN a story is classified as a frontend task AND the `frontend-design` skill is not available THE SYSTEM SHALL present a recommendation to install it and pause, awaiting the user's decision to install or to proceed
- R3.3: WHEN the user chooses to proceed without installing THE SYSTEM SHALL continue using the best available tool that fits the task context
- R3.4: WHERE the session is headless or non-interactive THE SYSTEM SHALL emit the recommendation as a logged note and proceed without blocking
- R3.5: THE SYSTEM SHALL surface the recommendation and the resulting tool decision during triage, not during task generation or execution

### R4. Optional-Tool Selection by Context

#### Acceptance Criteria

- R4.1: WHEN no favorite E2E tool is available AND an optional E2E tool is installed AND the task context calls for that tool THE SYSTEM SHALL select that optional tool for the story's E2E sub-tasks
- R4.2: THE SYSTEM SHALL apply a general preference rule — favorites first, an optional tool only when already installed AND clearly required by the task context — rather than a fixed signal-to-tool lookup table
- R4.3: WHEN multiple installed optional tools could fit THE SYSTEM SHALL select one and record a one-line justification for the choice

### R5. Frontend-Design Skill Preference

**User Story:** As an Epic user, I want frontend work to use the
`frontend-design` skill when it is installed, so that panels, pages, and
components are built with the dedicated aid instead of ad-hoc styling.

#### Acceptance Criteria

- R5.1: WHEN a story is classified as a frontend task AND `frontend-design` is available THE SYSTEM SHALL designate `frontend-design` as the preferred implementation aid for that story
- R5.2: WHEN a frontend implementation sub-task is executed AND `frontend-design` is the designated aid THE SYSTEM SHALL instruct the executor to use it
- R5.3: IF `frontend-design` is not available THEN THE SYSTEM SHALL fall back to the executor's default implementation approach after the R3.2 recommendation

### R6. Persistence of Tooling Decisions

#### Acceptance Criteria

- R6.1: WHEN preferred-tooling detection and selection complete during triage THE SYSTEM SHALL record the resolved tool selections in `design.md`
- R6.2: THE SYSTEM SHALL annotate the relevant E2E and frontend sub-tasks in `tasks.md` with the selected tool
- R6.3: THE SYSTEM SHALL ensure the executor and the Test Advisor consume the recorded selections without re-running detection

### R7. E2E Test Authorship by the Test Advisor

**User Story:** As an Epic user, I want E2E tests written before
implementation like unit tests, so that E2E sub-tasks follow the same
test-first discipline.

#### Acceptance Criteria

- R7.1: WHEN a sub-task carries a Tests field of type `E2E` THE SYSTEM SHALL have the Test Advisor author the E2E test file during Phase 3, using the story's selected E2E tool
- R7.2: THE SYSTEM SHALL defer Red-phase verification of an authored E2E test to Run mode rather than running it during Phase 3
- R7.3: WHEN Run mode executes an E2E sub-task that carries a pre-authored E2E test THE SYSTEM SHALL confirm the test fails before implementation and passes after implementation
- R7.4: THE SYSTEM SHALL leave the test-first flow for `Unit` and `Integration` sub-tasks unchanged

## Success Metrics

- 100% of E2E sub-tasks in stories created after this feature carry an explicit
  tool annotation in `tasks.md`.
- Zero silent downgrades: every story that needs E2E testing or frontend work
  with a missing favorite produces a visible recommendation during triage.
- No regression: the existing Unit/Integration test-first flow and all
  `validate-story.sh` / `cross-reference.sh` / `bats` checks continue to pass.

## Constraints

- All artifacts (new reference doc, agent edits) are written in English.
- The new reference document MUST mirror the structure of
  `references/mcp-integration.md` (priority table, detection procedure,
  graceful fallback, Fast-mode handling).
- Detection MUST favor passive inspection; a CLI version-probe command is run
  only when the dependency manifest is inconclusive (R2.3).
- The plugin MUST NOT run installation commands itself — it only recommends.
- Changes MUST keep `CHANGELOG.md`, `README.md`, and `ARCHITECTURE.md` in sync,
  per the established release convention.
- The test-first contract established by stories 001 and 002 for
  Unit/Integration sub-tasks MUST remain intact.

## Assumptions

Documented after the 3-round Clarify budget; adjust before approval if wrong.

- WHERE no favorite AND no fitting optional E2E tool is available, the plugin
  records "no E2E tooling available" as a story constraint and proceeds without
  E2E tool guidance.
- "Frontend task" classification reuses triage's existing type/complexity
  signals plus keyword detection (panels, pages, components, web elements).
- The headless pause-degradation (R3.4) reuses the same interactive/headless
  detection already performed by the Runtime dependency precheck.

## Out of Scope

- Automatically installing any tool — the plugin only recommends and links to
  install docs.
- A fixed, exhaustive signal-to-tool decision table for optional E2E tools
  (explicitly rejected in favor of the general rule in R4.2).
- Changing the test-first model for `Unit` and `Integration` sub-tasks.
- Supporting E2E tools beyond the six named (`playwright`, `chrome-devtools`,
  `browser-use`, `selenium`, `puppeteer`, `stagehand`).
- Deep integration of `frontend-design` into design.md generation — the scope
  is "prefer it for implementation if installed", not redesigning Phase 2.
- Detection or policy for any tooling category other than E2E testing and
  frontend implementation.
