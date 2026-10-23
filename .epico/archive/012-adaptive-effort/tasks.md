---
story: adaptive-effort
type: feature
scale: fast
status: archived
version: 1
created: 2026-08-16
---

# Implementation Plan - Adaptive Effort

## Overview

Lower the Validator agent's reasoning effort from `high` to `medium` and record
the per-agent effort policy where maintainers will look for it. The 2026-07-23
corpus analysis measured the validate ritual at 44% of all Epic sessions
(~US$ 5/story) doing majority-mechanical work — running scripts and comparing
outputs — while semantic judgment already lives with the Auditor (`max`).
One agent changes; every other tier is frozen by a policy test so future edits
are deliberate, not drift.

## Task List

- [x] 1 - Lower Validator effort and pin the effort policy
  - _Complexity: Trivial | Tests: Unit (bats) | Risks: subtler validation misses — mitigated by Auditor retaining `max` and by validate's script-driven design | Dependencies: None_
  - Objective: Validator runs at `medium`; the full agent-effort policy is asserted by a test and documented.

  - [x] 1.1 - Set `effort: medium` in the Validator agent definition
    - Context:
      - Files: `agents/validator.md` (frontmatter, line ~9), `agents/auditor.md` (tier reference — stays `max`)
    - Objective: The only mechanical-work post-implementation agent stops paying the `high` reasoning tier.
    - ToDo: Change `effort: high` to `effort: medium` in `agents/validator.md` frontmatter. Leave every other agent untouched. If the frontmatter edit fails validation in any consumer, surface the error — do not add fields.
    - Tests: Unit · `tests/agent-effort-policy.bats` — validator declares `medium`; auditor and executor declare `max`; analyst declares `medium`; every `agents/*.md` declares exactly one `effort:` line with a value in {medium, high, max}
    - Validation: `grep -c '^effort: medium' agents/validator.md` returns 1; new bats file passes
    - Commit: "chore(012): lower validator reasoning effort to medium"

  - [x] 1.2 - Record the effort policy in ARCHITECTURE.md
    - Context:
      - Files: `ARCHITECTURE.md` (agents section — has the tool-scoping table to sit beside)
    - Objective: The tier of each agent and the reason are findable without reading nine frontmatters.
    - ToDo: Add a compact table (agent → effort → one-line why) next to the existing agent tool-scoping documentation: executor/auditor `max` (implementation and judgment), architect/reviewer/tech-reviewer/test-advisor `high`, analyst/validator `medium` (discovery and mechanical verification). Note that `tests/agent-effort-policy.bats` enforces the table, so the doc and the code cannot drift silently.
    - Acceptance:
      - ARCHITECTURE.md names the effort tier for all 8 agents and points at the policy test
      - The table's values match the frontmatters byte-for-byte at commit time
    - Validation: table values match `grep '^effort:' agents/*.md` output
    - Commit: "docs(012): record the per-agent effort policy"

## Quality Gates

- [x] All task validations pass
- [x] `tests/agent-effort-policy.bats` green after the change (Red first: it must fail while validator still declares `high`)
- [x] No other agent frontmatter modified (`git diff --stat` touches only validator.md, ARCHITECTURE.md, the new bats file)
