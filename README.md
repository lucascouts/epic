# Epic — Structured Story Framework for Claude Code

Scale-adaptive plugin for creating, managing, and executing development work as structured stories (features and bugfixes). Epic turns vague requests into EARS-notation requirements, design documents, and a tracked task list — then orchestrates specialized sub-agents to implement, validate, and audit the work.

Invoked as `/epic:epic` inside Claude Code.

> **Scope is narrow.** Epic creates, structures, and manages epics/stories — nothing else. It does **not** perform ad-hoc code review, security review, refactors outside a planned story, general analysis, or exploratory code generation. See [PURPOSE.md](PURPOSE.md) for the full in-scope / out-of-scope contract and which Claude Code command to use for each refused case.

---

## Why Epic

Ad-hoc prompts lose context, drift in scope, and produce undocumented changes. Epic formalizes the loop:

- **Plan**: EARS requirements (`SHALL ...`), optional design doc with component interfaces, hierarchical tasks with validation commands.
- **Execute**: Sub-agent (`executor`) follows a strict 6-step protocol per sub-task (context → implementation → design fidelity → validation → refactor-or-tests → report). Step 5 is conditional: Refactor when the sub-task carries a pre-authored failing test, Tests when it does not.
- **Verify**: Validator runs every validation command; Auditor cross-checks code against story and design for scope creep, deviations, and unmet quality gates.

Scale is chosen per request:

| Mode | Artifacts | When |
|---|---|---|
| **Fast** | `tasks.md` only | 1–2 files, trivial scope |
| **Standard** | `story.md` + `tasks.md` | 2–5 files, clear scope |
| **Full** | `story.md` + `design.md` + `tasks.md` | 5+ files, design decisions, integrations |

All three modes are **test-first**. Standard and Full author tests at plan time — the Test Advisor writes one failing test per Unit/Integration/E2E sub-task in Phase 3. For an E2E sub-task the Test Advisor uses the story's selected E2E tool and **defers Red-phase verification to Run mode** (Run confirms the deferred Red before implementation and Green after). Fast mode is **test-first at run time and single-author**: a Fast sub-task carrying a `Tests` field has its test authored by the main agent and confirmed failing (Red) before implementation, then Green-then-Refactor — no Test Advisor sub-agent. A Fast sub-task with no testable logic carries an optional Fast-only `Acceptance` field instead — 1–3 observable-behavior statements; every implementing (non-Commit) Fast sub-task carries either a `Tests` field or an `Acceptance` field. Fast keeps its lightweight scale: no `story.md`, no design, no gate, no `.draft/`.

Epic ships an opinionated **preferred-tooling policy** ([references/preferred-tooling.md](references/preferred-tooling.md)) for E2E test tooling. Triage detects installed E2E tools — favorites are `playwright` and `chrome-devtools` — via MCP health-check, dependency-manifest inspection, and skill-list presence, in **all modes including Fast**. When no favorite is found, Epic recommends one and pauses rather than silently picking an optional tool (`puppeteer`, `selenium`, `browser-use`, `stagehand`). The resolved choice is persisted to `design.md`'s `## Tooling Decisions` block.

---

## Installation

### Marketplace (recommended)

Inside Claude Code:

```
/plugin marketplace add lucascouts/epic
/plugin install epic@lucascouts
```

Or from a shell:

```bash
claude plugin marketplace add lucascouts/epic
claude plugin install epic@lucascouts
```

### Local (development)

```bash
git clone https://github.com/lucascouts/epic.git
claude --plugin-dir ./epic
```

Run `/reload-plugins` after updating plugin files.

### Prerequisites

- **Claude Code v2.1.105+** — required for the full capability surface. Epic works on v2.1.85+ with degraded ergonomics (no compact recovery; hooks fire on every Write/Edit regardless of path; no plugin monitors).
- `bash`, `git`, `jq` available on PATH
- **Optional MCPs** for deeper context and research: `perplexity`, `brave-search`, `context7`. Epic health-checks each MCP before suggesting it; missing MCPs degrade gracefully.
- **Optional tooling for development**: `shellcheck` and `bats` for running the script test suite locally (`bats tests/`).

#### Minimum Claude Code version per component

