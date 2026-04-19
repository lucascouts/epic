# Architecture

Design-level view of the Epic plugin for contributors and integrators. The [README](README.md) covers *what* Epic is and how to install it; this document covers *how the pieces fit together* and *why*.

- Last verified against: **v0.1.5** (`.claude-plugin/plugin.json`)
- If you only want to add a new story mode or tweak an agent prompt, jump to [Extension points](#extension-points).

---

## Reading guide

| If you want to… | Read |
|---|---|
| Understand the end-to-end flow | [Conceptual model](#conceptual-model) |
| Know which file does what | [Component map](#component-map) |
| Trace who calls whom | [Sub-agent pipeline](#sub-agent-pipeline) |
| Know what agents read/write | [Artifact contracts](#artifact-contracts) |
| Debug a hook firing | [Hook matrix](#hook-matrix) |
| Understand how implementation happens | [Executor 6-step protocol](#executor-6-step-protocol) |
| Understand the validation layers | [Validation layers](#validation-layers) |
| Know why a choice was made | [Architectural decisions](#architectural-decisions) |

---

## Conceptual model

Epic turns an unstructured request into a tracked, validated implementation through three phases. Each phase has explicit artifacts, explicit gates, and specialized personas.

```
             ┌──────────────────────── Plan ────────────────────────┐
user request │  triage ─► clarify ─► analyst ─► architect           │
             │                    │           │  (full only)        │
             │                    │           ▼                     │
             │                    └──► story.md ─► design.md        │
             │                                         │            │
             │                                         ▼            │
             │                             test-advisor ─► tasks.md │
             │                                         │            │
             │                              reviewer ◄─┘ (full)     │
             └──────────────────────────────┬───────────────────────┘
                                            │
             ┌────────────────── Execute ───▼────────────────────┐
             │  per sub-task: executor (6 steps) ─► tech-reviewer│
             │                                        (boundary) │
             └────────────────────────┬──────────────────────────┘
                                      │
             ┌────────────────── Verify ─▼──────────────────────┐
             │  validator (per sub-task) ─► auditor (story-wide) │
             └───────────────────────────────────────────────────┘
```

Scale (Fast / Standard / Full) controls which artifacts exist and which personas activate. The triage step emits a single proposal covering complexity, mode, workflow variant, MCPs, and output path — see [`skills/task/SKILL.md`](skills/task/SKILL.md#triage-protocol).

---

## Component map

The plugin surface maps to Claude Code's extension points:

| Directory | Claude Code hook point | Role |
|---|---|---|
| `skills/task/` | Skill | The `/epic:task` entry point. Parses `$ARGUMENTS`, routes to modes, orchestrates agents, writes artifacts. |
| `agents/` | Sub-agents | 8 specialized personas with bounded tool access and dedicated context windows. |
| `hooks/hooks.json` | Hooks | 9 hook events, each `if:`-filtered to `.epic/**` paths or tool-arg patterns. |
| `monitors/monitors.json` | Monitors | Opt-in stale-story watcher (requires CC 2.1.105+). |
| `output-styles/epic.md` | Output style | Optional structured presentation mode. |
| `bin/` | PATH executables | `epic-validate`, `epic-xref` — thin wrappers over `scripts/`. |
| `scripts/` | — | Bash implementations behind hooks, bin, and CI. |
| `references/` | — | Mode-specific operational guides loaded on-demand by the skill. |
| `.claude-plugin/plugin.json` | Manifest | Plugin metadata + `userConfig` schema. |
| `assets/examples/` | — | Reference artifacts for each scale, used as format anchors. |
| `evals/` | — | Trigger-query + test-case suite. |
| `tests/` | — | `bats` unit tests for scripts. |

---

## Sub-agent pipeline

Epic's sub-agents are activated by scale and phase. The main agent (the skill itself) never implements code — it only orchestrates.

### Who activates when

| Persona | Fast | Standard | Full |
|---|---|---|---|
| Analyst | — | Phase 1 | Phase 1 |
| Architect | — | — | Phase 2 |
| Test-advisor | — | Phase 3 | Phase 3 |
| Reviewer | — | — | after Phase 3 |
| Executor | per sub-task | per sub-task | per sub-task |
| Tech-reviewer | multi-tech only | multi-tech only | multi-tech only |
| Validator | per completed task | per completed task | per completed task |
| Auditor | story end | story end | story end |

### Context isolation

Each sub-agent runs in its own context window. The main agent selects inputs (file list, design excerpt, sub-task text) and the sub-agent returns a structured report. No persona has access to the full conversation by default — this is what allows Epic to keep long orchestrations within context limits.

### Tool scoping

Each `agents/*.md` declares its allowed tools. Narrower scopes catch drift early:

- `executor`: `Read, Write, Edit, Bash, Glob, Grep` (implements code)
- `auditor`: adds `LSP` (reads symbols, writes deviation register)
- `analyst`, `architect`, `reviewer`, `test-advisor`, `tech-reviewer`: read-only surfaces
- `validator`: `Read, Glob, Grep, Bash` (runs validation commands, no writes)

---

## Artifact contracts

Artifacts are the stable interface between phases and between agents. Agents pass *artifacts*, not conversation state.

### Story directory layout

```
.epic/stories/NNN-kebab-name/
├── story.md              # requirements (EARS), written phase 1
├── design.md             # design context, written phase 2 (Full only)
├── tasks.md              # hierarchical tasks + validation cmds, phase 3
├── deviation-register.md # appended by executor on INTENTIONAL deviations
└── .draft/               # persisted mid-flight state (gitignored)
    ├── story.md          # after Phase 1 approval
    ├── design.md         # after Phase 2 approval
    ├── meta.yaml         # phase + project-hash + analyst cache
    └── *.md.wip          # checkpoint markers inside long artifacts
```

### Frontmatter contract

Every artifact carries a shared frontmatter block. See [`skills/task/SKILL.md`](skills/task/SKILL.md#output-rules):

```yaml
---
story: <story-name>
type: feature | bugfix
scale: fast | standard | full
version: 1
created: <date>
# optional on refine:
last-refined: <date>
history: [...]
---
```

All files in a story share the same `version`. It's an integer, not semver; bumped only via Refine mode.

### Cross-reference rules

- Requirements in `story.md` use R-numbers (`R1`, `R1.1`, `R2`) and must be independently testable.
- `design.md` components reference R-numbers they satisfy.
- `tasks.md` sub-tasks reference the R-number(s) they realize and the design component(s) they implement.
- `scripts/cross-reference.sh` enforces traceability (required for `--strict`).

### Archive immutability

`.epic/archive/**` is read-only at the tool level: `hook-archive-guard.sh` blocks `Write`/`Edit` via `PreToolUse`. Story numbers are never recycled — archive retains numbers permanently.

---

## Hook matrix

All hooks live in `hooks/hooks.json` at plugin scope, not skill frontmatter — so they fire on `.epic/**` edits even outside a `/epic:task` session (external editor, another skill, plain `Edit`). Each uses an `if:` filter or matcher to stay cheap when Epic is idle.

| Event | Matcher / if-filter | Script | Purpose | Min CC |
|---|---|---|---|---|
| `PostToolUse` | `Write(.epic/**)` | `hook-validate.sh` | Auto-run `validate-story.sh` on every story-artifact write | 2.1.85 |
| `PreToolUse` | `Edit(.epic/archive/**)` · `Write(.epic/archive/**)` | `hook-archive-guard.sh` | Block mutations to archived stories | 2.1.85 |
| `PreToolUse` | `Bash(git commit *)` | `hook-defer-commit.sh` | No-op interactively; returns `defer` when `CI=true`/`CLAUDE_CODE_HEADLESS=true` | 2.1.89 |
| `PreCompact` | — | `hook-precompact.sh` | Snapshot active-story state before autocompaction | 2.1.105 |
| `SessionStart` | `compact` | `hook-session-restore.sh` | Restore state after a compaction rewake | 2.1.105 |
| `SessionEnd` | `clear` | `hook-session-end-cleanup.sh` | Clean transient drafts on explicit clear | 2.1.85 |
| `TaskCompleted` | — (asyncRewake) | `hook-task-completed.sh` | Update tasks.md status markers from Executor reports | 2.1.85 |
| `PostToolUseFailure` | `Bash` | `hook-post-tool-failure.sh` | Capture failing validation context into the story's notes | 2.1.85 |
| `CwdChanged` | — | `hook-cwd-changed.sh` | Detect project switch; reset story cache | 2.1.85 |
| `FileChanged` | `constitution.md` | `hook-file-changed.sh` | Re-evaluate constitution constraints when it changes | 2.1.85 |
| `PermissionDenied` | `mcp__.*` | inline `{"retry": true}` | Retry MCP calls after a permission prompt | 2.1.89 |

Degradation on older CC versions is documented in [README.md#minimum-claude-code-version-per-component](README.md#minimum-claude-code-version-per-component).

---

## Executor 6-step protocol

A sub-task passes through the executor as an ordered pipeline. Skipping any step is a protocol violation — the auditor catches this. Full definition in [`agents/executor.md`](agents/executor.md).

1. **Context gathering** — read every file/doc listed in the sub-task's `Context:` field before writing code.
2. **Implementation** — implement literally what `ToDo:` says; deviate only with a documented reason.
3. **Design fidelity check** — diff the implementation's signatures, error paths, data structures, and contracts against `design.md`. Classify deviations as INTENTIONAL (with rationale, appended to deviation register) or ACCIDENTAL (fix before proceeding).
4. **Validation** — run the sub-task's `Validation:` command; report full output. On failure, STOP.
5. **Tests** — create/run tests listed in the sub-task's `Tests:` field. On failure, STOP.
6. **Report** — structured report back to the main agent.

The main agent does not implement code; the executor does not make scope decisions. This separation is load-bearing for the auditor's effectiveness.

---

## Validation layers

Epic has four distinct validation layers, each catching a different failure mode:

| Layer | When | What it catches | Script / agent |
|---|---|---|---|
| Artifact validation | On every write to `.epic/**` | Malformed frontmatter, missing sections, bad YAML | `scripts/validate-story.sh` (via `hook-validate.sh`) |
| Cross-reference | Manual or `--cross-ref` flag | Orphan R-numbers, design components unreferenced by tasks, tasks without R-numbers | `scripts/cross-reference.sh` |
| Task validation | After each sub-task | Implementation fails the sub-task's declared validation command | `validator` sub-agent + `scripts/validate-story.sh` |
| Story audit | After all tasks complete | Scope creep, deviations not in register, unmet quality gates, integration gaps | `auditor` sub-agent |

`--strict` mode promotes warnings to errors (exit 1 on any warning) — use it in CI gates.

---

## Story lifecycle

```
(request) ─► triage ─► clarify ─► Phase 1 ─► .draft/story.md + meta.yaml
                                    │
                                    ▼
                                  Phase 2 (Full) ─► .draft/design.md
                                    │
                                    ▼
                                  Phase 3 ─► tasks.md + artifacts promoted from .draft/
                                    │
                                    ▼
                                  Run mode ─► executor per sub-task ─► TaskCompleted hook
                                    │
                                    ▼
                                  Validate mode ─► validator + auditor
                                    │
                                    ▼
                                  Archive ─► .epic/archive/NNN-name/  (read-only)
```

Numbers auto-increment across `stories/` + `archive/` and are never recycled. A `999` cap forces archival before further stories are created.

---

## Architectural decisions

Short rationale for choices a contributor might otherwise second-guess:

### Bash for scripts, not Node/Python

All hook scripts and validators are bash. The plugin has zero runtime dependencies beyond `bash`, `git`, `jq` — which are baseline for any development environment. Adding Node/Python would force users into a runtime install for a plugin that mostly shells out to CC itself.

### Single skill (`/epic:task`), not multiple slash commands

Every mode (Create, List, Run, Validate, Refine, Archive, Teams, Init) lives under `/epic:task` via `$ARGUMENTS` routing. This keeps discovery simple (one command to remember), concentrates triage/orchestration in one place, and lets reference files share context-loading rules. Modes that diverge heavily load dedicated `references/*-mode.md` files on entry.

### Scale-adaptive (Fast / Standard / Full)

Forcing full planning ceremony on a 1-file change is user-hostile; skipping planning on a 10-file cross-cutting change is risk-hostile. Scale is chosen per-story during triage with an explicit trade-off statement. Upgrade paths exist (Fast → Standard → Full) if scope grows during planning.

### English-only artifacts, user's language in chat

Artifacts (story/design/tasks) are always English because Claude performs best on English technical content and these artifacts are consumed by later sub-agents. User-facing chat follows the user's prompt language. No override — this is in [SKILL.md](skills/task/SKILL.md#language).

### Hooks at plugin scope, not skill frontmatter

Plugin-scope hooks fire when the user edits `.epic/**` outside an active `/epic:task` session (plain `Edit`, external editor, another skill). Skill-frontmatter hooks would only apply during skill execution — none of Epic's hooks fit that profile. Detailed rationale is embedded in [SKILL.md](skills/task/SKILL.md#validation).

### Archive immutability via PreToolUse block, not convention

A `PreToolUse` hook on `.epic/archive/**` returns a blocking response. Convention-only (a note in the README) would fail when an agent writes without reading the convention. Enforcement at the tool layer is robust against both drift and unfamiliar users.

### Agent-teams as opt-in, project-scoped

Agent-teams is an experimental CC flag. Epic proposes it only when the story has 2+ likely-independent tracks and the project hasn't opted out (`.epic/teams-opt-out`). The proposal never blocks triage — the user picks `y`/`n`/`never` and flow continues. See [`references/teams-mode.md`](references/teams-mode.md).

### `defer` for headless commits

In headless mode (`CI=true`/`CLAUDE_CODE_HEADLESS=true`), `hook-defer-commit.sh` returns `permissionDecision: "defer"` on `git commit`. The Agent SDK wrapper can collect approval out-of-band (Slack, GitHub Action) and resume with `--resume`. Interactive sessions are unaffected. Requires CC 2.1.89+.

### Degrade gracefully on missing MCPs

MCPs (`perplexity`, `brave-search`, `context7`) are health-checked during triage. A missing MCP never blocks the flow — the skill substitutes an alternative or skips that category. No user-visible errors for optional tooling.

---

## Extension points

Common contributions and where they go:

| Change | Touch |
|---|---|
| New story mode (e.g., `review`, `rollback`) | Add routing line in [SKILL.md](skills/task/SKILL.md#command-routing), create `references/<name>-mode.md`, add mode row to Mode Dispatch table |
| New sub-agent persona | Add `agents/<name>.md` with frontmatter (tools, effort, model), wire activation in SKILL.md's persona tables and relevant phase procedure |
| New hook event | Append to `hooks/hooks.json` with `if:` filter, add script under `scripts/hook-*.sh`, document in [Hook matrix](#hook-matrix) |
| New validation rule | Extend `scripts/validate-story.sh` (errors vs warnings), add a `bats` test under `tests/` |
| New user-config field | Add schema entry under `userConfig` in `.claude-plugin/plugin.json`, read via `${CLAUDE_PLUGIN_CONFIG_*}` env in scripts |
| New eval case | Add under `evals/` (trigger-query + expected artifacts), runnable via `scripts/run-evals.sh` |

Before adding a new reference file under `references/`, check whether existing ones can absorb the content — reference fragmentation hurts skill-load discoverability.

---

## Non-goals

Epic deliberately does not do these things. Adding them would conflict with the design:

- **Idea exploration.** Epic formalizes work already decided. It does not brainstorm alternatives or write speculative code.
- **Generic code generation outside a story.** The `/epic:task` command refuses to implement without an approved task.
- **Repo-wide refactors as a single story.** Breaking large refactors into multiple stories is the correct pattern (linked via "based on" / "extends").
- **Runtime dependencies beyond bash/git/jq.** MCPs are optional and health-checked; their absence degrades gracefully.
- **Version-controlled drafts.** `.epic/` (including `.draft/`) is `.gitignored` by default; the user decides when a story is ready to commit.

---

## See also

- [README.md](README.md) — installation, feature list, version-compatibility matrix
- [`skills/task/SKILL.md`](skills/task/SKILL.md) — the orchestrator, command routing, phase execution
- [`references/phase-gates.md`](references/phase-gates.md) — gate protocol, cascade rollback, checkpoint recovery
- [`references/ci-mode.md`](references/ci-mode.md) — headless invocation, deferred commits
- [`references/teams-mode.md`](references/teams-mode.md) — agent-teams experimental flag
- [`references/mcp-integration.md`](references/mcp-integration.md) — MCP health-check procedure
- [`references/constitution.md`](references/constitution.md) — project-level constraints on stories
- [`CHANGELOG.md`](CHANGELOG.md) — release notes per version
