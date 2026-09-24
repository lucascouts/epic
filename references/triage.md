# Triage — Create and Instant

Loaded by Create and by Instant before anything is written. Instant reads it with its three pins already set. Moved out of [SKILL.md](../skills/epic/SKILL.md) so a run that does not need it does not carry it.

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

## Adaptive Modes

| Mode | When | Phases | Artifacts |
|---|---|---|---|
| **Fast** | Simple change, 1-2 files, no architectural decisions | Tasks only | `tasks.md` |
| **Standard** | Medium feature, 2-5 files, clear scope | Story + Tasks | `story.md` + `tasks.md` |
| **Full** | Complex feature, 5+ files, design decisions, integrations | Story + Design + Tasks | `story.md` + `design.md` + `tasks.md` |
| **Spike** | Time-boxed exploration — the deliverable is a decision, not a shipped change | Tasks only | `tasks.md` (with a mandatory `## Verdict`) |

Fast mode is **test-first at run time**: a sub-task carrying a `Tests` field has its test authored and confirmed failing (Red) before implementation, then Green-then-Refactor. A sub-task with no testable logic carries an optional Fast-only `Acceptance` field instead — 1-3 observable-behavior statements. Every implementing (non-Commit) Fast sub-task carries one or the other (the test-or-Acceptance contract rule). Fast stays single-author: no Test Advisor sub-agent, no `.draft/`, no `story.md`, no gate.

