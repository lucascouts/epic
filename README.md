# Epic — Structured Story Framework for Claude Code

Scale-adaptive plugin for creating, managing, and executing development work as structured stories (features and bugfixes). Epic turns vague requests into EARS-notation requirements, design documents, and a tracked task list — then orchestrates specialized sub-agents to implement, validate, and audit the work.

Invoked as `/epic:task` inside Claude Code.

---

## Why Epic

Ad-hoc prompts lose context, drift in scope, and produce undocumented changes. Epic formalizes the loop:

- **Plan**: EARS requirements (`SHALL ...`), optional design doc with component interfaces, hierarchical tasks with validation commands.
- **Execute**: Sub-agent (`executor`) follows a strict 6-step protocol per sub-task (context → implementation → design fidelity → validation → tests → report).
- **Verify**: Validator runs every validation command; Auditor cross-checks code against story and design for scope creep, deviations, and unmet quality gates.

Scale is chosen per request:

| Mode | Artifacts | When |
|---|---|---|
| **Fast** | `tasks.md` only | 1–2 files, trivial scope |
| **Standard** | `story.md` + `tasks.md` | 2–5 files, clear scope |
| **Full** | `story.md` + `design.md` + `tasks.md` | 5+ files, design decisions, integrations |

---

## Installation

### Local (development)

```bash
git clone https://github.com/lucascouts/epic.git
claude --plugin-dir ./epic
```

### Marketplace (planned)

```bash
claude plugin install epic@<marketplace>
```

Run `/reload-plugins` after updating plugin files.

### Prerequisites

- **Claude Code v2.1.105+** — required for conditional hooks (`if:`), stable plugin skill naming via frontmatter, skill `effort` field, extended descriptions (>250 chars), `EnterWorktree.path`, background monitors, and the `PreCompact` / `SessionStart(compact)` hooks used for context recovery. Epic works on v2.1.85+ with degraded ergonomics (no compact recovery; hooks fire on every Write/Edit regardless of path).
- `bash`, `git`, `jq` available on PATH
- **Optional MCPs** for deeper context and research: `perplexity`, `brave-search`, `context7`. Epic health-checks each MCP before suggesting it; missing MCPs degrade gracefully.
- **Optional tooling for development**: `shellcheck` and `bats` for running the script test suite locally (`bats tests/`).

---

## Quickstart

```bash
# 1. Initialize project configuration (wizard)
/epic:task init

# 2. Create a story (triage proposes scale, you confirm)
/epic:task Add email verification to the user signup flow

# 3. List stories
/epic:task stories

# 4. Run tasks of story 001
/epic:task stories run 001

# 5. Validate the implementation against story + design
/epic:task stories validate 001

# 6. Archive completed stories
/epic:task stories archive 001
```

Artifacts live in `.epic/stories/NNN-kebab-case/` (gitignored by default; keep or commit depending on your workflow).

---

## Command Reference

| Command | Purpose |
|---|---|
| `/epic:task` | Create story from free-text description (triage + clarify + phases) |
| `/epic:task init` | Set up `.epic/constitution.md`, `CLAUDE.md`, sub-agents |
| `/epic:task stories` | List all stories (summary) |
| `/epic:task stories full` | List all stories with tasks |
| `/epic:task stories NNN` | Show one story in detail |
| `/epic:task stories run NNN` | Execute pending tasks of story NNN |
| `/epic:task stories run NNN --auto` | Run non-stop, only halt on failure |
| `/epic:task stories run NNN --batch=N` | Gate every N task groups |
| `/epic:task stories run NNN --gate=commit` | Gate only at Commit sub-tasks |
| `/epic:task stories validate NNN` | Run Validator + Auditor on NNN |
| `/epic:task stories refine NNN` | Delta refinement (versioned) |
| `/epic:task stories archive NNN` | Move completed story to `.epic/archive/` |
| `/epic:task stories teams {status\|enable\|disable}` | Manage the experimental agent-teams flag (opt-in, per-project) |

