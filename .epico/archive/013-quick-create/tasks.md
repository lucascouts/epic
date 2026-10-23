---
story: quick-create
type: feature
scale: full
status: archived
version: 2
created: 2026-08-16
---

# Implementation Plan - Quick-Create

## Overview

The allocator first (it is the only scripted surface and single create adopts
it too), then the batch flow reference (the substance), then the SKILL wiring
(routing is last so it never points at a mode that does not exist yet), and an
interface-verification pass over the three-way contract helper ↔ reference ↔
router.

## Task List

- [x] 1 - The one allocator: next-story-number.sh
  - _Complexity: Simple | Tests: Unit | Risks: must scan archive/ too — the 0.3.1 skill's stories-only scan is the known bug shape | Dependencies: None_
  - Objective: Number allocation becomes a tested script instead of prose both create flows re-implement.

  - [x] 1.1 - Script: scan, allocate, reserve
    - Context:
      - Files: `scripts/story-git-status.sh:503-521` (story-dir resolution pattern), `scripts/archive-story.sh` (house JSON contract), `skills/epic/SKILL.md` Output Rules (the allocation prose this replaces)
    - Objective: `next-story-number.sh [--reserve N]` answers with the next number(s), race-aware.
    - ToDo: scan `.epic/stories/` AND `.epic/archive/` for the highest `NNN-` prefix; emit JSON `{next, reserved: []}`; with `--reserve N`, create the N zero-padded placeholder directories `NNN-reserved/` and re-scan after creation — on collision, re-slot the tail and record it in the JSON (`collisions: []`), never removing or overwriting a **foreign** dir — the allocator may re-slot away its own placeholder; refuse past 999 with exit 1 naming the cap; `set -euo pipefail`, exit 0/1/2, diagnostics on stderr.
    - Tests: Unit · `tests/next-story-number.bats` — empty project → 001 and stdout is exactly one JSON object; max across stories AND archive; zero-padding across the width boundary; a plain call reserves nothing on disk; `--reserve 3` returns consecutive zero-padded numbers whose placeholder dirs ARE the reservation (a re-run starts after them); plain call past 999 → exit 1 naming the cap; a `--reserve` crossing the cap refuses whole, reserving nothing; injected concurrent creator between scan and mkdir → tail re-slotted, collision recorded, foreign dir untouched
    - Validation: bats: max across both roots; N consecutive; zero-padding; 999 cap; empty project → 001; pre-created colliding dir mid-test → tail re-slotted
    - Requirements: R2.1, R2.2, R2.3, R2.4
    - Commit: "feat(013): next-story-number.sh — one tested allocator for both create flows"