| Component | Minimum CC version | Behavior on older versions |
|---|---|---|
| Conditional hooks (`if:` field in `hooks/hooks.json`) | **2.1.85** | `if:` ignored — hooks fire on every matched call (noisy but functional) |
| Skill `effort` field | **2.1.85** | Field ignored — inherits session effort |
| Skill description cap raised to 1,536 chars | **2.1.105** | Older sessions truncate at 250 chars (some Epic descriptions get cut) |
| `EnterWorktree.path` (switch into existing worktree) | **2.1.105** | Tool only creates new worktrees |
| `PreCompact` + `SessionStart(compact)` hooks (context recovery) | **2.1.105** | No automatic snapshot/restore around compactions; drafts still work |
| Plugin monitors (`monitors/monitors.json`, `when:` field) | **2.1.105** | Monitor never starts; stale-story detection unavailable |
| Plugin `bin/` executables on PATH | **2.1.91** | `epic-validate`/`epic-xref` not exposed; call scripts directly |
| Output style `keep-coding-instructions: true` | **2.1.94** | Activating `/output-style epic` may override skill directives |
| `PermissionDenied` hook with `{retry: true}` | **2.1.89** | MCP retry-on-deny disabled; user sees raw permission errors |
| `PreToolUse` `permissionDecision: "defer"` (headless commit gating) | **2.1.89** | `hook-defer-commit.sh` is a no-op in CI |
| Agent-teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) | **2.1.32** | Teams proposal silently skipped; falls back to sequential/worktree execution |
| `--bare` flag for headless invocation | **2.1.81** | Use plain `claude -p`; expect slower startup and reduced reproducibility |
| `disableSkillShellExecution` setting honored | **2.1.91** | Inline `!` shell blocks always execute (not blockable by managed policy) |

---

## Quickstart

```bash
# 1. Initialize project configuration (wizard)
/epic:epic init

# 2. Create a story (triage proposes scale, you confirm)
/epic:epic Add email verification to the user signup flow

# 3. List stories
/epic:epic stories

# 4. Run tasks of story 001
/epic:epic stories run 001

# 5. Validate the implementation against story + design
/epic:epic stories validate 001

# 6. Archive completed stories
/epic:epic stories archive 001
```

Artifacts live in `.epic/stories/NNN-kebab-case/` (gitignored by default; keep or commit depending on your workflow).

---

## Command Reference

| Command | Purpose |
|---|---|
| `/epic:epic` | Create story from free-text description (triage + clarify + phases) |
| `/epic:epic init` | Set up `.epic/constitution.md`, `CLAUDE.md`, sub-agents |
| `/epic:epic stories` | List all stories (summary) |
| `/epic:epic stories full` | List all stories with tasks |
| `/epic:epic stories NNN` | Show one story in detail |
| `/epic:epic stories run NNN` | Execute pending tasks of story NNN |
| `/epic:epic stories run NNN --auto` | Run non-stop, only halt on failure |
| `/epic:epic stories run NNN --batch=N` | Gate every N task groups |
| `/epic:epic stories run NNN --gate=commit` | Gate only at Commit sub-tasks |
| `/epic:epic stories validate NNN` | Run Validator + Auditor on NNN |
| `/epic:epic stories refine NNN` | Delta refinement (versioned) |
| `/epic:epic stories archive NNN` | Move completed story to `.epic/archive/` |
| `/epic:epic stories teams {status\|enable\|disable}` | Manage the experimental agent-teams flag (opt-in, per-project) |

---

### Sub-agents

| Agent | Role |
|---|---|
| `analyst` | Context discovery, codebase scan, completeness checklist |
| `architect` | Pattern research, design context, gotcha capture (Full mode) |
| `test-advisor` | Defines testing requirements per sub-task and authors one failing test per Unit/Integration/E2E sub-task with Red-phase verification — E2E tests use the story's selected E2E tool with Red verification deferred to Run mode (Phase 3, Standard + Full) |
| `reviewer` | Cross-artifact review — gaps, consistency, orphan wiring (Full mode) |
| `executor` | 6-step implementation protocol (context → implementation → design fidelity → validation → refactor-or-tests → report); step 5 is conditional — Refactor for a test-first sub-task, Tests for a test-after one |
| `tech-reviewer` | Correctness at technology boundaries (templates, SQL, APIs) |
| `validator` | Runs validation commands and tests per completed task |
| `auditor` | Compares built code against story + design; detects scope creep |

