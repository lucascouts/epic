# Run Mode

Triggered by `/epic:epic stories run NNN`, `/epic:epic stories NNN run all`, or `/epic:epic stories NNN run N`.

## Procedure

1. **Resolve story** — find `.epic/stories/NNN-*/`
2. **Read tasks.md** — parse all tasks, sub-tasks, and their fields
3. **Determine scope:**
   - `run NNN` or `NNN run all` → all pending tasks (those with `[ ]` — a `[~]` box is closed and is never pending)
   - `NNN run N` → specific task N and all its pending sub-tasks
   - `NNN run N.N` → specific sub-task only
4. **Check dependencies** — if a pending task depends on a task that is not **satisfied**, warn the user. Satisfied is defined once, in [tasks.md](tasks.md#dependency-satisfaction): every box `[x]` or terminal `[~]`, and a `[~] (deferred: …)` dependency is **not** satisfied
5. **Detect parallel groups** — identify non-blocking tasks (see Parallel Execution)
6. **Tech stack detection** — scan tasks to build tech profiles (see Tech Stack Detection)
7. **Materialize pre-authored tests (Standard/Full only)** — before any task execution, copy every file under the story's `.draft/authored-tests/**` into the real test tree at its mirrored path. This step is **idempotent**: if a target test path already exists in the real tree, **skip that file and emit a warning** (it may already exist from a prior Run, a partial `run N.N`, or a manual executor edit — never overwrite it). Files that do not yet exist are copied. Materialization runs once per Run, ahead of step 8. This step applies to **Standard and Full scales only** — they stage Test Advisor-authored tests in `.draft/authored-tests/`. **Fast mode has no `.draft/` staging**: its tests are authored at run time and written straight into the real test tree (see Task Execution Flow), so a Fast Run has nothing to materialize and skips this step. Materialization only **copies** files — it never runs them. A materialized E2E test whose `.draft/red-evidence.yaml` entry carries `red_deferred: true` has its Red confirmed at task-execution time, not here (see Deferred Red for E2E sub-tasks under Task Execution Flow).
8. **Present execution plan** — show which tasks will be executed, in order, highlighting parallel groups and executor assignment
9. **Wait for user confirmation** before executing

## Execution Flags

Parse flags from `$ARGUMENTS` after the run command:

| Flag | Behavior |
|---|---|
| (default) | Gate after every task group |
| `--auto` | Only stop on validation/test failure |
| `--batch=N` | Gate every N task groups |
| `--gate=commit` | Gate only at Commit sub-tasks |

Examples:
```
/epic:epic stories run 004                    ← default (gate after each group)
/epic:epic stories run 004 --auto             ← only stop on failure
/epic:epic stories run 004 --batch=3          ← gate every 3 groups
/epic:epic stories run 004 --gate=commit      ← gate only at commits
```

## Tech Stack Detection

Before executing any sub-task, the orchestrator detects the technologies involved by scanning:

1. The sub-task's Context, ToDo, and Objective fields for tech references
2. File extensions mentioned in ToDo (`.rs`, `.html`, `.py`, `.ts`, `.go`, `.java`, etc.)
3. Libraries/frameworks mentioned (actix-web, Tera, Django, React, Express, Spring, etc.)
4. The project's manifest file (Cargo.toml, package.json, requirements.txt, go.mod, pom.xml, etc.)

This produces a `tech_profile` for the sub-task:

```yaml
tech_profile:
  language: Rust
  frameworks: [actix-web]
  template_engines: [Tera]
  databases: [SQLite/sqlx]
  key_libraries: [jsonwebtoken, argon2]
  boundaries:             # where different technologies interact
    - handler → template  # server code passes data to template engine
    - handler → database  # application code executes SQL
```

The `tech_profile` is passed to the Executor sub-agent prompt. Boundaries trigger Tech Review after execution.

## Execution Threshold

| Task Complexity | Executor | Tech Review | Context Gathering |
|-----------------|----------|-------------|-------------------|
| Trivial | Main agent (inline) | No | Optional |
| Simple | Sub-agent | Only if multi-tech boundary | Required if Context field exists |
| Moderate | Sub-agent | Yes, if multi-tech boundary | Required |
| High | Sub-agent | Always (even single-tech) | Required + extra research |

For `--auto` flag: threshold unchanged. Sub-agents still run, but gates between tasks are removed (only stop on failure).

## Task Execution Flow

For each pending sub-task, in order:

### Run-time test-first ordering (Fast mode)

For a **Fast-mode** sub-task carrying a `Tests` field, the test is authored, run, and confirmed failing **before** implementation begins — the order is **author → Red → Green → Refactor**:

1. **Author** the test from the sub-task's `Tests` field, Objective, and Acceptance contract.
2. **Run** it and confirm **Red** — it must fail, and fail **for the right reason**: the behavior under test is absent or not yet correct. A failure caused by a broken test (syntax error, wrong import, misconfigured runner) is **not** valid Red; correct the test, then re-run, before implementation proceeds.
3. **Green** — implement until the test passes and the Validation command passes.
4. **Refactor** — improve the code while keeping the test and Validation green; revert any refactor that breaks either.

Unlike Standard/Full, Fast does **not** author tests at plan time — there is no Test Advisor sub-agent, no `.draft/authored-tests/`, and no `red-evidence.yaml`. Test authorship is done by the **main agent** at run time (the `test-advisor` sub-agent is not spawned), and the authored test is written **directly into the project's real test tree** — no `.draft/` staging, so step 7 (Materialize pre-authored tests) does not apply to Fast. Red confirmation lives in the run report only; it is not persisted to a file. This mirrors the "Plan time vs run time" note in `phase-gates.md` — the Test Advisor Lite checklist decides *whether* a test is needed; this section is *when* the test-first ordering happens.

A Fast-mode sub-task with no `Tests` field is implemented against its `Acceptance` field plus the Validation command — no test is authored.

**Unexpected green (Fast).** If an authored Fast test **passes on its first run**, the sub-task is blocked — the test is not establishing Red. Revise the test **once** so it fails for the expected reason. If it still passes after that single revision, **escalate to the user** rather than proceed — describe the test, the sub-task, and why it will not fail. Never weaken or delete assertions to force a failure. This is lighter than the Standard/Full 2-attempt cap.

The two paths below — Trivial inline and Simple+ via the Executor — apply this ordering; Standard/Full sub-tasks are unaffected.

### Trivial Complexity — Main Agent Inline

The main agent executes directly but MUST follow the same step sequence as the Executor. No step may be skipped. If a Context field exists, context MUST be gathered before implementation.

For a **Fast-mode Trivial** sub-task carrying a `Tests` field, the main agent is the **single author** for the whole cycle: it authors the test, runs it, confirms **Red** (for the right reason), then implements inline to **Green**, validates, and **Refactors** — all in the one inline execution. The unexpected-green rule above applies: revise once, then escalate.

### Simple+ Complexity — Executor Sub-agent

Spawn an Executor sub-agent with the prompt defined in the Executor Sub-agent section. The orchestrator:

1. Builds the Executor prompt with task fields + story context + design interfaces + tech profile
2. Spawns the Executor (with `isolation: "worktree"` for parallel tasks)
3. Waits for the Executor to complete
4. Reads the Executor's structured report
5. If PASS: check for tech boundaries → spawn Tech Reviewers if needed
6. If FAIL: report to user, ask how to proceed
7. After all reviews pass: mark the sub-task `[x]` in tasks.md — or `[~]` with a same-line qualifier (`deferred:`, `waived:`, `n-a:`, `superseded-by:`) when the box is closed without the work being done. See [tasks.md](tasks.md#checkbox-grammar) for the grammar. Then apply the story's status transition for that marking (see Status Transitions)

For a **Fast-mode Simple-or-higher** sub-task carrying a `Tests` field, the test-first cycle is **split** between the orchestrator and the Executor — but the Executor protocol itself is **reused unchanged**:

- **Before spawning the Executor**, the orchestrator (main agent) authors the test, runs it, and confirms **Red** (for the right reason). The unexpected-green rule above applies: revise once, then escalate to the user. The test is written directly into the project's real test tree — there is no `.draft/` staging for Fast.
- The orchestrator then passes that confirmed-failing test to the Executor as the read-only **"Pre-Authored Test"** input (its path and contents in the Executor prompt section of the same name). The Executor consumes it exactly like a materialized Standard/Full pre-authored test.
- The Executor runs the **existing six-step protocol with its conditional step 5** (see Executor Sub-agent): step 2 becomes Implementation (Green) — make the pre-authored test pass — and step 5 becomes Refactor. No new or Fast-specific Executor protocol is introduced.

### Status Transitions

The story's `status:` frontmatter field is **engine-written, never hand-edited**. Run mode owns two of the six values — `in-progress` and `done` — and writes them right after a box in tasks.md is marked. The other four belong elsewhere and Run mode never writes them: `draft` to CREATE, `validated` to VALIDATE, `superseded` to the supersede operation, `archived` to the archive operation. See [SKILL.md](../skills/epic/SKILL.md#lifecycle-status-status) for the full field spec.

**When the check runs:** after **every** marking in tasks.md — each sub-task marking, whichever path executed the sub-task (Trivial inline or Executor, step 7 above), and the end-of-Run quality-gate settlement, which is usually the marking that closes the last box.

Census the boxes **as just written** — `open`, `closed` and `deferred` are defined once, in [tasks.md](tasks.md#completion), and the census spans the task list **and** the Quality Gates — then apply the first rule that matches:

| # | After the marking | Then |
|---|---|---|
| 1 | no `[ ]` remains **and** no `[~] (deferred: …)` remains | write `done` (nothing to do if the field already reads `done`) |
| 2 | rule 1 did not fire, and `status:` is **absent or `draft`** | write `in-progress` |
| 3 | neither fired | write nothing |

Rule 1 is the canonical **`done`**: "every box is `[x]` or terminal `[~]`" and "no `[ ]` and no deferred `[~]`" are the same condition read from its two ends (see [tasks.md](tasks.md#completion) — do not restate it as a third variant). Rule 2 is the first marking of a story that has not been executed before: absence and `draft` are the two states a run can start from. Rule 3 keeps a story already `in-progress` where it is — the transition is written once, not re-affirmed on every sub-task. A marking that satisfies rule 1 on a story that had reached `validated` writes `done`: work done after a validation is work that validation did not cover, and VALIDATE earns `validated` back on its next pass.

**A deferred box blocks `done` — deliberately.** A story whose only remaining non-`[x]` boxes are `[~] (deferred: …)` does **not** get `status: done` from Run mode. Its status stays `in-progress`. Its completeness is visible as the computed condition **`done-except-external`**, which is derived from the boxes at read time and never persisted — LIST renders it `in-progress · done-except-external (N deferred)`. The persisted enum has no value for that condition, and that is deliberate, not an omission: the work is settled in the plan and still owed in the world, so the lifecycle state must not claim the story is finished.

**Writing the transition:**

1. **`Edit` the frontmatter line — never `Write` the file.** The PostToolUse hook in `hooks/hooks.json` matches **`Write` only**: a `Write` under `.epic/**` re-runs `validate-story.sh`. Transitions written with `Write` would fire a full validation pass after every marking — a validation storm on an advisory metadata update. An `Edit` of the single `status:` line does not trigger the hook.
2. **The same value in every artifact of the story that carries frontmatter** — `story.md`, `design.md`, `tasks.md`, whichever exist (a Fast story has only tasks.md). One story, one lifecycle state: artifacts declaring different values raise a validation warning naming them. An artifact with no frontmatter is skipped — there is no line to edit, and its silence is never counted as divergence.
3. **Legacy story with no `status:` field — the `Edit` adds it.** Most existing stories predate the field; absence is legal, silent, and never an error. Insert `status: <value>` as a new line inside the frontmatter block, before the closing `---`, in each artifact that has one.
4. **Add only the state this run observed.** The value added is what the engine just saw: a marking that leaves work open is `in-progress`; a marking that satisfies rule 1 is `done`. Never back-date `draft` onto a story the engine never saw created, and never write an intermediate value the run did not observe — a legacy story whose first marking also completes it goes straight from no field to `done`, in one write. The field is worth having only because it is evidence; a fabricated prior state is exactly the lie it exists to prevent.
5. **A failed write is reported, and the run continues.** If an `Edit` cannot be applied — no frontmatter block, the line is not where expected, a concurrent edit conflicts — report it in the Run output and carry on. `status:` is advisory metadata and must never block the run that is producing the actual work.

**Dry run.** `042-legacy-import`: three artifacts (`story.md`, `design.md`, `tasks.md`), none carrying `status:` — a legacy story.

```
tasks.md at the start                       status: in all three artifacts

- [ ] 1 - Import pipeline                   (absent)
  - [ ] 1.1 - Parse the vendor CSV
  - [ ] 1.2 - Load into staging
- [ ] 2 - Cutover
  - [ ] 2.1 - Switch the production reader
## Quality Gates
- [ ] Schema diff reviewed by the data owner
- [ ] Load test at 1k rps

1. Run starts. Nothing marked yet -> no census, no write.
   status: still absent. CREATE never ran on this story, so there is no `draft`
   to back-date: the run has observed nothing, so it records nothing.

2. 1.1 passes its reviews -> mark `- [x] 1.1`.
   Census: 6 open, 0 deferred -> rule 1 no. status: absent -> RULE 2.
   Edit story.md, design.md, tasks.md: add `status: in-progress`.
   validate-story.sh -> 0 errors, 0 warnings.

3. 1.2 passes -> mark `- [x] 1.2`, and `- [x] 1` now that its children are closed.
   Census: 4 open -> rule 1 no. status: in-progress -> rule 2 no.
   RULE 3: nothing written.

4. 2.1 passes -> mark `- [x] 2.1`, `- [x] 2`.
   Census: 2 open (both Quality Gates) -> rule 1 no. RULE 3: nothing written.

5. End-of-Run quality gates settled -> `- [x] Schema diff reviewed by the data owner`,
   `- [~] Load test at 1k rps (waived: no load-test rig on this host — user decision)`.
   Census: 0 open, 0 deferred (the waived gate is terminal, so it counts closed)
   -> RULE 1.
   Edit all three artifacts: status: in-progress -> done.
   validate-story.sh -> 0 errors, 0 warnings.
```

The same run, with one box deferred instead:

```
4'. 2.1 cannot be executed here — the vendor's production account does not exist yet.
    Mark `- [~] 2.1 - Switch the production reader (deferred: needs the vendor's
    production account)` and `- [x] 2`.

5'. Quality gates settled exactly as in step 5.
    Census: 0 open, 1 deferred -> rule 1 does NOT fire.
    status: in-progress -> rule 2 no. RULE 3: nothing written.
    The story stays `in-progress`. LIST renders it
    `in-progress · done-except-external (1 deferred)`.
    validate-story.sh -> 0 errors, 0 warnings.
```

Metadata lines and the `Objective`, `Validation`, `Requirements` and `Commit` fields are elided from both listings: they carry no checkbox and never enter the census.

### Commit Sub-tasks

Always executed by the main agent (not a sub-agent). Git operations require the main worktree context.

### Deferred Red for E2E sub-tasks

Most Standard/Full pre-authored tests have their Red confirmed by the Test Advisor at plan time (Phase 3) — their `.draft/red-evidence.yaml` entry records `failed: true` with a `reason` and `command`. **E2E tests are the exception.** An E2E test usually needs the application running, a browser driver, fixtures, or a built artifact — none of which exist at plan time — so the Test Advisor authors the E2E test but **defers** its Red confirmation, recording an entry with `red_deferred: true` and **omitting** `failed`, `reason`, and `command` (no run happened in Phase 3). The orchestrator owns that deferred Red check, and it runs at task-execution time:

For a sub-task whose pre-authored test's `red-evidence.yaml` entry carries `red_deferred: true`:

1. **Before spawning the Executor**, the orchestrator runs the materialized E2E test and confirms it **FAILS (Red)** — the behavior under test is absent or not yet correct. This is the same "valid Red" bar used elsewhere: a failure caused by a broken test (syntax error, wrong import, misconfigured runner, missing driver) is **not** valid Red.
2. **If the deferred Red does not fail as expected** — it passes, errors out, or cannot be run — the orchestrator does **not** spawn the Executor. **STOP and escalate to the user**, describing the test, the sub-task, and the unexpected result.
3. If Red is confirmed, the orchestrator spawns the Executor for the sub-task as normal.
4. **After the Executor completes**, the orchestrator runs the same E2E test again and confirms it now **PASSES (Green)**. A still-failing test is a failed sub-task — report it and stop, as with any validation/test failure.

**The Executor's protocol is unchanged.** The deferred-Red check is **orchestrator-owned**: the orchestrator runs the test before and after, the Executor never performs it. The Executor still receives the pre-authored E2E test as its read-only **"Pre-Authored Test"** input and therefore still treats the sub-task as a **test-first sub-task** — its conditional step 2/5 branching (step 2 Implementation/Green, step 5 Refactor) applies exactly as documented in the Executor Sub-agent section. No new or E2E-specific Executor protocol is introduced; `red_deferred` changes only *when and by whom* the Red is confirmed, not the Executor's six steps.

**Absent `failed` is valid for a `red_deferred` entry.** Run mode MUST distinguish two states of the `failed` key in `red-evidence.yaml`:

- `failed` key **absent** on a `red_deferred: true` entry — **valid**. No Phase 3 run happened by design; Red is confirmed at run time by the flow above. Run mode does **not** treat a missing `failed` key on a `red_deferred` entry as missing or invalid Red evidence, and does **not** block on it.
- `failed: false` **present** — a broken test that did not establish Red. This blocks Phase 3 and is **distinct** from an absent `failed` key. It is never produced by a `red_deferred` entry.

## Executor Sub-agent

The Executor is a dedicated sub-agent that implements a single sub-task following a strict 6-step protocol. The protocol is the Executor's entire purpose — no step may be skipped or reordered.

### Executor Prompt Template

> "You are implementing a sub-task from a structured story plan. Your tech context is [tech_profile.language] with [tech_profile.frameworks].
>
> ## Your Task
>
> **Sub-task:** [number] - [name]
> **Objective:** [objective field]
> **ToDo:** [todo field]
> **Validation:** [validation field]
> **Tests:** [tests field, if exists]
> **Requirements:** [requirements field]
>
> ## Story Context
>
> [Relevant requirements from story.md — only the Rn referenced by this sub-task]
>
> ## Design Context
>
> [Relevant component interfaces from design.md — only the components this sub-task implements, including exact struct definitions and function signatures]
>
> ## Project State
>
> Files created/modified by previous tasks: [list with paths]
> Design deviations from previous tasks: [deviation register entries, if any]
>
> ## Pre-Authored Test
>
> [INCLUDED ONLY when this sub-task has a pre-authored failing test. Path to the materialized test file plus its contents. This is a **read-only input** — you implement against it to make it pass; you do NOT author, replace, or weaken it. If this section is absent, this is a test-after sub-task: author tests yourself in step 5 as before.]
>
> ## Available MCPs
>
> [List of verified MCPs from triage: context7 for docs, brave/perplexity for research, etc.]
>
> ---
>
> ## Execution Protocol
>
> You MUST execute these steps IN ORDER. Do not skip any step. Do not proceed to the next step until the current one is complete. Report what you did in each step.
>
> **The protocol REMAINS SIX STEPS.** Only step 2 and step 5 change wording depending on whether the sub-task carries a pre-authored test:
>
> - A **test-first sub-task** has a pre-authored failing test supplied as a read-only input (the "Pre-Authored Test" section above). For it, step 2 is **Implementation (Green)** and step 5 is **Refactor**.
> - A **test-after sub-task** has no pre-authored test. For it, the protocol is unchanged: step 2 is **Implementation** and step 5 is **Tests**.
>
> ### Step 1: CONTEXT GATHERING
>
> **This step is mandatory when a Context field exists. It is not optional.**
>
> For each item in the Context field:
> - **Files:** Read each listed file using the Read tool. Note patterns, conventions, and existing code you must integrate with.
> - **Docs:** Fetch the documentation BEFORE writing any code — use the MCP named in the Context field if it is available to you, otherwise `WebFetch`/`WebSearch`. If every lookup fails, note the gap and proceed with caution, flagging it in your report.
> - **Research:** Query the research topic — use the MCP named in the Context field if it is available to you, otherwise `WebSearch`. Read the results and note findings relevant to implementation.
>
> Even if no Context field exists, read any files you will modify (if they already exist) to understand the current state.
>
> After gathering context, note any findings that affect implementation:
> - Framework behaviors that differ from common assumptions
> - API signatures or function behavior discovered from docs
> - Deprecation warnings or version-specific changes
> - Known pitfalls or gotchas from research
>
> ### Step 2: IMPLEMENTATION
>
> Implement the changes described in the ToDo field.
>
> For each item in the ToDo:
> - Follow it literally. If it says "handle error", implement error handling. If it says "redirect to /login", implement a redirect. If it says "return 500 on failure", use graceful error handling — not panic, unwrap, expect, or unhandled throw.
> - Apply findings from Step 1. If the docs revealed a framework behavior (e.g., template engine fails on missing variables, form deserialization happens before handler), adapt the implementation accordingly.
> - When the ToDo specifies a function signature, match it against the Design Context. If you need to deviate, document WHY.
>
> **Test-first sub-task — Implementation is the Green phase.** When the prompt carries a "Pre-Authored Test" section, your goal in this step is to make that pre-authored failing test pass. The test is a **read-only input** — you implement against it, you do not author or replace it.
>
> **Frozen-test rule.** The pre-authored test's **assertions are immutable** — you MUST NOT modify them, weaken them, or delete them to get a passing run. The test's **imports and signature call-sites** (how it imports the unit under test and how it invokes it) MAY be adjusted **only** to match an INTENTIONAL design deviation you confirm in step 3 — never for any other reason. Each such surface adjustment MUST be recorded in `.draft/deviations.yaml` with the field `test_surface_adjusted: true`.
>
> **Behavior-changing deviation — STOP and escalate.** If an intentional design deviation would change *what an assertion expects* (the behavior the test pins), rather than only the call surface (imports / signature), you MUST **STOP and escalate** instead of proceeding. Never edit an assertion to resolve the conflict.
>
> ### Step 3: DESIGN FIDELITY CHECK
>
> Before proceeding to validation, compare your implementation against the Design Context:
>
> 1. **Signatures:** Every function/method/class you implemented — does the name, parameters, and return type match design.md?
> 2. **Error handling:** Every error path in the ToDo — does the implementation use the specified approach? Map each ToDo error instruction to the actual code.
> 3. **Data structures:** Every struct/type/model — do the field names, types, and constraints match design.md?
> 4. **Behavioral contracts:** If this sub-task produces output consumed by another component (e.g., handler → template, API → client), verify the output contains every field the consumer expects.
>
> If you find a deviation:
> - **INTENTIONAL** (better approach discovered during implementation): document in a Note with the reason WHY the deviation is better. Include what the design says, what you did instead, and why.
> - **ACCIDENTAL** (oversight, shortcut, copy-paste error): fix it before proceeding.
>
> ### Step 4: VALIDATION
>
> Run the Validation command specified in the sub-task. Report the FULL output — do not summarize as "it passed". If the command fails, report the failure and STOP. Do not attempt to fix and retry without reporting first.
>
> ### Step 5: REFACTOR or TESTS (conditional)
>
> This step depends on whether the sub-task carries a pre-authored test. It is still **step 5 of the same six-step protocol** — only the wording changes.
>
> **Test-first sub-task → REFACTOR.** With the pre-authored test now passing (step 2) and Validation green (step 4), improve the implementation: remove duplication, clarify names, simplify structure. Use the passing test plus the Validation command as a **regression safety net** — re-run both after refactoring and confirm they **stay green**. The frozen-test rule still applies: do not modify the test's assertions. If a refactor cannot keep the test and validation green, revert it. If refactoring surfaces a behavior-changing design deviation, **STOP and escalate** — never edit an assertion.
>
> **Test-after sub-task → TESTS (if a Tests field exists).** Create or update the test file. Implement the test scenarios listed. Run tests and report full output. If fail: **STOP**.
>
> ### Step 6: REPORT
>
> Return a structured report:
>
> ```
> ## Executor Report — Sub-task [number]
>
> ### Files Created/Modified
> - [path]: [created | modified] — [brief description]
>
> ### Context Gathered
> - [MCP/source]: [key finding relevant to implementation]
> - [MCP/source]: [another finding]
> (or "No Context field — read existing files only")
>
> ### Design Deviations
> - [component]: design says [X], implemented [Y] — reason: [why]
> (or "None — all signatures and contracts match design")
>
> ### Validation Result
> [PASS | FAIL]
> [Full command output]
>
> ### Test Result
> [PASS | FAIL | No tests for this task]
> [Full test output if applicable]
>
> ### Warnings
> - [anything unexpected discovered during implementation]
> (or "None")
> ```"

### Executor Rules

- The Executor does NOT commit code. Commits are handled by the orchestrator via Commit sub-tasks.
- The Executor does NOT mark tasks as `[x]`. The orchestrator does this after verifying the report.
- The Executor does NOT skip steps. If Context Gathering finds nothing useful, the step still executes and reports "no actionable findings."
- If a step fails (validation, tests), the Executor STOPS and reports. It does not attempt fixes autonomously.
- The Executor receives only the relevant sections of story.md and design.md, not the full files, to keep context focused.

## Multi-Tech Review

When a sub-task's tech_profile includes 2+ distinct technologies that interact at a boundary, the orchestrator spawns Tech Reviewer sub-agents AFTER the Executor completes successfully.

### When to Trigger

Detect technology boundaries from the tech_profile:

| Boundary | Examples |
|----------|---------|
| Server code → template engine | Rust handler + Tera, Python view + Jinja2, Express + EJS, Spring + Thymeleaf, Phoenix + HEEx, Laravel + Blade |
| Application code → raw SQL | Any language with sqlx, raw queries, query builders |
| Backend → frontend contract | API response consumed by React/Vue/Angular client, SSR hydration |
| Application → external API | HTTP client calling third-party services |
| Application → message queue | Producer/consumer message format contracts |

If only one technology with no boundary interaction: skip review.

### Tech Reviewer Prompt Template

> "You are a [technology] specialist reviewing code for correctness at the [technology] boundary.
>
> ## Files to Review
>
> [Files created/modified by the Executor]
>
> ## Design Contract
>
> [Relevant interface from design.md for this boundary]
>
> ## Your Focus
>
> Review ONLY the [technology] aspects. Check for issues that a generalist implementer would miss.
>
> **For template engines** (Tera, Jinja2, Handlebars, EJS, Blade, Thymeleaf, HEEx, ERB, etc.):
> - Every variable referenced in the template (in interpolation, conditionals, loops, assignments) is provided by the handler in ALL rendering paths
> - When the same template is rendered by multiple handlers (e.g., GET empty form vs POST with validation errors), verify EACH handler provides all required variables
> - The template engine's behavior with missing or empty variables is handled correctly for the engine's mode (strict vs lenient)
>
> **For SQL/database:**
> - All queries use parameterized placeholders — no string interpolation
> - Foreign key references point to existing entities or the code handles the missing-entity case
> - Types in application structs match the database column types
>
> **For API contracts:**
> - Response structures match what consumers expect (field names, types, nesting)
> - Error response format is consistent across endpoints
> - HTTP status codes match the design specification
>
> **For external integrations:**
> - Request/response types match the external API documentation
> - Error responses from the external service are handled (timeouts, 4xx, 5xx)
> - Authentication credentials are not hardcoded
>
> ## Protocol
>
> 1. Fetch current docs for [technology] to verify behavior assumptions — via a documentation MCP if one is available to you, otherwise `WebFetch`/`WebSearch`
> 2. Review the implementation files against your focus area
> 3. Report:
>    - **PASS** — no issues found at this boundary
>    - **ISSUES** — list each issue with file path, line reference, and what is wrong
>
> Do NOT modify files. Only report."

### Orchestrator Handling of Tech Review

- If all Tech Reviewers report PASS: proceed to next sub-task
- If any report ISSUES:
  1. Present issues to user (in `--auto` mode: attempt fix first)
  2. Spawn a new Executor instance with the original task + issues to fix
  3. Re-run only the affected Tech Reviewers
  4. Maximum 2 fix cycles. If still failing after 2 cycles, stop and escalate to user
- Tech Reviews are skipped for Commit sub-tasks

## Context Passing Between Tasks

Each Executor sub-agent starts with a fresh context. The orchestrator bridges information between tasks to prevent context loss.

### What Gets Passed to Next Executor

After each sub-task completes, the orchestrator extracts from the Executor's report:

1. **Files modified** — paths only (the next executor reads them fresh via Read tool)
2. **Design deviations** — any intentional deviations that downstream tasks must know about. Example: "AppConfig::from_env returns Result<Self, String> instead of Result<Self, AppError> — downstream callers must handle String errors"
3. **Framework discoveries** — gotchas found during context gathering that apply to future tasks. Example: "Tera requires all variables referenced in {% if %} to exist in context, even with empty values"

When a sub-task has a pre-authored failing test, the orchestrator also passes the **pre-authored test as a read-only input** — the materialized test file's path and contents in the Executor prompt's "Pre-Authored Test" section. The Executor implements against that test to make it pass and does not author, replace, or weaken it.

### What Does NOT Get Passed

- Full file contents (executor reads files directly)
- Implementation details beyond deviations (executor follows its own ToDo)
- Validation output (only PASS/FAIL status)

### Deviation Register

The orchestrator maintains a deviation register across task execution:

```yaml
# .epic/stories/<name>/.draft/deviations.yaml
deviations:
  - task: "2.1"
    component: "AppConfig::from_env"
    design: "Result<Self, AppError>"
    actual: "Result<Self, String>"
    reason: "AppConfig is used in main before AppError module is available"
    impact: "main.rs uses unwrap_or_else — no downstream AppError conversion needed"
  - task: "3.1"
    component: "AppError::Display"
    design: "user-friendly messages only"
    actual: "includes variant prefix 'Database error:'"
    reason: "single Display impl serves both logging and response"
    impact: "HTTP error responses leak error category name"
  - task: "4.2"
    component: "parse_config signature"
    design: "parse_config(path: &str)"
    actual: "parse_config(path: &Path)"
    reason: "callers already hold a Path; &str forced a redundant conversion"
    impact: "call surface only — no behavior change"
    test_surface_adjusted: true   # executor adjusted the pre-authored test's call-site to match
discoveries:
  - task: "5.3"
    tech: "actix-web"
    finding: "HttpMessage trait must be imported for extensions_mut()"
  - task: "7.1"
    tech: "Tera"
    finding: "Variables in {% if %} must exist in context — default filter only works in {{ }}"
```

A deviation entry carries the optional boolean field `test_surface_adjusted`. It is `true` on a deviation where the Executor adjusted a pre-authored test's imports or signature call-sites to match that INTENTIONAL deviation (the only test edit the frozen-test rule permits — assertions are never touched). The field is absent on deviations that did not require any test surface change.

The register is:
- Updated after each Executor completes
- Passed as "Project State" context to subsequent Executors
- Included in the Auditor's context during validate-mode
- Written to `.draft/deviations.yaml` for persistence across sessions

## Parallel Execution

When multiple pending tasks share the same dependency set and all dependencies are **satisfied** ([tasks.md](tasks.md#dependency-satisfaction) — deliberately not the same test as story *completion*), these tasks are **non-blocking** relative to each other.

### Detection

1. Build dependency graph from tasks.md parent task `Dependencies` field
2. Identify parallel group: tasks where all deps are **satisfied** ([tasks.md](tasks.md#dependency-satisfaction) — `[x]` or terminal `[~]`; a dep closed as `[~] (deferred: …)` is **not**) and no task in the group depends on another task in the same group
3. Verify no file conflicts: tasks that modify the same files should NOT be parallelized
4. Present to user: "Tasks N, M, P are independent (all depend only on satisfied tasks). Execute in parallel? [y/n]"

### Execution

If confirmed:
1. **Create an isolated worktree per task** using the native `EnterWorktree` tool (Claude Code v2.1.105+). Each worktree branches from the current HEAD into `.epic/worktrees/<story>-<task>/` so parallel Executors cannot collide on the same files.
   - **Fallback (< v2.1.105):** spawn each Executor with `isolation: "worktree"` (Agent tool option) or manually create worktrees via `Bash + git worktree add`.
2. Each Executor follows the full 6-step protocol in its isolated worktree
3. Wait for all Executors to complete
4. Run Tech Reviews for each Executor's output (can be parallel)
5. If ALL pass: merge worktrees sequentially, then run Commit sub-task for the group. Call `ExitWorktree` on each worktree after merging to clean up.
6. If ANY fail: report failures, ask user how to proceed (retry failed tasks, skip, or abort). Worktrees of failed executors are preserved for inspection until the user decides.

### Rules

- Commit sub-tasks are ALWAYS sequential (post-merge), executed by the main agent
- If user declines parallel execution, fall back to sequential (no worktrees created)
- Maximum parallel Executors: 5 (to avoid resource exhaustion)
- Each parallel Executor gets the full story context (story.md, design.md relevant sections)
- Deviation register is merged after parallel execution completes (before commit)
- `EnterWorktree` integrates with Claude Code checkpointing — `ExitWorktree` is cancellable and safe to call on already-exited worktrees

## Run Mode Rules

- **Sequential by default** — tasks run in order, respecting dependencies
- **Parallel when possible** — independent tasks can be parallelized (see Parallel Execution)
- **Stop on failure** — if validation or tests fail, stop and report. Do not continue to next task.
- **No step skipping** — every step in the Executor protocol is mandatory. Context Gathering is not optional when a Context field exists. Validation commands must be executed and their output reported. This is the fundamental rule of Run Mode.
- **User gates** — controlled by execution flags (default: gate after every task group)
- **Context is fresh** — each Executor reads files directly. The orchestrator passes only metadata (paths, deviations, discoveries) between tasks.
- **Commit granularity** — follow the Commit fields defined in tasks. Never commit in the middle of a task group unless a Commit sub-task says so.
- **Completion** — a story is **complete** when **no `[ ]` remains**: it is **`done`** when every box is `[x]` or terminal `[~]` (`waived:`, `n-a:`, `superseded-by:`), and **`done-except-external`** when the only non-`[x]` boxes are `[~] (deferred: …)`. `done-except-external` is computed at read time, never written to a file. Progress reads `closed/total (+D deferred)`. See [tasks.md](tasks.md#completion)
- **Lifecycle status** — Run mode writes `status: in-progress` when a marking finds the field absent or `draft`, and `status: done` when a marking leaves no `[ ]` and no deferred `[~]`. Always with `Edit` on the frontmatter line, never `Write`; the same value in every artifact that carries frontmatter; on a legacy story the `Edit` adds the field with the state this run observed, never a back-dated one. A failed write is reported and the run continues. See Status Transitions
- **Quality gates check** — after all tasks complete (or after the last requested task), run through quality gates and report status. Settling a gate box is a marking like any other: apply the status transition after it, since it is usually the marking that closes the story's last box
- **Validator integration** — after all requested tasks complete, optionally spawn the Validator sub-agent for verification. Ask: "All tasks completed. Run Validator to verify? (y/n)"

## Progress Tracking

During execution, maintain a TodoWrite task list mirroring the tasks being executed. Update in real-time:
- `pending` → tasks not yet started
- `in_progress` → currently executing sub-task (show Executor status)
- `completed` → sub-task passed validation + tech review

## Agent Teams Mode (Experimental, opt-in)

See [teams-mode.md](teams-mode.md) for the full feature reference (enable/disable/status, limitations, troubleshooting). This section covers only the Run-phase dispatch logic.

### Trigger conditions

Offer Agent Teams as an alternative execution strategy when **all** hold:

1. `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is active — verify via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/teams-config.sh" status` and parse `.state == "active"`.
2. The execution plan has **2 or more** independent parallel groups that touch disjoint files.
3. Each group has 3+ sub-tasks (amortises the team spawn/cleanup overhead).
4. No group depends on another group's output mid-Run.

If the conditions do not hold, use the `EnterWorktree` path (Parallel Execution section above). Do **not** ask the user to pick a strategy when teams cannot realistically help — the question is a distraction.

### Strategy prompt (only when conditions hold)

> "This story has N independent task groups and agent-teams is enabled.
> Two execution strategies available:
>
> 1. **Worktrees (default)** — parallel `EnterWorktree` per group, sub-agents via the Agent tool
> 2. **Agent Teams (experimental)** — dedicated teammates per group with shared task list and direct messaging. Higher token cost, but teammates can coordinate and challenge each other.
>
> Choose strategy?"

### If Agent Teams chosen

1. **Team lead** = the current (main) session — reads story, manages deviation register, handles commits.
2. **One teammate per group** — spawn via natural language referencing Epic's existing agent definitions: *"Spawn a teammate named track-<name> using the `executor` agent type with this prompt: …"*. Teammates inherit the `executor` body, tool allowlist, model, and effort. They do **not** inherit `skills:` / `mcpServers:` (irrelevant — `executor` does not declare them).
3. **Shared task list** mirrors tasks.md — each group has one lead task the teammate claims.
4. **Tech Reviews** — after each teammate reports done, the lead spawns Tech Reviewer sub-agents (not teammates — Tech Review is short-lived and single-turn).
5. **Validation** — the `TaskCompleted` hook already runs `validate-story.sh` on completion.
6. **Commits** — always by the lead, sequentially, after all teammates complete.
7. **Cleanup** — the lead explicitly calls *"clean up the team"* at end of Run so the next Run-in-session starts fresh (one team at a time per [limitations](https://code.claude.com/docs/en/agent-teams#limitations)).

### Rules specific to agent-teams mode

- **No nested teams** — teammates (running as `executor`) cannot spawn their own Agent sub-agents. If a track needs heavy research via sub-agents, switch that story back to worktrees mode.
- **No `/resume` of teammates** — if the session is interrupted, resume will lose the in-process teammates. Tell the lead to spawn fresh teammates for the remaining groups.
- **Maximum 5 teammates** — matches the worktree parallel limit; keeps coordination overhead manageable.
- **Split-pane display** — optional; requires tmux or iTerm2. In-process (single-terminal) works everywhere and is the default per [agent-teams#display-mode](https://code.claude.com/docs/en/agent-teams#choose-a-display-mode).
- **Fallback is automatic** — if spawning the team fails for any reason (runtime bug, missing upstream support, permission denial), the Run proceeds with the worktree path and reports the fallback in the Run report.

## Handling Missing Tasks for Quality Gates

If after running all tasks, a Quality Gate is unmet and no existing task covers it:
1. Report the unmet gate
2. Ask user: "Create a new task to cover this gate, mark as N/A, or skip?"
3. If create: generate a new task following the standard format, append to tasks.md, and execute it
