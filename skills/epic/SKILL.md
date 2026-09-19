---
name: epic
description: >
  Structured story creation, management, and execution for features and
  bugfixes — requirements, design, task breakdown, and implementation
  with scale-adaptive intelligence. Trigger for "let's plan this before
  coding", "break this into tasks", or any request to formalize
  development work. Use when asked to: create, refine, or expand a
  story; list or manage existing stories; run/execute tasks from a
  story; validate implementation against plan. It also routes the
  management modes: init, instant for disposable work that nobody will
  maintain, migrate a story to the current format,
  create --batch to draft many stories from one document, archive,
  supersede, and teams. Also trigger when the user says "create an epic
  for X", "document this feature", "structure this sprint", "what
  needs to be done to implement X?", "list stories", "run story",
  "execute tasks", "validate implementation" — even without saying
  "epic" or "story" explicitly.
argument-hint: "[description] or [instant <description>] or [stories migrate NNN] or [stories create --batch <doc>] or [stories] or [stories full] or [stories run|validate|refine NNN] or [stories supersede NNN --by MMM] or [stories NNN run N|all] or [init]"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - Bash
  - TaskCreate
  - TaskGet
  - TaskList
  - TaskUpdate
  - TodoWrite
  - Agent
  - AskUserQuestion
  - EnterWorktree
  - ExitWorktree
paths:
  - ".epic/**"
  - "tasks.md"
  - "story.md"
---

# Epic

Scale-adaptive story framework for features and bugfixes. Invoked as `/epic:epic`. Use ultrathink for complex design decisions.

## Scope (MUST read first)

Epic exists solely to **create, structure, and manage epics and their stories** (`story.md` + `design.md` + `tasks.md`). Before running any mode, verify the request fits this purpose.

**Refuse immediately** if the request is for any of the following — respond with a one-line refusal and the suggested alternative:

| Request pattern | Refuse because | Tell the user |
|---|---|---|
| "Review this code / PR / branch" | No story artifact to anchor to | Use `/review`, `/security-review`, or `/code-review` |
| "Security review of …" | Same | `/security-review` |
| "Refactor X" (no existing story) | Skips design-fidelity contract | Create a Fast/Standard story first, then `run` it |
| "Analyze / explain this codebase" | Epic artifacts are the only valid analysis container here | `/gsd-explore`, `/gsd-map-codebase`, or plain chat |
| "Write this script / change this file" (no approved sub-task) | Implementation only happens inside Executor for an approved sub-task | Create a story (often Fast) then run its tasks |
| "Debug this incident / failing test" | Debug flow is out-of-scope | `/gsd-debug` |
| "Architecture advice for existing code" | No design.md to validate against | `/tab` or `/gsd-explore` |

The refusal is hard. Do not partially engage, do not propose an Epic-wrapped version unless the user rewrites the request as story/task work. See [`../../PURPOSE.md`](../../PURPOSE.md) for the full boundary.

## Prerequisites

- `bash`, `git`, and `jq` available on `PATH`
- Claude Code **v2.1.105+** (for conditional hooks `if:`, skill `effort`/`paths:`, description caps, background monitors, `EnterWorktree.path`). Core planning features work on v2.1.85+ but with degraded ergonomics.
- Optional MCP servers for research. See [mcp-integration.md](../../references/mcp-integration.md) for the full priority order and cost policy. Default search MCP is `brave-search`; `perplexity` is **never** the default (premium/high-cost).

## Runtime dependency precheck (MANDATORY before Standard/Full triage)

Standard and Full modes depend on two interactive tools that may not be loaded in every environment. The skill MUST verify both are callable **before** entering the Triage Protocol and MUST notify the user explicitly when either is missing — do not degrade silently.

| Tool | Required by | Fallback if missing |
|---|---|---|
| `AskUserQuestion` | Clarify Protocol (multi-choice rounds) | Numbered-list confirmation prose |
| `TaskCreate` / `TaskList` / `TaskUpdate` (interactive sessions) **or** `TodoWrite` (headless/Agent SDK) | Task tracking during Clarify / Run modes | Plain-text bullet list in chat |

### Procedure

1. **Detect session kind:**
   - If the function schema list exposes `TaskCreate` → interactive session. Use `TaskCreate` / `TaskList` / `TaskUpdate`.
   - Else if `TodoWrite` is exposed → headless or Agent SDK. Use `TodoWrite`.
   - Else → neither is available.

2. **Verify `AskUserQuestion`:**
   - If the function schema list exposes `AskUserQuestion` → proceed.
   - Else → missing.

3. **Notify the user explicitly** before starting Triage, using this exact format:

   ```
   Runtime dependency check:
   - Task tracking: [TaskCreate | TodoWrite | MISSING — will use plain-text bullet fallback; progress not persisted]
   - AskUserQuestion: [available | NOT LOADED — Clarify will use numbered-list fallback; may affect UX quality]
   ```

4. **For Fast mode:** skip this precheck entirely. Fast mode does not use Clarify rounds or multi-phase task tracking.

5. Never omit the notification when a tool is missing. Silent degradation is a bug — the user must know that UX is reduced so they can abort and restart in a richer environment if desired.

## Project State

### Existing stories
!`ls -1d .epic/stories/*/ 2>/dev/null | sed 's|.*/\(.*\)/|\1|' | head -20 || echo "(none)"`

### Constitution
!`if [ -f .epic/constitution.md ]; then head -30 .epic/constitution.md; else echo "(none)"; fi`

### Git state
!`git rev-parse --short HEAD 2>/dev/null && git diff --stat HEAD 2>/dev/null | tail -1 || echo "(not a git repo)"`

## Concepts

| Term | Meaning |
|---|---|
| **Epic** | This plugin / the `/epic:epic` command |
| **Story** | A unit of work: feature, bugfix, or initiative |
| **Task** | An implementation action inside tasks.md |

## Personas

Sub-agents with specialized roles. Scale determines which personas are activated.

### Planning Personas (story creation)