### Automatic validation

When a story artifact is written to `.epic/stories/*/`, a PostToolUse hook runs `scripts/validate-story.sh` to check frontmatter, structure, and cross-references (R-numbers traceability). Archive directories are read-only — edits are blocked by a PreToolUse hook.

---

## Directory Layout

```
epic/
├── .claude-plugin/plugin.json   # manifest (name, userConfig, homepage, repository)
├── settings.json                # plugin defaults (subagentStatusLine)
├── skills/epic/SKILL.md         # main skill (/epic:epic)
├── agents/                      # 8 specialized sub-agents
├── hooks/hooks.json             # 7 hook events, all if:-filtered or matcher-scoped
├── monitors/monitors.json       # opt-in background watcher (stale stories)
├── output-styles/epic.md        # optional structured output style
├── bin/                         # PATH-exposed wrappers (epic-validate, epic-xref)
├── references/                  # mode-specific operational guides
├── scripts/                     # bash validators + hook scripts + monitor + eval runner
├── assets/examples/             # reference outputs for each scale
├── evals/                       # trigger queries + test cases
├── tests/                       # bats unit tests for scripts
└── .github/workflows/           # shell-ci (shellcheck + bats + example validation)
```

---

## CI / Headless Usage

Run validation as a CI step without launching an interactive session:

```bash
EPIC_PLUGIN_ROOT=./epic  # path to cloned plugin
bash "$EPIC_PLUGIN_ROOT/scripts/validate-story.sh" .epic/stories/001-feature/ --cross-ref
```

Use `--strict` in CI gates for stories expected to be production-ready (promotes warnings to errors, exit 1 on any warning):

```bash
bash "$EPIC_PLUGIN_ROOT/scripts/validate-story.sh" .epic/stories/001-feature/ --cross-ref --strict
```

When the plugin is active, the scripts are also on PATH as `epic-validate` and `epic-xref`.

Generate stories programmatically with the Agent SDK:

```bash
claude -p "/epic:epic Add retry logic to the payment gateway" \
  --allowedTools "Read,Write,Glob,Grep,Bash,Agent" \
  --bare --output-format json
```

See [references/ci-mode.md](references/ci-mode.md) for GitHub Actions examples.

### Gated commits in headless mode

