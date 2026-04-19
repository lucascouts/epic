# MCP Integration

During triage, detect available MCP servers that could enhance sub-agent capabilities. **Before suggesting any MCP, verify it works** by making a lightweight test call (e.g., a simple search query or health check). This prevents recommending MCPs that are unavailable due to expired API keys, missing balance, rate limits, or misconfiguration.

## Health Check Procedure

1. For each candidate MCP, attempt a minimal call (e.g., `brave_web_search("test")`, `perplexity_search("hello")`, `resolve-library-id("react")`)
2. If the call **succeeds**: mark MCP as available and include it in the proposal
3. If the call **fails**: do NOT suggest it. Instead:
   - Identify a working alternative from the same category (e.g., if `perplexity` fails, try `brave-search` for research)
   - If no alternative exists in the category, notify the user: "MCP `perplexity` is unavailable ([error reason]). No alternative found for deep research. Consider installing `brave-search` or another search MCP."
4. Group MCPs by capability category to find substitutes:
   - **Research/Search:** perplexity, brave-search, kagi
   - **Documentation:** context7
   - **Other:** domain-specific MCPs

Present only verified MCPs to the user.

## Rules

- Only suggest MCPs relevant to the request (don't list all installed MCPs)
- Always health-check before suggesting — never recommend an untested MCP
- The user can accept, decline, or suggest other MCPs
- MCPs are passed to sub-agent prompts as available tools
- For Fast mode: skip MCP detection
