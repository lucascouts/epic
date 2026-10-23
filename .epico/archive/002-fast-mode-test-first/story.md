---
story: fast-mode-test-first
type: feature
scale: full
version: 1
created: 2026-05-17
status: archived
---

# Story - Fast-Mode Test-First Execution with Intent Anchor

## Introduction

Epic's Fast mode executes sub-tasks test-after: the "Test Advisor Lite" checklist decides which sub-tasks need tests, and the executor writes them after the implementation — the same coupling story 001 removed from Standard and Full. A test written after the code it checks can codify a bug as correct, and Fast mode has no `story.md` or auditor backstop to catch it. This story brings test-first execution to Fast mode in a deliberately lightweight form and adds an optional `Acceptance` field, so that every Fast-mode sub-task carries a verifiable contract — a failing-first test or a stated expected behavior — without Fast gaining a `story.md`, a gate, or a sub-agent.

## Related Stories

- Related: `.epic/stories/001-test-first-execution/story.md` — story 001 brought test-first execution to Standard and Full and explicitly deferred "a Fast-mode normative intent anchor" to a follow-up. This story is that follow-up.

## Requirements

### R1. Test-First Ordering for Fast-Mode Sub-tasks

**User Story:** As a developer using Epic, I want a Fast-mode test written and confirmed failing before its implementation, so that the test cannot be shaped to match buggy code.

#### Acceptance Criteria

- R1.1: WHEN the Test Advisor Lite checklist determines a Fast-mode sub-task needs a test THE SYSTEM SHALL produce that test in a confirmed-failing state before the sub-task's implementation begins
- R1.2: WHEN a Fast-mode test is run to confirm its failure THE SYSTEM SHALL accept the failure as valid Red only if it is caused by the absent or not-yet-correct behavior under test
- R1.3: IF a Fast-mode test fails because the test itself is broken — syntax error, wrong import, misconfigured runner — THEN THE SYSTEM SHALL require the test corrected before treating Red as established

### R2. Green-Then-Refactor for Fast-Mode Sub-tasks

**User Story:** As a developer using Epic, I want the Fast-mode implementer to make a pre-authored test pass and then refactor under it, so that implementation is test-driven and cleanup is safe.

#### Acceptance Criteria

- R2.1: WHERE a Fast-mode sub-task carries a pre-authored failing test THE SYSTEM SHALL require its implementation to make that test pass rather than authoring a new test
- R2.2: WHEN a Fast-mode sub-task's pre-authored test and validation command both pass THE SYSTEM SHALL perform a refactor step before the sub-task is reported complete
- R2.3: WHILE refactoring a Fast-mode sub-task THE SYSTEM SHALL keep the pre-authored test and the validation command passing, and SHALL revert any refactor that breaks either

### R3. Sub-task Intent Anchor — the Acceptance Field

**User Story:** As a developer using Epic, I want every Fast-mode sub-task to state a checkable expected behavior, so that correctness has an anchor even when a sub-task has no test.

#### Acceptance Criteria

- R3.1: THE SYSTEM SHALL support an optional `Acceptance` field on Fast-mode `tasks.md` sub-tasks, holding one to three statements of observable expected behavior
- R3.2: WHERE a Fast-mode sub-task carries no test and is not a Commit sub-task THE SYSTEM SHALL require it to carry an `Acceptance` field, so that every implementing Fast-mode sub-task has either a test or an `Acceptance` field as its verifiable contract
- R3.3: WHERE a Fast-mode sub-task carries a test THE SYSTEM SHALL treat that test as the sub-task's intent anchor and SHALL NOT require an `Acceptance` field
- R3.4: WHEN an `Acceptance` field is written THE SYSTEM SHALL place it in the sub-task body alongside the `Validation` field, and SHALL NOT place it on a parent task
- R3.5: WHERE the story scale is Standard or Full THE SYSTEM SHALL NOT introduce the `Acceptance` field, because the EARS requirement referenced by the sub-task already serves as the anchor

### R4. Lightweight Execution — Paths and No New Ceremony

**User Story:** As a developer using Epic, I want Fast-mode test-first to reuse existing machinery, so that the lightweight character of Fast mode is preserved.

#### Acceptance Criteria