Epic ships a `PreToolUse` hook that detects `git commit` invocations. In interactive sessions it is a no-op (normal permission flow applies). When `CI=true` or `CLAUDE_CODE_HEADLESS=true` is set, the hook returns `permissionDecision: "defer"` — pausing the session at the commit and letting an Agent SDK wrapper (GitHub Action, Slack approval bot, etc.) collect a decision before resuming with `-p --resume`. See [`scripts/hook-defer-commit.sh`](scripts/hook-defer-commit.sh) and the [Deferred tool execution docs](https://code.claude.com/docs/en/hooks-guide).

### Running the eval suite

The `evals/` directory ships 6 test cases and 24 trigger queries. The runner invokes `claude -p` against a fresh working directory per case and validates artifacts:

```bash
bash scripts/run-evals.sh                # full suite
bash scripts/run-evals.sh --cases        # artifact generation only
bash scripts/run-evals.sh --triggers     # SKILL description sensitivity only
```

Requires `claude`, `jq`, and network access for MCP health-checks.

---

## Plugin Options

Configurable via the install wizard or directly through settings. Each option is non-sensitive and injected into scripts as `CLAUDE_PLUGIN_OPTION_<KEY>`.

| Option | Default | Purpose |
|---|---|---|
| `defaultScale` | `standard` | Fallback mode when triage cannot determine complexity |
| `artifactLanguage` | `en` | Override only if your organisation mandates non-English artifacts |
| `enableStaleMonitor` | `false` | Enable the background watcher for stories with no progress past the staleness threshold |
| `staleThresholdDays` | `7` | Days of inactivity before a story with pending tasks is flagged (only when stale monitor is enabled) |
| `staleCheckIntervalSeconds` | `3600` | Poll cadence for the stale watcher in seconds (only when stale monitor is enabled) |

---

## Background Monitors (optional)

When `enableStaleMonitor=true`, a background script (`monitors/monitors.json` → `scripts/monitor-stale.sh`) starts on the first `/epic:epic` invocation and periodically reports stories with pending tasks untouched for more than 7 days. Stdout lines surface as notifications to the main agent.

Constraints:

- Requires Claude Code **v2.1.105+**
- Only runs in interactive sessions — skipped on Bedrock, Vertex AI, Microsoft Foundry, and when `DISABLE_TELEMETRY` or `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` are active
- Opt-in by design: without the user option set, the script exits immediately

---

## Agent Teams (experimental, opt-in)

Epic integrates with Claude Code's experimental [agent-teams](https://code.claude.com/docs/en/agent-teams) feature for the Run phase. When enabled, stories with 2+ independent tracks can spawn a dedicated teammate per track, each using Epic's existing `executor` agent definition in its own context window — an alternative to the default sequential / `EnterWorktree` execution.

```
/epic:epic stories teams status     # inspect state
/epic:epic stories teams enable     # opt in (restart required)
/epic:epic stories teams disable    # opt out
```

The flag is written to `.claude/settings.local.json` in the project, which Claude Code auto-gitignores. Nothing global is changed. When the flag is off, Run mode behaviour is identical to 1.3.0.

During Triage of a **Full mode** story, if the request decomposes into independent tracks, the plugin will offer to enable agent-teams with a `[y] / [n] / [never]` prompt. Never activates silently. See [references/teams-mode.md](references/teams-mode.md) for the full reference and [agent-teams limitations](https://code.claude.com/docs/en/agent-teams#limitations).

---

## Output Style (optional)

Epic ships with a structured output style for Triage proposals, Phase Gates, Run reports, and Validator/Auditor output. Activate it with:

```
/output-style epic
```

This is opt-in — no default behaviour changes. Defined in `output-styles/epic.md`. Declares `keep-coding-instructions: true` so activating the style cannot override the skill's implementation directives.

---

## Running in restricted environments

### `disableSkillShellExecution`

The `## Project State` block in `skills/epic/SKILL.md` uses inline shell execution (`!` prefix) to list existing stories, print the constitution header, and report git HEAD. When the managed setting `disableSkillShellExecution: true` is active, these commands are replaced with `[shell command execution disabled by policy]` and the skill renders without initial context.

The skill still functions — pass the missing context explicitly in the prompt:

```
/epic:epic Add password reset. Context: project already has stories 001 (signup), 002 (login).
```

See the [setting reference](https://code.claude.com/docs/en/settings#settings-files) for managed-settings deployment.

### Why Epic does not use `CronCreate` / scheduled tasks

[Scheduled tasks](https://code.claude.com/docs/en/scheduled-tasks) (`CronCreate`, `/loop`) are session-scoped, expire after 7 days, and consume the 50-task session budget. For the stale-story use case Epic uses a [plugin monitor](https://code.claude.com/docs/en/plugins-reference#monitors) instead — it persists for the entire session without polling from the model, and its opt-in userConfig keeps it silent for users who don't want it. For cross-session scheduling (e.g. nightly validation in CI), see the CI example in [`references/ci-mode.md`](references/ci-mode.md) or use [Routines](https://code.claude.com/docs/en/routines).

---

## Design Principles

- **Artifacts in English** — consistent quality across Claude models
- **EARS notation** — `SHALL`, one condition per requirement, each independently testable
- **Hierarchical traceability** — R-numbers flow from story → tasks → code
- **Test-first at every scale** — Standard and Full author failing tests at plan time (Test Advisor, Phase 3); Fast authors them at run time, single-author. A Fast sub-task without testable logic pins behavior via its `Acceptance` field instead
- **Fail fast** — executors stop on validation failure, never auto-fix silently
- **Draft recovery** — each phase approval saves `.draft/` inside the story directory (gitignored) so interrupted sessions resume cleanly. Drafts live in the project, not in `${CLAUDE_PLUGIN_DATA}`, keeping them tied to the repo and visible to teammates inspecting the same checkout.
- **Numbers never recycled** — archived stories keep their numbers permanently

---

## Contributing

See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the maintainer-facing
overview: pipeline, persistence layer, hook web, invariants, and
extension points.

## License

MIT — see [LICENSE](LICENSE).

## Author

[lucascouts](https://github.com/lucascouts) · lucascs@protonmail.com

## Version

0.2.0 — see [CHANGELOG](./CHANGELOG.md).
