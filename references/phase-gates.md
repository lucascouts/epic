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

After the main agent generates the task list structure (with Objective, ToDo, Validation, Requirements — but **without Tests fields**), spawn the **Test Advisor** sub-agent (`subagent_type: test-advisor`, defined in `agents/test-advisor.md`) to define testing requirements per sub-task **and author one test file per Unit/Integration/E2E sub-task** (Unit/Integration are Red-verified in Phase 3; E2E defers Red to Run mode):

> "Analyze these tasks, define which sub-tasks need tests, and author the test files (Unit/Integration as failing tests, E2E with Red deferred to Run mode).
>
> Story requirements: [path to story.md]
> Story scale: [Standard | Full]
> Design testing strategy: [testing strategy section from design.md, if exists]
> Design contract excerpts: [Full mode only — signatures/data shapes from design.md, per Unit/Integration sub-task]
> Task list: [generated tasks WITHOUT Tests fields, and WITHOUT ToDo fields for authoring]
> Story directory: [.epic/stories/NNN-name]
> Project language/framework and test conventions: [detected from codebase analysis]
>
> ### Part 1 — Determine the Tests mapping
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
> Include a 1-line justification for every 'None' and 'Covered by' entry.
>
> ### Part 2 — Author the test files
>
> For each sub-task whose final Tests field type is `Unit`, `Integration`, or `E2E`, author a test file before Phase 3 completes. A `Unit` or `Integration` test is authored as a failing test and Red-verified during Phase 3; an `E2E` test is authored with the story's selected E2E tool and its Red-phase verification is DEFERRED to Run mode — it is not run during Phase 3. Never author for `None`, `Covered by`, or Commit sub-tasks.
>
> **Context boundary — author from the contract, not the implementation.** When authoring a test for a sub-task you may use ONLY: the sub-task's EARS requirement text, the sub-task Objective, the sub-task Tests scenarios, the project test conventions, and — Full mode only — the relevant design.md contract excerpt. You are NOT given the sub-task's `ToDo` field and MUST NOT request or rely on it. The test must describe *what* the behavior should be (its contract), never *how* the implementer will build it.
>
> **Standard-mode contract fallback.** Where the story scale is Standard and no design.md exists, derive the test's contract from the Objective + EARS requirement + Tests scenarios only. Tests authored this way are behavior-level, not signature-pinned — assert observable behavior and outcomes rather than exact internal signatures.
>
> **Where to write.** Write each authored test under the story's `.draft/authored-tests/` directory, mirroring the target test path in the real test tree — e.g. a Tests field targeting `tests/foo.test.ts` is authored at `.epic/stories/NNN-name/.draft/authored-tests/tests/foo.test.ts`. Do NOT write into the project's real test tree; materialization happens later, in Run mode.
>
> **Red-phase verification and record (Unit and Integration).** After authoring each `Unit` or `Integration` test file: run it with the project's test runner, confirm it fails AND fails for the expected reason — the code under test does not yet exist or does not yet behave as specified (e.g. `ReferenceError`, `ImportError`, assertion mismatch). A failure from a broken test (syntax error, wrong import, misconfigured runner) does NOT count as valid Red. Record each confirmed failure in `.draft/red-evidence.yaml` with one entry per authored test (`task`, `test_file`, `target_path`, `command`, `failed`, `reason`, `recorded`).
>
> **Deferred-Red verification and record (E2E).** For an authored `E2E` test, DEFER Red-phase verification to Run mode — do NOT run the test during Phase 3. E2E tests need the application running and an E2E tool environment that Phase 3 does not set up, so Run mode confirms Red just before implementation instead. Record a deferred-Red entry in `.draft/red-evidence.yaml` with `red_deferred: true` and a `tool:` field, OMITTING `failed`, `reason`, and `command` (no run happened). GOTCHA — do **not** write `failed: false` for an E2E entry: Run mode reads `failed: false` as a broken-test error. The `red_deferred: true` entry and a `failed:` key are mutually exclusive — never write both. An E2E entry has this shape:
>
> ```yaml
>   - task: "4.2"                       # E2E — deferred Red
>     test_file: ".draft/authored-tests/e2e/checkout.spec.ts"
>     target_path: "e2e/checkout.spec.ts"
>     tool: "playwright"
>     red_deferred: true                # Red confirmed in Run mode, not Phase 3
>     recorded: 2026-05-17
> ```
>
> **Unexpected green.** IF an authored `Unit` or `Integration` test passes instead of failing, Phase 3 is blocked — do NOT report the test as ready. Revise the test so it genuinely fails for the expected reason; you may revise up to 2 times. IF it still passes after the 2nd revision, escalate to the user — describe the test, the sub-task, and why it will not fail — rather than proceeding. Do not weaken or delete assertions just to force a failure. (An `E2E` test is never run in Phase 3, so this check applies only to Unit/Integration.)
>
> You may write ONLY inside the story's `.draft/` directory (authored tests and `red-evidence.yaml`). You MUST NOT modify any other project file.
>
> Return the Tests mapping, and for each authored test report the authored path and its `target_path`, the Red-verification result (command run, failure reason), and any test that required revision or was escalated."

