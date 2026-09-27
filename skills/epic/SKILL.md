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
  create --batch to draft many stories from one document, archive and
  supersede. Also trigger when the user says "create an epic
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
  - mcp__ai-memory__memory_status
  - mcp__ai-memory__memory_recent
  - mcp__ai-memory__memory_query
  - mcp__ai-memory__memory_write_page
---

# Epic

Scale-adaptive story framework for features and bugfixes. Invoked as `/epic:epic`.

## Scope (MUST read first)

Epic exists solely to **create, structure, and manage epics and their stories** (`story.md` + `design.md` + `tasks.md`). Before running any mode, verify the request fits this purpose.

**Refuse immediately** if the request is for any of the following — respond with a one-line refusal and the suggested alternative:

| Request pattern | Refuse because | Tell the user |
|---|---|---|
| "Review this code / PR / branch" | No story artifact to anchor to | Use `/review`, `/security-review`, or `/code-review` |
| "Security review of …" | Same | `/security-review` |
| "Refactor X" (no existing story) | Skips design-fidelity contract | Create a Fast/Standard story first, then `run` it |
| "Analyze / explain this codebase" | Epic artifacts are the only valid analysis container here | Plain chat, or `/review` for a change |
| "Write this script / change this file" (no approved sub-task) | Implementation only happens inside Executor for an approved sub-task | Create a story (often Fast) then run its tasks |
| "Debug this incident / failing test" | Debug flow is out-of-scope | Plain chat |
| "Architecture advice for existing code" | No design.md to validate against | Plain chat, or `/code-review` for a change |

The refusal is hard. Do not partially engage, do not propose an Epic-wrapped version unless the user rewrites the request as story/task work. See [`../../PURPOSE.md`](../../PURPOSE.md) for the full boundary.

## Language

**Everything the Epic writes under `.epic/` is written in English — stories, design, tasks, backlog, reports and every other document.** This is not an option and no setting changes it: these files are read later by sub-agents, and Claude models perform best on English technical content. The project itself may carry comments and domain terms in other languages; that is the project's choice, and the Epic neither rewrites nor flags them.

- **Spec artifacts** (story.md, design.md, tasks.md): always English
- **EARS keywords**: always English and CAPS (SHALL, WHEN, WHILE, IF, WHERE)
- **Communication with the user**: always in the user's language — the `language` setting when the user has set one, otherwise the language of their prompt — **every line they can see, including a note between two tool calls and the closing message**. A status line is communication: "Now closing the final checks" in the middle of a Portuguese conversation is the same defect as an English menu.
- **Code identifiers the Epic introduces**: English (function names, variables, etc.)
- **What the requester's own users read**: the program's interface — menu, prompts, error messages — and the documentation of how to use it (its README). **This is the one thing the English rule does not cover**, and it is not the Epic's to decide: it belongs to whoever will read it.

**The interface language is asked, not assumed.** A request written in a language other than English carries no instruction about the program's own text, and the English rule above is about artifacts — reading it as a rule about the interface ships a menu the requester cannot read, decided by a rule that was never about them. So:

