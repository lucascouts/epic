---
story: requester-block-and-registers
type: feature
scale: standard
version: 1
created: 2026-09-17
status: archived
---

# Implementation Plan - The requester block and the two registers

## Overview

The block lands in the triage protocol first, because every other site cites it. The two registers follow: the plain one gains the positive rule and its role as the layperson seed, the developer one is new. The doc-contract suite is updated last, with the Fast-lock assertion retired for its reason.

## Task List

- [x] 1 - The block in the skill
  - _Complexity: Simple | Tests: Unit | Risks: the Fast-lock assertion in the suite must be retired, not silenced | Dependencies: None_
  - Objective: Triage records the four-field block, the level never changes the scale, and Clarify grows the rules from answers.

  - [x] 1.1 - Triage paragraph, step 4 and the proposal line
    - Context:
      - Files: `skills/epic/SKILL.md` (Triage Protocol, the proposal block)
    - Objective: The requester paragraph defines the block and states what the level changes and what it never changes.
    - ToDo: Replace the 0.6.0 requester paragraph with the block definition (`level`, `persona`, `always`, `never`), the developer-when-unsure rule, the evidence rule for `persona`, the seed rule for `always`/`never`, and the sentence that the level never changes the scale with its reason. Rewrite step 4 to derive the mode from the request for every level. Rewrite the proposal's `Requester:` line as level — persona.
    - Tests: Unit · `tests/requester-register.bats` — Q1 pins the four fields, developer when unsure, `never changes the scale`, and the absence of the Fast lock
    - Validation: `bats tests/requester-register.bats` green
    - Requirements: R1.1, R1.2, R1.3, R2.1, R2.2

  - [x] 1.2 - Draft metadata and the Clarify re-read
    - Context:
      - Files: `skills/epic/SKILL.md` (Draft Saving, Clarify Protocol)
    - Objective: `meta.yaml` carries the block, and Clarify appends revealed rules to it.
    - ToDo: Replace the `requester:` line of the `meta.yaml` example with the block; make `questions_asked` count questions. In Clarify, extend the re-read sentence: tool vocabulary re-reads `requester.level` as `developer`, outcome words keep `layperson`, and an answer that reveals a working rule is appended to `always` or `never`.
    - Tests: Unit · `tests/requester-register.bats` — Q12 pins the block in the Draft Saving example; Q13 pins the append in Clarify
    - Validation: `bats tests/requester-register.bats` green
    - Requirements: R1.2, R1.4

  - Commit: "feat(022): the requester is a four-field block, and the level never changes the scale"

- [x] 2 - The two registers
  - _Complexity: Simple | Tests: Unit | Risks: None | Dependencies: Task 1_
  - Objective: Each level has a register that seeds `always` and `never`.

  - [x] 2.1 - The plain register seeds the layperson and explains by example
    - Context:
      - Files: `references/plain-register.md`
    - Objective: The plain register names itself as the layperson seed and carries the positive rule.
    - ToDo: Rewrite the opening line as the seed of `requester.always`/`never` for `level: layperson`. Add an `## Explain by example` section: one example or analogy per new concept, inside the ceiling, never a definition. Add to `## What does not change` that the level never changes the scale.
    - Tests: Unit · `tests/requester-register.bats` — Q11 pins the section and its two words
    - Validation: `bats tests/requester-register.bats` green
    - Requirements: R3.1, R3.2

  - [x] 2.2 - The developer register
    - Context:
      - Files: `references/plain-register.md` (the shape to mirror), `references/phase-gates.md` (the file-review gate a developer keeps)
    - Objective: A developer is asked directly, with context and an example on every option, and never taught the basics.
    - ToDo: Create `references/developer-register.md` with `## Always`, `## Never`, `## What does not change` and a `## Measured` section that says nothing is measured yet. State that the difference from the plain register is directness, not the amount of context.
    - Tests: Unit · `tests/requester-register.bats` — Q10 pins the file, its sections and the words `example`, `direct`, `basics`
    - Validation: `bats tests/requester-register.bats` green
    - Requirements: R3.1, R3.3

  - Commit: "feat(022): the two registers — the plain one explains by example, the developer one is direct"

- [x] 3 - Suite and changelog
  - _Complexity: Trivial | Tests: Unit | Risks: None | Dependencies: Task 2_
  - Objective: The doc contract pins the new rules and the changelog records the retired one.

  - [x] 3.1 - Retire the Fast-lock assertion and pin the block
    - Context:
      - Files: `tests/requester-register.bats`
    - Objective: Q1 asserts the block and the decoupling; Q10–Q13 pin the registers, the draft example and the Clarify append.
    - ToDo: Rewrite Q1 (drop `unless they ask`, assert the four fields, `developer-register`, `never changes the scale`, and fail if the lock text returns). Add Q10, Q11, Q12, Q13. Keep the header comment's index current.
    - Tests: Unit · `tests/requester-register.bats` — the suite is its own test
    - Validation: `bats tests/requester-register.bats` green; `bats tests/` green
    - Requirements: R1.1, R2.1, R3.1

  - [x] 3.2 - Changelog entry
    - Objective: `[Unreleased]` records the block, the decoupling and its reason.
    - ToDo: Add a `### Changed` entry under `[Unreleased]` naming the four fields, the retired Fast lock and the measurement behind retiring it.
    - Acceptance:
      - The entry names `level`, `persona`, `always`, `never` and says the level never changes the scale
    - Validation: `command grep -c 'never changes the scale' CHANGELOG.md` is at least 1
    - Requirements: R2.1

  - Commit: "test(022): the doc contract pins the block; changelog records the retired lock"

## Quality Gates

- [x] All acceptance criteria validated
- [x] All task validations pass
- [x] All tests written and passing
- [x] Code integrated (no orphaned implementations)
- [~] Error handling implemented (n-a: prose-only story — no code path handles an error; the suite is the guard)
