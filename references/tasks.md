# Tasks Template

Use this template for the `tasks.md` file in all story types and scales.

## Template

```markdown
---
story: <story-name>
type: feature | bugfix
scale: fast | standard | full
version: 1
created: <date>
---

# Implementation Plan - [Story Name]

## Overview

[2-3 sentences: implementation approach, sequencing strategy, and key dependencies.]

## Task List

- [ ] 1 - [Task Name]
  - _Complexity: [level] | Tests: [summary] | Risks: [summary] | Dependencies: [refs]_
  - Objective: [Clear coding goal — what this achieves]

  - [ ] 1.1 - [Sub-task Name]
    - _Complexity: [level]_
    - Context:
      - Files: `path/to/file` (reason to read)
      - Docs: library-name reference (context7)
      - Research: "specific query" (perplexity)
    - Objective: [Concrete coding goal]
    - ToDo: [Technical approach — files to create/modify, patterns to follow]
    - Tests: [Type] · `path/to/test_file` — scenarios to cover
    - Validation: [Command or check that proves it works]
    - Requirements: R1.1, R2.3

  - [ ] 1.2 - [Another sub-task]
    - Objective: [...]
    - ToDo: [...]
    - Validation: [...]
    - Requirements: R1.2

  - [ ] 1.3 - Commit
    - Validation: All tests from 1.1 and 1.2 pass
    - Commit: "feat: description of what this group achieves"

- [ ] 2 - [Next Task]
  - _Complexity: [level] | Tests: [summary] | Risks: [summary] | Dependencies: Task 1_
  - Objective: [...]

  - [ ] 2.1 - [Sub-task]
    - [...]

## Quality Gates

- [ ] All acceptance criteria validated
- [ ] All task validations pass
- [ ] All tests written and passing
- [ ] Code integrated (no orphaned implementations)
- [ ] Error handling implemented
```

## Task Format Rules

### Structure

1. **Maximum 2 hierarchy levels.** Tasks (1, 2, 3) and sub-tasks (1.1, 1.2). No deeper nesting.
2. **Title format:** `- [ ] N - Task Name` — no bold wrappers, no classification prefix in the title.
3. **Metadata line:** First line after task title, always in italics (`_..._`). Contains only: Complexity, Tests, Risks, Dependencies. Pipe-separated.
4. **Sub-tasks inherit** parent metadata. Only declare fields that differ from the parent.
5. **Omit fields** that are not applicable or inherited unchanged. Never fill "None" in a sub-task if the parent already says "None".

### Checkbox Grammar

Every task, sub-task, and Quality Gate carries one of three boxes:

| Box | State | Meaning |
|---|---|---|
| `- [ ]` | open | still owed — the only state that counts as pending |
| `- [x]` | closed | the work was done |
| `- [~]` | closed without doing the work | must say why on the same line |

A `- [~]` box **MUST** carry a qualifier on the **same line**: a box closed without doing the work has to say why. Syntax: `- [~] N.N - Title (qualifier: reason)`.

| Qualifier | Meaning | Terminal? |
|---|---|---|
| `deferred: <reason>` | resolved in the plan, execution awaits an external actor (hardware, operator, live proof) | **no** — the story becomes `done-except-external` |
| `waived: <reason>` | gate consciously dispensed (tool absent, user decision) | **yes** |
| `n-a: <reason>` | not applicable by construction | **yes** |
| `superseded-by: NNN` | this sub-task's scope moved to story NNN | **yes** |

- The qualifier is mandatory. A `[~]` with none, or with an unrecognized one, is a **validation error** naming the line and the four valid forms.
- Matching is token-anchored: `(n-a: ...)` qualifies, the tail of a word like `man-a:` does not.
- If a line carries both `deferred:` and a terminal qualifier, **`deferred:` wins** — the work is still owed by someone.
- Implementing sub-tasks and Quality Gates use the same grammar. There is no per-line-type distinction.

### Completion

One definition, used by every mode that reads a task list:

- A story is **complete** when **no `[ ]` remains**.
- It is **`done`** when every box is `[x]` or terminal `[~]`.
- It is **`done-except-external`** when the only non-`[x]` boxes are `[~] (deferred: …)`.

`done-except-external` is a **computed condition** — derived from the boxes at read time, never written to a file.

Counting, for progress and reporting:

- `total` = every box, whatever its state (`[ ]`, `[x]`, `[~]`)
- `closed` = `[x]` + terminal `[~]`
- `deferred` = `[~]` qualified `deferred:`
- progress renders as `closed/total (+D deferred)` — the `+D` is omitted when `D` is 0

