# Agent Teams (experimental, opt-in)

This reference documents Epic's integration with Claude Code's experimental [agent-teams](https://code.claude.com/docs/en/agent-teams) feature. Agent teams let the Run phase spawn multiple Claude Code instances that work in parallel, each in its own context window, coordinated through a shared task list.

> **Experimental.** Enabling agent-teams opts into a Claude Code feature flag that may change behaviour across upgrades. Epic falls back to the sequential / `EnterWorktree` execution if the flag is inactive.

## When to use

Use agent-teams when a story's Run phase meets **all** of the following:

1. **Scale** is Full (tasks.md produced via Full mode pipeline).
2. **Tracks** — 2+ groups of sub-tasks that touch disjoint files and have no data dependency on each other (e.g. `src/auth/` middleware vs. `migrations/` vs. `ui/settings/`).
3. **Effort** — each track has enough work (3+ sub-tasks) to amortise the coordination overhead.

Do not use when:

- Tracks share files (overwrite conflicts between teammates).
- Work is mostly sequential (migration A must finish before B runs).
- The story is Fast or Standard — overhead dwarfs the gain.
- You are resuming a session (`/resume` / `/rewind` do not restore in-process teammates).

For the generic decision framework, see [agent-teams#when-to-use](https://code.claude.com/docs/en/agent-teams#when-to-use-agent-teams).

## Enable, disable, inspect

Epic ships a subcommand and a script — both do the same thing.

```
/epic:task teams status     # inspect current state
/epic:task teams enable     # sets CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
/epic:task teams disable    # removes the flag
```

Or invoke the script directly:

```bash
bash scripts/teams-config.sh {status|enable|disable}
```

Both paths write to `.claude/settings.local.json` in the project root. This file is **auto-gitignored by Claude Code itself** — you do not need to edit your `.gitignore`.

**Restart required.** Env vars configured via `settings.local.json` are applied when Claude Code starts a session. After enable/disable, exit and relaunch Claude Code for the change to take effect.

Status JSON looks like:

```json
{
  "command": "status",
  "settings_file": ".claude/settings.local.json",
  "state": "active",
  "env_key": "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS",
  "env_value": "1",
  "docs": "https://code.claude.com/docs/en/agent-teams",
  "limitations": "https://code.claude.com/docs/en/agent-teams#limitations"
}
```

`state` is one of: `active`, `inactive`, `not-configured`.

## How Epic uses teams in Run mode

When `stories run NNN` fires **and** the flag is active **and** tasks.md shows 2+ independent tracks, the main session becomes the **team lead** and spawns teammates — one per track — using Epic's existing sub-agent definitions.

```
Lead (this session)
  ├─ teammate "track-auth"    ← uses `executor` agent type
  ├─ teammate "track-ui"      ← uses `executor` agent type
  └─ teammate "track-data"    ← uses `executor` agent type
```

Teammates inherit:

- The `tools` allowlist from their agent definition (`executor`: Read, Write, Edit, Bash, Glob, Grep).
- The agent's `model` and `effort`.
- The agent's body — appended to the teammate's system prompt as additional instructions.
- `CLAUDE.md` files from the working directory.

Teammates **do not** inherit:

- The `skills:` and `mcpServers:` frontmatter fields of the agent definition — those are ignored when a subagent runs as a teammate. Epic's agents do not use these fields, so nothing breaks.
- The lead's conversation history.

After all teammates mark their tasks complete, the lead synthesises a Run report, then calls cleanup on the team. This is the only team allowed per session (see limitations below), so subsequent Run commands in the same session reuse the sequential fallback.

## Fallback behaviour

When the flag is **inactive** or when the story does not meet the "2+ independent tracks" signal, Run mode behaves exactly as in 1.3.0:

- Sequential execution for small stories.
- `EnterWorktree` parallel execution for larger stories.

Enabling the flag **never** makes non-team behaviour go away. It only adds teams as an option when the structure fits.

## Limitations

These are inherited from the upstream feature. Read them before enabling.

| Limitation | Source | Impact on Epic |
|---|---|---|
| Experimental; can change across upgrades | [agent-teams#top](https://code.claude.com/docs/en/agent-teams) | Epic pins only the flag; upstream behaviour changes are user's responsibility |
| No `/resume` or `/rewind` of in-process teammates | [#limitations](https://code.claude.com/docs/en/agent-teams#limitations) | After resume, tell the lead to spawn fresh teammates |
| One team per session | same | Epic uses teams only in the Run phase; Validate/Triage stay sequential in 1.4.0 |
| No nested teams | same | Teammates cannot spawn their own sub-agents. If a track needs heavy research via sub-agents, use sequential mode for that story |
| Task status can lag | same | The `TaskCompleted` hook mitigates partially — if a task is stuck, check manually |
| Split panes require tmux or iTerm2 | [agent-teams#display-mode](https://code.claude.com/docs/en/agent-teams#choose-a-display-mode) | Epic uses `in-process` by default; split panes are the user's opt-in |
| Token usage scales linearly per teammate | [agent-teams#token-usage](https://code.claude.com/docs/en/agent-teams#token-usage) | Epic limits proposals to stories where the structure justifies the cost |

## Troubleshooting

### `teams status` says `inactive` after `teams enable`

The flag was written but the session was not restarted. Close this Claude Code session and start a fresh one. The Claude runtime does not guarantee hot-reload of env vars from `settings.local.json`.

### "team already exists" error when starting a new Run

A previous Run did not clean up its team. Ask the current lead session:

```
clean up the team
```

Or, if the session is gone and the state is stale, remove the stored team manually:

```bash
rm -rf ~/.claude/teams/<team-name>
```

### A teammate fails silently and tasks stall

The lead may not notice immediately. Check on the teammate (Shift+Down in in-process mode, or click the pane in split mode) and either:

- Give it additional instructions directly.
- Ask the lead to spawn a replacement teammate for the remaining work.

### Orphan tmux session

If a session ends without cleanup and split-pane mode was used:

```bash
tmux ls
tmux kill-session -t <session-name>
```

### Flag was set but `/epic:task teams status` still reports `inactive`

Verify by inspecting the file directly:

```bash
jq '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' .claude/settings.local.json
```

If the value is `"1"`, the settings file is correct but the runtime did not pick it up — restart.

## Opt out per project

To tell Epic "never propose agent-teams in this project":

```bash
touch .epic/teams-opt-out
```

The Triage flow reads this file and skips the proposal entirely. Delete the file to re-enable proposals.

## Future expansion

Agent-teams integration in 1.4.0 covers the Run phase only. Natural next candidates, tracked but not implemented:

- **Validate phase** — validator + auditor + tech-reviewer in parallel is a classic "parallel review" use case from the upstream docs. High-value, low-complexity extension.
- **Triage phase** — analyst + architect + reviewer would require sequential dependencies; the gain is marginal. Probably never implemented.

See the `## Decisions documented (not applied)` section in CHANGELOG 1.4.0 for rationale.
