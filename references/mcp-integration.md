# MCP Integration

Epic sub-agents can use MCP (Model Context Protocol) servers when available. The goal is to **prefer what is already installed** on the user's system, respect cost, and fall back gracefully to Claude Code's native web tools (`WebFetch`, `WebSearch`) when no research MCP is present.

This document covers **research** MCPs (docs, web search) and, in its own section below, the **memory** MCP. For the policy on selecting an E2E testing tool or a frontend implementation aid — favorite vs. optional tiers, detection, and the recommend-and-pause fallback — see [preferred-tooling.md](preferred-tooling.md).

## Priority order

When multiple research MCPs are detected, pick the first one from this ordered list. This list is the default; if the user explicitly asks for a different one, honor the request.

| # | MCP | Role | Cost | When to pick |
|---|---|---|---|---|
| 1 | `context7` | Library / framework / SDK documentation | Free | Always, for doc lookups — never skip when available |
| 2 | `brave-search` | General web search | Low | Default for web research |
| 3 | `exa` | Semantic web search | Low | Alternative to brave-search when more relevance is needed |
| 4 | `tavily` | Research + extraction | Low–medium | Multi-hop research with structured output |
| 5 | `firecrawl` | Crawling / scraping | Medium | When the task needs full-page extraction |
| 99 | `perplexity` | Premium reasoning search | **High (paid per query)** | **Last resort only.** Never the default. Only when the user explicitly asks, or when every lower-priority option has failed health-check |

### Hard rules

- **Never suggest `perplexity` by default.** It is premium and expensive. The plugin only uses it when the user explicitly asks for it, OR when every other research MCP has been health-checked and failed — and in that case, the plugin must ask before calling: `"All free/low-cost research MCPs are unavailable. Fall back to perplexity (premium cost per query)? [y/n]"`.
- **`context7` is always included** when available, independently of the search MCP choice — it serves a different category (docs, not web search).
- If the user's system has `brave-search` + `perplexity` installed, the plugin uses `brave-search` and ignores `perplexity` unless the user explicitly invokes it.
- If no research MCP is available, **fall back to Claude Code's native tools** (`WebFetch`, `WebSearch`) and surface one proactive suggestion (see "No MCP available" below).

## Health check procedure

Before suggesting any MCP during triage, check that it is connected — without calling it. Claude Code already reports this: a connected server's tools are in your tool list (directly or as deferred tools), and a server that failed to connect is named in a failure notice with its error.

1. A candidate is **available** when its tools are in the tool list and no failure notice names it. Make no probe call: a probe spends a metered query, may raise a permission prompt, and teaches nothing the tool list does not.
2. If it is **not available**: do NOT suggest it. Drop to the next candidate in the priority list for the same category.
3. A server can be connected and still fail on its first real call (an expired key, an exhausted quota). Treat that failure like an absent server: fall back as below, and do not retry it for the rest of the story.
4. Categories:
   - **Docs**: `context7`
   - **Web search / research**: `brave-search` → `exa` → `tavily` → `firecrawl` → `perplexity` (never the default: it is premium; suggest it only when the user has opted in)

Present only available MCPs to the user.

## No MCP available

If no research MCP is detected (empty category after health-check):

1. Fall back to Claude Code's native `WebFetch` and `WebSearch` tools for research tasks. Do not block the flow.
2. Surface a one-time suggestion in the triage output:

   > "No research MCP detected. Epic will use Claude Code's native `WebFetch` / `WebSearch`. For better research quality, consider installing one of: `brave-search` (recommended default, low cost), `exa`, or `tavily`. See https://code.claude.com/docs/en/mcp#find-and-connect-mcp-servers."

3. Let the user choose:
   - Proceed without an MCP (default — use native tools).
   - Install one now (pause and point to the install docs).

Never hard-block triage on missing MCPs. The suggestion is informative, not gating.

## Memory MCP

A second category, separate from research: **memory**. One candidate, `ai-memory`, the long-term project-memory server. It is **optional and recommended**: when it is reachable the story is enriched by what the project already knows; when it is not, nothing changes — every reader of memory below behaves as it does without memory, and the only trace is one line in the triage proposal.

