# Memory modes — stories from memory, docs from memory

Two modes turn what the memory pool learned into something the project keeps, and neither touches code: **memory → story → run** is the only way a finding becomes a change, and **memory → doc diff → the user's yes** is the only way it becomes a document. Both need memory available ([mcp-integration.md](mcp-integration.md#memory-mcp)); without it, say so in one line and stop.

## Stories from memory

`/epic:epic stories from-memory [<page>]` drafts a story from a `proposal` page ([Typed pages](mcp-integration.md#typed-pages)) — a change an outside classifier or a supervisor thinks the project needs.

1. **Pick the proposal.** With `<page>`, read it (`memory_read_page`). Without, list this project's `epic/proposal/` pages not yet drafted (no `drafted:` line), newest `as_of` first, at most ten, and ask which one with `AskUserQuestion`. Headless: print the list and stop — choosing a story to open is the user's decision, never an assumption.
2. **Verify it against the code** ([lookup-order.md](lookup-order.md)). Every file, line, behaviour or number the page states is checked; what no longer holds is said beside the proposal, and a proposal whose premise the code contradicts is reported and not drafted.
3. **Draft it through CREATE**, with the verified proposal as the request — triage, the constitution gate, clarify and the phase gates exactly as for any request. The story's `story.md` frontmatter carries `source: memory:<page path>`.
4. **Mark the proposal drafted**: rewrite its page with a `drafted: <NNN-slug>` line under the header, so it is never drafted twice.

The story then runs like any other. Nothing in the proposal is executed, and nothing it says skips a gate.

## Sync docs

`/epic:epic sync-docs` turns `finding` and `decision` pages into a diff for the project's own documents, and writes only what the user accepts.

1. **Collect** this project's `epic/finding/` and `epic/decision/` pages with an `as_of` after the last sync — the date in `.epic/.sync-docs` (absent: every page). Verify each against the code; a page the code contradicts is listed as stale and synced nowhere.
2. **Map each page to its document**, the ones the project has:
   - `ROADMAP.md` — a decision that adds, drops or reorders planned work
   - the PRD (`PRD.md`, `docs/PRD.md`) — a decision that changes a requirement or its scope
   - `.epic/constitution.md` `## Invariants` — a finding that became a rule, as `- Never <X> — <the incident>`; `epic-claude-md write` then carries it into `CLAUDE.md`
   - `docs/adr/` — an architectural decision
3. **ADRs are never edited.** A decision that changes an existing ADR is a **new** ADR with the next number, `Supersedes: ADR-<n>` and the reason; the old file is left exactly as it is. A decision with no ADR yet is a new ADR too.
4. **Show the diff, one document at a time, and ask** with `AskUserQuestion` — each document is accepted or declined on its own. Write only what was accepted; headless writes nothing and prints the diff.
5. **Record the sync**: today's date in `.epic/.sync-docs`, and the pages each written document took, in the closing.

Sync docs writes documents, never code, never `.epic/stories/`, and never a page back into memory except the `drafted:`-style markers this file names.
