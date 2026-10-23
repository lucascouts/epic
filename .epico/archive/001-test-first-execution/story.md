---
story: test-first-execution
type: feature
scale: full
version: 1
created: 2026-05-17
status: archived
---

# Story - Test-First Execution with Independent Test Authorship

## Introduction

Epic currently executes sub-tasks test-after: the `executor` sub-agent writes the implementation and then writes its own tests, in the same context window. A test written this way can codify a bug in the just-written code as "correct", and that test then passes every downstream validation layer (executor, validator, auditor). This story evolves Standard and Full stories to a test-first model with **independent test authorship** — the `test-advisor` sub-agent authors failing tests before implementation, and the `executor` implements against them — closing the only gap in Epic's validation pipeline that has no defense today. Fast mode is unchanged.

## Requirements

### R1. Test-Advisor as Test Author

**User Story:** As a developer using Epic, I want tests authored by a persona separate from the implementer, so that a test cannot be shaped to match buggy implementation code.

#### Acceptance Criteria

- R1.1: WHEN the test-advisor runs in Phase 3 for a Standard or Full story THE SYSTEM SHALL author one failing test file for each sub-task whose Tests field has type Unit or Integration
- R1.2: WHEN the test-advisor authors a test file THE SYSTEM SHALL write it under the story's `.draft/` directory and SHALL NOT write it into the project's real test tree
- R1.3: WHERE a sub-task has no Tests field, or its Tests field type is neither Unit nor Integration, THE SYSTEM SHALL NOT author a test for that sub-task and SHALL preserve the current test-after behavior
- R1.4: WHERE the story scale is Fast THE SYSTEM SHALL NOT invoke test authorship

### R2. Context Separation Between Author and Implementer

**User Story:** As a developer using Epic, I want the test author and the implementer to see disjoint context, so that the test reflects the specification and not the chosen implementation approach.

#### Acceptance Criteria

- R2.1: WHEN the test-advisor authors a test THE SYSTEM SHALL provide it the sub-task's EARS requirement, the sub-task Objective, the Tests scenarios, and — for Full stories — the relevant design.md contract
- R2.2: WHEN the test-advisor authors a test THE SYSTEM SHALL NOT provide it the sub-task's ToDo field
- R2.3: WHERE the story scale is Standard and no design.md exists THE SYSTEM SHALL derive the test author's contract from the sub-task Objective, the EARS requirement, and the Tests scenarios only
- R2.4: WHEN the executor implements a sub-task that has a pre-authored test THE SYSTEM SHALL provide the executor the ToDo field and the pre-authored failing test as a read-only input

### R3. Executor Green-Then-Refactor Protocol

**User Story:** As a developer using Epic, I want the executor to implement against a pre-authored failing test and then refactor under that test, so that implementation is driven by the test and improvements stay safe.

#### Acceptance Criteria

- R3.1: WHERE a sub-task has a pre-authored failing test THE SYSTEM SHALL require the executor to make that test pass rather than author a new test
- R3.2: WHEN the executor has made the pre-authored test pass THE SYSTEM SHALL require a Refactor step, using the passing test as a regression safety net, before the executor reports
- R3.3: WHERE a sub-task has no pre-authored test THE SYSTEM SHALL require the executor to follow the existing test-after protocol unchanged

### R4. Frozen Test with Audited Exceptions

**User Story:** As a developer using Epic, I want the authored test's assertions to be immutable during implementation, so that the implementer cannot weaken the behavioral contract.

#### Acceptance Criteria

- R4.1: WHILE implementing a sub-task that has a pre-authored test THE SYSTEM SHALL forbid the executor from modifying the test's assertions
- R4.2: IF the executor must change a pre-authored test's imports or signature references to match an INTENTIONAL design deviation THEN THE SYSTEM SHALL permit only that change and SHALL record it in the deviation register
- R4.3: IF an intentional design deviation changes behavior rather than only the call surface THEN THE SYSTEM SHALL require the executor to stop and escalate instead of modifying the test

### R5. Red-Phase Verification

**User Story:** As a developer using Epic, I want every authored test confirmed to fail before implementation, so that no-op tests and already-satisfied tests are caught at planning time.

#### Acceptance Criteria

- R5.1: WHEN the test-advisor authors a test THE SYSTEM SHALL run that test and confirm it fails for the expected reason before Phase 3 completes
- R5.2: WHEN the test-advisor confirms an authored test fails THE SYSTEM SHALL record the failure output as Red evidence for that sub-task
- R5.3: IF an authored test passes instead of failing THEN THE SYSTEM SHALL block Phase 3 completion and require the test-advisor to revise the test until it genuinely fails
- R5.4: IF an authored test still passes after the bounded number of revision attempts THEN THE SYSTEM SHALL escalate to the user rather than proceed

### R6. Auditor Red-Evidence Check

#### Acceptance Criteria

- R6.1: WHEN the auditor reviews a Standard or Full story THE SYSTEM SHALL verify that every sub-task with a pre-authored test has Red evidence recorded prior to its implementation
- R6.2: IF a sub-task with a pre-authored test lacks preceding Red evidence THEN THE SYSTEM SHALL require the auditor to report it as a finding

### R7. Internal Documentation Consistency

#### Acceptance Criteria

- R7.1: WHEN the test-first capability is delivered THE SYSTEM SHALL update every documentation surface that describes the executor protocol, the test-advisor role, or sub-agent tool scoping so that none describes the superseded test-after behavior
- R7.2: WHERE the executor protocol's step sequence is stated in more than one document THE SYSTEM SHALL state it identically in every occurrence

## Success Metrics

- Every sub-task with a pre-authored test in a Standard/Full story has Red evidence dated before its implementation
- The executor authors zero test files for sub-tasks that have a Tests field — authorship is fully owned by the test-advisor
- The test author and the implementer are distinct personas with verifiably disjoint context (ToDo never reaches the test author)
- No documentation surface describes the test-after protocol for testable Standard/Full sub-tasks after delivery

## Constraints

- Agent definitions and references are markdown; the plugin has no runtime dependency beyond `bash`, `git`, `jq`
- Test-first applies to Standard and Full modes only; Fast mode behavior is unchanged
- The scale-adaptive principle must hold — sub-tasks without a Tests field gain no new ceremony
- `.draft/` is gitignored — authored tests must survive between the planning session and the Run session within the same checkout, and materialize into the real test tree when Run starts
- The test-advisor changes from a read-only sub-agent to one holding `Write` and `Bash` tools
- The change must not break the existing eval suite (`evals/`) or the `bats` script tests (`tests/`)
- The bounded revision limit for R5.4 is **2 attempts**, mirroring the existing Tech Review fix-cycle cap in `run-mode.md`

## Out of Scope

- Acceptance tests generated from EARS requirements (the SDD outer loop) — a separate follow-up story
- Spec-drift detection between completed stories and later code changes
- A Fast-mode normative intent anchor
- Persistent code-level traceability (`trace.md`)
- A `--tdd` flag or a "Test-First" workflow variant — test-first is the default for Standard/Full, not a toggle
- Any change to Fast mode behavior
