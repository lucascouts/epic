# Preferred Tooling

Epic personas that select an end-to-end (E2E) testing tool, or an implementation aid for a frontend story, must follow this policy. The goal is to **prefer a small set of favorite tools**, fall back to an optional tool only when one is already installed and the task context calls for it, and — when no favorite is present — recommend installing one and pause for the user's decision rather than guessing. This document is the single source of truth referenced by `SKILL.md` triage, the Test Advisor, and the Executor. For research MCP selection (a separate concern), see [mcp-integration.md](mcp-integration.md).

## Priority order

When a story involves E2E testing and more than one E2E tool is available, pick by the **When to pick** column — that column is the context rule. The `#` column is **only** a last-resort tie-break used when the context does not disambiguate between two otherwise-equal candidates; it is not a ranking to walk top-down.

| # | Tool | Tier | Kind | When to pick |
|---|---|---|---|---|
| 1 | `playwright` | Favorite | MCP | Default favorite for any E2E need |
| 2 | `chrome-devtools` | Favorite | MCP | Favorite when the task is Chrome-specific (perf, DevTools traces) |
| 3 | `puppeteer` | Optional | Library/CLI | Already installed; Chrome/Chromium scripting without a favorite |
| 4 | `selenium` | Optional | Library/CLI | Already installed; legacy or multi-browser grid context |
| 5 | `browser-use` | Optional | MCP | Already installed; AI-driven, exploratory interaction |
| 6 | `stagehand` | Optional | MCP | Already installed; AI-driven structured extraction |

`frontend-design` is a Claude Code **skill** — it is not in the E2E table. It is the favorite implementation aid for frontend stories: when a story is a frontend task and `frontend-design` is available, designate it as the preferred implementation aid. If it is not available, fall back to the Executor's default approach after surfacing the install recommendation described under "No favorite available".

### Hard rules

- **Favorites first.** When a story involves E2E and more than one E2E tool is available, prefer a favorite (`playwright`, `chrome-devtools`) over any optional tool. `playwright` is the default favorite; choose `chrome-devtools` only when the task is Chrome-specific.
- **An optional tool is selected only when both conditions hold:** it is already installed, AND the task context clearly requires it. Apply this as a general preference rule — not a fixed signal-to-tool lookup table. Never install an optional tool just to use it; that path is the favorite recommendation below.
- **Multi-fit tie-break.** When multiple installed optional tools could fit, select one by the `When to pick` context; if still tied, fall back to the table `#` order. Record a one-line justification for the choice.
- **No favorite and no fitting optional tool:** record `no E2E tooling available` as a story constraint and proceed — do not block.
- **Detection runs in ALL modes, including Fast mode.** Unlike research-MCP detection, preferred-tooling detection is **not** skipped in Fast mode: it is cheap, and the selection annotations matter for E2E sub-tasks even in a 1–2 file change. Run it during triage in Fast, Standard, and Full mode alike.

## Detection procedure

Run during triage, in **all modes including Fast**, to resolve which tools are available. Each tier has its own mechanism.

1. **MCP tools** (`playwright`, `chrome-devtools`, `browser-use`, `stagehand`): verify availability via a minimal health-check call — the same pattern as the research-MCP health-check in [mcp-integration.md](mcp-integration.md). If the call succeeds, mark the tool available; if it fails, mark it absent.
2. **Library/CLI tools** (`puppeteer`, `selenium`): inspect the dependency manifest **first** (`package.json` and its lockfiles, `requirements.txt`, `pyproject.toml`, etc.). Run a version-probe CLI command (`npx <tool> --version` or the equivalent) **only when the manifest is inconclusive** — never probe unconditionally. Detection must stay passive: read the manifest before running any command.
3. **Skill** (`frontend-design`): check for its presence in the session's available-skills list. Present means available; absent from the list means not available.
4. **When a mechanism cannot run, mark the tool `undetermined`** — never assume it is installed. A mechanism cannot run WHERE there is no dependency manifest present for a library/CLI tool, or WHERE the session's available-skills list is unavailable for `frontend-design`. Mark the affected tool `undetermined` rather than installed, and proceed.

## No favorite available

When a story requires E2E testing and no favorite E2E tool (`playwright`, `chrome-devtools`) is available — or when a story is a frontend task and the `frontend-design` skill is unavailable — present an install recommendation rather than silently downgrading.

1. **Interactive session:** present the install recommendation with a `[y/n]` install/proceed choice, and link to the relevant install docs (https://code.claude.com/docs/en/mcp#find-and-connect-mcp-servers for an MCP tool; the skill's install docs for `frontend-design`). **Pause** for the user's decision.

   > "No favorite E2E tool detected. Epic recommends installing `playwright` (default favorite, MCP). Install now, or proceed with the best available tool? [y/n]  See https://code.claude.com/docs/en/mcp#find-and-connect-mcp-servers."

2. **If the user installs:** re-run detection for that tool and select the favorite.
3. **If the user proceeds without installing:** continue using the best available tool that fits the task context — an installed optional E2E tool when one fits (see "Priority order"), otherwise record `no E2E tooling available` as a story constraint. For a frontend task with no `frontend-design`, fall back to the Executor's default approach.
4. **Headless / non-interactive session:** do **not** pause and do **not** call `AskUserQuestion`. Emit the recommendation as a logged note and proceed immediately with the best available tool (or the recorded constraint). The recommendation is informative, never gating, in a headless session.

## Rules

- The favorite/optional tier lists in this document are the single source of truth — every persona that selects an E2E tool references this file rather than re-deriving the lists.
- Always run the detection procedure before recommending or selecting a tool — never assume a tool is installed.
- Detection runs in **every mode, including Fast** — it is cheap and the selection annotations matter for E2E sub-tasks. Do not skip it.
- Detection is passive: inspect the dependency manifest before running a version-probe command, and probe only when the manifest is inconclusive.
- A tool whose detection mechanism cannot run is `undetermined`, not installed — proceed without assuming availability.
- In an interactive session, a missing favorite triggers a recommend-and-pause `[y/n]` choice; in a headless session, the same recommendation is a logged note and the flow proceeds without blocking.
- When proceeding without a favorite, prefer an installed optional tool only when the task context calls for it; on a multi-fit tie use the table `#` order and record a one-line justification.
