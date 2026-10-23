---
story: clarify-as-an-architect
type: feature
scale: standard
version: 1
created: 2026-09-17
status: archived
---

# Implementation Plan - Clarify as an architect

## Overview

The protocol is rewritten in place, keeping every anchor and keyword the doc-contract suite pins. The Analyst's checklist and the context-discovery rules are then pointed at the new form, so the raw questions and the asked questions agree. The suite pins the new rules last.

## Task List

- [x] 1 - The protocol
  - _Complexity: Simple | Tests: Unit | Risks: breaking the Q3 anchors or keywords | Dependencies: None_
  - Objective: Clarify asks what and what for, proposes the how, bundles only independent questions, and counts a budget of questions.

  - [x] 1.1 - Rewrite the Clarify Protocol
    - Context:
      - Files: `skills/epic/SKILL.md` (Clarify Protocol), `references/plain-register.md` (Explain by example), `references/developer-register.md`
    - Objective: The protocol carries the orientation round, the consequence rule, the context-and-example rule, the recommendation rule, the bundling rule and the question-counted budget.
    - ToDo: Replace the bullets from "One question budget per story" through the bundling bullet with the new set, keeping the calibration question, the "left open" adaptive rule, the 2–4 options rule, implicit capability detection, the Fast skip rule and "Never skip clarify for Standard/Full". State the budget numbers and the measurement they rest on.
    - Tests: Unit · `tests/requester-register.bats` — Q3 stays green; Q14 pins orientation, consequence, mechanism, example, recommend; Q15 pins the budget counted in questions
    - Validation: `bats tests/requester-register.bats` green
    - Requirements: R1.1, R1.2, R1.3, R1.4, R2.1, R2.2, R3.1, R3.2, R4.1

  - [x] 1.2 - The Question shape example
    - Context:
      - Files: `skills/epic/SKILL.md` (Question shape)
    - Objective: The example shows a consequence question with a labelled recommendation and context on every option.
    - ToDo: Replace the token-TTL example with one that asks a consequence, offers a `(Recommended)` option first with its reason, and keeps the `context` line naming the requirement it affects.
    - Tests: Unit · `tests/requester-register.bats` — Q16 pins `(Recommended)` and a reason in the example block
    - Validation: `bats tests/requester-register.bats` green
    - Requirements: R1.2, R1.4

  - Commit: "feat(023): Clarify asks what and what for, proposes the how, and counts questions"

- [x] 2 - The checklist feeds the form
  - _Complexity: Trivial | Tests: Unit | Risks: None | Dependencies: Task 1_
  - Objective: The Analyst's assertive items and the context-discovery rules agree with the protocol.

  - [x] 2.1 - Analyst and context-discovery
    - Context:
      - Files: `agents/analyst.md` (Function 2), `references/context-discovery.md` (Completeness Checklist rules)
    - Objective: The Analyst phrases X and Y as what the requester can observe, and the orchestrator presents the items in rounds, not one numbered list.
    - ToDo: In Function 2, extend step 5: phrase the assertion as an observable consequence, never a mechanism. In context-discovery Rules, replace "present all questions in a single numbered list" with rounds per the Clarify Protocol, the numbered list being the headless fallback.
    - Tests: Unit · `tests/requester-register.bats` — Q17 pins `consequence` in analyst.md Function 2 and `rounds` in the checklist rules
    - Validation: `bats tests/requester-register.bats` green
    - Requirements: R4.2

  - Commit: "feat(023): the Analyst's checklist speaks in consequences"

- [x] 3 - Suite and changelog
  - _Complexity: Trivial | Tests: Unit | Risks: None | Dependencies: Task 2_
  - Objective: The doc contract pins the format and the changelog records it.

  - [x] 3.1 - Cases Q14–Q17
    - Context:
      - Files: `tests/requester-register.bats`
    - Objective: Four cases pin the orientation round, the consequence rule, the question-counted budget, the example and the Analyst form.
    - ToDo: Add Q14, Q15, Q16, Q17 in the file's style — anchored blocks, keyword assertions — and extend the header index.
    - Tests: Unit · `tests/requester-register.bats` — the suite is its own test
    - Validation: `bats tests/requester-register.bats` green; `bats tests/` green
    - Requirements: R1.1, R3.1, R4.2

  - [x] 3.2 - Changelog entry
    - Objective: `[Unreleased]` records the format and the budget change.
    - ToDo: Add an entry under `### Changed` naming the orientation round, the consequence rule, the recommendation rule, the bundling rule and the budget counted in questions with its numbers.
    - Acceptance:
      - The entry names the six budget numbers and the word `consequence`
    - Validation: `command grep -c 'counted in questions' CHANGELOG.md` is at least 1
    - Requirements: R3.1

  - Commit: "test(023): the doc contract pins the architect's format"

## Quality Gates

- [x] All acceptance criteria validated
- [x] All task validations pass
- [x] All tests written and passing
- [x] Code integrated (no orphaned implementations)
- [~] Error handling implemented (n-a: prose-only story — no code path handles an error; the suite is the guard)
