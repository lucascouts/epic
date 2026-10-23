---
story: sub-agents-in-the-foreground
type: bugfix
scale: fast
version: 1
created: 2026-09-17
status: archived
---

# Implementation Plan - Every sub-agent runs in the foreground

## Quality Requirements

- Q1: Unit tests — `bats tests/` green (the doc contract is the plugin's test surface)

## Overview

Measured on the first 0.7.0 runs (2026-09-17): the orchestrator spawned the Analyst and the Test Advisor with `run_in_background: true`, ended its turn to "call back when it returns", and every persona reply became a user turn spent waiting. The beginner's Standard run burned 12 of 12 user turns, wrote no code and cost US$ 7.04; the developer's Go run did the same for ten turns. The fix is one rule stated where the personas are defined and repeated at every spawn site: the orchestrator's next step is the sub-agent's result, so the call is made in the foreground.

## Task List

- [x] 1 - The rule and its sites
  - _Complexity: Trivial | Tests: Unit | Risks: None | Dependencies: None_
  - Objective: Every place the plugin spawns a sub-agent says foreground, and the Personas section says why.

  - [x] 1.1 - Personas rule and the spawn sites
    - Context:
      - Files: `skills/epic/SKILL.md` (Personas — the main-agent paragraph), `references/phase-gates.md` (Test Advisor, Architect, Reviewer spawns), `references/context-discovery.md` (Analyst spawn), `references/run-mode.md` (Executor spawn), `references/validate-mode.md` (Validator and Auditor spawns)
    - Objective: The rule, its measurement and its one clarification (a parallel group is several foreground calls in one message) live in Personas; each spawn site names the foreground.
    - ToDo: Add the rule paragraph to Personas. At each spawn site add "in the foreground (`run_in_background: false`)" with the reason in a clause.
    - Tests: Unit · `tests/run-defaults.bats` — D6 pins `run_in_background: false` and `foreground` in the Personas section and at the Test Advisor and Analyst spawn sites
    - Validation: `bats tests/run-defaults.bats` green
    - Quality: Q1

  - [x] 1.2 - Case D6 and the changelog entry
    - Objective: The doc contract pins the rule and the changelog records the measurement behind it.
    - ToDo: Add D6 to `tests/run-defaults.bats` and its header line. Add a `### Fixed` entry under `[Unreleased]`.
    - Tests: Unit · `tests/run-defaults.bats` — the suite is its own test
    - Validation: `bats tests/run-defaults.bats` green; `bats tests/` green; `command grep -c 'foreground' CHANGELOG.md` is at least 1
    - Quality: Q1

  - Commit: "fix(026): every sub-agent runs in the foreground — a turn ended to wait is a turn the requester spends waiting"

## Quality Gates

- [x] All acceptance criteria validated
- [x] All task validations pass
- [x] All tests written and passing
- [x] Code integrated (no orphaned implementations)
- [~] Error handling implemented (n-a: prose-only fix — no code path handles an error; the suite is the guard)
- [x] Q1 — Unit tests: `bats tests/` green
