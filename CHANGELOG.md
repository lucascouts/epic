# Changelog

All notable changes to the Epic plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each release notes the **minimum Claude Code version** required to use the new
capabilities introduced in that version. Earlier Claude Code versions degrade
gracefully (see README "Prerequisites").

## [Unreleased]

_Capabilities adopted but not yet released. See README and `references/` for the full surface._

## [0.1.2] — 2026-04-19

### Fixed
- **`plugin.json` userConfig schema** — install was failing with `Validation errors: userConfig.*.type: Invalid option ...` because each entry now requires `type` (one of `string` | `number` | `boolean` | `directory` | `file`) and `title`. Added both fields to all five userConfig entries and converted numeric defaults from string (`"7"`, `"3600"`) to number (`7`, `3600`).

## [0.1.1] — 2026-04-19

### Added
- **`.claude-plugin/marketplace.json`** — enables one-line install via `/plugin marketplace add lucascouts/epic` + `/plugin install epic@lucascouts`. Marketplace name: `lucascouts`; plugin `epic` sourced from the same repo (`source: "./"`).

## [0.1.0] — 2026-04-19

Initial public release. Internal pre-public history (referenced in `references/teams-mode.md` as "1.3.0 → 1.4.0") is collapsed into this release.

**Minimum Claude Code:** v2.1.105 for full capability surface (plugin monitors with `when:`, `PreCompact` hook, `EnterWorktree.path`, skill description cap of 1,536 chars, `effort` field on skills/agents). Degraded operation on v2.1.85+ (no compact recovery; conditional hooks still work; monitors absent).

### Plugin manifest (`plugin.json`)

- Top-level metadata: `name`, `version`, `description`, `author`, `license`, `homepage`, `repository`, `keywords`.
- **`userConfig`** with 5 options (all non-sensitive, exported as `CLAUDE_PLUGIN_OPTION_*` env vars):
  - `defaultScale` (string, default `"standard"`) — fallback mode when triage cannot determine complexity
  - `artifactLanguage` (string, default `"en"`) — override only if the organisation mandates non-English artifacts
  - `enableStaleMonitor` (boolean, default `false`) — opt-in for the stale-story background watcher
  - `staleThresholdDays` (number, default `7`) — days of inactivity before a story is flagged
  - `staleCheckIntervalSeconds` (number, default `3600`) — poll cadence

### Marketplace (`marketplace.json`)

- Single-plugin marketplace named `lucascouts`, sourced from the same repo (`source: "./"`).

### Skill — `/epic:task`

- Scale-adaptive workflow with three modes (Fast / Standard / Full) and two workflow variants (Requirements-First / Design-First).
- Sub-routes: `init`, `stories`, `stories full`, `stories NNN`, `stories run NNN [--auto|--batch=N|--gate=commit]`, `stories validate NNN`, `stories refine NNN`, `stories archive NNN[-MMM]|--done`, `stories teams {status|enable|disable}`, `archive`.
- Frontmatter uses `effort: max`, `paths: [".epic/**", "tasks.md", "story.md"]`, full `allowed-tools` whitelist (incl. `EnterWorktree`/`ExitWorktree`).
- Inline shell `!` blocks for project-state context (existing stories, constitution head, git HEAD); falls back gracefully when `disableSkillShellExecution: true`.

### Sub-agents (8)

| Agent | Role | Activated for |
|---|---|---|
| `analyst` | Codebase scan, completeness checklist | Standard + Full |
| `architect` | Pattern research, gotcha capture | Full |
| `test-advisor` | Defines tests per sub-task | Standard + Full (Phase 3) |
| `reviewer` | Cross-artifact review | Full |
| `executor` | 6-step implementation protocol | Simple+ tasks (all scales) |
| `tech-reviewer` | Multi-tech boundary correctness | All scales (multi-tech) |
| `validator` | Runs validation commands | All scales |
| `auditor` | Story/design fidelity, scope creep | All scales |

All agents declare `model: inherit`, `tools` whitelist, `maxTurns`, and `effort` calibrated by role.

### Hooks (7 events, all `if:`-filtered or matcher-scoped)

- `PostToolUse(Write, if: Write(.epic/**))` → `validate-story.sh`
- `PreToolUse(Edit|Write, if: Edit/Write(.epic/archive/**))` → blocks edits to archive
- `PreToolUse(Bash, if: Bash(git commit *))` → `permissionDecision: "defer"` in CI/headless
- `PreCompact` → snapshots active story to `.draft/compact-snapshot.md` _(requires v2.1.105)_
- `SessionStart(compact)` → re-injects snapshot into context
- `SessionEnd(clear)` → cleanup
- `TaskCompleted` → re-runs validate against active story
- `PermissionDenied(matcher: mcp__.*)` → returns `{retry: true}` _(requires v2.1.89)_

### Plugin monitors (1, opt-in)

- `epic-stale-stories` (`when: on-skill-invoke:task`) — surfaces stories with no progress past `staleThresholdDays`. Requires `enableStaleMonitor: true` and Claude Code v2.1.105+.

### Output style (1, opt-in)

- `epic` style for triage proposals, phase gates, run reports, validator/auditor output. Declares `keep-coding-instructions: true` _(requires v2.1.94)_.

### `bin/` executables (PATH-exposed)

- `epic-validate` (wrapper around `validate-story.sh`)
- `epic-xref` (wrapper around `cross-reference.sh`)

_(Plugin `bin/` requires Claude Code v2.1.91+.)_

### Scripts (10)

- `validate-story.sh`, `cross-reference.sh` — validation engines (JSON output, exit 0/1/2).
- `hook-validate.sh`, `hook-archive-guard.sh`, `hook-defer-commit.sh`, `hook-precompact.sh`, `hook-session-restore.sh`, `hook-task-completed.sh`, `hook-session-end-cleanup.sh` — hook implementations.
- `monitor-stale.sh` — opt-in background watcher.
- `teams-config.sh` — manages `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` flag in `.claude/settings.local.json`.
- `run-evals.sh` — runs the eval suite.

### References (17 markdown files)

- Mode-specific operational guides: `init-mode.md`, `list-mode.md`, `run-mode.md`, `validate-mode.md`, `refine-mode.md`, `ci-mode.md`, `teams-mode.md`.
- Methodology: `ears-notation.md`, `requirements.md`, `design-guide.md`, `tasks.md`, `bugfix.md`, `bugfix-design.md`, `phase-gates.md`, `self-review-checklist.md`, `context-discovery.md`, `mcp-integration.md`, `constitution.md`.

### Examples & evals

- `assets/examples/`: `fast-feature.md`, `standard-feature.md`, `full-feature.md`, `bugfix-complete.md`.
- `evals/`: 6 cases + 24 trigger queries with `run-evals.sh`.

### Tests & CI

- `tests/`: `validate-story.bats`, `teams-config.bats` (bats unit tests).
- `.github/workflows/shell.yml`: shellcheck + bats + example validation.

### Agent-teams integration (experimental, opt-in)

- During Full-mode triage with 2+ independent tracks, offers `[y]/[n]/[never]` proposal to enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` _(requires v2.1.32)_.
- Teammates reuse the `executor` agent definition (one per track, in its own context).
- `/epic:task stories teams {status|enable|disable}` for direct flag management.
- Per-project opt-out via `.epic/teams-opt-out` sentinel file.

[Unreleased]: https://github.com/lucascouts/epic/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/lucascouts/epic/releases/tag/v0.1.2
[0.1.1]: https://github.com/lucascouts/epic/releases/tag/v0.1.1
[0.1.0]: https://github.com/lucascouts/epic/releases/tag/v0.1.0
