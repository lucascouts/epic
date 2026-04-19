---
name: epic
description: >
  Structured output style for the /epic:task skill. Produces consistent,
  scannable layouts for triage proposals, phase gates, run reports, and
  validator/auditor output.
keep-coding-instructions: true
---

# Epic Output Style

Activate with `/output-style epic`. Opt-in; no default behaviour changes.

This style shapes how the `/epic:task` skill emits updates during long operations (Create, Run, Validate). It does **not** override the Epic workflow — only the presentation layer.

## Global Conventions

- Use ATX headings (`## Phase N — <name>`) for section boundaries
- Use `---` as a divider between unrelated sections
- Use short code fences for commands and paths; full block-fences (` ```bash `) only for multi-line blocks
- Omit emoji; prefer plain ASCII markers
- Never paste the full artifact into chat — reference the file path and ask for review
- Use block quotes (`>`) to highlight user-facing decisions and gate actions

## Triage Proposal

Present a **single proposal** as a table, followed by a single confirmation prompt. Never ask each dimension separately.

```
## Triage Proposal

| Dimension | Choice | Reason |
|---|---|---|
| Event | Create | — |
| Type | Feature | User-facing SHALL statements |
| Complexity | Moderate | 5–10 files, 2 integration points |
| Mode | Full | Architectural decisions + cross-cutting |
| Workflow | Requirements-First | Business feature |
| MCPs | context7, perplexity (healthy) | — |
| Output | .epic/stories/003-email-verification/ | — |

> Confirm or adjust?
```

## Phase Gates

After writing a phase artifact, announce the file path and the gate action in a block quote:

```
## Phase 1 — story.md

Written to `.epic/stories/003-email-verification/story.md`.

> [APPROVE] to continue to Phase 2
> [REVISE] to request changes
> [ABORT] to cancel this story
```

Never paste the artifact content. The file IS the artifact.

## Run Report (per sub-task)

```
### Task 2.3 — Add JWT middleware

- [impl] src/middleware/jwt.ts
- [test] src/middleware/jwt.test.ts (3 scenarios)
- [validation] npm test -- jwt — PASS
- [tests] PASS

> Task 2.3 complete. Continue to 2.4?
```

## Phase Gate (batch, --batch=N mode)

```
## Batch Gate — tasks 1.1–1.3

| Task | Status | Notes |
|---|---|---|
| 1.1 | PASS | — |
| 1.2 | PASS | — |
| 1.3 | FAIL | validation: type error on line 42 |

> [CONTINUE] to fix 1.3 inline
> [HALT] to stop and review
```

## Validator + Auditor Report

```
## Validation Report — Story 003

### Validator
- PASS: tasks 1.1, 1.2, 2.1, 2.2
- FAIL: task 2.3 — integration test timeout at 5s

### Auditor
- R2.1 — implemented (src/email/verify.ts:12)
- R2.3 — NOT implemented (no trace)
- Scope creep: src/email/analytics.ts (not in story)
- Code review findings: 2 info, 1 warning

> 2 gaps found. Offer to create follow-up tasks?
```

## Rules

- Tables over prose for multi-dimensional data
- Single confirmation prompts at the bottom of a section, never scattered
- Commands inside `` `backticks` ``; file paths relative to repo root
- Quality gates and deviation numbers cited explicitly (`R2.3`, `T1.2`, `G3`)
- Communication with the user stays in the user's language; headings and artifact snippets stay in English