Its LLM work — the consolidation that turns raw observations into pages, the lint that finds contradictions between them — needs a provider Anthropic's terms allow for a third-party tool: an **API key** with a Haiku-class model, since the work is summarisation, or a **local model** through an OpenAI-compatible endpoint. **Never a Claude subscription OAuth token.** Since February 2026, OAuth from the Free, Pro and Max plans is for Claude Code and Claude.ai only — any other product, tool or service, the Agent SDK included, is outside the terms — and ai-memory's own documentation warns that its `anthropic-oauth` provider risks the account. The Epic's own reads and writes below need no LLM on the server at all.

### Detection

- **Health check:** one call to `memory_status`. It is local and free, so — unlike the research checks — it runs in **every scale, Fast and spike included**. A success marks memory as available for the whole story; a failure, or a tool that is not there at all, marks it unavailable, silently.
- **Opt-out:** `aiMemory` set to `off` (its value is in SKILL.md's *Plugin options*) skips the check and every memory read or write below.
- **Scope is the server's rule, not ours.** Follow the ai-memory server's own scope instructions, which reach you whenever it is connected. When scope cannot be resolved, treat memory as **unavailable**.
- Record the outcome once, in the triage proposal's `**Memory:**` line, and reuse it for the whole story — the same reuse rule the research MCPs follow.

### Where memory is read and written

| Point | Read | Write |
|---|---|---|
| Triage / Phase 1 — [context-discovery.md](context-discovery.md#prior-knowledge) | `memory_recent` (5) and one `memory_query` built from the request's own nouns | — |
| Run — [run-mode.md](run-mode.md#procedure) | one `memory_query` per run for prior deviations, discoveries and gotchas on the detected techs, passed to every Executor as Project State | at End of Run, the deviation register as one page: `epic/deviations/NNN-<slug>.md` |
| Validate — [validate-mode.md](validate-mode.md#auditor-sub-agent) | prior structural audit findings, handed to the Auditor as things to verify | after the verdict, one page per structural finding: `epic/audit/<subject>.md` |

**The orchestrator is the only writer.** Pages are composed from files that already exist — `.draft/deviations.yaml`, `.draft/audit-report.yaml` — so no sub-agent needs a memory tool in its grant, and the sub-agents' own `.claude/agent-memory/` directories are untouched by this section.

**Supersession is by path.** `memory_write_page` versions a page in place: writing the same `path` again replaces what search returns, and there is no `supersedes` argument to pass. So every page above lives at a **stable path** — the story number for deviations, the subject for audit findings — and an updated finding is a rewrite of that path, never a second page beside the old one. Start each body with an H1 and omit the `title` argument.

### Hard rules

- **Memory is never evidence.** A recalled page says where to look; a finding still needs the file and the line that show it. An audit gap, a deviation verdict or a coverage claim resting on memory alone is a protocol violation — memory is an input to verify, not a source to quote. A recalled page can describe code that has since changed, so a finding that rests on it alone can report a defect the code does not have.
- **Never call `memory_feedback`**, and never write a handoff by hand — the server's own lifecycle hooks capture sessions and hand off between them. The Epic writes durable pages and nothing else.
- **Never copy a secret, a token or personal data** into a page. The register and the audit report are the sources; if one of them carries such a value, it is dropped from the page, not carried over.
- **Recommend `ignore_paths = [".epic/**"]`** in the user's `.ai-memory.toml`, once, the first time memory is detected on a project — the server's hooks would otherwise capture the artifacts the Epic already versions, and the two records would drift. Informative, never gating.

## Rules

- Only suggest MCPs relevant to the current mode (don't list all installed MCPs unconditionally).
- Always health-check before suggesting — never recommend an MCP that is not connected.
- Research-capable sub-agents (analyst, architect, executor, tech-reviewer) carry native `WebFetch`/`WebSearch` as a guaranteed fallback; a sub-agent calls a research/docs MCP only when its own tool grant includes it. The verified MCP list is passed in the sub-agent prompt as a preference — MCP-based research is most reliable from the orchestrator, which has full tool access.
- For **Fast mode**: skip MCP detection entirely — the overhead outweighs the gain for 1–2 file changes. The one exception is the memory check (see Memory MCP): a single local call, so Fast runs it too.
- For **Standard/Full mode**: run the health-check once during triage and reuse the result for the whole story.
- Perplexity's cost rule applies even during clarify rounds: never auto-call it.
