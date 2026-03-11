# Search Fallback Playbook (Brave → DDG MCP)

## Goal
Use Brave as primary search and DuckDuckGo MCP as fallback to improve resilience without changing core provider config.

## Decision Rules (apply in order)
1. **Brave timeout/error**: HTTP/network failure, timeout > 8s
2. **Brave quota/token exhausted**: 401/402/429 or explicit quota-limit message
3. **Zero results**: Brave returns 0 useful results
4. **Low diversity**: fewer than 3 unique domains
5. **Low relevance/freshness gap**: top results not matching intent or missing fresh coverage

If any rule triggers, run DDG MCP search and merge results.

## Output policy
- Label source per result: `[Brave]` / `[DDG]` / `[RSS]`
- Prefer overlap (same fact from 2+ sources) for confidence
- If conflict exists, report both and mark uncertainty
- For news queries, fuse search results with RSS headlines before final summary

## Cost/safety notes (free-tier)
- Keep Brave as default to retain consistency
- Use DDG only on fallback triggers to avoid noise
- Never expose API keys in logs or chat output

## Ops check (weekly)
- Fallback trigger rate
- Duplicate/noise rate
- Time-to-answer impact
- Any blocked/failed provider incidents
