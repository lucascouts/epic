---
name: epic
description: >
  Structured story creation, management, and execution for features and
  bugfixes — requirements, design, task breakdown, and implementation
  with scale-adaptive intelligence. Trigger for "let's plan this before
  coding", "break this into tasks", or any request to formalize
  development work. Use when asked to: create, refine, or expand a
  story; list or manage existing stories; run/execute tasks from a
  story; validate implementation against plan. Also trigger when the
  user says "document this feature", "structure this sprint", "what
  needs to be done to implement X?", "list stories", "run story",
  "execute tasks", "validate implementation" — even without saying
  "epic" or "story" explicitly.
argument-hint: "[description] or [stories] or [stories full] or [stories run|validate|refine NNN] or [stories NNN run N|all] or [init]"
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
effort: max
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
| **Test Advisor** | Authors one failing test per Unit/Integration sub-task during Phase 3, runs Red verification, records red-evidence | standard + full (Phase 3) | `agents/test-advisor.md` |
| **Reviewer** | Cross-artifact review, gap detection, consistency check | full only | `agents/reviewer.md` |

### Execution Personas (task implementation)

| Persona | Role | Scale | Agent file |
|---|---|---|---|
| **Executor** | Implements a sub-task following the strict 6-step protocol; step 5 is conditional (Refactor for test-first sub-tasks, Tests for test-after) | all scales (Simple+ complexity) | `agents/executor.md` |
| **Tech Reviewer** | Reviews implementation at technology boundaries | all scales (multi-tech tasks) | `agents/tech-reviewer.md` |

### Post-Implementation Personas (validation)

| Persona | Role | Scale | Agent file |
|---|---|---|---|
| **Validator** | Runs validation commands and tests per completed task | all scales | `agents/validator.md` |
| **Auditor** | Compares implemented code against story + design artifacts | all scales | `agents/auditor.md` |

The **main agent** (this skill) orchestrates: generates artifacts (story.md, design.md, tasks.md) during planning, delegates to Executors during run-mode, and coordinates Validators/Auditors during validation. The main agent retains conversation context with the user and handles git operations (commits).

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

"stories"
  → LIST mode (summary)

"stories full"
  → LIST mode (detailed, all stories with tasks)

"stories NNN"
  → LIST mode (detailed, single story NNN)

"stories run NNN [--auto|--batch=N|--gate=commit]"
  → RUN mode (all pending tasks of story NNN)

"stories validate NNN"
  → VALIDATE mode (Validator + Auditor on story NNN)

"stories refine NNN"
  → REFINE mode (delta workflow on story NNN)

"stories archive NNN[-MMM]|--done"
  → ARCHIVE mode (move completed stories to archive)

"stories teams {status|enable|disable}"
  → TEAMS mode (manage experimental agent-teams flag for this project)

"stories NNN run all [--auto|--batch=N|--gate=commit]"
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
| **Init** | `/epic:epic init` | Load [init-mode.md](../../references/init-mode.md) |
| **List** | `/epic:epic stories [full] [NNN]` | Load [list-mode.md](../../references/list-mode.md) |
| **Run** | `/epic:epic stories run NNN` or `NNN run N\|all` | Load [run-mode.md](../../references/run-mode.md) |
| **Validate** | `/epic:epic stories validate NNN` | Load [validate-mode.md](../../references/validate-mode.md) |
| **Refine** | `/epic:epic stories refine NNN` | Load [refine-mode.md](../../references/refine-mode.md) |
| **Archive** | `/epic:epic stories archive NNN` | Load [list-mode.md](../../references/list-mode.md) (archive section) |
| **Teams** | `/epic:epic stories teams {status\|enable\|disable}` | Load [teams-mode.md](../../references/teams-mode.md) |
| **Expand** | User says "based on", "extends" existing story | Create new story referencing source |
| **CI/Headless** | Programmatic invocation via Agent SDK | Load [ci-mode.md](../../references/ci-mode.md) |

**For Create mode, continue reading this file. For all other modes, load the referenced file first.**

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

Fast mode is **test-first at run time**: a sub-task carrying a `Tests` field has its test authored and confirmed failing (Red) before implementation, then Green-then-Refactor. A sub-task with no testable logic carries an optional Fast-only `Acceptance` field instead — 1-3 observable-behavior statements. Every implementing (non-Commit) Fast sub-task carries one or the other (the test-or-Acceptance contract rule). Fast stays single-author: no Test Advisor sub-agent, no `.draft/`, no `story.md`, no gate.

## Workflow Variants (Full mode, feature only)

| Variant | When to suggest | Phase order |
|---|---|---|
| **Requirements-First** | Business features, user-facing functionality | P1: story.md > P2: design.md > P3: tasks.md |
| **Design-First** | Infrastructure, tooling, technical constraints, NFRs | P1: design.md > P2: derived story.md > P3: tasks.md |

Bugfix always follows: P1: story.md (bug analysis) > P2: design.md (root cause) > P3: tasks.md

## Triage Protocol

Analyze the request (or `$ARGUMENTS` if invoked via `/epic:epic`) and present a **single proposal** for confirmation. Never ask each decision separately.