The main agent merges the Test Advisor mapping into the task list before writing tasks.md to disk. The Test Advisor writes **only** inside the story's `.draft/` directory — the authored test files under `.draft/authored-tests/` and the Red evidence in `.draft/red-evidence.yaml` — and modifies no other project file. Every Unit/Integration test it authors must be confirmed Red before Phase 3 completes; an authored Unit/Integration test that passes blocks Phase 3 until revised (up to 2 attempts) or escalated to the user. An authored E2E test is not run in Phase 3 — its Red verification is deferred to Run mode and recorded as a `red_deferred: true` entry.

### Test Advisor Lite (Fast mode)

For Fast mode, the main agent decides Tests inline (no sub-agent) using this 4-check checklist:

1. **State change?** Does this sub-task create/update/delete data?
   → YES: add at least 1 test that verifies resulting state (not just return code)
   → NO: skip

2. **Boundary?** Does this sub-task handle external input (HTTP, CLI, file)?
   → YES: add 1 happy path + 1 error path test
   → NO: skip

3. **Existing tests?** Does the modified code already have test coverage?
   → YES: verify existing tests still pass (add to Validation)
   → NO: apply rules 1-2 above

4. **Contract rule.** Every implementing (non-Commit) sub-task carries either a `Tests` field or an `Acceptance` field — a sub-task with testable logic gets a `Tests` field, a structural sub-task with no testable logic gets an `Acceptance` field. Commit sub-tasks are exempt (they implement nothing).
   → checks 1-3 say a test is needed: add the `Tests` field
   → checks 1-3 say no test is needed: add an `Acceptance` field (1-3 observable-behavior statements)

Keep it lightweight — 1-2 test entries max per sub-task.

**Plan time vs run time.** Unlike Standard/Full Phase 3, Fast does **not** author tests at plan time — there is no Test Advisor sub-agent, no `.draft/authored-tests/`, and no `red-evidence.yaml`. This checklist only decides *whether* a test is needed and records that decision as the `Tests` or `Acceptance` field. The test-first ordering itself — authoring the test, confirming Red, then implementing — happens at run time (see `run-mode.md`).

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

After the final phase approval (standard and full scales only), generate a traceability table. **Build it from `cross-reference.sh`, never by hand-counting** — manual tallying is error-prone at scale. Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cross-reference.sh" .epic/stories/NNN-name
```

The JSON output carries everything the table needs: `mapping` is the requirement → sub-tasks relation, `orphan_requirements` lists requirements no task declares, `phantom_references` lists task references with no requirement. Render the table directly from those fields — task numbers come straight from `mapping`:

```markdown
| Requirement | Tasks | Status |
|---|---|---|
| R1.1 | 1.1 | Covered |
| R2.3 | — | No task |
| — | 5.1 | No requirement |
```

Rules:
- Built from the `cross-reference.sh` `mapping` field — never hand-counted
- Orphan requirements (`orphan_requirements`; empty `mapping` array) → warning shown to user
- Phantom references (`phantom_references`) → warning shown to user
- Warnings are informational — user decides whether to address them
- For bugfix stories, verify Unchanged Behavior items have regression test tasks
- If `status` is `clean`, show the table briefly and proceed to write
- Skipped for Fast mode (no requirements to trace)
