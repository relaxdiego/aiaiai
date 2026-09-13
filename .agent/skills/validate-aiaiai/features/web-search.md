# Web search

SearXNG gives agents web search without a paid search API. It listens on loopback only, and agents reach it through LiteLLM. Any client can call `POST /v1/search/local-search`. Claude Code's built-in `web_search` tool is served by LiteLLM's interception callback on Bedrock calls.

## Sub-features

- `search-endpoint` returns results from `POST /v1/search/local-search`.
- `search-interception` answers Claude Code's `web_search` tool during a Bedrock call.

## How to get to it (user POV)

- Call `POST http://<LITELLM_HOST>:4000/v1/search/local-search` with an agent key and `{"query": "..."}`.
- Ask Claude Code, configured against the gateway, to search the web.

## Driving it with validate.sh

Preconditions:

- `agent-keys` passed, so a minted key exists.
- The machine can reach the public internet.

- **Search endpoint.** `validate.sh drive "$OUT" web-search` sends `{"query":"Linux kernel","max_results":3}` with the agent key. Checks `search-endpoint-200` and `search-returns-results` pass on HTTP 200 with a non-empty `results` list. LiteLLM 1.89.2 ignores `max_results` for SearXNG, so expect about 20 results, not 3.
- **Interception.** Recorded as `SKIP`. It needs a real Bedrock call, and the validator has no credentials.
- **Proof.** `evidence/web-search/search.txt`.

## Gotchas

- Upstream engines rate-limit by IP. The template disables Google and Startpage, which serve CAPTCHAs to self-hosted instances, and enables Bing because Brave and DuckDuckGo often throttle. An empty result list usually means every enabled engine was throttled, but a SearXNG misconfiguration looks the same. Read the SearXNG log before blaming throttling.
- The redacted log reaches `evidence/logs/process-compose.log` only when `secret-hygiene` or cleanup runs. Before that, read `$OUT/repo/logs/process-compose.log`.
- Only LiteLLM needs SearXNG. Do not expose port 8888 to the VM.