1. Detect event from request context
2. Classify type (feature vs bugfix)
3. **Assess overall story complexity** (see table below)
4. **Recommend mode with trade-off explanation**
5. Suggest workflow variant (full mode only)
6. Check for context files — load [context-discovery.md](../../references/context-discovery.md)
7. **Health-check candidate MCPs** — load [mcp-integration.md](../../references/mcp-integration.md)
7b. **Detect preferred tooling** — load [preferred-tooling.md](../../references/preferred-tooling.md). Runs in **all modes, including Fast** (unlike step 7, which Fast skips). Detect every favorite and optional E2E tool plus the `frontend-design` aid, then resolve the selection:
   - WHEN a favorite is available, select it (`playwright` by default; `chrome-devtools` when the task is Chrome-specific). For a frontend story with `frontend-design` available, designate it the preferred implementation aid.
   - WHEN no favorite is available, recommend installing one and **pause** for the user's `[y/n]` decision. The pause reuses the Runtime dependency precheck's interactive/headless signal — `TaskCreate` present = interactive session, so pause; in a **headless** session do not pause, emit a logged note instead and proceed. WHEN the user proceeds without installing, select the best installed optional tool that fits the task context (per [preferred-tooling.md](../../references/preferred-tooling.md)).
   - WHEN no favorite and no fitting optional tool exist, record `none — no E2E tooling available` in design.md's `## Tooling Decisions` block AND as a story Constraint.

   The recommendation/pause happens at triage **only**. The resolved decision is written to design.md's `## Tooling Decisions` block and the relevant E2E/frontend sub-tasks are annotated in tasks.md — the Executor and Test Advisor consume that decision without re-detecting.
8. Auto-increment story number from existing stories in `.epic/stories/`
9. Propose output path in `NNN-kebab-case`
10. If no existing stories in `.epic/stories/`: append EARS primer

### Complexity & Mode Recommendation

| Complexity | Signals | Recommended Mode | Trade-off |
|---|---|---|---|
| **Trivial** | 1-2 files, single concern | Fast | No formal traceability or design docs |
| **Simple** | 3-5 files, clear scope | Standard | No design docs; upgrade to Full if architectural decisions appear |
| **Moderate** | 5-10 files, design decisions | Full | More upfront time, but traceable requirements and documented design |
| **High** | 10+ files, cross-cutting | Full | Highest upfront cost, but prevents scope drift and design mismatches |

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
> - **Complexity:** Trivial / Simple / Moderate / High (justification)
> - **Mode:** Fast / Standard / Full (reason + trade-offs)
> - **Workflow:** Requirements-First / Design-First (full mode only)
> - **Context:** [files found and how they'll be used]
> - **MCPs:** [verified MCPs and any substitutions]
> - **Tooling:** [detected E2E tools + `frontend-design`; resolved E2E/frontend selection; any favorite-absent install recommendation]
> - **Output:** `.epic/stories/NNN-<proposed-name>/`
>
> Confirm or adjust?"

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

- Use up to **3 rounds** of clarification. Each `AskUserQuestion` call may
  bundle 3–7 related questions; the user answers them together. If ambiguities
  remain after 3 rounds, document assumptions explicitly in story.md and
  proceed. Quality matters more than speed, but infinite clarification defeats
  the purpose.
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
question:    "Should new email-verification tokens expire after?"
options:     ["1 hour (default)", "24 hours", "Configurable per environment", "No expiration"]
description: "Affects R2.3 (token TTL) and downstream session handling"
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
- Auto-increment: detect highest existing number across `.epic/stories/` AND `.epic/archive/`, add 1
- Numbers are NEVER recycled — archived stories retain their numbers permanently
- If 999 is reached: "Maximum story count reached. Archive old stories with `/epic:epic stories archive` to free space."
- Create directory before writing files
- User can override path; accept without further questions
- Add version frontmatter to each artifact on creation:
  ```yaml
  ---
  story: <story-name>
  type: feature | bugfix
  scale: fast | standard | full
  version: 1
  created: <date>
  status: draft
  ---
  ```
- `status: draft` applies to **newly created stories only**. Never add the field
  to a story that already exists — an existing story's state is whatever the
  engine observed, and CREATE observed nothing about it. See
  [Lifecycle Status](#lifecycle-status-status) for the full field spec.
- Refine does not write `status:` — it is not one of the field's writers. A
  refined story keeps whatever value it already carried, including none.
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
- Maximum 10 history entries; older entries: "see git history"
- All files in a story share the same version number

### Lifecycle Status (`status:`)

`status:` is the story's lifecycle state, carried in the frontmatter of every artifact that has frontmatter. Six values, no others:

| Value | Written by |
|---|---|
| `draft` | CREATE — when the artifacts are first written |
| `in-progress` | RUN — when execution of the story starts |
| `done` | RUN — when the story is complete (no `[ ]` remains) |
| `validated` | VALIDATE — after Validator and Auditor pass |
| `superseded` | the supersede operation |
| `archived` | the archive operation |

- **Engine-written, never hand-edited.** The writer list above is exhaustive — no other mode touches the field. A human editing it is tolerated, not blocked: validation only flags the result. A value outside the six is an **error**; `done` or `validated` while a `[ ]` box is still open is a **warning** (the status is ahead of the checkboxes).
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