- **Asked once, in the requester's own language**, as an ordinary clarify question: English · the language you wrote to me in · another one. It is a `what` question, not a `how` — the requester is the one who reads the result.
- **Not asked when the request is already in English** — the answer is not in doubt, and a question whose answer is known is a defect in either register ([Clarify Protocol](#clarify-protocol)).
- **When no round will run** — `instant`, or a budget already spent — the default is **the language the request was written in**, taken and stated on its line, never the artifacts' English inherited by mistake.

## Validation

Validation runs automatically via a PostToolUse hook when a story artifact under `.epic/stories/` is written with the Write tool; its errors come back to you as hook context. Manual validation is also available:

```bash
epic-validate <story-directory>
```

For cross-reference checks (requirements traceability):

```bash
epic-xref <story-directory>
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
- **A run that finishes a story ends with an `AskUserQuestion`** — validate, refine or archive — after the closing message, layperson included; see [End of Run](../../references/run-mode.md#end-of-run--next-step-index)
- Fast → Standard upgrade: recommend upgrading during triage or task generation when scope grows, **or** when a change genuinely needs requirement traceability or design documentation — Fast provides neither
- Constitution constraints are soft — warnings, not blocks
- This skill formalizes work into structured stories — it does NOT explore ideas from scratch or write implementation code
## Prerequisites

- `bash`, `git`, and `jq` available on `PATH`
- Claude Code **v2.1.105+** (for conditional hooks `if:`, skill `effort`/`paths:`, description caps). Core planning features work on v2.1.85+ but with degraded ergonomics.
- Optional MCP servers for research. See [mcp-integration.md](../../references/mcp-integration.md) for the full priority order and cost policy. Default search MCP is `brave-search`; `perplexity` is **never** the default (premium/high-cost).

## Runtime dependency precheck (MANDATORY before Standard/Full triage)

**Before Standard or Full triage, run the precheck in [triage.md](../../references/triage.md#runtime-dependency-precheck-mandatory-before-standardfull-triage).**

**Headless — `AskUserQuestion` is not callable, so nobody can answer:** take every gate and question with its recommended option, record each as an assumption, and run the mode to its end; stop only on a failure.

## Project State

### Existing stories
!`ls -1d "${CLAUDE_PROJECT_DIR:-.}"/.epic/stories/*/ 2>/dev/null | sed 's|.*/\(.*\)/|\1|' | head -20 | grep . || echo "(none)"`

### Constitution
!`f="${CLAUDE_PROJECT_DIR:-.}/.epic/constitution.md"; if [ -f "$f" ]; then head -30 "$f"; else echo "(none)"; fi`

### Git state
!`cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null; if ! git rev-parse --git-dir >/dev/null 2>&1; then echo "(not a git repo)"; elif ! git rev-parse -q --verify HEAD >/dev/null; then echo "(no commits yet)"; else git rev-parse --short HEAD; git diff --stat HEAD | tail -1; fi`

## Plugin options

The user's plugin settings, substituted by Claude Code when this skill loads. Only a saved value is substituted: a value that still reads `${user_config.…}` was never saved, so use the default in brackets.

- `aiMemory`: `${user_config.aiMemory}` [`auto`] — `off` skips every ai-memory call ([mcp-integration.md](../../references/mcp-integration.md#memory-mcp))
- `defaultScale`: `${user_config.defaultScale}` [`standard`] — the scale proposed when triage cannot settle one
- `staleThresholdDays`: `${user_config.staleThresholdDays}` [`7`] — the story list flags pending work untouched this long
- `spikeStaleThresholdDays`: `${user_config.spikeStaleThresholdDays}` [`14`] — the story list flags an open spike Verdict untouched this long

## Concepts

| Term | Meaning |
|---|---|
| **Epic** | This plugin / the `/epic:epic` command |
| **Story** | A unit of work: feature, bugfix, or initiative |
| **Task** | An implementation action inside tasks.md |

## Personas

**Before spawning any sub-agent, read [personas.md](../../references/personas.md)** — who each one is, when it is spawned, the MCP and tooling hand-off.

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
| **Create** | `/epic:epic` or `/epic:epic <description>` | Read [triage.md](../../references/triage.md), then [clarify.md](../../references/clarify.md) when a round runs, then [phase-execution.md](../../references/phase-execution.md) for Standard/Full |
| **Instant** | `/epic:epic instant <description>` | Read [instant-mode.md](../../references/instant-mode.md), then [triage.md](../../references/triage.md) with its three pins set — no clarify round |
| **Migrate** | `/epic:epic stories migrate NNN [--apply]` | Run `epic-migrate` — dry run by default; it reports the rewrites as JSON and the diff on stderr, and writes only with `--apply` |
| **Batch Create** | `/epic:epic stories create --batch <doc>` | Load [batch-create.md](../../references/batch-create.md) — one interview, N stories; numbers come from `epic-next-number` |
| **Init** | `/epic:epic init` | Load [init-mode.md](../../references/init-mode.md) |
| **List** | `/epic:epic stories [full] [NNN]` | Load [list-mode.md](../../references/list-mode.md) |
| **Run** | `/epic:epic stories run NNN` or `NNN run N\|all` | Load [run-mode.md](../../references/run-mode.md) |
| **Validate** | `/epic:epic stories validate NNN` | Load [validate-mode.md](../../references/validate-mode.md) |
| **Refine** | `/epic:epic stories refine NNN` | Load [refine-mode.md](../../references/refine-mode.md) |
| **Archive** | `/epic:epic stories archive NNN[-MMM]\|--done` | Load [list-mode.md](../../references/list-mode.md) (Archive Command) — the mode resolves which stories to archive and calls `epic-archive` once per story; it never moves a directory or writes a manifest entry itself |
| **Supersede** | `/epic:epic stories supersede NNN --by MMM` | Load [supersede-mode.md](../../references/supersede-mode.md) |
| **Expand** | User says "based on", "extends" existing story | Create new story referencing source |
| **CI/Headless** | Programmatic invocation via Agent SDK | Load [ci-mode.md](../../references/ci-mode.md) |

**Every mode loads its reference first.** Any mode that writes a story artifact also reads [output-rules.md](../../references/output-rules.md). Other references are loaded from these: [constitution.md](../../references/constitution.md) (the project constitution's format), [personas.md](../../references/personas.md) (before any sub-agent), [mcp-integration.md](../../references/mcp-integration.md) (research and memory servers).

## Instant — the disposable-work shortcut

`/epic:epic instant <description>`: **read [instant-mode.md](../../references/instant-mode.md) before anything else** — the three pins, what the shortcut drops and what it must still say.

## Story Types

| Type | Artifacts | Detection signals |
|---|---|---|
| **Feature** | `story.md` + `design.md` + `tasks.md` | New functionality, sprint work, updates, pages, infrastructure |
| **Bugfix** | `story.md` + `design.md` + `tasks.md` | "fix", "bug", "correct", "broken", error descriptions |

## Triage Protocol

**Create and Instant: read [triage.md](../../references/triage.md) now, before anything is written** — the runtime precheck, the three scales, the workflow variants and the triage protocol with its proposal line. Instant reads it with its pins already set.

**Then load the requester's register, before the plan is written** — triage reads `requester.level`, and the register is where that level's defaults live: [plain-register.md](../../references/plain-register.md) for a `layperson`, [developer-register.md](../../references/developer-register.md) for a `developer`. Read the whole file; it is short. A layperson's defaults are not optional: tests are written and run in every scale, git is never a question, and nothing technical is asked — skipping the register is how a beginner's program ships with no test.

## Clarify Protocol

**When a question round runs, read [clarify.md](../../references/clarify.md) first** — Standard and Full always, Fast when the request is ambiguous. Instant never asks and never loads it.

## Phase Execution

**Standard and Full: read [phase-execution.md](../../references/phase-execution.md) before writing the first phase** — completeness checklist, phase order, draft saving and resume.

## Output Rules

**Before creating or refining any story artifact, read [output-rules.md](../../references/output-rules.md)** — path, numbering, the shared frontmatter and the version history.