| Persona | Role | Scale | Agent file |
|---|---|---|---|
| **Analyst** | Context discovery, domain research, checklist generation | standard + full | `agents/analyst.md` |
| **Architect** | Codebase pattern research, design context gathering | full only | `agents/architect.md` |
| **Test Advisor** | Authors one failing test per Unit/Integration sub-task during Phase 3, runs Red verification, records red-evidence | standard + full at engineering level `project` or `product` (Phase 3, and per added sub-task in Refine); an `experiment` or `tool` story writes its tests at run time, as Fast does ([engineering-level.md](../../references/engineering-level.md)) | `agents/test-advisor.md` |
| **Reviewer** | Cross-artifact review, gap detection, consistency check | full only | `agents/reviewer.md` |

### Execution Personas (task implementation)

| Persona | Role | Scale | Agent file |
|---|---|---|---|
| **Executor** | Implements a sub-task following the strict 6-step protocol; step 5 is conditional (Refactor for test-first sub-tasks, Tests for test-after). Ends its report with a machine-liftable **closing block** — sub-task id, outcome (`done` / `close-tilde` + qualifier + reason / `failed`) and the pre-authored commit message it validated against. **Marks no box and runs no `git commit`**: the orchestrator lifts that block into `scripts/close-subtask.sh`, the one writer of the checkbox grammar | all scales (delegated route) | `agents/executor.md` |
| **Tech Reviewer** | Reviews implementation at technology boundaries; holds `Bash` for measurement only (never mutating files or git state), so a finding resting on a runnable check carries the command and its output | all scales (multi-tech tasks) | `agents/tech-reviewer.md` |

### Post-Implementation Personas (validation)

| Persona | Role | Scale | Agent file |
|---|---|---|---|
| **Validator** | Runs validation commands and tests per completed task, writing the verdict to `.draft/validation-report.yaml` before any prose summary | all scales | `agents/validator.md` |
| **Auditor** | Compares implemented code against story + design artifacts, writing `.draft/audit-report.yaml` before any prose summary | all scales | `agents/auditor.md` |

The **main agent** (this skill) orchestrates: generates artifacts (story.md, design.md, tasks.md) during planning, delegates to Executors during run-mode, and coordinates Validators/Auditors during validation. The main agent retains conversation context with the user and handles git operations (commits) — post-merge, with the pre-authored message verbatim. It closes boxes too, but never by editing one: it invokes `scripts/close-subtask.sh` with the Executor's closing block, and the script performs the marking, the census and the `status:` stamp in a single transaction (a `failed` outcome makes no call at all).

**Every sub-agent this skill spawns runs in the foreground — `run_in_background: false` on the Agent call.** The orchestrator's next step is the sub-agent's result: the Analyst's scan feeds the proposal, the Test Advisor's tests gate Phase 3, the Executor's closing block closes the box, the Validator's and the Auditor's verdicts end the mode. A turn ended to wait for a sub-agent is a turn the requester spends saying "still waiting". Measured on 2026-09-17: a Standard run for a beginner spawned the Test Advisor in the background, spent 12 of 12 user turns on "ainda tá fazendo?", wrote no code and cost US$ 7; a developer's run did the same for ten turns. Both registers assume the assistant is working, not waiting. A parallel Executor group is not an exception: it is several foreground calls in one message, joined before the next step.

### MCP Integration

During triage, detect and health-check available MCPs. Load [mcp-integration.md](../../references/mcp-integration.md) for the full health-check procedure and category mapping.

Key rule: Never suggest an MCP without a successful health-check first. For Fast mode: skip MCP detection.

### Preferred Tooling

During triage, detect available E2E testing tools and the `frontend-design` aid, then resolve which to use. Load [preferred-tooling.md](../../references/preferred-tooling.md) for the favorite/optional tiers, the detection procedure, and the no-favorite recommendation.

Key rule: prefer a favorite (`playwright`, `chrome-devtools`); an optional tool is selected only when already installed AND the task context calls for it. Unlike MCP detection, preferred-tooling detection runs in **all modes, including Fast**.

## Command Routing

When invoked via `/epic:epic`, parse `$ARGUMENTS` using this cascading routing table:

```
$ARGUMENTS parsing:

(empty) or (free text not starting with "stories" or "init" or "archive")
  → CREATE mode

"init"
  → INIT mode (project configuration wizard)

"instant <description>"
  → CREATE mode, pinned: fast scale, `experiment` level, security floor only,
    no technical question round. The disposable-work shortcut (see Instant).

"stories migrate NNN [--apply]"
  → MIGRATE mode (normalize a legacy story into the canonical shapes;
    dry run by default — scripts/migrate-story.sh writes nothing without --apply)

"stories create --batch <doc>"
  → BATCH-CREATE mode (one interview, N stories derived from a source document)
    ORDER IS THE GUARD: this arm is matched BEFORE the bare "stories" arm below.
    The cascade is prefix-loose, so placing it lower would let LIST claim the
    invocation and the mode would be unreachable.

"stories"
  → LIST mode (summary)

"stories full"
  → LIST mode (detailed, all stories with tasks)

"stories NNN"
  → LIST mode (detailed, single story NNN)

"stories run NNN [--auto|--batch=N|--gate=commit|--serial]"
  → RUN mode (all pending tasks of story NNN)

"stories validate NNN"
  → VALIDATE mode (Validator + Auditor on story NNN)

"stories refine NNN"
  → REFINE mode (delta workflow on story NNN)

"stories archive NNN[-MMM]|--done"
  → ARCHIVE mode (delegates to scripts/archive-story.sh, one call per story;
    a range or --done is expanded here — the script takes exactly one story)

"stories supersede NNN --by MMM"
  → SUPERSEDE mode (replace story NNN with MMM: banner, status, index, archive offer)

"stories teams {status|enable|disable}"
  → TEAMS mode (manage experimental agent-teams flag for this project)

"stories NNN run all [--auto|--batch=N|--gate=commit|--serial]"
  → RUN mode (all pending tasks of story NNN)

"stories NNN run N"
  → RUN mode (specific task N of story NNN)

"stories NNN run N.N"
  → RUN mode (specific sub-task N.N of story NNN)

"archive"
  → ARCHIVE LIST mode (show archived stories)
```