---

## Architecture

### Sub-agents

| Agent | Role |
|---|---|
| `analyst` | Context discovery, codebase scan, completeness checklist |
| `architect` | Pattern research, design context, gotcha capture (Full mode) |
| `test-advisor` | Defines testing requirements per sub-task (Phase 3, Standard + Full) |
| `reviewer` | Cross-artifact review — gaps, consistency, orphan wiring (Full mode) |
| `executor` | 6-step implementation protocol (context → impl → fidelity → validation → tests → report) |
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
├── skills/task/SKILL.md         # main skill (/epic:task)
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
claude -p "/epic:task Add retry logic to the payment gateway" \
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

When `enableStaleMonitor=true`, a background script (`monitors/monitors.json` → `scripts/monitor-stale.sh`) starts on the first `/epic:task` invocation and periodically reports stories with pending tasks untouched for more than 7 days. Stdout lines surface as notifications to the main agent.

Constraints:

- Requires Claude Code **v2.1.105+**
- Only runs in interactive sessions — skipped on Bedrock, Vertex AI, Microsoft Foundry, and when `DISABLE_TELEMETRY` or `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` are active
- Opt-in by design: without the user option set, the script exits immediately

---

## Agent Teams (experimental, opt-in)

Epic integrates with Claude Code's experimental [agent-teams](https://code.claude.com/docs/en/agent-teams) feature for the Run phase. When enabled, stories with 2+ independent tracks can spawn a dedicated teammate per track, each using Epic's existing `executor` agent definition in its own context window — an alternative to the default sequential / `EnterWorktree` execution.

```
/epic:task stories teams status     # inspect state
/epic:task stories teams enable     # opt in (restart required)
/epic:task stories teams disable    # opt out
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

The `## Project State` block in `skills/task/SKILL.md` uses inline shell execution (`!` prefix) to list existing stories, print the constitution header, and report git HEAD. When the managed setting `disableSkillShellExecution: true` is active, these commands are replaced with `[shell command execution disabled by policy]` and the skill renders without initial context.

The skill still functions — pass the missing context explicitly in the prompt:

```
/epic:task Add password reset. Context: project already has stories 001 (signup), 002 (login).
```

See the [setting reference](https://code.claude.com/docs/en/settings#settings-files) for managed-settings deployment.

### Why Epic does not use `CronCreate` / scheduled tasks

[Scheduled tasks](https://code.claude.com/docs/en/scheduled-tasks) (`CronCreate`, `/loop`) are session-scoped, expire after 7 days, and consume the 50-task session budget. For the stale-story use case Epic uses a [plugin monitor](https://code.claude.com/docs/en/plugins-reference#monitors) instead — it persists for the entire session without polling from the model, and its opt-in userConfig keeps it silent for users who don't want it. For cross-session scheduling (e.g. nightly validation in CI), see the CI example in [`references/ci-mode.md`](references/ci-mode.md) or use [Routines](https://code.claude.com/docs/en/routines).

---

## Design Principles

- **Artifacts in English** — consistent quality across Claude models
- **EARS notation** — `SHALL`, one condition per requirement, each independently testable
- **Hierarchical traceability** — R-numbers flow from story → tasks → code
- **Fail fast** — executors stop on validation failure, never auto-fix silently
- **Draft recovery** — each phase approval saves `.draft/` inside the story directory (gitignored) so interrupted sessions resume cleanly. Drafts live in the project, not in `${CLAUDE_PLUGIN_DATA}`, keeping them tied to the repo and visible to teammates inspecting the same checkout.
- **Numbers never recycled** — archived stories keep their numbers permanently

---

## License

MIT — see [LICENSE](LICENSE).

---

## Related Documents

- [CHANGELOG.md](CHANGELOG.md) — release history
- [SKILL.md](skills/task/SKILL.md) — full skill specification
- [phase-gates.md](references/phase-gates.md) — phase gates and recovery procedures
