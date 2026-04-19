# Context Discovery

## File Discovery (all scales)

1. Glob for `spec.md`, `roadmap.md`, `*.spec.md` in project root
2. Check for `.epic/stories/` directory (existing stories)
3. Check for `.epic/constitution.md`
4. Check for `docs/` with relevant documentation
5. Check for `CLAUDE.md`, `AGENTS.md` in project root and parent directories

Include findings assertively in triage. If user mentions files directly, use them without asking.

## Codebase Analysis (standard + full scales)

If existing code is detected, spawn the **Analyst** sub-agent:

> "Analyze this project and the user's request to provide context for story creation.
>
> User request: [original request]
> Context files found: [list]
> Available MCPs: [list of relevant MCPs approved by user]
>
> Tasks:
> 1. Scan directory structure — detect architectural pattern, framework, key dependencies
> 2. Sample 3-5 representative files — detect naming conventions, patterns, module organization
> 3. If research MCPs are available, look up best practices relevant to the request domain
> 4. If documentation MCPs are available, fetch current docs for detected framework/libraries
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
| `.epic/constitution.md` | Before Phase 1 (all scales) |
| `CLAUDE.md` | Phase 2 (design) + Phase 3 (tasks) |
| `AGENTS.md` | Phase 2 (design) + Phase 3 (tasks) |
| Analyst output | Triage + Completeness Checklist + Phase 2 (design) |

- Files are read if they exist, silently skipped if absent
- Content is injected as context, not modified
- Conflicts between context files and user input → user input wins
- Constitution constraints appear as `[CONSTITUTION]` tags in story requirements

## Completeness Checklist

For **standard and full scales**, spawn the **Analyst** sub-agent to generate a context-specific checklist. For **fast scale**, ask 1-2 inline questions only.

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
> 4. If research MCPs are available, check for common pitfalls and edge cases in this domain
> 5. Generate 5-10 assertive questions formatted as: 'I understand X will work as Y. Confirm?'
> 6. For each proposed approach, evaluate whether it fully satisfies the requirement's intent
>
> Do NOT read files, scan directories, or call MCPs for project research — the analysis above is current.
> Do NOT ask questions already answered by the request."

**Rules:**
- Present all questions to the user in a single numbered list
- If the user answers "out of scope", add to Out of Scope in story.md
- For Fast mode: skip sub-agent, ask 1-2 inline questions only if needed
