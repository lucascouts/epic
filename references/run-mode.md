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
5. **Detect parallel groups** — identify non-blocking tasks (see [run-parallel.md](run-parallel.md))
6. **Tech stack detection** — scan tasks to build tech profiles (see Tech Stack Detection)
6a. **Recall prior deviations (when memory is available)** — one `memory_query` per run, `deviation OR discovery OR gotcha` plus the tech names from step 6, `limit: 10`. The hits go into every Executor's Project State beside this run's own register, as leads to verify. Absent memory, nothing is added ([mcp-integration.md](mcp-integration.md#memory-mcp))
7. **Materialize pre-authored tests (Standard/Full at engineering level `project` or `product` only)** — before any task execution, copy every file under the story's `.draft/authored-tests/**` into the real test tree at its mirrored path. This step is **idempotent**: if a target test path already exists in the real tree, **skip that file and emit a warning** (it may already exist from a prior Run, a partial `run N.N`, or a manual executor edit — never overwrite it). Files that do not yet exist are copied. Materialization runs once per Run, ahead of step 8. This step applies to **Standard and Full scales at `project` or `product` level only** — they are the ones that stage Test Advisor-authored tests in `.draft/authored-tests/` ([engineering-level.md](engineering-level.md)). **Fast and spike have no `.draft/`, and an `experiment` or `tool` story at any scale stages no test in it**, so such a Run has nothing to materialize and skips this step: Fast writes its tests at run time straight into the real test tree (see Task Execution Flow), and a spike is tasks-only by contract — `tasks.md` and nothing else ([tasks.md](tasks.md#spike-scale-adaptations)). Materialization only **copies** files — it never runs them. A materialized E2E test whose `.draft/red-evidence.yaml` entry carries `red_deferred: true` has its Red confirmed at task-execution time, not here (see Deferred Red for E2E sub-tasks under Task Execution Flow).

   **Materialization also checks the converse, because copying what exists cannot see what is absent.** Before copying, cross the pending task list against `.draft/`: a sub-task whose `Tests:` field is **not `None`** and which has **neither** a file under `.draft/authored-tests/` **nor** an entry in `.draft/red-evidence.yaml` never went through Phase 3. **Do not execute it — stop and report it by number**, then offer to author it now via the Test Advisor (the same one-sub-task flow [refine-mode.md](refine-mode.md#red-evidence-for-added-sub-tasks) defines) or to proceed with the sub-task's `Tests:` field explicitly waived and the waiver recorded in `.draft/deviations.yaml`. Running it as if it were test-first is the one option that is not available: the Executor would be handed a test-first sub-task with no test, and its conditional step 5 would branch on a premise that is false. **The usual cause is a refinement that added the sub-task after Phase 3 ran**, which is why the producing side is fixed there and this is the guard rather than the fix — one end of the wire is not a wire. **Fast and spike are exempt from this check exactly as they are from the copy** — and so is a Standard or Full story at engineering level `experiment` or `tool`, whose tests are written at run time by decision ([engineering-level.md](engineering-level.md)): none of them has authored tests for the cross to read, so the absence it hunts for is their normal state and never evidence of a skipped Phase 3. The exemption is load-bearing for a spike, whose `Tests` field is **optional but permitted** ([tasks.md](tasks.md#spike-scale-adaptations)) — a spike sub-task that does carry `Tests:` would otherwise be refused execution here by a guard about a phase a spike never runs.
8. **Present execution plan** — open with **the recorded line** — scale, requester level, engineering level with its expected multiple, and the plan size in Task List boxes, e.g. `standard · developer · tool (2–3×) · 11 boxes` ([engineering-level.md](engineering-level.md#where-it-is-recorded)) — then show which tasks will be executed, in order, highlighting parallel groups and executor assignment. A parallel group is **stated, not asked**: it runs as a group unless `--serial` was passed (see Parallel Execution)
9. **Wait for user confirmation** before executing

## Execution Flags

Parse flags from `$ARGUMENTS` after the run command:

| Flag | Behavior |
|---|---|
| (default) | Standard and Full: gate after every task group. **Fast runs as `--auto`**: it stops on a validation or test failure and on a doubt the constitution defaults do not cover, and nowhere else — a Fast story is small enough to see whole at the end, and its per-group gate was one round of the question budget spent on "go on" |
| `--auto` | Only stop on a failure or an uncovered doubt — the Fast default, made explicit for Standard and Full |
| `--step` | Gate after every task group in a Fast run — the one way to ask a Fast story for its stops back |
| `--batch=N` | Gate every N task groups |
| `--gate=commit` | Gate only where a group's `Commit:` field is executed |
| `--serial` | Run every task and sub-task in order, including the ones detection proved independent — for a run that must read as a sequence |

Examples:
```
/epic:epic stories run 004                    ← default (gate after each group)
/epic:epic stories run 004 --auto             ← only stop on failure (a Fast story's default)
/epic:epic stories run 004 --step             ← a Fast run that gates after each group
/epic:epic stories run 004 --batch=3          ← gate every 3 groups
/epic:epic stories run 004 --gate=commit      ← gate only at commits
/epic:epic stories run 004 --serial           ← no parallel groups, whatever detection finds
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

**The route is chosen per sub-task, and it is not read off `Complexity`.** `Complexity` is a parent-task field — [tasks.md](tasks.md#metadata-line-fields) makes it *Always on parent* and merely optional on the sub-task — so routing on it alone sends every sub-task of a `Moderate` parent to a sub-agent, the ones whose spec is already closed included. That is the expensive mistake: a sub-agent starts with an empty context and has to re-read what the orchestrator is already holding, so delegating a closed spec buys isolation nobody needed and pays for it in rediscovery.

Read the sub-task's own body and take the **first** route that matches.

| The sub-task is… | How you can tell, from its body | Route | Why |
|---|---|---|---|
| **Verification** | its Objective is to review, audit or validate work that is already done | **Sub-agent, always** | here the fresh context *is* the product — whoever did not watch the author work is the only one who can see what the author cannot |
| **Exploratory** | `Context.Files` lists many files, or names a directory instead of files, or the ToDo says where to look rather than what to change | **Sub-agent** | the throwaway reading dies with the sub-agent instead of settling into the orchestrator's context for the rest of the run |
| **Closed spec** | the ToDo names the files to create or modify, `Validation` carries a runnable command, and `Context` is absent or lists at most a couple of files | **Main agent, inline** — or a **fork** each, when several of them are independent (see Fork Route) | every input is already in hand; a sub-agent would spend its first minutes re-deriving them, and a fork has them already |
| anything else | — | **Sub-agent** | when the sub-task does not say enough to route it, the isolated context is the safe default |

`Complexity` still governs the two columns the route does not decide. A sub-task carrying its own `Complexity` override uses that value; otherwise it inherits the parent's:

| Task Complexity | Tech Review | Context Gathering |
|-----------------|-------------|-------------------|
| Trivial | No | Optional |
| Simple | Only if multi-tech boundary | Required if Context field exists |
| Moderate | Yes, if multi-tech boundary | Required |
| High | Always (even single-tech) | Required + extra research |

**The route never relaxes the protocol.** Inline means the main agent runs the same six steps an Executor would (see Inline Route — Main Agent), gathers context whenever a Context field exists, and closes the box through `close-subtask.sh` like everyone else. It is the same work done in a cheaper place — never less work.

For `--auto` flag: routing unchanged. Sub-agents still run wherever the table sends them, but gates between tasks are removed (only stop on failure).

## Task Execution Flow

For each pending sub-task, in order:

### Run-time test-first ordering

**Two scales and two engineering levels land here, and for the same reason: nothing about their tests exists before the run starts.** Fast and spike are the single-author scales, with no `.draft/` at all; a Standard or Full story at engineering level `experiment` or `tool` skips the Test Advisor by decision ([engineering-level.md](engineering-level.md)) and keeps its `.draft/` for everything else. That is what makes the ordering below a *run-time* one. Standard and Full at `project` or `product` stage their tests at plan time and are unaffected by everything in this section.

For a sub-task of any of them carrying a `Tests` field, the test is authored, run, and confirmed failing **before** implementation begins — the order is **author → Red → Green → Refactor**:

1. **Author** the test from the sub-task's `Tests` field, Objective, and Acceptance contract.
2. **Run** it and confirm **Red** — it must fail, and fail **for the right reason**: the behavior under test is absent or not yet correct. A failure caused by a broken test (syntax error, wrong import, misconfigured runner) is **not** valid Red; correct the test, then re-run, before implementation proceeds.
3. **Green** — implement until the test passes and the Validation command passes.
4. **Refactor** — improve the code while keeping the test and Validation green; revert any refactor that breaks either.

None of them authors tests at plan time — there is no Test Advisor sub-agent, no `.draft/authored-tests/`, and no `red-evidence.yaml`. Test authorship is done by the **main agent** at run time (the `test-advisor` sub-agent is not spawned), and the authored test is written **directly into the project's real test tree** — no `.draft/` staging, which is why step 7 (Materialize pre-authored tests) does not apply to any of them. Red confirmation lives in the run report only; it is not persisted to a file. **For a `layperson` requester it lives there and nowhere else — and what keeps it there is form, not vocabulary: between tool calls, a build turn writes nothing to the chat.** Each step's note — the test authored, its Red and why it was valid, the Green — is collected as it happens and written into `run-report.md` **once, at the end of the turn**: one `Write`, not an `Edit` per step. The turn's only visible text is its closing three lines. A vocabulary rule alone does not hold this line — forbidden words leak in the interstitial text, never in the closing message ([plain-register.md](plain-register.md#ceiling-per-turn)); the form rule is what removes the place they leak into. This mirrors the "Plan time vs run time" note in `phase-gates.md` — the Test Advisor Lite checklist decides *whether* a test is needed; this section is *when* the test-first ordering happens.

A sub-task with no `Tests` field is implemented against its `Acceptance` field plus the Validation command — no test is authored. **The two scales differ in what may be absent**: Fast requires one of `Tests` or `Acceptance` on every implementing sub-task, while a spike may carry neither ([tasks.md](tasks.md#spike-scale-adaptations)) — probe code is throwaway and the Verdict is the deliverable. A spike sub-task carrying only `Validation` is therefore well-formed, and is implemented against that alone. A Standard or Full story at `experiment` or `tool` anchors a structural sub-task on its `Requirements` field with `Tests: None`, and at `experiment` may omit the field, like a spike.

**Unexpected green (every run-time test).** If a test authored at run time **passes on its first run**, the sub-task is blocked — the test is not establishing Red. Revise the test **once** so it fails for the expected reason. If it still passes after that single revision, **escalate to the user** rather than proceed — describe the test, the sub-task, and why it will not fail. Never weaken or delete assertions to force a failure. This is lighter than the Standard/Full 2-attempt cap.

The two routes below — inline and delegated — apply this ordering; Standard/Full sub-tasks at `project` or `product` are unaffected.

### Inline Route — Main Agent

The main agent executes directly but MUST follow the same step sequence as the Executor. No step may be skipped. If a Context field exists, context MUST be gathered before implementation.

For an **inline-routed** sub-task under the run-time ordering above (Fast, spike, or an `experiment`/`tool` story, `Tests` present), the main agent is the **single author** for the whole cycle: it authors the test, runs it, confirms **Red** (for the right reason), then implements inline to **Green**, validates, and **Refactors** — all in the one inline execution. The unexpected-green rule above applies: revise once, then escalate.

**The box is closed the same way it is on the Executor path** — one `close-subtask.sh` invocation, never a hand edit (see Closing a Box). Being the single author makes the main agent the executor here; it does not make it a second writer of the checkbox grammar. It produces the same closing block for itself that an Executor would have reported, and feeds it to the same script.

### Fork Route — inline, in parallel

**A fork is the orchestrator duplicated, not a fresh worker.** It inherits the parent conversation instead of starting fresh, receives the main conversation's exact tool pool, and runs on the main conversation's model. That is precisely the property the Closed-spec row was written around: the row routes inline because a fresh sub-agent would spend its first minutes re-deriving what the orchestrator is already holding. A fork holds it already — so what it buys over inline is not context, it is **overlap**. Several closed-spec sub-tasks that are independent under the Parallel Execution detection run at once instead of one after another.

**The protocol travels in the prompt.** A fork does not carry the Executor's system prompt — it carries the orchestrator's — so the six steps, the sub-task body and the closing block are written into the spawn prompt verbatim. A fork is *inline done elsewhere*: same steps, same `close-subtask.sh` call, same closing block, and the box is closed in the main tree by the orchestrator when the fork returns.

**When to take it — and why it is rarely the answer.** The three tests are the ones the detection in [run-parallel.md](run-parallel.md) already runs, at sub-task granularity: two or more pending sub-tasks route Closed spec, their dependencies are satisfied, and they touch no common file. One closed-spec sub-task alone stays inline. The same maximum of five applies.

**But a fork must first beat inline, and at this plugin's unit size it usually does not.** Ten trivial independent sub-tasks, same machine, same model:

| Route | Wall clock | Cost |
|---|---|---|
| inline, one after another | **10.9 s** | **$0.071** |
| ten forks in one message | 20.7 s | $0.319 |
| ten `general-purpose` sub-agents | 21.2 s | $0.470 |

Spawn overhead dominates when the unit is small, and a sub-task here is small by construction — one Executor pass with a `Validation:` command that proves it alone. **Take the Fork Route only when each sub-task is large enough for overlap to repay the spawn**, and record the reason. A plan whose sub-tasks each finish in under a minute is a plan to run inline.

**Two environment gates, and neither does what its name suggests.**

- `CLAUDE_CODE_FORK_SUBAGENT=1` enables the fork agent type. It is off by default in non-interactive mode (`-p`) and in the Agent SDK, so a run that does not set it gets `Agent type 'fork' not found` and must fall back to inline, in order, without comment.
- `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` is **not a fork setting and is required on every run**, fork or no fork. Under `-p`, sub-agents are backgrounded **by default with fork mode off**: without the variable, spawns report `is_backgrounded: true` whether or not fork mode is on. A backgrounded sub-agent's result arrives only as a completion notification in a later turn — exactly the failure story 026 fixed — and it reaches the Analyst, the Validator and the Auditor as much as any fork. With the variable set, spawns report `is_backgrounded: false`: it **does** restore the foreground, in fork mode and out of it.

**Worktrees are still the isolation.** Forks writing different files at once are as capable of colliding as Executors are; the group runs under the same worktree discipline as Parallel Execution, and boxes are closed only in the main tree, sequentially, after each merge.

### Delegated Route — Executor Sub-agent

Spawn an Executor sub-agent with the prompt defined in the Executor Sub-agent section. The orchestrator:

1. Builds the Executor prompt with task fields + story context + design interfaces + tech profile
2. Spawns the Executor in the foreground — `run_in_background: false`; with `isolation: "worktree"` for parallel tasks, a parallel group being several foreground calls in one message, joined before the next step ([SKILL.md](../skills/epic/SKILL.md#personas))
3. Waits for the Executor to complete
4. Reads the Executor's structured report
5. If PASS: check for tech boundaries → spawn Tech Reviewers if needed
6. If FAIL — the report's closing block carries `outcome: failed`: report to user, ask how to proceed. **No close call is made**: the box stays `[ ]` and nothing is written
7. After all reviews pass: **close the box** — one invocation of `close-subtask.sh` carrying the report's closing block (see Closing a Box). The orchestrator never edits the checkbox itself, and never re-reads tasks.md afterwards: the census and the status transition come back inside the script's JSON

For a **delegated** sub-task under the run-time ordering above (Fast, spike, or an `experiment`/`tool` story, `Tests` present), the test-first cycle is **split** between the orchestrator and the Executor — but the Executor protocol itself is **reused unchanged**:

- **Before spawning the Executor**, the orchestrator (main agent) authors the test, runs it, and confirms **Red** (for the right reason). The unexpected-green rule above applies: revise once, then escalate to the user. The test is written directly into the project's real test tree — none of them stages tests in `.draft/`.
- The orchestrator then passes that confirmed-failing test to the Executor as the read-only **"Pre-Authored Test"** input (its path and contents in the Executor prompt section of the same name). The Executor consumes it exactly like a materialized Standard/Full pre-authored test.
- The Executor runs the **existing six-step protocol with its conditional step 5** (see Executor Sub-agent): step 2 becomes Implementation (Green) — make the pre-authored test pass — and step 5 becomes Refactor. No new or scale-specific Executor protocol is introduced.

### Closing a Box

**Every `[x]` and every `[~]` this engine writes is written by one script.** The orchestrator does not edit a checkbox: not after an Executor, not on the inline route, not when settling a Quality Gate, and never inside a worktree.

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/close-subtask.sh" <NNN|story-dir> <N.N|N|gate:<text-prefix>> \
  [--tilde "<qualifier>: <reason>"]
```

**One box per invocation.** The story number (`010`) works in place of the directory — it resolves against the nearest `.epic/`. The box is named the way the grammar names it: a sub-task (`3.1`), a task group (`3`), or a Quality Gate by a **prefix of its own text** (`gate:All task validations`) — gates carry no number, so a prefix is how one is pointed at.

#### From the closing block to the call

The Executor's step-6 report ends with a machine-liftable **closing block** (defined in [executor.md](../agents/executor.md)); on the Trivial inline path the main agent produces the same block for itself. Lift the arguments from it and change nothing on the way:

| Closing block `outcome` | The call |
|---|---|
| `done` | `close-subtask.sh <story> <task>` — a plain `[x]` |
| `close-tilde` | `close-subtask.sh <story> <task> --tilde "<qualifier>: <reason>"` — a `[~]`, closed **without** the work being done |
| `fulfill` | `close-subtask.sh <story> <task> --fulfill "<evidence>"` — an outstanding `[~] (deferred: …)` becomes `[x]`, carrying both the debt and its discharge ([tasks.md](tasks.md#discharging-a-deferral)) |
| `restate` | `close-subtask.sh <story> <task> --restate "<reason>"` — the box stays `[~] (deferred: …)`, its reason is replaced ([tasks.md](tasks.md#discharging-a-deferral)) |
| `failed` | **no call at all** |

`<qualifier>` is one of the four the grammar defines — `deferred:`, `waived:`, `n-a:`, `superseded-by:` ([tasks.md](tasks.md#checkbox-grammar)) — and the reason is passed through verbatim, into the file rather than into the report.

**Neither `fulfill` nor `restate` is an Executor outcome.** The closing-block enum stays `done` / `close-tilde` / `failed`: an Executor closes a box it just worked, and a deferral is by definition work it could not do. The orchestrator makes this call later, when the external actor the deferral named has finally acted and the evidence exists. `restate` is the same shape of call for the case where the deferral still stands but its reason stopped being true. Both refuse on every state that is not an outstanding deferral, so neither can be used to tidy a box.

**A `failed` outcome makes no close call.** It routes through step 6's FAIL path — report to the user, ask how to proceed — and the box stays `[ ]` with nothing written anywhere. The enum's third arm is consumed here, by *not* closing.

**Group headers close themselves.** When a close leaves its task group with no open `[ ]` children, the script closes the group header `[x]` in the **same write** (R1.7) — so a header normally needs no call of its own, and closing the last child of a group is one invocation, not two. Closing a header directly is refused while a `[ ]` child remains: an `[x]` there would claim work still owed. `--tilde` is the one way to close such a header, because a `[~]` says on its own line why the group is closed without the work. Never close a header by hand to tidy up after a batch.

#### What comes back

**One JSON object on stdout**, every diagnostic on stderr. Measured, closing `1.1` of the dry run below:

```json
{"story":"042-legacy-import","task":"1.1","box":"x","qualifier":null,
 "census":{"total":7,"open":6,"closed":1,"deferred":0},
 "status_written":{"from":null,"to":"in-progress"},
 "validate":{"errors":0,"warnings":0,"status":"pass"},
 "reason":""}
```

Read the run's state from that object, and do **not** re-open tasks.md for it:

- **`census`** — `{total, open, closed, deferred}` over the whole file, task list **and** Quality Gates, measured *after* the write. This is the story's progress; a re-read would only be a second, later opinion about the same file
- **`status_written`** — `{from, to}` when this invocation wrote the story's `status:`, and **`null`** when it wrote none. `from` is `null` on a legacy story that had no field to move. `null` covers every non-transition: rule 4 fired, or the field already read the value the table asked for — rule 1's parenthesised no-op — or no artifact carries frontmatter. The field reports what was **written**, never which rule was evaluated — which is exactly what makes it the archive offer's trigger (see Status Transitions, then End of Run)
- **`qualifier`** — the bare token (`deferred` | `waived` | `n-a` | `superseded-by`), `null` on a plain `[x]`. The reason **text** lives beside the box in tasks.md and is deliberately not carried here
- **`validate`** — the story's verdict `{errors, warnings, status}`, taken by the script itself after both writes; **`null` when no verdict could be taken**. `null` means *no verdict*, never *no errors* — report the story as unvalidated and say so (the script says why on stderr). Errors here **never** roll the marking back: a close whose story fails validation still exits `0`, because the close succeeded and the story has errors, and both are true at once. Surface the counts and carry on
- **`reason`** — why a refusal refused; empty on success

**Why the script validates at all.** A Bash write fires no PostToolUse hook, so the per-marking validation `hooks/hooks.json` would otherwise trigger is carried by the script instead.

#### Exit codes, and refusals

| Exit | Meaning | What the orchestrator does |
|---|---|---|
| `0` | the box was closed | read `census`, `status_written` and `validate` from the JSON and continue |
| `1` | **refused** — nothing was written, not even a temp file | surface `reason` verbatim; never retry with different arguments to get past it |
| `2` | the command line is malformed — **no JSON at all** | fix the call and re-run |

A refusal names its own reason in `reason`, and each arm is a statement about the world rather than about the call:

- the box does not exist in this story's task list, or no Quality Gate opens with that prefix
- the box is **already closed**, naming the state it is in
- the `--tilde` qualifier is outside the four-form grammar
- `--tilde` names a qualifier and gives **no reason**
- the `--tilde` reason smuggles a **second** qualifier token — every reader matches a qualifier anywhere on the line, so the file and the report would end up disagreeing about the same box
- the target is **ambiguous**: more than one line answers to it, and which one was meant is not something a writer may guess
- the story lives under `.epic/archive/` — an archived story is read-only
- the group header still has open children (above), or the story, its `tasks.md`, or the rewrite itself could not be reached

**On a resumed run, "already closed" is benign confirmation, not a failure.** A run interrupted after a close and before its report is replayed over boxes that already carry their mark: read that refusal as *this one is already done*, log it, and move to the next box. Do not "repair" it by editing the file. The script stays strict on purpose — outside a resume, a second close is a real disagreement about what happened, and a silent one is what the refusal exists to prevent.

**Close one story at a time.** `hook-task-completed.sh` picks the **most-recently-modified `tasks.md`** under `.epic/stories/` as the active story, so interleaving closes across two stories mid-run points that hook at whichever story was written last, and its validation then lands on a story nobody was working on. The script itself only ever touches the story it was invoked for — the hazard is in the ordering, not in the write — so finish one story's closes before starting another's.

### Status Transitions

The story's `status:` frontmatter field is **engine-written, never hand-edited**. Run mode owns two of the six values — `in-progress` and `done` — and writes them right after a box in tasks.md is marked. The other four belong elsewhere and Run mode never writes them: `draft` to CREATE, `validated` to VALIDATE, `superseded` to the supersede operation, `archived` to the archive operation. `in-progress` has one further writer, and only for one edge: REFINE mode, when a refinement reopens a story (R1.8) — the table below is the single definition both modes apply. See [SKILL.md](../skills/epic/SKILL.md#lifecycle-status-status) for the full field spec.

**When the check runs:** after **every** marking in tasks.md — each sub-task marking, whichever path executed the sub-task (Trivial inline or Executor, step 7 above), and the end-of-Run quality-gate settlement, which is usually the marking that closes the last box.

**In Run mode, `close-subtask.sh` runs it** — census and table both, inside the same invocation that closed the box (see Closing a Box), so a marking and its status can never be left apart. The orchestrator reads the outcome from the JSON's `status_written` and takes no census of its own. **Refine mode takes the same census by hand**, at its own point (see [refine-mode.md](refine-mode.md#status-census)): a refinement does not mark boxes, it **adds** them — which is the one way a story that already reads `done` gains open work, and there is no close call to carry the write, so REFINE performs the `Edit` itself. The table below is one definition with two performers, never two tables.

Census the boxes **as they now stand** — `open`, `closed` and `deferred` are defined once, in [tasks.md](tasks.md#completion), and the census spans the task list **and** the Quality Gates — then apply the first rule that matches:

| # | After the census | Then |
|---|---|---|
| 1 | no `[ ]` remains **and** no `[~] (deferred: …)` remains | write `done` (nothing to do if the field already reads `done`) |
| 2 | rule 1 did not fire, at least one `[ ]` remains, and `status:` reads **`done` or `validated`** | write `in-progress` — the story was **reopened** (R1.7) |
| 3 | rules 1–2 did not fire, and `status:` is **absent or `draft`** | write `in-progress` |
| 4 | none fired | write nothing |

Rule 1 is the canonical **`done`**: "every box is `[x]` or terminal `[~]`" and "no `[ ]` and no deferred `[~]`" are the same condition read from its two ends (see [tasks.md](tasks.md#completion) — do not restate it as a third variant). Rule 2 is the **reopen** edge, and it sits *below* rule 1 on purpose: a marking that re-completes the story still writes `done`, so reopening is only ever recorded when work is genuinely open again. Rule 3 is the first marking of a story that has not been executed before: absence and `draft` are the two states a run can start from. Rule 4 keeps a story already `in-progress` where it is — the transition is written once, not re-affirmed on every sub-task. A marking that satisfies rule 1 on a story that had reached `validated` writes `done`: work done after a validation is work that validation did not cover, and VALIDATE earns `validated` back on its next pass.

**Reopening is defined by `[ ]`, and only by `[ ]`.** Rule 2 fires on an open box, never on a deferred one — a `done` story that gains a `[~] (deferred: …)` box is not reopened by it, because nobody here owes that work. This is the same reading `validate-story.sh` applies to its ahead-of-checkboxes warning, and it is why the two agree: rule 2 exists precisely so the engine never leaves behind the `done`-with-an-open-box state that warning exists to expose.

**A deferred box blocks `done` — deliberately.** A story whose only remaining non-`[x]` boxes are `[~] (deferred: …)` does **not** get `status: done` from Run mode. Its status stays `in-progress`. Its completeness is visible as the computed condition **`done-except-external`**, which is derived from the boxes at read time and never persisted — LIST renders it `in-progress · done-except-external (N deferred)`. The persisted enum has no value for that condition, and that is deliberate, not an omission: the work is settled in the plan and still owed in the world, so the lifecycle state must not claim the story is finished.

**Writing the transition.** The five rules below are what the write must satisfy, **whoever performs it**. Run mode performs none of them by hand — `close-subtask.sh` does, inside the close — while REFINE and VALIDATE cite this list as the single definition and perform the `Edit` themselves:

1. **`Edit` the frontmatter line — never `Write` the file.** The PostToolUse hook in `hooks/hooks.json` matches **`Write` only**: a `Write` under `.epic/**` re-runs `validate-story.sh`. Transitions written with `Write` would fire a full validation pass after every marking — a validation storm on an advisory metadata update. An `Edit` of the single `status:` line does not trigger the hook. `close-subtask.sh` satisfies the same requirement from the other side: it replaces that one line through a temp file renamed into place, and a Bash write fires **no** PostToolUse hook at all — which is why the script runs `validate-story.sh` once itself, after the marking and the stamp, and reports the verdict in the JSON's `validate` field rather than leaving it to a hook that no longer fires.
2. **The same value in every artifact of the story that carries frontmatter** — `story.md`, `design.md`, `tasks.md`, whichever exist (a Fast story has only tasks.md). One story, one lifecycle state: artifacts declaring different values raise a validation warning naming them. An artifact with no frontmatter is skipped — there is no line to edit, and its silence is never counted as divergence.
3. **Legacy story with no `status:` field — the `Edit` adds it.** Most existing stories predate the field; absence is legal, silent, and never an error. Insert `status: <value>` as a new line inside the frontmatter block, before the closing `---`, in each artifact that has one.
4. **Add only the state this run observed.** The value added is what the engine just saw: a marking that leaves work open is `in-progress`; a marking that satisfies rule 1 is `done`; a census that finds open work on a story reading `done` or `validated` is `in-progress` again. Never back-date `draft` onto a story the engine never saw created, and never write an intermediate value the run did not observe — a legacy story whose first marking also completes it goes straight from no field to `done`, in one write. The field is worth having only because it is evidence; a fabricated prior state is exactly the lie it exists to prevent.
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

1. Run starts. Nothing closed yet -> no call, no census, no write.
   status: still absent. CREATE never ran on this story, so there is no `draft`
   to back-date: the run has observed nothing, so it records nothing.

2. 1.1 passes its reviews -> close-subtask.sh 042 1.1
   {"box":"x","census":{"total":7,"open":6,"closed":1,"deferred":0},
    "status_written":{"from":null,"to":"in-progress"},
    "validate":{"errors":0,"warnings":0,"status":"pass"}}
   6 open, 0 deferred -> rule 1 no. status: absent -> rule 2 no
   (nothing to reopen) -> RULE 3. The script stamps `status: in-progress` into
   story.md, design.md and tasks.md; `from` is null because there was no field
   to move, not because the write was skipped.

3. 1.2 passes -> close-subtask.sh 042 1.2
   {"box":"x","census":{"total":7,"open":4,"closed":3,"deferred":0},
    "status_written":null,"validate":{"errors":0,"warnings":0,"status":"pass"}}
   closed went 1 -> 3 in ONE call: `- [x] 1` closed in the same write as its
   last open child (R1.7), so no second call names the header.
   4 open -> rule 1 no. status: in-progress -> rules 2 and 3 no. RULE 4:
   nothing written, which is what status_written null reports.

4. 2.1 passes -> close-subtask.sh 042 2.1
   {"box":"x","census":{"total":7,"open":2,"closed":5,"deferred":0},
    "status_written":null,"validate":{"errors":0,"warnings":0,"status":"pass"}}
   `- [x] 2` closed with it. 2 open (both Quality Gates). RULE 4.

5. End-of-Run quality gates settled, one call per gate:
   close-subtask.sh 042 "gate:Schema diff reviewed by the data owner"
   {"box":"x","census":{"total":7,"open":1,"closed":6,"deferred":0},
    "status_written":null,"validate":{"errors":0,"warnings":0,"status":"pass"}}
   close-subtask.sh 042 "gate:Load test at 1k rps" \
     --tilde "waived: no load-test rig on this host — user decision"
   {"box":"~","qualifier":"waived",
    "census":{"total":7,"open":0,"closed":7,"deferred":0},
    "status_written":{"from":"in-progress","to":"done"},
    "validate":{"errors":0,"warnings":0,"status":"pass"}}
   0 open, 0 deferred (the waived gate is terminal, so it counts closed)
   -> RULE 1. status: in-progress -> done in all three artifacts, and
   status_written.to == "done" is what sends the run to the archive offer.
```

The same run, with one box deferred instead:

```
4'. 2.1 cannot be executed here — the vendor's production account does not exist
    yet. The Executor reports outcome close-tilde, and the orchestrator lifts it:
    close-subtask.sh 042 2.1 \
      --tilde "deferred: needs the vendor's production account"
    {"box":"~","qualifier":"deferred",
     "census":{"total":7,"open":2,"closed":4,"deferred":1},
     "status_written":null,"validate":{"errors":0,"warnings":0,"status":"pass"}}
    `- [x] 2` still closes with it: a deferred child is not an OPEN child.

5'. Quality gates settled exactly as in step 5. The last call returns
    {"census":{"total":7,"open":0,"closed":6,"deferred":1},
     "status_written":null,"validate":{"errors":0,"warnings":0,"status":"pass"}}
    0 open, 1 deferred -> rule 1 does NOT fire.
    status: in-progress -> rules 2 and 3 no. RULE 4: nothing written.
    The story stays `in-progress`. LIST renders it
    `in-progress · done-except-external (1 deferred)`.
    status_written is null on every call of this run -> NO archive offer.
```

And the reopen edge, on the story left at `done` by step 5:

```
6. A Refine adds a task the story did not have:
   `- [ ] 3 - Backfill the rows the first import dropped`.

   Census (refine-mode, after the merged tasks.md is written — taken BY HAND:
   a refinement adds boxes and closes none, so there is no call to carry it):
   1 open, 0 deferred -> rule 1 no. status: done + an open [ ] -> RULE 2.
   Edit all three artifacts: status: done -> in-progress.
   validate-story.sh -> 0 errors, 0 warnings — without this write it would
   report "status is ahead of the checkboxes".
```

Metadata lines and the `Objective`, `Validation`, `Requirements` and `Commit` fields are elided from all three listings: they carry no checkbox and never enter the census. The JSON objects are elided too, to their load-bearing fields — every call also returns `story`, `task` and `reason`. Every value shown was measured on this fixture, not projected from the rules.

### The Commit Field

**The tail of a group runs in one order:** close the boxes through `close-subtask.sh`, take the status census it runs (which may write `done`), execute the group's `Commit:` field with its pre-authored message, then make the archive offer if the story is complete. The census precedes the commit deliberately — a group that finished is `done` before its commit exists, so the commit records a state the file already claims rather than one it is about to.

**Dependency satisfaction reads the boxes that exist.** A group carrying a `Commit:` field has no Commit box, so nothing in the plan waits on one.

Always executed by the main agent (not a sub-agent). Git operations require the main worktree context, so in a parallel batch the commit runs **after** the merge and never inside a worktree (see Parallel Execution).

**Stage by name, never `git add -A` or `git add .`.** The commit stages the files the sub-tasks named and nothing else. A blanket add sweeps in whatever the run happened to leave beside them — measured 2026-09-19, that is how `.epic/` itself reached the index in a session where the `epic-gitignore.sh` SessionStart hook had not run, which is every Agent SDK session and every `-p` invocation. The hook is a convenience, not a guarantee, and a rule that only holds when a hook fired is not a rule. Staging by name also keeps the generated artifacts, the runtime data file and the compiled binary out of the commit without depending on a `.gitignore` anyone remembered to write.

**When `.epic/` is untracked and no ignore rule covers it, leave it that way and say so in one line.** Do not add an ignore rule on the story's behalf: whether the artifacts belong in git is the workspace's policy to declare, and `scripts/epic-gitpolicy.sh` is what reports a workspace contradicting itself. Silently committing them decides that policy by accident.

**The message is the pre-authored one, verbatim (R3.4).** The `Commit:` message was written at plan time and carries the story's `type(NNN):` anchor — the one `validate-story.sh` lints for and `story-git-status.sh` counts back as `anchored_commits`. Rewording it at commit time spends that anchor, and the story's own commits stop being findable. The Executor never runs `git commit`: it reports, in its closing block, the pre-authored message it validated against, and the orchestrator is what executes it.

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
> Prior deviations and discoveries on this project (from memory — verify before relying on any): [memory hits from step 6a, if any]
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
> Execute the six steps of your Execution Protocol **in order**, exactly as your agent definition states them. Nothing in this prompt restates or overrides the protocol, the report format, the closing block or the prohibitions.
>
> **Only step 2 and step 5 change wording**, and only with what this prompt carries above:
>
> - a **test-first** sub-task (one that carries a "Pre-Authored Test" section) makes step 2 Implementation (**Green** — make that test pass, assertions frozen) and step 5 **Refactor**;
> - a **test-after** sub-task has step 2 Implementation and step 5 **Tests**.

### Executor Rules

- The Executor does NOT commit code. Commits are handled by the orchestrator from each group's `Commit:` field — post-merge, in the main tree, with the pre-authored message verbatim (R3.4). A parallel Executor sits in a worktree, where a commit would land on a branch nobody has merged yet
- The Executor does NOT mark tasks — not `[x]`, and not `[~]` either: `close-tilde` is something its closing block *reports*, never something it writes. The orchestrator does the marking, after verifying the report — and it does it through `close-subtask.sh`, the one sanctioned writer of the checkbox grammar (see Closing a Box). This is not a matter of trust: a box marked anywhere else is a box written outside the only writer that takes the census, stamps the status and validates the story in the same transaction — and, inside a worktree, written into a copy of tasks.md that the merge would then have to reconcile (R3.3)
- The Executor does NOT skip steps. If Context Gathering finds nothing useful, the step still executes and reports "no actionable findings."
- If a step fails (validation, tests), the Executor STOPS and reports. It does not attempt fixes autonomously.
- The Executor receives only the relevant sections of story.md and design.md, not the full files, to keep context focused.

## Multi-Tech Review

When a sub-task's `tech_profile` carries two or more technologies that meet at a boundary (handler to template, app to SQL, API to client), Tech Reviewer sub-agents review that boundary after execution. **Read [run-tech-review.md](run-tech-review.md) when the profile has such a boundary** — the trigger table, the reviewer prompt template and the orchestrator's handling live there. A single-technology sub-task skips it.
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

Two or more pending tasks whose dependencies are all satisfied may run at once, each in its own worktree. **Read [run-parallel.md](run-parallel.md) before grouping anything** — detection at both levels, the file-collision test, the worktree protocol and the merge order live there. A run that takes one sub-task at a time never opens it.
## Run Mode Rules

- **Parallel when proven, sequential otherwise** — a group that passed the three detection checks (see [run-parallel.md](run-parallel.md)) runs in parallel without asking; everything not proven independent runs in order, respecting dependencies. `--serial` forces order for the whole run
- **Stop on failure** — if validation or tests fail, stop and report. Do not continue to next task.
- **No step skipping** — every step in the Executor protocol is mandatory. Context Gathering is not optional when a Context field exists. Validation commands must be executed and their output reported. This is the fundamental rule of Run Mode.
- **Run-time questions count against the story's question budget** ([SKILL.md](../skills/epic/SKILL.md#clarify-protocol)). A decision with a default in the constitution's `## Defaults` block or in the [plain register](plain-register.md#decisions-the-requester-is-not-asked) table is taken and mentioned, never asked — the measured run asked a beginner how to commit on `master`, with three branch options
- **For a `layperson` requester** ([plain-register.md](plain-register.md)): run and show — never ask them to run a command; a stop per group is promised only when `--step` was passed — under the Fast default the run goes to the end and shows the result once, and a doubt the defaults do not cover stops it like a failure would — and when it is promised, it is one group per turn; visible text per turn stays under ~1,500 characters, the rest goes to files. **A build turn writes nothing to the chat between tool calls**: the step-by-step is collected as it happens and written into `run-report.md` once at the end of the turn — one `Write`, never an `Edit` per step (Fast already writes that report) — and the turn's only visible text is its closing three lines — what to type, what it does, and one choice that was made for them. Measured three times: the interstitial notes were what carried "Red confirmado" into the chat, and what pushed the build turn to 1,420–1,766 characters
- **User gates** — controlled by execution flags (default: gate after every task group)
- **Context is fresh** — each Executor reads files directly. The orchestrator passes only metadata (paths, deviations, discoveries) between tasks.
- **Commit granularity** — follow the Commit fields defined in tasks. Never commit in the middle of a task group.
- **Completion** — a story is **complete** when **no `[ ]` remains**: it is **`done`** when every box is `[x]` or terminal `[~]` (`waived:`, `n-a:`, `superseded-by:`), and **`done-except-external`** when the only non-`[x]` boxes are `[~] (deferred: …)`. `done-except-external` is computed at read time, never written to a file. Progress reads `closed/total (+D deferred)`. See [tasks.md](tasks.md#completion)
- **Marking** — every box this mode closes is closed by `close-subtask.sh`, one invocation per box; the orchestrator never edits a checkbox, and never re-reads tasks.md for a census the call already returned. See Closing a Box
- **Lifecycle status** — Run mode writes `status: in-progress` when a census finds the field absent or `draft`, or finds an open `[ ]` on a story reading `done` or `validated` (the reopen edge, R1.7), and `status: done` when a marking leaves no `[ ]` and no deferred `[~]`. **Run mode writes none of it by hand**: the same `close-subtask.sh` invocation that closed the box takes the census, applies the table, stamps every artifact that carries frontmatter — the same value in each, the field added on a legacy story with the state this run observed and never a back-dated one — and reports what it wrote in `status_written`. A failed write is reported and the run continues. See Status Transitions
- **Quality gates check** — after all tasks complete (or after the last requested task), run through quality gates and report status. Settling a gate box is a marking like any other: it is closed with `close-subtask.sh <story> gate:<text prefix>` and carries its own status transition, since it is usually the marking that closes the story's last box
- **Validator integration** — after all requested tasks complete, optionally spawn the Validator sub-agent for verification. Ask: "All tasks completed. Run Validator to verify? (y/n)"
- **Spike promote offer** — when a run **sets** a `scale: spike` story's `## Verdict` to `promote`, offer to create the follow-up story, pre-filled with the spike's `conclusion:`. It is offered **at that moment, not at end of run**, and so lands ahead of the Archive offer — which is the order that works, since a promote whose follow-up was never created is not archivable yet. **The offer is defined once**, in [list-mode.md](list-mode.md#spike-lifecycle) — its gate, the ask-first rule, what is recorded on acceptance and the repeat after an interrupted run all live there, and Run mode reuses them unchanged. A spike's deliverable is the answer, and `promote` is the answer "this needs a story": the offer is how that answer becomes one, instead of a note nobody acts on
- **Archive offer** — when the run's last close came back with **`status_written.to == "done"`** (rule 1 of Status Transitions, written by that invocation), offer `Archive story NNN? [y/n]`; on `[y]` run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/archive-story.sh" <story-dir>` and surface its JSON verdict in full — `blocked` and `refused` included, verbatim, since a refusal nobody sees is the failure this offer exists to end. In a **headless** session do not pause: log the suggestion and proceed. **The offer is defined once**, in [validate-mode.md](validate-mode.md#archive-offer) — gate, prompt text, the deferred-items variant, verdict surfacing and the headless branch all live there, and Run mode reuses them unchanged
- **Index refresh** — regenerate the managed index block at the end of a completed run: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-index.sh"`. Defined once, in [validate-mode.md](validate-mode.md#index-refresh); a non-zero exit warns and never gates the run
- **The recorded line** — the end-of-run report opens with the line the execution plan opened with — scale, requester level, engineering level with its multiple, plan size in Task List boxes — and adds the wall clock and the boxes closed beside it ([engineering-level.md](engineering-level.md#where-it-is-recorded)). It is what the persona harness compares against the control; a report without it cannot be measured

### End of Run — Validator, archive, index

A completed run finishes with these three steps, in this order:

1. **Validator offer** — "All tasks completed. Run Validator to verify? (y/n)"
2. **Archive offer** — made here **only** when the Validator offer was declined or not made. If the user accepted it, VALIDATE runs and makes the archive offer at its own pass point ([validate-mode.md](validate-mode.md#archive-offer), step 3 of the ordering table), where the gate is true anyway because the pass has just written `validated`. The user is asked once, not twice
3. **Index refresh** — last, for the same reason it is last at the pass point: it renders what the steps before it changed. A zero-diff no-op when VALIDATE already refreshed it

**One memory write precedes the three, when memory is available and the register is not empty.** Write the deviation register as one page at `epic/deviations/NNN-<slug>.md`: an H1 `# Deviations of story NNN — <title>` and then the register's entries — deviations and discoveries — as they stand in `.draft/deviations.yaml`, with no secret carried over. One page per story at a stable path, so a re-run of the story rewrites it instead of adding a second. An empty register writes nothing; unavailable memory calls nothing ([mcp-integration.md](mcp-integration.md#memory-mcp)).

**The trigger is the transition, not the census.** Run mode offers the archive only when *this run* wrote `done` — rule 1 of Status Transitions — and it reads that from the closing call's **`status_written.to == "done"`**. Same trigger as before, new source. A run that ends with the story still `in-progress`, or that changed no status at all, makes no offer: the offer marks the moment a story became finished, and a story that was already `done` before the run started did not become finished here. **Never re-derive the trigger from the census.** `census.open == 0` with `census.deferred == 0` is equally true of the story that arrived already `done`, and on that story `status_written` comes back `null` — the field is null on every close that wrote no transition, which is exactly the distinction the offer needs and the only one the census cannot make.

**`done-except-external` never reaches this offer.** Rule 1 writes `done` only when no `[ ]` **and** no deferred `[~]` remains, so a story whose computed condition is `done-except-external` stays `in-progress`, every one of its closes returns `status_written: null`, and it is never offered the archive by Run mode — the deferred-items variant of the prompt is unreachable from here **by construction**, not by omission. It is reachable from VALIDATE, where such a story can pass and take the `in-progress → validated` edge documented in [validate-mode.md](validate-mode.md#status-transition-validated). The asymmetry is deliberate: the offer follows the transition, and only one of the two modes can transition a story that still owes work to the outside world.

## Progress Tracking

During execution, maintain a TodoWrite task list mirroring the tasks being executed. Update in real-time:
- `pending` → tasks not yet started
- `in_progress` → currently executing sub-task (show Executor status)
- `completed` → sub-task passed validation + tech review **and its box has been closed**. Completing a TodoWrite item fires `hook-task-completed.sh`, which validates the *most-recently-modified* story — so completing it right after that story's own close is what points the hook at the right story (see Closing a Box)

## Agent Teams Mode (Experimental, opt-in)

An opt-in alternative execution strategy: several Executors in one team instead of one at a time. **Read [teams-mode.md](teams-mode.md) before offering it** — the trigger conditions, the offer, the hand-off and the exit live there, with the rest of the feature reference. Nothing here changes when teams are off, which is the default.
## Handling Missing Tasks for Quality Gates

If after running all tasks, a Quality Gate is unmet and no existing task covers it:
1. Report the unmet gate
2. Ask user: "Create a new task to cover this gate, close it as N/A, or skip?"
3. If create: generate a new task following the standard format, append to tasks.md, and execute it
4. If N/A: close the gate with `close-subtask.sh <story> gate:<text prefix> --tilde "n-a: <reason>"`, the reason being the user's own (see Closing a Box). Skip closes nothing — the gate stays `[ ]` and the story stays short of `done`