- [x] 2 - references/batch-create.md: the flow
  - _Complexity: Moderate | Tests: None | Risks: restating grammars that already have a single home — cite, don't copy | Dependencies: Task 1_
  - Objective: The batch mode has its own reference, complete enough that the orchestrator needs nothing else.

  - [x] 2.1 - Derivation, consolidated triage, reservation
    - Context:
      - Files: `skills/epic/SKILL.md` (triage table + single-proposal protocol), `references/context-discovery.md` (analyst procedure — one wave-batch pass, this wave's own precedent)
    - Objective: A source document in, one confirmable N-row proposal out, numbers reserved on confirmation.
    - ToDo: unreadable/empty doc → refuse naming the path, before any reservation (R1.2); derivation yields N proposals each with event/type/complexity/scale from the existing triage table (R1.3); zero story-shaped items → report and stop (R1.4); precheck + MCP + tooling once per batch (R1.5); on confirmation call the allocator with `--reserve N` and rename placeholders to real slugs (R2.1); document the allocator's full JSON contract — `next`, `reserved`, `collisions` — in the reservation section; collision handling surfaces the allocator's `collisions` field (R2.2); an allocator exit 1 at the 999 cap → surface the existing maximum-story-count message and stop before the interview, nothing reserved (R2.4); source doc cross-linked in each story's Related Stories — and the audited story too, when the doc audits one.
    - Tests: None — orchestrator prose, no executable logic; every arm is grep-verifiable in Validation, and the reservation contract it consumes is pinned by Task 1.1 (producer) and Task 4.1 (round-trip)
    - Validation: reference file covers every arm above; `command grep -n 'next-story-number' references/batch-create.md` hits the reservation step
    - Requirements: R1.2, R1.3, R1.4, R1.5, R2.1, R2.2

  - [x] 2.2 - Interview, per-story pipeline, approval, resume
    - Context:
      - Files: `skills/epic/SKILL.md` Clarify Protocol (round caps, headless fallback), `references/list-mode.md:305-315` (batch verdict grammar — cite as the single definition), `references/run-mode.md:18` (materialization guard the pipeline must satisfy)
    - Objective: The conversation collapses; the contract does not.
    - ToDo: one round-set, `[story N/M — slug]` tags, 3-7 per call, ≤3 rounds globally, leftovers become documented assumptions (R3.1); Fast members keep their clarify skip (R3.2); headless = assertion list + logged assumptions, no pause (R3.3); Phase 3 Test Advisor per approved Standard/Full member before materialization — advisors parallel-safe across stories (R4.1); materialization requires a clean validate pass (R4.2); size-ceiling warnings surface in the approval block, splits defer to post-batch create (R4.3); one approval with per-story verdicts `created`/`skipped`/`blocked` + tally, citing the LIST grammar (R5.1); skipped → draft seed `.draft/meta.yaml` with `phase: 0` + proposal + `source-doc:` path (R5.2); materialized → `status: draft` + index refresh via `epic-index.sh` (R5.3); interrupted batch = N per-story drafts, aggregated resume line grouping drafts by the persisted `source-doc:` field, and leftover `NNN-reserved/` placeholders recognized as interrupted reservation (R5.4); state the agent-teams suppression during batch — the proposal belongs to each story's Run, never the batch flow.
    - Tests: None — orchestrator prose, no executable logic; the R3-R5 arms are section-mapping checks in Validation, and the grammar-citation anchor is pinned executably by Task 4.1
    - Validation: every R3-R5 criterion maps to a named section; list-mode grammar cited, not restated
    - Requirements: R3.1, R3.2, R3.3, R4.1, R4.2, R4.3, R5.1, R5.2, R5.3, R5.4

  - Commit: "feat(013): batch-create reference — one interview, N stories, per-story verdicts"

- [x] 3 - SKILL wiring and routing eval
  - _Complexity: Simple | Tests: Unit | Risks: cascade order — the new arm must match before the bare stories LIST arm | Dependencies: Task 2_
  - Objective: The router knows the mode; an eval pins the routing.

  - [x] 3.1 - Routing cascade, dispatch row, Output Rules
    - Context:
      - Files: `skills/epic/SKILL.md` (routing cascade, argument-hint, Mode Dispatch table, Output Rules auto-increment prose)
    - Objective: `stories create --batch <doc>` reaches batch-create.md; allocation prose points at the allocator.
    - ToDo: add the routing arm above the bare `"stories"` arm with an order comment (R1.1); argument-hint gains the form; Mode Dispatch row → `references/batch-create.md`; Output Rules: auto-increment prose now names `scripts/next-story-number.sh` as the allocator for single create too (R2.3).
    - Tests: Covered by Task 4.1 — the dispatch-row/reference/allocator cross-resolution is pinned by the contract bats, and the routing behavior itself is pinned by 3.2's eval cases; a separate suite here would duplicate both
    - Validation: `command grep -n 'batch' skills/epic/SKILL.md` shows the arm above the LIST arm; Output Rules names the script
    - Requirements: R1.1, R2.3

  - [x] 3.2 - Trigger eval for the new arm (fulfilled: trigger eval 5/5 on 2026-09-12 16h32 and again 5/5 on 2026-09-14 21h39, two days apart, same tree and same SKILL.md md5 08440add, run-evals exit 0 both times (logs .draft/logs/batch-trigger-spike.log and batch-stability-2.log); held two days under a stability criterion because the same query had read 0/30 before; original deferral — the arm NOW FIRES — 5/5 measured 2026-09-12 at 16h32, run-evals exit 0, and all three phrasing variants tested alongside it read 5/5 too (log .draft/logs/batch-trigger-spike.log). It is held open anyway. The same query read 0/30 across every earlier measurement, including 0/5 at 06h11 the SAME day on the same tree and the same SKILL.md md5 08440add. A single 5/5 ten hours after a 0/30 is not evidence that the arm works — it is evidence that the instrument moves under it. Closing needs 5/5 sustained across two measurements separated by hours; the follow-up that actually settles this is moving the assertion off the trigger eval and onto a deterministic lint, the way tests/skill-description-coverage.bats already asserts the description side)
    - Context:
      - Files: `evals/trigger-queries.json` (existing routing evals shape)
    - Objective: Routing regression is caught by the eval suite, not by a user.
    - ToDo: add cases: `stories create --batch docs/audit.md` → batch-create; bare `stories` still LIST; `create a story for X` still CREATE.
    - Tests: None — the eval cases this sub-task adds to `evals/trigger-queries.json` ARE the test; its Red/Green is the `bash scripts/run-evals.sh` trigger section in Validation, and a bats duplicate would test the eval runner, not the routing
    - Validation: `bash scripts/run-evals.sh` trigger section passes
    - Requirements: R1.1

  - Commit: "feat(013): route stories create --batch and pin it with a trigger eval"

- [x] 4 - Interface verification: helper ↔ reference ↔ router
  - _Complexity: Simple | Tests: Integration | Risks: None | Dependencies: Task 1, Task 2, Task 3_
  - Objective: The three-way contract is checked as one thing before the story closes.

  - [x] 4.1 - Contract round-trip check
    - Context:
      - Files: `references/batch-create.md`, `scripts/next-story-number.sh`, `skills/epic/SKILL.md`
    - Objective: Producer and consumers agree on every key and pointer.
    - ToDo: bats-driven verification: the JSON keys batch-create.md documents (`next`, `reserved`, `collisions`) are exactly what the script emits (run it against a fixture tree and compare); SKILL's dispatch row and batch-create.md exist and cross-resolve; batch-create.md cites list-mode's grammar section anchor and that anchor exists.
    - Tests: Integration · `tests/batch-create-contract.bats` — documented JSON keys {`next`, `reserved`, `collisions`} round-trip both directions against a live allocator run on a fixture tree; SKILL Mode Dispatch batch row ↔ `references/batch-create.md` ↔ `scripts/next-story-number.sh` cross-resolve (file exists, script parses); the `list-mode.md#…` grammar anchor cited by batch-create.md resolves to a real heading
    - Validation: the new integration bats file passes; full suite green
    - Requirements: R1.1, R2.3
    - Commit: "test(013): pin the helper-reference-router contract"

## Quality Gates

- [x] All acceptance criteria validated (R1.1-R5.4 covered by bats, eval, or grep-verifiable reference content)
- [x] All task validations pass (fulfilled: 3.2's trigger-eval arm, the one clause owed, is discharged — 5/5 on two measurements two days apart; original deferral — every task validation executed and passed except 3.2's trigger-eval arm — see its box. That arm now measures 5/5, and measured 0/30 before, including 0/5 ten hours earlier the same day with identical code. Held open pending a stability criterion rather than ticked on one reading)
- [x] All tests written and passing (allocator + contract suites green; trigger evals pass) (fulfilled: the trigger-evals half is discharged — 5/5 on 2026-09-12 and 5/5 on 2026-09-14; the full suite is 648 green; original deferral — the allocator and contract suites are green and the full suite is 625 green as of 2026-09-12; the clause still owed is the trigger-evals half, for the same reason as 3.2 — the arm now reads 5/5 but read 0/30 before, and a gate resting on a trigger eval flaps without a line of code changing)
- [x] Code integrated (router actually dispatches to the reference; single create actually uses the allocator)
- [x] Error handling implemented (unreadable doc, zero items, collision, 999 cap all have stated arms)