### Metadata Line Fields

The metadata line appears on parent tasks and optionally on sub-tasks (only overridden fields).

| Field | Values | Required |
|---|---|---|
| Complexity | Trivial / Simple / Moderate / High | Always on parent |
| Tests | None / summary (e.g. "Unit", "Unit + Integration") | Always on parent |
| Risks | None / short description | Always on parent |
| Dependencies | None / Task references (e.g. "Task 1", "Task 2.3") | Always on parent |

### Content Fields

Content fields appear in sub-task bodies. Include only fields that are applicable.

| Field | When to include | Description |
|---|---|---|
| Context | Sub-task needs research before implementation | Files to read, Docs (MCP), Research (MCP) |
| Objective | Always | What this achieves (1 line) |
| ToDo | Always (except Commit sub-tasks) | Steps to implement |
| Tests | Sub-task produces testable code (set by Test Advisor) | Type · `path` — scenarios to cover |
| Acceptance | Fast-mode sub-task without a `Tests` field | 1-3 observable-behavior statements |
| Validation | Always | Command or check proving completion |
| Requirements | Standard + Full scales | R1.1, R2.3 format. Omit for fast scale |
| Commit | Last sub-task of a group, or inline on single sub-tasks | Conventional commit message |

### Context Field

The Context field tells the implementer (human or agent) where to gather information before coding.

```markdown
- Context:
  - Files: `path/to/existing.go` (existing auth pattern)
  - Docs: golang-jwt/jwt/v5 API reference (context7)
  - Research: "Argon2id recommended parameters 2026" (perplexity)
```

- Only include sub-fields that apply. If only Docs is needed, omit Files and Research.
- MCP tools in parentheses are suggestions based on servers detected during triage.
- Multiple MCP tools can be suggested: `(context7 or perplexity)`.

### Tests Field

Format: `Type · \`path/to/test_file\` — scenario1, scenario2, scenario3`

For an `E2E` sub-task the format carries the selected E2E tool as an explicit segment: `` E2E · `tool` · `path/to/test` — scenarios `` (for example `` E2E · `playwright` · `e2e/checkout.spec.ts` — scenarios ``). The `tool` segment is the story's selected E2E tool, read from the `## Tooling Decisions` block of `design.md` (the `E2E tool:` line, e.g. `playwright`).

- **Type is always explicit:** Unit, Integration, E2E — because test conventions vary across languages.
- **Path** uses the target language/framework test conventions.
- **Scenarios** are a concise comma-separated list of what to cover.
- When a sub-task's logic is already tested by another task: `Covered by Task X.Y`
- The Tests field is populated by the **Test Advisor** sub-agent (see SKILL.md), not by the main agent.

**Standard + Full scales — the Tests field is _authored_, not merely specified.** During Phase 3, the test-advisor writes the actual test file under the story's `.draft/authored-tests/` directory, mirroring the target test path (the `path` shown in the Tests field). A `Unit` or `Integration` test is authored as a failing test and Red-verified during Phase 3 — the test-advisor runs it to confirm it fails for the right reason and records that Red verification in `.draft/red-evidence.yaml`. An `E2E` test is authored at plan time too, using the story's selected E2E tool, but its Red-phase verification is **DEFERRED to Run mode** — it is not run during Phase 3 (E2E tests need the running application and an E2E environment Phase 3 does not set up); the test-advisor records a deferred-Red entry instead. The `path` in the Tests field is therefore the target location an executor will copy the authored test into — the test itself already exists in `.draft/authored-tests/` before implementation begins.

### Acceptance Field

Format: a bullet list of 1-3 observable-behavior statements, placed in the sub-task body alongside `Validation`.

```markdown
- Acceptance:
  - Loading a well-formed config file returns a populated config object
  - Loading a missing file returns a clear error, not a crash
```

- **Optional** — present only on sub-tasks that have no `Tests` field. A sub-task carries one or the other, never both.
- **Fast-only** — Standard and Full sub-tasks use the EARS R-number in their `Requirements` field as the anchor, so the `Acceptance` field does not exist there.
- **Sub-task-level** — never on a parent task; never on a Commit sub-task.
- **EARS-lite** — plain statements of what is observably true, with no EARS `SHALL` ceremony. Describe the behavior, not how it is built.

### Commit Sub-tasks

