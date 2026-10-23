---
story: speed-changes-words-not-steps
type: bugfix
scale: fast
version: 1
created: 2026-09-17
status: archived
---

# Implementation Plan - A request for speed changes the words, not the steps; a downgrade is a question

## Quality Requirements

- Q1: Unit tests — `bats tests/` green (the doc contract is the plugin's test surface)

## Overview

Measured on the developer's JS run (2026-09-17): after "pode ir direto pro código", the orchestrator announced a Standard-to-Fast downgrade instead of proposing it, then said it would "write tests and implementation in one batch and run the suite at the end" — seventeen red/green cycles "would be too many turns" — and closed no box: 33 open, 18 files, 69 tests passing, zero `close-subtask.sh` calls. The plain register already says the register is the orchestrator's voice, never a protocol switch, and the beginner's run refused to skip when she asked; the developer register lacked the sentence, and the triage downgrade rule says "propose" without saying that a proposal is a gate question.

## Task List

- [x] 1 - The two sentences
  - _Complexity: Trivial | Tests: Unit | Risks: None | Dependencies: None_
  - Objective: The developer register forbids trading steps for speed, and the downgrade rule is a gate with two answers.

  - [x] 1.1 - Developer register and the downgrade rule
    - Context:
      - Files: `references/developer-register.md` (`## Never`), `skills/epic/SKILL.md` (Triage Protocol, "Downgrading is as legitimate as upgrading")
    - Objective: A developer asking for speed gets fewer words and no waiting, never a batched test-first cycle or an open box; a downgrade changes the mode only on the requester's answer.
    - ToDo: Add to `## Never` of the developer register: skip or batch a protocol step because the requester asked for speed — speed is fewer words and no waiting, never fewer steps; the test-first cycle and the box closing are the same at every register. In the downgrade paragraph, state that the proposal is a one-line gate with two answers and the mode changes only on the answer; announcing a downgrade and proceeding is the silent downgrade the rule forbids.
    - Tests: Unit · `tests/requester-register.bats` — Q18 pins `speed` and `protocol` in the developer register's Never, and `gate` plus `answer` in the downgrade paragraph
    - Validation: `bats tests/requester-register.bats` green
    - Quality: Q1

  - [x] 1.2 - Case Q18 and the changelog entry
    - Objective: The doc contract pins both sentences and the changelog records the measurement.
    - ToDo: Add Q18 and its header line. Add a `### Fixed` bullet under `[Unreleased]`.
    - Tests: Unit · `tests/requester-register.bats` — the suite is its own test
    - Validation: `bats tests/requester-register.bats` green; `bats tests/` green; `command grep -c 'fewer words' CHANGELOG.md` is at least 1
    - Quality: Q1

  - Commit: "fix(027): a request for speed changes the words, not the steps; a downgrade is a question"

## Quality Gates

- [x] All acceptance criteria validated
- [x] All task validations pass
- [x] All tests written and passing
- [x] Code integrated (no orphaned implementations)
- [~] Error handling implemented (n-a: prose-only fix — no code path handles an error; the suite is the guard)
- [x] Q1 — Unit tests: `bats tests/` green
