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

- **Search endpoint.** `validate.sh drive "$OUT" web-search` sends `{"query":"Linux kernel","max_results":3}` with the agent key. Checks `search-endpoint-200` and `search-returns-results` pass on HTTP 200 with a non-empty `results` list.
- **Interception.** Recorded as `SKIP`. It needs a real Bedrock call, and the validator has no credentials.
- **Proof.** `evidence/web-search/search.txt`.

## Gotchas

- Upstream engines rate-limit by IP. Brave, DuckDuckGo, Qwant, and Startpage often answer a self-hosted instance with CAPTCHAs or 429s, which is why the template enables Bing. An empty result list means every enabled engine was throttled. The redacted SearXNG log is in `evidence/logs/process-compose.log`.
- Only LiteLLM needs SearXNG. Do not expose port 8888 to the VM.