Spike mode is **exploration, not delivery**: the story exists to answer a question, and the answer is the mandatory `## Verdict` section of its `tasks.md`. A spike is tasks-only — no `story.md`, no `design.md`, no `.draft/` — and has **no requirements chain**: an R-reference such as `R1.1` inside a spike is a validation error, because no story.md exists for it to point at. It takes every Fast carve-out in this document (no runtime-dependency precheck, no MCP detection, no drafts, no phase gate) and stays single-author. What makes a spike terminal is the Verdict, not the checkboxes: `promote` (the orchestrator offers CREATE for the follow-up story, pre-filled with the conclusion, and records `promoted-to: NNN`) or `wont-do`. A Verdict left `open` is the failure mode this scale exists to prevent — LIST surfaces stale open spikes so they get promoted or closed. Template and grammar: [tasks.md](tasks.md#spike-scale-adaptations).

**The scale is one axis; the engineering level is the other.** The scale says which artifacts are written. The engineering level — `experiment`, `tool`, `project`, `product` — says how long the thing must last, and from that how much of the quality catalog, of Phase 3 and of the plan the story pays for. It is defined once in [engineering-level.md](engineering-level.md), read at triage (below), and it never changes the scale.

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

`level` is the switch the rules read. A **`developer`** names files, tools, patterns or a stack, and uses git / npm / test vocabulary. A **`layperson`** describes an outcome rather than a mechanism, self-describes as starting or learning, and shows no tool vocabulary — "the black window", "a program that stores things". When unsure, **`developer`**: a wrong `layperson` patronizes an expert, while a wrong `developer` costs one calibration question in Clarify. `persona` is one line and ends with the evidence the reading rests on, so a wrong reading can be challenged and re-read from the answers. `always` and `never` start as the level's register — [plain-register.md](plain-register.md) for a layperson, [developer-register.md](developer-register.md) for a developer — and grow from what the answers reveal about this person: "I don't know how to run a command" becomes a `never`.

**The level changes four things and nothing else — the register the chat is written in, the question budget, the defaults taken silently, and the shape of a gate — and it never changes the scale.** The scale follows the request and the complexity table below, for every level. The 0.6.0 rule that held a layperson at Fast came from one trivial request; what had made Standard hurt a beginner — out-of-reach questions, document reviews, 23k-character turns — is closed by the register, the budget and the defaults, and a beginner who asks for something Full-shaped is owed Full, with its gates in one line. The files, the protocols and the sub-agents do not change.

**Read what it is for next — the engineering level — from the request, and propose it with its price.** Four levels, defined in [engineering-level.md](engineering-level.md): `experiment` (disposable, 1×), `tool` (kept and fixed when it breaks, 2–3×), `project` (maintained, others depend on it, 4–6×), `product` (may be published or sold, 8×+). Read it from the words the request carries — "for a class", "to see if it works", "my team", "customers" — record it in the proposal and, where a `.draft/` exists, in `meta.yaml` beside the `requester` block, and take **`tool` when the request does not settle it**: `experiment` and `product` are never assumed, since the first drops every check and the second buys every one. The proposal states the level in one line with its multiple, in the register's words, so the triage gate confirms it without spending a question; when triage was unsure, round 0 of Clarify fishes for it with the indirect questions that file lists — never "which level is this?" — and the line is restated once if the answer moves it. The level never changes the scale and never changes the requester level: the three are read independently and recorded side by side.

1. Detect event from request context
2. Classify type (feature vs bugfix)
3. **Assess overall story complexity** (see table below)
3a. **Read the engineering level** (above) — from the request, `tool` when unsettled, proposed with its multiple in one line
4. **Recommend mode with trade-off explanation** — from the request and the table, for every level; the level never changes the mode (above)
5. Suggest workflow variant (full mode only)
6. Check for context files — load [context-discovery.md](context-discovery.md)
7. **Health-check candidate MCPs** — load [mcp-integration.md](mcp-integration.md)
7a. **Detect memory** — `ai-memory`, per the Memory MCP section of [mcp-integration.md](mcp-integration.md#memory-mcp). One local `memory_status` call, in **all modes including Fast**; skipped only by `aiMemory: "off"`. WHEN available, gather Prior Knowledge before the Analyst runs — [context-discovery.md](context-discovery.md#prior-knowledge). WHEN unavailable, say so in the proposal's `**Memory:**` line and change nothing else.
7b. **Detect preferred tooling** — load [preferred-tooling.md](preferred-tooling.md). Runs in **all modes, including Fast** (unlike step 7, which Fast skips). Detect every favorite and optional E2E tool plus the `frontend-design` aid, then resolve the selection:
   - WHEN a favorite is available, select it (`playwright` by default; `chrome-devtools` when the task is Chrome-specific). For a frontend story with `frontend-design` available, designate it the preferred implementation aid.
   - WHEN no favorite is available, recommend installing one and **pause** for the user's `[y/n]` decision. The pause reuses the Runtime dependency precheck's interactive/headless signal — `TaskCreate` present = interactive session, so pause; in a **headless** session do not pause, emit a logged note instead and proceed. WHEN the user proceeds without installing, select the best installed optional tool that fits the task context (per [preferred-tooling.md](preferred-tooling.md)).
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

**Downgrading is as legitimate as upgrading.** The upgrade rule on the Simple row has a mirror. WHEN the clarify phase resolves the open questions and no architectural signal survives, **propose dropping to the lighter mode** — Full to Standard, or Standard to Fast — and name what the user gives up: Full to Standard loses the design doc, Standard to Fast loses the requirements chain and its traceability. The proposal is a one-line gate with two answers — drop, or keep the mode — and the mode changes only on the answer; announcing the drop and proceeding is the silent downgrade this rule forbids (measured on 2026-09-17: a developer's "just go straight to the code" was answered with an announced Standard-to-Fast drop, and the run ended with 33 open boxes). A request for speed is answered with fewer words and no waiting, never with fewer steps ([developer-register.md](developer-register.md)). One downgrade is forbidden outright, and it is the subject of the next note.

**Exploratory is a shape, not a size.** Propose Spike only when the request's own goal is to find something out, or when the user asks for one explicitly. A small feature is **Fast**, never Spike — the skill **never auto-downgrades a feature to a spike**: doing so would trade a deliverable for a question the user never asked.

Always explain trade-offs in the triage proposal. Include EARS primer on first story only (see [ears-notation.md](ears-notation.md)):

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

For a `layperson`, the same decisions are presented in the [plain register](plain-register.md): three lines in their words, one question — go on, or change something. The table above is what gets recorded, not what they are shown.

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
> - see [teams-mode.md](teams-mode.md) for details"

On `[y]`: call `bash "${CLAUDE_PLUGIN_ROOT}/scripts/teams-config.sh" enable` and proceed with the current story sequentially (the flag applies to the **next** session).
On `[n]`: no side effects; continue triage.
On `[never]`: `touch .epic/teams-opt-out` and continue triage.

The proposal does **not** block triage — user choice is captured and the flow proceeds immediately.
