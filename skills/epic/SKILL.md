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

**Before Standard or Full triage, run the precheck in [triage.md](../../references/triage.md#runtime-dependency-precheck-mandatory-before-standardfull-triage).**

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
| **Create** | `/epic:epic` or `/epic:epic <description>` | Read [triage.md](../../references/triage.md), then [clarify.md](../../references/clarify.md) when a round runs, then [phase-execution.md](../../references/phase-execution.md) for Standard/Full |
| **Instant** | `/epic:epic instant <description>` | Read [triage.md](../../references/triage.md) with the three pins of [Instant](#instant--the-disposable-work-shortcut) set — no clarify round |
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

**Every mode loads its reference first.** Create and Instant keep reading this file for routing, Instant, Output Rules, Language and Validation; the protocols they run live in the files named above.

## Instant — the disposable-work shortcut

`/epic:epic instant <description>` is **Create with three pins, not a fourth scale.** It writes the same `tasks.md` every Fast story writes; what it removes is the deciding, not the artifact.

| Pin | Value | Why it is pinned rather than asked |
|---|---|---|
| `scale` | `fast` | the floor every story starts from ([engineering-level.md](../../references/engineering-level.md#how-the-level-is-read)) |
| `engineering` | `experiment` | typing `instant` **is** the answer to the first cascade question — asking it again would be asking someone to repeat themselves |
| Quality legend | the **security floor** only — supported and declared runtime, secrets, dependency CVEs, a README that says how to run it ([quality-catalog.md](../../references/quality-catalog.md#the-security-floor--four-items-no-level-drops)) | the floor is three commands, one file and no configuration file; anything dropped below it would be dropping the machine's safety, not the story's ceremony |

**No technical question round.** The intent cascade is already answered and does not run. A technical choice the request leaves open is taken as a recommended default and recorded on its line — never turned into a question. The requester asked for the short path; spending their turn on a menu is the one thing `instant` exists to avoid.

**The interface speaks the language the request was written in.** `instant` asks nothing, so it does not ask this either — and the artifacts' English is about artifacts, never about the menu the requester reads. Take their language, and say so on its line: *"menu in Portuguese, the language you wrote in — say the word and I'll switch it"*. Shipping an interface the requester cannot read, on a rule that was never about them, is the shortcut deciding something that was not its to decide ([Language](#language)).

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

## Triage Protocol

**Create and Instant: read [triage.md](../../references/triage.md) now, before anything is written** — the runtime precheck, the three scales, the workflow variants and the triage protocol with its proposal line. Instant reads it with its pins already set.

## Clarify Protocol

**When a question round runs, read [clarify.md](../../references/clarify.md) first** — Standard and Full always, Fast when the request is ambiguous. Instant never asks and never loads it.

## Phase Execution

**Standard and Full: read [phase-execution.md](../../references/phase-execution.md) before writing the first phase** — completeness checklist, phase order, draft saving and resume.

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

The `status:` field, its six values and who writes each: [lifecycle-status.md](../../references/lifecycle-status.md). Read it before writing or reading `status:`.

## Language

**Artifacts are always written in English.** Claude models perform best processing English-language technical content. This ensures optimal quality when artifacts are consumed later for implementation. There is no override for this rule.

- **Spec artifacts** (story.md, design.md, tasks.md): always English
- **EARS keywords**: always English and CAPS (SHALL, WHEN, WHILE, IF, WHERE)
- **Communication with the user**: always in the user's language (detected from their prompt) — **every line they can see, including a note between two tool calls and the closing message**. A status line is communication: "Now closing the final checks" in the middle of a Portuguese conversation is the same defect as an English menu.
- **Code identifiers**: always English (function names, variables, etc.)
- **What the requester's own users read**: the program's interface — menu, prompts, error messages — and the documentation of how to use it (its README). **This is the one thing the English rule does not cover**, and it is not the Epic's to decide: it belongs to whoever will read it.

**The interface language is asked, not assumed.** A request written in a language other than English carries no instruction about the program's own text, and the English rule above is about artifacts — reading it as a rule about the interface ships a menu the requester cannot read, decided by a rule that was never about them. So:

- **Asked once, in the requester's own language**, as an ordinary clarify question: English · the language you wrote to me in · another one. It is a `what` question, not a `how` — the requester is the one who reads the result.
- **Not asked when the request is already in English** — the answer is not in doubt, and a question whose answer is known is a defect in either register ([Clarify Protocol](#clarify-protocol)).
- **When no round will run** — `instant`, or a budget already spent — the default is **the language the request was written in**, taken and stated on its line, never the artifacts' English inherited by mistake.

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