- Last sub-task of each task group when the group has 2+ working sub-tasks.
- Contains only **Validation** (aggregated from the group) and **Commit** message.
- If a task has only 1 working sub-task, the Commit field goes inline on that sub-task — no separate Commit sub-task needed.
- Commit messages follow conventional commits: `feat:`, `fix:`, `chore:`, `refactor:`, `test:`.

### Complexity Guide

| Level | Signal | Examples |
|---|---|---|
| Trivial | Single command, config change, boilerplate | Create directory, install deps, add config |
| Simple | Straightforward logic, clear input/output, 1 file | CRUD function, simple validation |
| Moderate | Technical decisions, multiple files, edge cases | Auth middleware, pagination logic |
| High | Cross-cutting concerns, integrations, unknowns | External API integration, complex state |

## Rules

1. **Coding tasks only.** Exclude: deployment, documentation writing, UAT, performance metrics collection.
2. **Every sub-task references requirements** (standard and full scales). Use R1.1, R2.3 format. For bugfixes, reference Current/Expected/Unchanged behavior items. For fast scale, omit this field.
3. **Checkboxes on all items.** The grammar is `- [ ]` open, `- [x]` done, `- [~]` closed without doing the work — and a `- [~]` always carries a same-line qualifier (`deferred:`, `waived:`, `n-a:`, `superseded-by:`). See Checkbox Grammar above.
4. **Dependencies are explicit.** If task 2 requires task 1, the metadata line says so. Sub-task dependencies reference parent.task format (e.g. "Task 1.2").
5. **Validation is testable.** "Works correctly" is not acceptable. "`go test ./models/...` passes" is.
6. **Quality Gates are mandatory.** Always include the quality gates section at the end.
7. **Traceability.** After generating tasks, the skill cross-references every requirement with tasks (standard and full scales). Every requirement must appear in at least one sub-task's Requirements field.
8. **Quality Gate coverage.** Every item in Quality Gates must be addressed by at least one task. No gate should exist without a corresponding task or validation.
9. **Task granularity.** Do not split tasks that affect the same file or that represent sequential steps with no independent verification point between them. Each sub-task should represent a meaningful, independently verifiable unit of work.
10. **Commit coverage.** Every task group must have a Commit field (either as sub-task or inline). No implemented code should remain uncommitted.
11. **Error propagation in ToDo fields.** When a ToDo describes calling a function, method, or service that can fail (returns error, throws exception, returns nullable/optional), the ToDo must explicitly state how the error is handled. Write "call X and return 500 on error" or "call X, on failure re-render with error message" — never just "call X". This applies to all internal calls (store, service, repository, external API), not just user-facing operations.

## Sequencing Guidelines

- Order tasks so each one builds on the previous
- Group related sub-tasks into tasks by component or feature area
- Place infrastructure/setup tasks before feature tasks
- Place integration tasks after the components they integrate
- **Interface verification tasks:** When design.md defines components that exchange data (producer→consumer), the last task group before the final wiring/main task must include a sub-task that verifies the data contract between them. This is not a test — it's a verification that the producer's output structure matches what the consumer expects. Examples: handler data struct contains all fields referenced by the view template; API response type matches the client's expected type; event payload contains all fields the listener reads. This sub-task catches integration mismatches before they reach the final assembly step.

## Gotchas

- Title format: `- [ ] N - Name` — no bold wrappers, no [T1] prefix
- A `[~]` box without a same-line qualifier is a validation error — closing a box without doing the work must say why
- Complete means no `[ ]` remains — not "every box is `[x]`"
- Maximum 2 hierarchy levels (task 1. + sub-task 1.1)
- Coding-only — no deploy, docs, UAT, performance metrics
- Each sub-task references requirement numbers (R1.1, R2.3) — except fast scale
- Metadata line in italics on parent tasks (Complexity, Tests, Risks, Dependencies)
- Tests field is populated by the Test Advisor, not the main agent (standard + full)
- Every task group must have a Commit field (inline or as sub-task)
- Sub-tasks inherit parent metadata — only override what differs

## Fast Scale Adaptations

When generating tasks for fast scale (no story.md):
- Omit `Requirements` field (no requirements to reference)
- Keep the same structure otherwise (metadata line, content fields)
- Quality Gates section is still mandatory
- **Test-or-Acceptance contract rule:** every implementing (non-Commit) sub-task carries either a `Tests` field or an `Acceptance` field — a sub-task with testable logic gets a `Tests` field, a structural sub-task with no testable logic gets an `Acceptance` field. Commit sub-tasks are exempt (they implement nothing).
- If during generation the scope appears larger than expected, recommend upgrading to standard scale
