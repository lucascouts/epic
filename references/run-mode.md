# Run Mode

Triggered by `/epic:task stories run NNN`, `/epic:task stories NNN run all`, or `/epic:task stories NNN run N`.

## Procedure

1. **Resolve story** — find `.epic/stories/NNN-*/`
2. **Read tasks.md** — parse all tasks, sub-tasks, and their fields
3. **Determine scope:**
   - `run NNN` or `NNN run all` → all pending tasks (those with `[ ]`)
   - `NNN run N` → specific task N and all its pending sub-tasks
   - `NNN run N.N` → specific sub-task only
4. **Check dependencies** — if a pending task depends on an uncompleted task, warn the user
5. **Detect parallel groups** — identify non-blocking tasks (see Parallel Execution)
6. **Tech stack detection** — scan tasks to build tech profiles (see Tech Stack Detection)
7. **Present execution plan** — show which tasks will be executed, in order, highlighting parallel groups and executor assignment
8. **Wait for user confirmation** before executing

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
/epic:task stories run 004                    ← default (gate after each group)
/epic:task stories run 004 --auto             ← only stop on failure
/epic:task stories run 004 --batch=3          ← gate every 3 groups
/epic:task stories run 004 --gate=commit      ← gate only at commits
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

### Trivial Complexity — Main Agent Inline

The main agent executes directly but MUST follow the same step sequence as the Executor. No step may be skipped. If a Context field exists, context MUST be gathered before implementation.

### Simple+ Complexity — Executor Sub-agent

Spawn an Executor sub-agent with the prompt defined in the Executor Sub-agent section. The orchestrator:

1. Builds the Executor prompt with task fields + story context + design interfaces + tech profile
2. Spawns the Executor (with `isolation: "worktree"` for parallel tasks)
3. Waits for the Executor to complete
4. Reads the Executor's structured report
5. If PASS: check for tech boundaries → spawn Tech Reviewers if needed
6. If FAIL: report to user, ask how to proceed
7. After all reviews pass: mark sub-task `[x]` in tasks.md

### Commit Sub-tasks

Always executed by the main agent (not a sub-agent). Git operations require the main worktree context.

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
> ### Step 1: CONTEXT GATHERING
>
> **This step is mandatory when a Context field exists. It is not optional.**
>
> For each item in the Context field:
> - **Files:** Read each listed file using the Read tool. Note patterns, conventions, and existing code you must integrate with.
> - **Docs:** Fetch documentation using the specified MCP tool. Call the MCP and read the result BEFORE writing any code. If the MCP call fails, try an alternative (brave_web_search, perplexity_search) to find the same information. If no MCP works, note the gap and proceed with caution, flagging it in your report.
> - **Research:** Query the specified MCP for the research topic. Read the results and note findings relevant to implementation.
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
> ### Step 5: TESTS (if Tests field exists)
>
> Create or update the test file at the specified path. Implement the test scenarios listed. Run the tests and report the full output. If tests fail, report and STOP.
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
> 1. If relevant documentation MCPs are available, fetch current docs for [technology] to verify behavior assumptions
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
discoveries:
  - task: "5.3"
    tech: "actix-web"
    finding: "HttpMessage trait must be imported for extensions_mut()"
  - task: "7.1"
    tech: "Tera"
    finding: "Variables in {% if %} must exist in context — default filter only works in {{ }}"
```

The register is:
- Updated after each Executor completes
- Passed as "Project State" context to subsequent Executors
- Included in the Auditor's context during validate-mode
- Written to `.draft/deviations.yaml` for persistence across sessions

## Parallel Execution

When multiple pending tasks share the same dependency set and all dependencies are complete, these tasks are **non-blocking** relative to each other.

### Detection

1. Build dependency graph from tasks.md parent task `Dependencies` field
2. Identify parallel group: tasks where all deps are `[x]` and no task in the group depends on another task in the same group
3. Verify no file conflicts: tasks that modify the same files should NOT be parallelized
4. Present to user: "Tasks N, M, P are independent (all depend only on completed tasks). Execute in parallel? [y/n]"

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
- **Quality gates check** — after all tasks complete (or after the last requested task), run through quality gates and report status
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