- R4.1: WHEN a Fast-mode sub-task of Trivial complexity is executed inline by the main agent THE SYSTEM SHALL apply the test-first ordering within that inline execution
- R4.2: WHEN a Fast-mode sub-task of Simple or higher complexity is executed THE SYSTEM SHALL pass the pre-authored failing test to the Executor sub-agent as a read-only input
- R4.3: WHEN the Executor receives a pre-authored test for a Fast-mode sub-task THE SYSTEM SHALL reuse the existing Executor six-step protocol with its conditional step 5
- R4.4: WHEN Fast-mode test authorship occurs THE SYSTEM SHALL perform it with the main agent and SHALL NOT spawn the test-advisor sub-agent
- R4.5: WHEN Fast-mode test-first execution runs THE SYSTEM SHALL write the authored test directly into the project's real test tree and SHALL NOT create a `.draft/` directory, a `red-evidence.yaml` file, or any other new persisted artifact

### R5. Bounded Unexpected-Green Handling

#### Acceptance Criteria

- R5.1: IF an authored Fast-mode test passes on its first run instead of failing THEN THE SYSTEM SHALL require the test revised so it fails for the expected reason
- R5.2: IF a revised Fast-mode test still passes after one revision attempt THEN THE SYSTEM SHALL escalate to the user rather than proceed to implementation
- R5.3: WHILE resolving an unexpected-green Fast-mode test THE SYSTEM SHALL NOT weaken or delete assertions to force a failure

### R6. Scale Boundary Preserved

#### Acceptance Criteria

- R6.1: WHEN a Fast-mode story uses test-first execution THE SYSTEM SHALL NOT require a `story.md`, a Phase 1 gate, EARS R-numbers, or a planning sub-agent
- R6.2: IF a change genuinely requires requirement traceability or design documentation THEN THE SYSTEM SHALL recommend during triage that the story be upgraded from Fast to Standard

### R7. Documentation Consistency

#### Acceptance Criteria

- R7.1: WHEN the Fast-mode test-first capability is delivered THE SYSTEM SHALL update every documentation surface that describes Fast-mode test handling or the Test Advisor Lite checklist so that none describes the superseded test-after behavior
- R7.2: WHERE the Fast-mode test-first execution flow is described in more than one document THE SYSTEM SHALL describe it identically in every occurrence

## Success Metrics

- Every Fast-mode sub-task that needs a test has that test confirmed failing before the sub-task is implemented
- Every implementing Fast-mode sub-task carries exactly one verifiable contract — a test or an `Acceptance` field — and none carries neither
- The Fast-mode flow adds zero new artifact files, zero sub-agent spawns, and zero new gates
- `agents/executor.md` has an empty diff for this story — the existing protocol is reused, not modified
- After delivery, no documentation surface describes Fast-mode test-after for sub-tasks that need a test

## Constraints

- Agent definitions and references are markdown; the plugin keeps zero runtime dependency beyond `bash`, `git`, `jq`
- The change touches Fast mode only — Standard and Full behavior is unchanged
- `agents/executor.md` MUST NOT be modified; the existing conditional six-step protocol already consumes a pre-authored test and is reused as-is
- The scale-adaptive principle holds — Fast gains no `story.md`, no Phase 1 gate, no EARS R-numbers, and no planning sub-agent
- The unexpected-green revision limit for Fast is one attempt, then escalate — lighter than the two-attempt cap used in Standard and Full
- Test-first ordering applies only to sub-tasks the Test Advisor Lite checklist already flags as needing a test — structural sub-tasks gain no test ceremony
- The change must not regress the existing eval suite (`evals/`) or the `bats` script tests (`tests/`)

## Out of Scope

- Changes to `scripts/validate-story.sh` to structurally validate the `Acceptance` field — separate follow-up story
- Any new `auditor` check for Fast-mode stories — separate follow-up story
- New eval cases covering test-first behavior — separate follow-up story; this story only verifies that existing evals do not contradict the new behavior
- Independent test authorship for Fast mode by a separate persona — Fast keeps single-author by design
- A `red-evidence.yaml` or any persisted Red record for Fast mode
- Any change to Standard or Full mode test-first behavior — delivered by story 001
- The SDD outer loop, spec-drift detection, and code-level traceability — separate initiatives