**NNN** = story number (001, 002...) — matches directory prefix in `.epic/stories/`.
**N** = task number, **N.N** = sub-task number.

### Story Resolution

When a command references `NNN`:
1. Glob `.epic/stories/NNN-*/` to find the matching directory
2. If not found: "Story NNN not found. Available stories:" + list
3. If multiple matches (shouldn't happen with zero-padded numbers): show options

## Mode Dispatch

| Mode | Trigger | Reference to load |
|---|---|---|
| **Create** | `/epic:epic` or `/epic:epic <description>` | Continue below (Triage + Clarify + Phases) |
| **Instant** | `/epic:epic instant <description>` | Continue below — Create with the three pins of [Instant](#instant--the-disposable-work-shortcut) |
| **Migrate** | `/epic:epic stories migrate NNN [--apply]` | Run `scripts/migrate-story.sh` (or `bin/epic-migrate`) — dry run by default; it reports the rewrites as JSON and the diff on stderr, and writes only with `--apply` |
| **Batch Create** | `/epic:epic stories create --batch <doc>` | Load [batch-create.md](../../references/batch-create.md) — one interview, N stories; numbers come from `scripts/next-story-number.sh` |
| **Init** | `/epic:epic init` | Load [init-mode.md](../../references/init-mode.md) |
| **List** | `/epic:epic stories [full] [NNN]` | Load [list-mode.md](../../references/list-mode.md) |
| **Run** | `/epic:epic stories run NNN` or `NNN run N\|all` | Load [run-mode.md](../../references/run-mode.md) |
| **Validate** | `/epic:epic stories validate NNN` | Load [validate-mode.md](../../references/validate-mode.md) |
| **Refine** | `/epic:epic stories refine NNN` | Load [refine-mode.md](../../references/refine-mode.md) |
| **Archive** | `/epic:epic stories archive NNN[-MMM]\|--done` | Load [list-mode.md](../../references/list-mode.md) (Archive Command) — the mode resolves which stories to archive and calls `scripts/archive-story.sh` once per story; it never moves a directory or writes a manifest entry itself |
| **Supersede** | `/epic:epic stories supersede NNN --by MMM` | Load [supersede-mode.md](../../references/supersede-mode.md) |
| **Teams** | `/epic:epic stories teams {status\|enable\|disable}` | Load [teams-mode.md](../../references/teams-mode.md) |
| **Expand** | User says "based on", "extends" existing story | Create new story referencing source |
| **CI/Headless** | Programmatic invocation via Agent SDK | Load [ci-mode.md](../../references/ci-mode.md) |

**For Create mode, continue reading this file. For all other modes, load the referenced file first.**

## Instant — the disposable-work shortcut

`/epic:epic instant <description>` is **Create with three pins, not a fourth scale.** It writes the same `tasks.md` every Fast story writes; what it removes is the deciding, not the artifact.

| Pin | Value | Why it is pinned rather than asked |
|---|---|---|
| `scale` | `fast` | the floor every story starts from ([engineering-level.md](../../references/engineering-level.md#how-the-level-is-read)) |
| `engineering` | `experiment` | typing `instant` **is** the answer to the first cascade question — asking it again would be asking someone to repeat themselves |
| Quality legend | the **security floor** only — supported runtime, secrets, dependency CVEs ([quality-catalog.md](../../references/quality-catalog.md#the-security-floor--three-items-no-level-drops)) | the floor is three commands and no configuration file; anything dropped below it would be dropping the machine's safety, not the story's ceremony |

**No technical question round.** The intent cascade is already answered and does not run. A technical choice the request leaves open is taken as a recommended default and recorded on its line — never turned into a question. The requester asked for the short path; spending their turn on a menu is the one thing `instant` exists to avoid.

**What it does not remove.** The three pins are the whole difference. Triage still runs, the plan is still written, and every box still carries a `Validation:` that proves it alone.

**What it does cost, said plainly.** `instant` does not only drop ceremony — **it drops protections the person using the program would have had**, and it drops them without asking. Measured across three runs on 2026-09-19, two requesters and two languages, the shortcut decided alone to: leave out an operation the same requester had asked for when asked; make an unreadable answer cost a point where the un-shortcut run re-asked the question for free; delete a record without confirming; and ship an interface in a language the requester had chosen differently when consulted. In one run it produced **no README at all** — less documentation than the same request answered with no Epic in the session.

That is a fair bargain for something disposable, and it is not a bug. It stops being fair the moment it is silent. So:

**Every decision taken alone that reduces protection or documentation goes in the end-of-run report, not only in the plan.** One line each, naming what was dropped and what it would have cost to keep — the requester finds out by reading, never by being bitten. A decision that merely picks between equivalent means (a library, a file layout, an identifier scheme) stays in the plan where it belongs.

**When the request is plainly bigger than the shortcut** — several integrated surfaces, or a thing the description itself says others will depend on — **say so in one line and proceed anyway.** The requester chose the level; a shortcut that argues is a shortcut nobody uses. The line is a note, never a gate:

> Noted: this looks larger than `instant` usually covers. Proceeding at `experiment` as asked — say the word and I will re-run it at `tool`.

**Recorded like any other story.** `scale: fast` and `engineering: experiment` go in the frontmatter, so validation, the index and the telemetry read an `instant` story exactly as they read any other. There is no `instant` value anywhere in the artifacts — the shortcut is an entrance, not a state.

## Story Types

| Type | Artifacts | Detection signals |
|---|---|---|
| **Feature** | `story.md` + `design.md` + `tasks.md` | New functionality, sprint work, updates, pages, infrastructure |
| **Bugfix** | `story.md` + `design.md` + `tasks.md` | "fix", "bug", "correct", "broken", error descriptions |

## Adaptive Modes

| Mode | When | Phases | Artifacts |
|---|---|---|---|
| **Fast** | Simple change, 1-2 files, no architectural decisions | Tasks only | `tasks.md` |
| **Standard** | Medium feature, 2-5 files, clear scope | Story + Tasks | `story.md` + `tasks.md` |
| **Full** | Complex feature, 5+ files, design decisions, integrations | Story + Design + Tasks | `story.md` + `design.md` + `tasks.md` |
| **Spike** | Time-boxed exploration — the deliverable is a decision, not a shipped change | Tasks only | `tasks.md` (with a mandatory `## Verdict`) |

Fast mode is **test-first at run time**: a sub-task carrying a `Tests` field has its test authored and confirmed failing (Red) before implementation, then Green-then-Refactor. A sub-task with no testable logic carries an optional Fast-only `Acceptance` field instead — 1-3 observable-behavior statements. Every implementing (non-Commit) Fast sub-task carries one or the other (the test-or-Acceptance contract rule). Fast stays single-author: no Test Advisor sub-agent, no `.draft/`, no `story.md`, no gate.

Spike mode is **exploration, not delivery**: the story exists to answer a question, and the answer is the mandatory `## Verdict` section of its `tasks.md`. A spike is tasks-only — no `story.md`, no `design.md`, no `.draft/` — and has **no requirements chain**: an R-reference such as `R1.1` inside a spike is a validation error, because no story.md exists for it to point at. It takes every Fast carve-out in this document (no runtime-dependency precheck, no MCP detection, no drafts, no phase gate) and stays single-author. What makes a spike terminal is the Verdict, not the checkboxes: `promote` (the orchestrator offers CREATE for the follow-up story, pre-filled with the conclusion, and records `promoted-to: NNN`) or `wont-do`. A Verdict left `open` is the failure mode this scale exists to prevent — LIST surfaces stale open spikes so they get promoted or closed. Template and grammar: [tasks.md](../../references/tasks.md#spike-scale-adaptations).

**The scale is one axis; the engineering level is the other.** The scale says which artifacts are written. The engineering level — `experiment`, `tool`, `project`, `product` — says how long the thing must last, and from that how much of the quality catalog, of Phase 3 and of the plan the story pays for. It is defined once in [engineering-level.md](../../references/engineering-level.md), read at triage (below), and it never changes the scale.

## Workflow Variants (Full mode, feature only)

| Variant | When to suggest | Phase order |
|---|---|---|
| **Requirements-First** | Business features, user-facing functionality | P1: story.md > P2: design.md > P3: tasks.md |
| **Design-First** | Infrastructure, tooling, technical constraints, NFRs | P1: design.md > P2: derived story.md > P3: tasks.md |

Bugfix always follows: P1: story.md (bug analysis) > P2: design.md (root cause) > P3: tasks.md

## Triage Protocol

Analyze the request (or `$ARGUMENTS` if invoked via `/epic:epic`) and present a **single proposal** for confirmation. Never ask each decision separately.

**Read who is asking first — from the request alone, never from a question.** The reading is recorded as a `requester` block with four fields, in the proposal and, where a `.draft/` exists, in `meta.yaml`:

```yaml
requester:
  level: layperson      # layperson | developer — developer when unsure
  persona: "beginner, 14, informal, has never opened a terminal. Read from: 'the black window', describes an outcome and not a mechanism"
  always:               # seeded from the level's register, extended from the answers
    - explain by example, one per new concept
    - run and show the result; never ask them to run a command
  never:
    - ask about git, npm or versioning — the defaults decide
    - a word from the plain register's list in the chat
```

`level` is the switch the rules read. A **`developer`** names files, tools, patterns or a stack, and uses git / npm / test vocabulary. A **`layperson`** describes an outcome rather than a mechanism, self-describes as starting or learning, and shows no tool vocabulary — "the black window", "a program that stores things". When unsure, **`developer`**: a wrong `layperson` patronizes an expert, while a wrong `developer` costs one calibration question in Clarify. `persona` is one line and ends with the evidence the reading rests on, so a wrong reading can be challenged and re-read from the answers. `always` and `never` start as the level's register — [plain-register.md](../../references/plain-register.md) for a layperson, [developer-register.md](../../references/developer-register.md) for a developer — and grow from what the answers reveal about this person: "I don't know how to run a command" becomes a `never`.

**The level changes four things and nothing else — the register the chat is written in, the question budget, the defaults taken silently, and the shape of a gate — and it never changes the scale.** The scale follows the request and the complexity table below, for every level. The 0.6.0 rule that held a layperson at Fast came from one trivial request; what had made Standard hurt a beginner — out-of-reach questions, document reviews, 23k-character turns — is closed by the register, the budget and the defaults, and a beginner who asks for something Full-shaped is owed Full, with its gates in one line. The files, the protocols and the sub-agents do not change.

**Read what it is for next — the engineering level — from the request, and propose it with its price.** Four levels, defined in [engineering-level.md](../../references/engineering-level.md): `experiment` (disposable, 1×), `tool` (kept and fixed when it breaks, 2–3×), `project` (maintained, others depend on it, 4–6×), `product` (may be published or sold, 8×+). Read it from the words the request carries — "for a class", "to see if it works", "my team", "customers" — record it in the proposal and, where a `.draft/` exists, in `meta.yaml` beside the `requester` block, and take **`tool` when the request does not settle it**: `experiment` and `product` are never assumed, since the first drops every check and the second buys every one. The proposal states the level in one line with its multiple, in the register's words, so the triage gate confirms it without spending a question; when triage was unsure, round 0 of Clarify fishes for it with the indirect questions that file lists — never "which level is this?" — and the line is restated once if the answer moves it. The level never changes the scale and never changes the requester level: the three are read independently and recorded side by side.

1. Detect event from request context
2. Classify type (feature vs bugfix)
3. **Assess overall story complexity** (see table below)
3a. **Read the engineering level** (above) — from the request, `tool` when unsettled, proposed with its multiple in one line
4. **Recommend mode with trade-off explanation** — from the request and the table, for every level; the level never changes the mode (above)
5. Suggest workflow variant (full mode only)
6. Check for context files — load [context-discovery.md](../../references/context-discovery.md)
7. **Health-check candidate MCPs** — load [mcp-integration.md](../../references/mcp-integration.md)
7a. **Detect memory** — `ai-memory`, per the Memory MCP section of [mcp-integration.md](../../references/mcp-integration.md#memory-mcp). One local `memory_status` call, in **all modes including Fast**; skipped only by `aiMemory: "off"`. WHEN available, gather Prior Knowledge before the Analyst runs — [context-discovery.md](../../references/context-discovery.md#prior-knowledge). WHEN unavailable, say so in the proposal's `**Memory:**` line and change nothing else.
7b. **Detect preferred tooling** — load [preferred-tooling.md](../../references/preferred-tooling.md). Runs in **all modes, including Fast** (unlike step 7, which Fast skips). Detect every favorite and optional E2E tool plus the `frontend-design` aid, then resolve the selection:
   - WHEN a favorite is available, select it (`playwright` by default; `chrome-devtools` when the task is Chrome-specific). For a frontend story with `frontend-design` available, designate it the preferred implementation aid.
   - WHEN no favorite is available, recommend installing one and **pause** for the user's `[y/n]` decision. The pause reuses the Runtime dependency precheck's interactive/headless signal — `TaskCreate` present = interactive session, so pause; in a **headless** session do not pause, emit a logged note instead and proceed. WHEN the user proceeds without installing, select the best installed optional tool that fits the task context (per [preferred-tooling.md](../../references/preferred-tooling.md)).
   - WHEN no favorite and no fitting optional tool exist, record `none — no E2E tooling available` in design.md's `## Tooling Decisions` block AND as a story Constraint.

   The recommendation/pause happens at triage **only**. The resolved decision is written to design.md's `## Tooling Decisions` block and the relevant E2E/frontend sub-tasks are annotated in tasks.md — the Executor and Test Advisor consume that decision without re-detecting.
8. Allocate the story number with `bash scripts/next-story-number.sh` — the one tested allocator, used by single create and batch create alike
9. Propose output path in `NNN-kebab-case`
10. If no existing stories in `.epic/stories/`: append EARS primer

### Complexity & Mode Recommendation

| Complexity | Signals | Recommended Mode | Trade-off |
|---|---|---|---|
| **Trivial** | 1-2 files, single concern | Fast | No formal traceability or design docs |
| **Simple** | 3-5 files, clear scope | Standard | No design docs; upgrade to Full if architectural decisions appear |
| **Moderate** | 5-10 files, design decisions | Standard | Traceable requirements and a task breakdown, with no design doc to write and keep current; upgrade to Full only on an architectural signal (below) |
| **High** | 10+ files, cross-cutting | Full | Highest upfront cost, but prevents scope drift and design mismatches |
| **Exploratory** | "probe", "spike", "experiment", "harness", "find out whether" / "descobrir se" — the goal of the request is to learn something; no deliverable is committed to yet | Spike | Tasks-only and time-boxed: no requirements chain, no design doc; ends in a Verdict that promotes to a real story or closes the question |

**Full is opt-in on an architectural signal, not on file count.** A design doc earns its cost only when there is a decision to record *before* the code exists. Propose Full when the request carries at least one of:

- a **new contract between systems** — an API, an event, a schema that two components must agree on
- a **data migration**, or any change to the shape of something already persisted
- a **cross-cutting change with no established pattern** in the codebase to follow
- **2+ independent tracks** that have to be designed to fit together (the same signal the Agent-Teams proposal reads)
- the user asking for Full explicitly

Absent every one of them, a Moderate story is **Standard** however many files it touches: file count measures typing, not design risk.

**Downgrading is as legitimate as upgrading.** The upgrade rule on the Simple row has a mirror. WHEN the clarify phase resolves the open questions and no architectural signal survives, **propose dropping to the lighter mode** — Full to Standard, or Standard to Fast — and name what the user gives up: Full to Standard loses the design doc, Standard to Fast loses the requirements chain and its traceability. The proposal is a one-line gate with two answers — drop, or keep the mode — and the mode changes only on the answer; announcing the drop and proceeding is the silent downgrade this rule forbids (measured on 2026-09-17: a developer's "just go straight to the code" was answered with an announced Standard-to-Fast drop, and the run ended with 33 open boxes). A request for speed is answered with fewer words and no waiting, never with fewer steps ([developer-register.md](../../references/developer-register.md)). One downgrade is forbidden outright, and it is the subject of the next note.

**Exploratory is a shape, not a size.** Propose Spike only when the request's own goal is to find something out, or when the user asks for one explicitly. A small feature is **Fast**, never Spike — the skill **never auto-downgrades a feature to a spike**: doing so would trade a deliverable for a question the user never asked.

Always explain trade-offs in the triage proposal. Include EARS primer on first story only (see [ears-notation.md](../../references/ears-notation.md)):

> "This framework uses EARS notation for requirements:
> - SHALL = mandatory behavior
> - One condition per requirement, each independently testable
> - Example: WHEN user submits form THE SYSTEM SHALL validate and return confirmation
> - Reference: https://alistairmavin.com/ears/"

Present as:

> "Based on your request:
> - **Event:** Create / Refine / Expand
> - **Type:** Feature / Bugfix
> - **Requester:** level — persona (the evidence, in a few words)
> - **Engineering:** experiment / tool / project / product — what it means for this request, and the multiple, in one line
> - **Complexity:** Trivial / Simple / Moderate / High (justification)
> - **Mode:** Fast / Standard / Full (reason + trade-offs)
> - **Workflow:** Requirements-First / Design-First (full mode only)
> - **Context:** [files found and how they'll be used]
> - **MCPs:** [verified MCPs and any substitutions]
> - **Memory:** [ai-memory — N pages recalled | not detected]
> - **Tooling:** [detected E2E tools + `frontend-design`; resolved E2E/frontend selection; any favorite-absent install recommendation]
> - **Output:** `.epic/stories/NNN-<proposed-name>/`
>
> Confirm or adjust?"

For a `layperson`, the same decisions are presented in the [plain register](../../references/plain-register.md): three lines in their words, one question — go on, or change something. The table above is what gets recorded, not what they are shown.

### Agent-teams proposal (Full mode only, structural)

After the main triage block, if **all** of the following hold, append the Agent-Teams proposal block below. Otherwise, skip it silently.

Gating conditions:
- Mode is **Full** (Fast/Standard never propose)
- The request implies **2+ likely-independent tracks** (disjoint files, no cross-track data dependency; e.g. frontend + backend + migrations, or service-A + service-B)
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is **not** already `"1"` (nothing to propose)
- `.epic/teams-opt-out` does **not** exist in the project
- The file `.claude/settings.local.json` has not been edited by the user in a way that already sets the flag

Append to the triage proposal:

> "**Parallel execution opportunity (Full mode):**
>
> The story decomposes into likely-independent tracks. Enabling agent-teams
> (experimental) would let the Run phase spawn one teammate per track, each
> using Epic's existing `executor` agent definition and its own context window.
>
> Options:
>   [y]     enable the flag now (restart required; writes to
>           `.claude/settings.local.json`, auto-gitignored)
>   [n]     proceed with current sequential/worktree execution
>   [never] opt out of this proposal for this project
>           (creates `.epic/teams-opt-out`)
>
> Caveats:
> - agent-teams is experimental
> - teammates are not restored by `/resume` or `/rewind`
> - teammates cannot spawn their own sub-agents
> - one team at a time (cleanup is automatic at end of Run phase)
> - see [teams-mode.md](../../references/teams-mode.md) for details"

On `[y]`: call `bash "${CLAUDE_PLUGIN_ROOT}/scripts/teams-config.sh" enable` and proceed with the current story sequentially (the flag applies to the **next** session).
On `[n]`: no side effects; continue triage.
On `[never]`: `touch .epic/teams-opt-out` and continue triage.

The proposal does **not** block triage — user choice is captured and the flow proceeds immediately.

## Clarify Protocol

**Mandatory for standard and full modes.** After triage confirmation, gather
clarifications using the `AskUserQuestion` tool. Multiple-choice prompts are
faster for the user than free-text confirmations and yield structured answers
the orchestrator can route on without re-parsing prose.

**The Epic asks the way an architect asks a client.** The requester came to
have something built, not to give instructions; whatever their level, they
know what it is and what it must do, and the how — the stack, the storage,
the pattern, the tooling — is not settled in their head. So every question
is about **what and what for**, and the **how is proposed, never asked**: it
arrives between the questions as a recommended option with its reason, in
words the requester can choose by. The level sets directness, not the amount
of context: a `developer` is asked in the stack's own terms, a `layperson` in
the plain register, and both get the context and the example.

- **Round 0 is orientation.** At most three context questions — who uses
  it, what exists today, what "done" looks like — or one open question in
  the requester's own words: "describe it as you would to a friend".
  Skipped when the request already answers them; a question the request
  answered is a defect in either register. When triage could not settle
  the engineering level, this round carries its indirect questions — will
  you open this again, when it breaks do you fix it or redo it, will anyone
  besides you run it, could it be published or sold
  ([engineering-level.md](../../references/engineering-level.md)) — asked as
  consequences, inside the same count.
- **Ask the consequence, never the mechanism.** "What happens to the data
  when the program closes?" decides persistence; "JSON or SQLite?" asks the
  requester to be the architect. The consequence is what they can observe
  and choose by; the mechanism is what their answer decides for them.
- **Every option carries its context and one example** — what choosing it
  implies, shown on this project. A bare label is a quiz. When the choice is
  technical and `requester.level` is `layperson`, add the analogy that lets
  them choose by logic ([plain-register.md](../../references/plain-register.md#explain-by-example));
  a `developer` gets the term instead, with the same context and example
  ([developer-register.md](../../references/developer-register.md)).
- **The how is a recommendation, never a question.** When a technical
  decision is due — stack, storage, pattern, tooling — offer it as options
  with the recommended one first and labelled `(Recommended)`, its reason
  in one line, and each alternative's trade-off in one line. Never an open
  "how do you want this built?".
- **Rounds are free in size, and built from what the last one left open.**
  Bundle only questions whose answers cannot change each other; a question
  whose answer can prune another goes alone, and first. Before composing
  round N+1, apply round N's answers: an `out-of-scope` answer removes its
  whole branch; a default taken removes the follow-ups that default implies;
  an answer given in tool vocabulary re-reads `requester.level` as
  `developer` for the rest of the story, and one given in outcome words
  keeps `layperson`; an answer that reveals how to work with this person —
  "I don't know how to run a command" — is appended to `requester.never`
  or `requester.always` and applied from then on. A question whose answer
  no longer changes the plan is not asked. When triage was unsure of the
  requester, round 0 opens with **one calibration question** — "How do you want me to work with you?" with two
  options in plain words: *explain in plain words and decide the technical
  details for me* / *ask me the technical questions* — and every round after
  it follows that answer.
- **One question budget per story, counted in questions from triage to the
  last box.** Every question in an `AskUserQuestion` call (or its
  numbered-list fallback) counts one; the orientation round counts one
  whatever its size; every phase gate and every question asked during Run
  counts one, against the same budget: **`layperson` — Fast 3, Standard 9,
  Full 12; `developer` — Fast 4, Standard 10, Full 14.** Measured on the
  format's own trial (September 2026, a Standard-shaped request):
  orientation, four, four with the gate — nine. Before any budget existed:
  1 out-of-reach question in Fast and 5–8 in Standard, for one beginner and
  one request. When the budget is spent, decide by the constitution's
  `## Defaults` and the
  [plain register](../../references/plain-register.md#decisions-the-requester-is-not-asked)
  table, write each decision as an assumption in story.md (Fast: in the run
  report) and proceed. Infinite clarification defeats the purpose — and so
  does a question the requester cannot answer.
- For each ambiguity, build a question with **2–4 mutually-exclusive options**.
  When the answer is binary, prefer `[yes / no / out-of-scope]` over open
  phrasings.
- Focus on: ambiguities, scope boundaries, edge cases, dependencies.
- **Stack recommendation must consider story complexity.**
- **Implicit capability detection:** For each requirement, identify whether
  it implicitly depends on an architectural capability not yet established in
  the design. Add it as a multi-choice question (`include now / defer to
  follow-up story / explicitly out of scope`).
- For Fast mode: skip clarify only if request is unambiguous.
- **Never skip clarify for Standard/Full.**

### Question shape

```
question:    "What happens to the other signed-in devices when a user changes their password?"
             ← the consequence; "invalidate the other tokens?" would ask the mechanism
options:
  - "They are all signed out (Recommended)" — "the password change is the moment they wanted the others out; one extra query"
  - "They keep working until they expire" — "nothing to build; a stolen session survives the change"
  - "Out of scope for this story"
context:     "Affects R2.3 (token TTL) and downstream session handling"
```

### Fallback (headless or AskUserQuestion unavailable)

When the tool is not callable (some `-p` modes, restricted permission scopes),
revert to the legacy assertion style — present a single message with a numbered
list of `"I understand X will work as Y. Confirm?"` items.

## Completeness Checklist

For standard/full: spawn Analyst sub-agent per procedure in [context-discovery.md](../../references/context-discovery.md#completeness-checklist).
For Fast: ask 1-2 inline questions only if needed.

## Phase Execution

Before entering any phase, load the corresponding reference files:

- Before writing any phase artifact: load [self-review-checklist.md](../../references/self-review-checklist.md)
- For Phase Gates, Checkpoint Recovery, Cascade Rollback, sub-agents: load [phase-gates.md](../../references/phase-gates.md)
- For reference files per phase (ears-notation, requirements, design-guide, etc.): see table in phase-gates.md
- On format doubts, load the relevant example from `assets/examples/`
- For a `layperson` requester, every phase gate takes the one-line shape in [plain-register.md](../../references/plain-register.md#gates-are-one-line) and counts against the question budget

**Authoring ceiling at Phase 3.** When the generated `tasks.md` passes the size threshold defined once in [tasks.md](../../references/tasks.md) (Authoring Ceiling) — warn and make the two offers: **cut** the scope, or **split** the plan into waves. Interactively as a question, headless as a logged note that proceeds. It is a warning, never a block: a story that genuinely needs a large plan keeps it. **There is no ceiling on the number of tasks** — how many a story has follows from the work; what is bounded is the unit, and a sub-task that cannot be proved on its own by its `Validation:` command is too big whatever the total. In batch create the offer is not re-entered into the live interview; the warning surfaces in the approval block and the split happens post-batch (see [batch-create.md](../../references/batch-create.md)).

## Persistence and Recovery

### Draft Saving (Standard and Full modes only)

After each phase approval, save to draft:

```
.epic/stories/<name>/
  .draft/
    story.md       <- after Phase 1 approval
    design.md      <- after Phase 2 approval (full only)
    meta.yaml      <- phase progress + project state + analyst output
```

Draft metadata (`meta.yaml`):
```yaml
phase: 2
approved: 2026-04-01
project-hash: <short SHA of HEAD at approval time>
requester:                  # read at triage, re-read from Clarify answers
  level: layperson          # layperson | developer
  persona: "beginner, informal, has never opened a terminal. Read from: 'the black window'"
  always:
    - explain by example, one per new concept
  never:
    - ask about git, npm or versioning
engineering: tool          # experiment | tool | project | product — proposed at triage, confirmed by its gate
questions_asked: 2          # questions spent against the story's question budget
analyst_output: |
  <cached output from Codebase Analysis Analyst>
```

### Resume Detection

If `.epic/stories/<name>/.draft/` exists when Create mode is detected for the same topic:

1. Compare `project-hash` with current HEAD
2. If diverged: "Found a draft (Phase N approved), but the project has commits since then. Resume anyway, or start fresh?"
3. If unchanged: "Found a draft with Phase N approved. Resume from Phase N+1?"

### Rules

- Draft saved only after explicit user approval of each phase
- Resume is always optional — user can choose to start fresh
- Draft cleared after successful completion (final artifacts replace draft)
- Refine mode: abort leaves original files untouched
- `.draft/` directories should be gitignored
- Fast mode does not use drafts (single phase)

## Output Rules

- Default path: `.epic/stories/NNN-<name>/`
- Naming: `NNN-kebab-case` where NNN is auto-incremented (zero-padded, 001-999)
- Auto-increment: `scripts/next-story-number.sh` detects the highest existing number across `.epic/stories/` AND `.epic/archive/` and adds 1. It is the single allocator — neither create flow re-implements the scan, and `--reserve N` claims numbers on disk (directory existence is the reservation)
- Numbers are NEVER recycled — archived stories retain their numbers permanently
- If 999 is reached: "Maximum story count reached. Archive old stories with `/epic:epic stories archive` to free space."
- Create directory before writing files
- User can override path; accept without further questions
- Add version frontmatter to each artifact on creation:
  ```yaml
  ---
  story: <story-name>
  type: feature | bugfix
  scale: fast | standard | full | spike
  engineering: experiment | tool | project | product
  version: 1
  created: <date>
  status: draft
  ---
  ```
- `status: draft` applies to **newly created stories only**. Never add the field
  to a story that already exists — an existing story's state is whatever the
  engine observed, and CREATE observed nothing about it. See
  [Lifecycle Status](#lifecycle-status-status) for the full field spec.
- Refine writes `status:` for exactly **one** transition: the reopen edge. A
  refinement that leaves an open `[ ]` on a story reading `done` or `validated`
  writes `in-progress` (R1.7, R1.8) — see
  [Status Census](../../references/refine-mode.md#status-census). It writes no
  other value: a refinement that does not reopen the story leaves the field
  exactly as it was, including absent.
- On Refine, increment version and add history entry:
  ```yaml
  ---
  story: <story-name>
  type: feature
  scale: full
  version: 2
  created: <original-date>
  last-refined: <today>
  history:
    - v1: Initial story
    - v2: <one-line summary of refinement>
  ---
  ```
- Version is a simple integer, not semver
- Maximum 10 history entries; older entries: "see git history" — **unless the artifacts are not in git, in which case the cap does not apply.** The rule relegates old entries, and relegation needs somewhere to relegate them *to*. Where `.epic/` is gitignored — the default this plugin ships, and verifiable with `git ls-files .epic/` returning nothing — dropping the eleventh entry destroys it instead of moving it, and the escape hatch the rule names does not exist. Check before trimming; a story that has genuinely been refined eleven times keeps eleven entries, and that is not a violation. Where the artifacts *are* tracked, the cap holds as written
- All files in a story share the same version number

### Lifecycle Status (`status:`)

`status:` is the story's lifecycle state, carried in the frontmatter of every artifact that has frontmatter. Six values, no others:

| Value | Written by |
|---|---|
| `draft` | CREATE — when the artifacts are first written |
| `in-progress` | RUN — when execution of the story starts, written by `scripts/close-subtask.sh` inside the close; RUN **or** REFINE when a census finds open work on a story reading `done` or `validated` (the reopen edge, R1.7/R1.8) — REFINE performs that one `Edit` itself, since a refinement adds boxes and closes none |
| `done` | RUN — written by `scripts/close-subtask.sh` when a marking satisfies rule 1 of the [status transition table](../../references/run-mode.md#status-transitions); a deferred `[~]` blocks it (R1.3) |
| `validated` | VALIDATE — after Validator and Auditor pass |
| `superseded` | the supersede operation |
| `archived` | the archive operation |

- **Engine-written, never hand-edited.** The writer list above is exhaustive — no other mode touches the field. A human editing it is tolerated, not blocked: validation only flags the result. A value outside the six is an **error**; `done` or `validated` while a `[ ]` box is still open is a **warning** (the status is ahead of the checkboxes).
- **In RUN the write is script-mediated — the orchestrator does not perform it.** `scripts/close-subtask.sh` marks the box, takes the census, applies the transition table and stamps every artifact that carries frontmatter, all inside the invocation that closed the box; the orchestrator supplies the Executor's closing block and reads back `status_written` from the returned JSON. Neither the orchestrator nor the Executor edits the field — or the box — by hand (R3.2). The other writers in the table above perform their own `Edit`, because no close call is passing through to carry it.
- **Same value in every artifact** of the story, exactly like `version`. Artifacts declaring **different** values raise a warning naming them. An artifact with no `status:` carries no opinion and is never counted as divergent.
- **Absence is legal and silent.** A story with no `status:` anywhere is neither an error nor a warning — stories written before the field validate byte-identically. The field is never required by validation.
- **Persisted values only.** `done-except-external` is not a `status:` value: it is a condition computed from the checkboxes at read time (see [tasks.md](../../references/tasks.md#completion)), never written to a file.
- **Written with `Edit`, not `Write`** — deliberately. The `hook-validate` PostToolUse matcher in `hooks/hooks.json` is `Write` only, so engine status transitions must not re-trigger a validation pass on every write.
- **Companion field `superseded-by: MMM`** — optional, written **only** by the supersede operation, next to `status: superseded`. It names the story that took over the scope and is the machine-readable source the story index renders. Nothing else writes it.

## Language

**Artifacts are always written in English.** Claude models perform best processing English-language technical content. This ensures optimal quality when artifacts are consumed later for implementation. There is no override for this rule.

- **Spec artifacts** (story.md, design.md, tasks.md): always English
- **EARS keywords**: always English and CAPS (SHALL, WHEN, WHILE, IF, WHERE)
- **Communication with the user**: always in the user's language (detected from their prompt)
- **Code identifiers**: always English (function names, variables, etc.)

## Validation

Validation runs automatically via PostToolUse hook when any story artifact is written to `.epic/stories/`. Manual validation is also available:

> **Architectural note.** Hooks live in `hooks/hooks.json` (plugin scope), not
> in this skill's frontmatter, by design. They must fire when the user edits
> `.epic/` files outside an active `/epic:epic` session — e.g. through a plain
> `Edit` call, an external editor, or a different skill. All hooks use `if:`
> filters scoped to `.epic/**` paths or specific tool arguments, so cost is
> negligible when no Epic story exists. Skill-frontmatter hooks would only
> apply during `/epic:epic` execution — none of the current hooks fit that
> profile.


```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-story.sh" <story-directory>
```

For cross-reference checks (requirements traceability):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cross-reference.sh" <story-directory>
```

Its JSON `mapping` field gives the requirement → sub-tasks relation directly — the Traceability Check builds its table from it, never by hand-counting.

- Output is JSON with `errors`, `warnings`, and `status` (pass/fail)
- Errors must be fixed before considering the story complete
- Warnings are informational — present them to the user

## Gotchas

- EARS: use `SHALL`, never `SHOULD` — one condition per requirement, each independently testable
- Requirements: number hierarchically (R1, R1.1, R1.2, R2...)
- Bugfix: Unchanged Behavior section is **mandatory**, minimum 2 items
- Fast mode is test-first at run time: a sub-task with a `Tests` field is authored Red, then Green-then-Refactor; a sub-task with no testable logic carries an `Acceptance` field (1-3 observable-behavior statements) instead — every implementing (non-Commit) sub-task carries one or the other
- Fast → Standard upgrade: recommend upgrading during triage or task generation when scope grows, **or** when a change genuinely needs requirement traceability or design documentation — Fast provides neither
- Constitution constraints are soft — warnings, not blocks
- This skill formalizes work into structured stories — it does NOT explore ideas from scratch or write implementation code
