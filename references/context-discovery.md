# Context Discovery

## File Discovery (all scales)

1. Glob for `spec.md`, `roadmap.md`, `*.spec.md` in project root
2. Check for `.epic/stories/` directory (existing stories)
3. Check for `.epic/constitution.md`
4. Check for `docs/` with relevant documentation
5. Check for `CLAUDE.md`, `AGENTS.md` in project root and parent directories

Include findings assertively in triage. If user mentions files directly, use them without asking.

## Prior Knowledge

Runs in **all scales**, and only when triage step 7a found memory available ([mcp-integration.md](mcp-integration.md#memory-mcp)). Two calls, before the Analyst is spawned and before any inline question is asked:

1. `memory_recent` with `limit: 5` — what the last sessions on this project left behind
2. one `memory_query` whose query is the request's own nouns joined by `OR` — the entities, actions and files the user named — with `limit: 10`

The hits are injected as a **Prior Knowledge** block in the triage proposal and in the Analyst prompt below, one line per hit: path, title, snippet. Rules:

- **A hit is a lead, not a fact.** The Analyst verifies it against the code before it reaches the story; a stale page loses to the file every time, and a hit no file supports is dropped without comment
- Prior knowledge never replaces the Codebase Analysis — it points the Analyst at what past stories found surprising, so the scan starts there instead of from zero
- Nothing here asks the user anything; a user who mentioned files directly still has them used without asking
- Absent memory, this section is skipped in silence and the flow below is unchanged

## Codebase Analysis (standard + full scales)

If existing code is detected, spawn the **Analyst** sub-agent:

> "Analyze this project and the user's request to provide context for story creation.
>
> User request: [original request]
> Context files found: [list]
> Available MCPs: [list of relevant MCPs approved by user]
> Prior knowledge (from memory — verify against the code before using any of it): [Prior Knowledge hits, or "none"]
>
> Tasks:
> 1. Scan directory structure — detect architectural pattern, framework, key dependencies
> 2. Sample 3-5 representative files — detect naming conventions, patterns, module organization
> 3. Look up best practices relevant to the request domain — via a research MCP if one is available to you, otherwise `WebSearch`
> 4. Fetch current docs for the detected framework/libraries — via a documentation MCP if available to you, otherwise `WebFetch`/`WebSearch`
>
> Return a concise summary (max 20 lines) covering:
> - Detected project patterns and conventions
> - Relevant best practices or patterns from research
> - Potential integration points with existing code
>
> Do NOT read every file — be lightweight and fast."

Results are saved to `.draft/meta.yaml` under `analyst_output` key and passed as context to Phase 2 (design) and the Completeness Checklist.

## Context File Usage

| File | Applied At |
|---|---|
| `.epic/constitution.md` | Before Phase 1 (all scales); its `## Defaults` block again at Clarify and Run, as decisions taken silently |
| `CLAUDE.md` | Phase 2 (design) + Phase 3 (tasks) |
| `AGENTS.md` | Phase 2 (design) + Phase 3 (tasks) |
| Analyst output | Triage + Completeness Checklist + Phase 2 (design) |
| Prior knowledge (memory, when detected) | Triage + Codebase Analysis — as leads to verify, never as facts |

- Files are read if they exist, silently skipped if absent
- Content is injected as context, not modified
- Conflicts between context files and user input → user input wins
- Constitution constraints appear as `[CONSTITUTION]` tags in story requirements
- Constitution `## Defaults` are applied, never re-asked — [plain-register.md](plain-register.md#decisions-the-requester-is-not-asked)

## Completeness Checklist

For **standard and full scales**, spawn the **Analyst** sub-agent to generate a context-specific checklist. For **fast and spike scales**, ask 1-2 inline questions only — both are single-author scales, with no sub-agents and no `.draft/meta.yaml` to cache an Analyst's output in, and a probe whose whole point is to be time-boxed is not improved by a 10-question intake.

**Analyst sub-agent prompt (uses cached output from Codebase Analysis):**

> "Generate a completeness checklist of clarifying questions for this story.
> Use the codebase analysis below as your ONLY source of project information — do NOT re-scan the codebase.
>
> Codebase analysis (from triage — mandatory, always present):
> [Analyst output from Context Discovery, stored in .draft/meta.yaml]
>
> User request: [original request]
> Context files: [summaries of CLAUDE.md, constitution, etc.]
> Available MCPs: [list of approved MCPs]
>
> Focus exclusively on:
> 1. Identify every entity, action, input, and collection in the request
> 2. For each, determine what implicit decisions the user hasn't stated
> 3. For each state-changing action (create, login, enable, open, start), verify the inverse (delete, logout, disable, close, stop) is addressed or explicitly excluded
> 4. Check for common pitfalls and edge cases in this domain — via a research MCP if one is available to you, otherwise `WebSearch`
> 5. Generate 5-10 assertive questions formatted as: 'I understand X will work as Y. Confirm?'
> 6. For each proposed approach, evaluate whether it fully satisfies the requirement's intent
>
> Do NOT read files or scan directories to re-analyze the project — the codebase analysis above is current.
> Do NOT ask questions already answered by the request."

**Rules:**
- Present all questions to the user in a single numbered list
- If the user answers "out of scope", add to Out of Scope in story.md
- For fast and spike scales: skip the sub-agent, ask 1-2 inline questions only if needed
