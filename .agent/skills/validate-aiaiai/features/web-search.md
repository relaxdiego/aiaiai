# Web search

SearXNG gives agents web search without a paid search API. It listens on loopback only, and agents reach it through LiteLLM. Any client can call `POST /v1/search/local-search`. Copilot has no web search. When Claude Code sends its standalone `web_search` request to a Copilot model, LiteLLM answers it from SearXNG without calling Copilot.

## Sub-features

- `search-endpoint` returns results from `POST /v1/search/local-search`.
- `search-interception` answers Claude Code's standalone `web_search` request on `POST /v1/messages` with search results and no Copilot call.

## How to get to it (user POV)

- Call `POST http://<LITELLM_HOST>:4000/v1/search/local-search` with an agent key and `{"query": "..."}`.
- Ask Claude Code, configured against the gateway, to search the web.

## Driving it with validate.sh

Preconditions:

- `agent-keys` passed, so a minted key exists.
- The machine can reach the public internet.

- **Search endpoint.** `validate.sh drive "$OUT" web-search` sends `{"query":"Linux kernel","max_results":3}` with the agent key. Checks `search-endpoint-200` and `search-returns-results` pass on HTTP 200 with a non-empty `results` list. LiteLLM ignores `max_results` for SearXNG, so expect every result SearXNG returns (30 in a recent run), not 3.
- **Interception.** It sends `POST /v1/messages` for `claude-sonnet-5` with the agent key, only the `web_search_20250305` tool, and the user message `Linux kernel`. That is the shape of Claude Code's search sub-request. Check `interception-200` passes on HTTP 200. Check `websearch-interception` passes when the first `content` block is `text` holding SearXNG results as `Title:`, `URL:`, and `Snippet:` lines, and `usage.output_tokens` is 0. The validator's Copilot API base is dead, so a 200 means LiteLLM never called Copilot.
- **No device flow.** Check `no-device-flow-in-server-log` passes when the LiteLLM log has no `Please visit` line.
- **Proof.** `evidence/web-search/search.txt`, `interception.txt`, and `evidence/logs/process-compose.log`.

## Gotchas

- Interception applies only to a request whose tools are all web-search tools. A Claude Code turn that also carries other tools goes to Copilot, which the validator cannot reach, so that path is not verified.
- The agent key cannot send `mock_response`, and interception does not need it. If `interception-200` fails with a connection error to `127.0.0.1:9`, the short-circuit did not fire. Check `enabled_providers` in the rendered config.
- Upstream engines rate-limit by IP. The template disables Google and Startpage, which serve CAPTCHAs to self-hosted instances, and enables Bing because Brave and DuckDuckGo often throttle. An empty result list usually means every enabled engine was throttled, but a SearXNG misconfiguration looks the same. Read the SearXNG log before blaming throttling.
- The redacted log reaches `evidence/logs/process-compose.log` only when `secret-hygiene` or cleanup runs. Before that, read `$OUT/repo/logs/process-compose.log`.
- Only LiteLLM needs SearXNG. Do not expose port 8888 to the VM.
