# MCP Integration

Epic sub-agents can use MCP (Model Context Protocol) servers when available. The goal is to **prefer what is already installed** on the user's system, respect cost, and fall back gracefully to Claude Code's native web tools (`WebFetch`, `WebSearch`) when no research MCP is present.

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

Before suggesting any MCP during triage, verify it is actually reachable.

1. For each candidate MCP, attempt a minimal call:
   - `context7`: `resolve-library-id("react")` or equivalent trivial lookup
   - `brave-search`: `brave_web_search("test")`
   - `exa`: a trivial search query
   - `tavily`: a trivial search query
   - `firecrawl`: a trivial extract on a stable URL
   - `perplexity`: **do not health-check by default** (costs money). Only call when the user has explicitly opted in.
2. If the call **succeeds**: mark MCP as available. Proceed to priority selection.
3. If the call **fails**: do NOT suggest it. Drop to the next candidate in the priority list for the same category.
4. Categories:
   - **Docs**: `context7`
   - **Web search / research**: `brave-search` → `exa` → `tavily` → `firecrawl` → `perplexity` (gated)

Present only verified MCPs to the user.

## No MCP available

If no research MCP is detected (empty category after health-check):

1. Fall back to Claude Code's native `WebFetch` and `WebSearch` tools for research tasks. Do not block the flow.
2. Surface a one-time suggestion in the triage output:

   > "No research MCP detected. Epic will use Claude Code's native `WebFetch` / `WebSearch`. For better research quality, consider installing one of: `brave-search` (recommended default, low cost), `exa`, or `tavily`. See https://code.claude.com/docs/en/mcp#find-and-connect-mcp-servers."

3. Let the user choose:
   - Proceed without an MCP (default — use native tools).
   - Install one now (pause and point to the install docs).

Never hard-block triage on missing MCPs. The suggestion is informative, not gating.

## Rules

- Only suggest MCPs relevant to the current mode (don't list all installed MCPs unconditionally).
- Always health-check before suggesting — never recommend an untested MCP.
- MCPs are passed to sub-agent prompts as available tools; the sub-agent decides when to call them.
- For **Fast mode**: skip MCP detection entirely — the overhead outweighs the gain for 1–2 file changes.
- For **Standard/Full mode**: run the health-check once during triage and reuse the result for the whole story.
- Perplexity's cost rule applies even during clarify rounds: never auto-call it.
