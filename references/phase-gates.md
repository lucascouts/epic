# Phase Gates

## Gate Protocol

Each phase: generate artifact > **write to disk** > notify user > gate (approve / request changes / abort).

**Write-first, chat-minimal approach:** Artifacts are written directly to the story directory. **Never show full file contents in chat** — this wastes context and clutters the conversation. The user accesses files directly to review.

**Three-step notification pattern:**
1. **Before writing:** "Creating `story.md`..."
2. **After writing:** "Phase 1 written to `.epic/stories/NNN-name/story.md`. Review and approve to continue."
3. **User reviews the file directly** — they can edit it or request changes via chat.

- Do NOT paste artifact contents into the chat — the file IS the artifact
- If the user rejects a phase, offer cascade rollback (see below)
- If the user edits the file directly, read the updated version before proceeding to the next phase
- If the user aborts, delete the entire story directory

## Cascade Rollback

When a user rejects Phase N, determine the cause:

1. Ask: "What needs to change?"
   - **(a) This phase only** — rewrite the current phase artifact with different approach
   - **(b) Previous phase impact** — a requirement/decision in Phase N-1 needs to change
   - **(c) Abort** — cancel this story

2. If **(b)**, generate a **delta reverso** automatically:

```markdown
## Cascade Rollback: Phase N → Phase N-1

### Reason
[Why the current phase revealed a problem in the previous phase]

### Proposed Delta to [phase N-1 artifact]

#### MODIFIED
- [requirement/component]: [old] → [new]

#### IMPACTED
- [downstream items that may need re-evaluation]

### Action
1. Apply delta to [artifact]? [y/n]
2. If yes, re-approve [artifact]
3. Then regenerate current phase with updated constraints
```

3. Apply delta only after user approval, then regenerate the current phase.

## Checkpoint Recovery

During phase generation, save incremental progress to prevent data loss on interruption.

### Checkpoint File Format

Before generating each major section of an artifact, write a `.wip` file:

```yaml
# .epic/stories/NNN-name/.draft/story.md.wip
checkpoint: 3
sections_completed:
  - frontmatter
  - introduction
  - R1-user-registration
sections_pending:
  - R2-user-login
  - R3-logout
  - remaining-sections
```

The partial artifact is written to disk incrementally. A checkpoint marker is inserted:

```markdown
<!-- CHECKPOINT:3 — resume from here -->
```

### Resume Procedure

On detecting a `.wip` file:

1. Read the `.wip` to determine progress
2. Present: "Found incomplete Phase N (M/T sections written: [list]). Resume from [next section], or restart Phase N?"
3. If resume: read the partial artifact, continue generating from the checkpoint marker
4. If restart: delete the `.wip` and partial artifact, regenerate from scratch

### Rules

- `.wip` files are deleted after the phase artifact is complete (before gate)
- `.wip` files are always gitignored
- Only one `.wip` file per artifact at a time

## Reference Files Loaded Per Phase

| Phase | Feature Req-First | Feature Design-First | Bugfix |
|---|---|---|---|
| Phase 1 | `ears-notation.md` + `requirements.md` | `design-guide.md` | `bugfix.md` + `ears-notation.md` |
| Phase 2 | `design-guide.md` | `ears-notation.md` + `requirements.md` | `bugfix-design.md` |
| Phase 3 | `tasks.md` | `tasks.md` | `tasks.md` |

For Fast mode, only `tasks.md` reference is loaded.
For Standard mode, Phase 1 + Phase 3 references are loaded.

On format doubts, load the relevant example from `assets/examples/`.

Additionally, if `CLAUDE.md`, `AGENTS.md`, or `.epic/constitution.md` were found during Context Discovery, their relevant sections are loaded as constraints.

## Architect Sub-agent (Full mode, before Phase 2)

Before generating design.md, spawn the **Architect** sub-agent to research the codebase:

> "Research this project's codebase to provide design context.
>
> Story requirements: [path to story.md]
> Codebase analysis: [Analyst output from Context Discovery]
> Available MCPs: [list of approved MCPs]
>
> Tasks:
> 1. Search for existing patterns similar to what this story needs (e.g., existing handlers, models, middleware)
> 2. Identify conventions the new code should follow (naming, structure, error handling)
> 3. If documentation MCPs are available, fetch current docs for relevant libraries/frameworks
> 4. Note any integration points where the new feature connects to existing code
> 5. **Implementation gotchas:** For each architectural pattern or library usage identified, research known pitfalls, common misconfiguration, or non-obvious setup steps. Format these as concrete warnings: 'GOTCHA: [pattern/library] — [what goes wrong] — [correct approach]'. These will be propagated to task ToDo fields to prevent implementation errors.
>
> Return a concise design context (max 40 lines) that the main agent should consider when writing design.md."

The Architect output is injected as context when generating design.md. Skipped for Fast and Standard modes.

**Gotcha propagation rule:** When the Architect identifies implementation gotchas, the main agent MUST incorporate them into the relevant task ToDo fields as concrete implementation notes — not as vague references to patterns. Example: instead of "use base layout pattern", write "parse each page template together with base.html into a separate template set — calling ExecuteTemplate on the page name alone will produce empty output". The gotcha must survive from research → design → task without losing specificity.

## Test Advisor Sub-agent (Standard + Full, during Phase 3)

After the main agent generates the task list structure (with Objective, ToDo, Validation, Requirements — but **without Tests fields**), spawn the **Test Advisor** sub-agent (`subagent_type: test-advisor`, defined in `agents/test-advisor.md`) to define testing requirements per sub-task:

