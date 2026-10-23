---
story: fast-auto-effort-and-memory-wording
type: feature
scale: fast
version: 1
created: 2026-09-17
status: archived
---

# Implementation Plan - Fast runs auto, the orchestrator's effort is the session's, and memory names a permitted provider

## Quality Requirements

- Q1: Unit tests — `bats tests/` green (the doc contract is the plugin's test surface)

## Overview

Three small changes decided in the 0.7.0 planning, each one or two lines with the prose around them. Fast runs as `--auto` by default and stops only on a failure or a doubt the defaults do not cover; the orchestrator's `effort: max` leaves the skill frontmatter so the session decides; the ai-memory recommendation names a provider Anthropic's terms allow and rules the subscription token out. A new doc-contract suite pins the three.

## Task List

- [x] 1 - Fast runs `--auto` by default
  - _Complexity: Trivial | Tests: Unit | Risks: the layperson promise "I stop after each group" must not be made under auto | Dependencies: None_
  - Objective: A Fast run goes to the end unless a failure or an uncovered doubt stops it; `--step` asks for the gates back.

  - [x] 1.1 - Flags table, `--step`, the layperson rule and the README row
    - Context:
      - Files: `references/run-mode.md` (the flags table, Run Mode Rules — the layperson bullet), `README.md` (the run command table)
    - Objective: The flags table says Fast defaults to auto and names `--step`; the layperson bullet promises a stop per group only under `--step`; the README row agrees.
    - ToDo: In the flags table rewrite the `(default)` row — gate after every group for Standard and Full; Fast runs as `--auto` — and add a `--step` row that restores the per-group gate for a Fast run. Add an example line. In Run Mode Rules, rewrite the layperson clause: a stop per group is promised only when `--step` was passed; otherwise the run goes to the end and shows the result once, and a doubt the defaults do not cover stops it like a failure. Update the README row for `--auto` and add one for `--step`.
    - Tests: Unit · `tests/run-defaults.bats` — D1 flags table names Fast and `--step`; D2 Run Mode Rules names `--step` and keeps the run-and-show words; D5 README names `--step`
    - Validation: `bats tests/run-defaults.bats tests/requester-register.bats` green
    - Quality: Q1

  - Commit: "feat(025): Fast runs auto by default, the orchestrator's effort is the session's, memory names a permitted provider"

- [x] 2 - The orchestrator's effort is the session's
  - _Complexity: Trivial | Tests: Unit | Risks: None | Dependencies: None_
  - Objective: The skill frontmatter no longer pins the orchestrator at `max`.

  - [x] 2.1 - Remove `effort: max` from the skill frontmatter
    - Context:
      - Files: `skills/epic/SKILL.md` (frontmatter, line 35)
    - Objective: The session's effort applies to the orchestrator, and a fork inherits the same.
    - ToDo: Delete the `effort: max` line. Leave the agents' own `effort` fields untouched — `tests/agent-effort-policy.bats` pins them by decision.
    - Tests: Unit · `tests/run-defaults.bats` — D3 the frontmatter carries no `effort:` line
    - Validation: `bats tests/run-defaults.bats tests/agent-effort-policy.bats` green
    - Quality: Q1

- [x] 3 - The memory recommendation names a permitted provider
  - _Complexity: Trivial | Tests: Unit | Risks: None | Dependencies: None_
  - Objective: The recommendation says which providers Anthropic's terms allow for ai-memory's LLM work, and rules the subscription token out with the reason.

  - [x] 3.1 - `mcp-integration.md` wording
    - Context:
      - Files: `references/mcp-integration.md` (the Memory MCP paragraph that says "optional and recommended")
    - Objective: One sentence names the permitted providers, one rules out OAuth and says why.
    - ToDo: After "optional and recommended", add: the LLM consolidation that turns raw observations into pages needs a provider Anthropic's terms allow for a third-party tool — an API key with a Haiku-class model, since the work is summarisation, or a local model through an OpenAI-compatible endpoint — and never a Claude subscription OAuth token: since February 2026 OAuth from Free, Pro and Max plans is for Claude Code and Claude.ai only, and ai-memory's own documentation warns that path risks the account.
    - Tests: Unit · `tests/run-defaults.bats` — D4 the Memory section names `OAuth`, `never`, `API key`
    - Validation: `bats tests/run-defaults.bats tests/ai-memory-integration.bats` green
    - Quality: Q1

- [x] 4 - Suite and changelog
  - _Complexity: Trivial | Tests: Unit | Risks: None | Dependencies: Task 1, Task 2, Task 3_
  - Objective: The doc contract pins the three changes and the changelog records them.

  - [x] 4.1 - `tests/run-defaults.bats` and the changelog entry
    - Context:
      - Files: `tests/requester-register.bats` (the anchored-block style)
    - Objective: Five cases pin the flags table, the rules, the frontmatter, the memory wording and the README; the changelog carries one entry per change.
    - ToDo: Write D1–D5 in the anchored-block style with a header index. Add a `### Changed` entry for Fast auto and the effort, and a `### Changed` entry for the memory wording, under `[Unreleased]`.
    - Tests: Unit · `tests/run-defaults.bats` — the suite is its own test
    - Validation: `bats tests/run-defaults.bats` green; `bats tests/` green; `command grep -c -- '--step' CHANGELOG.md` is at least 1
    - Quality: Q1

## Quality Gates

- [x] All acceptance criteria validated
- [x] All task validations pass
- [x] All tests written and passing
- [x] Code integrated (no orphaned implementations)
- [~] Error handling implemented (n-a: prose-only story — no code path handles an error; the suite is the guard)
- [x] Q1 — Unit tests: `bats tests/` green