> "Analyze these tasks and define which sub-tasks need tests, what type, and what to cover.
>
> Story requirements: [path to story.md]
> Design testing strategy: [testing strategy section from design.md, if exists]
> Task list: [generated tasks without Tests fields]
> Project language/framework: [detected from codebase analysis]
>
> For each sub-task, determine:
> 1. Does this sub-task create or modify logic with input/output? → needs test
> 2. Does this sub-task create or modify an HTTP endpoint or handler? → needs integration test
> 3. Is this sub-task purely structural (dirs, configs, boilerplate)? → no test
> 4. Is the logic already tested by another sub-task's tests? → 'Covered by Task X.Y'
>
> Rules:
> - Never duplicate test coverage between sub-tasks
> - Use the project's test conventions (file naming, test framework, directory structure)
> - Every acceptance criterion in story.md must be covered by at least one test across all tasks
> - If design.md defines a testing strategy, ensure all levels (unit, integration, E2E) mentioned there have at least one corresponding task
> - Be conservative: skip tests for Trivial/Simple complexity tasks that are purely structural
> - Commit sub-tasks never have tests
> - Format: `Type · \`path/to/test_file\` — scenario1, scenario2, scenario3`
> - Type is always explicit: Unit, Integration, E2E (because test conventions vary across languages)
> - **Side-effect verification rule:** For state-changing operations in **synchronous architectures** (create, update, delete), at least one integration test per operation MUST verify the resulting state after the operation — not just the HTTP/response status. Example: after POST /items returns 303, query the store/database to confirm the item exists with correct fields. An integration test that only checks the HTTP status code without verifying the side effect is a **shallow test** — flag it with: `⚠ Shallow: verify state after operation`. For **asynchronous or eventually-consistent architectures** (event-driven, CQRS), the test should verify the command was accepted AND include a note on how eventual side-effects are verified (polling, test event listener, or explicit scope exclusion).
> - **Test fidelity rule:** When integration tests must exercise the real interaction between components (e.g., handler rendering a real template, controller calling a real service, API returning a real response), at least one scenario per integration boundary must use the actual dependency — not a simplified stub or inline mock that bypasses the integration surface. If the test setup uses simplified/mocked versions of a dependency (e.g., inline template strings instead of real template files, mock API responses instead of real HTTP calls), flag it with a note: `⚠ Fidelity: uses simplified [dependency] — add at least one scenario with real [dependency] to catch integration mismatches`. This prevents bugs that only manifest when real components interact (wrong data shapes, misconfigured wiring, incompatible interfaces).
>
> Return a mapping of sub-task numbers to their Tests field value:
> - `1.1: Unit · \`path/to/test_file\` — scenarios`
> - `1.2: Covered by Task 1.1`
> - `1.3: None — structural task, no testable logic`
>
> Include a 1-line justification for every 'None' and 'Covered by' entry."

The main agent merges the Test Advisor output into the task list before writing tasks.md to disk. The Test Advisor does NOT modify files — it only returns the Tests field mapping.

### Test Advisor Lite (Fast mode)

For Fast mode, the main agent decides Tests inline (no sub-agent) using this 3-check checklist:

1. **State change?** Does this sub-task create/update/delete data?
   → YES: add at least 1 test that verifies resulting state (not just return code)
   → NO: skip

2. **Boundary?** Does this sub-task handle external input (HTTP, CLI, file)?
   → YES: add 1 happy path + 1 error path test
   → NO: skip

3. **Existing tests?** Does the modified code already have test coverage?
   → YES: verify existing tests still pass (add to Validation)
   → NO: apply rules 1-2 above

Keep it lightweight — 1-2 test entries max per sub-task.

## Reviewer Sub-agent (Full mode only)

After **all phases are written**, spawn the **Reviewer** sub-agent (`subagent_type: reviewer`, defined in `agents/reviewer.md`) for cross-artifact validation:

> "Review these story artifacts for completeness, consistency, and gaps.
>
> Files to read:
> - [path to story.md]
> - [path to design.md]
> - [path to tasks.md]
>
> Check:
> 1. Every requirement in story.md has at least one task in tasks.md
> 2. Every entity in story.md has a data model in design.md
> 3. Every route/endpoint in design.md maps to a handler in tasks.md
> 4. Error paths in story.md are addressed in design.md error handling
> 5. No task references a requirement that doesn't exist
> 6. No design component exists without a corresponding task
> 7. Interface contract consistency: for every data boundary between components in design.md, verify that the producer's output structure contains every field the consumer references. Flag any field referenced by a consumer that is not produced by the corresponding producer task.
> 8. Error propagation in tasks: for every sub-task ToDo that calls a function/method returning an error or failure state, verify the ToDo explicitly mentions error handling. Flag any store/service/repository call in a ToDo that silently discards the result.
> 9. Unused wiring detection: for every public function/class/component defined in the implementation that was specified in design.md, verify it is called or referenced in the application's composition root or in a downstream consumer. Classify orphans as: (a) premature implementation, (b) wiring gap, (c) over-specification.
>
> Return a list of issues found, or 'No issues found' if clean.
> Be specific: cite requirement numbers, task numbers, and component names."

- If the Reviewer finds issues, present them to the user and offer to fix
- If clean, proceed to Traceability Check
- Reviewer does NOT modify files — only reports

## Traceability Check

After the final phase approval (standard and full scales only), generate a traceability table:

```markdown
| Requirement | Tasks | Status |
|---|---|---|
| R1.1 — [description] | T1, T1.1 | Covered |
| R2.3 — [description] | — | No task |
| — | T5 | No requirement |
```

Rules:
- Generated automatically — no user action needed
- Orphan requirements (no tasks) → warning shown to user
- Orphan tasks (no requirement) → warning shown to user
- Warnings are informational — user decides whether to address them
- For bugfix stories, verify Unchanged Behavior items have regression test tasks
- If no orphans found, show the table briefly and proceed to write
- Skipped for Fast mode (no requirements to trace)
