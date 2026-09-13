# Gateway API

Coding agents call LiteLLM on port 4000. Claude Code uses the Anthropic Messages format. OpenCode and similar tools use the OpenAI Chat Completions format. Every API request needs a key. Only the health endpoints, such as `/health/liveliness`, answer without one.

## Sub-features

- `api-auth` rejects a request with no key.
- `api-models` lists every model in `litellm/config.yaml.example`.
- `api-openai` answers `POST /v1/chat/completions`.
- `api-anthropic` answers `POST /v1/messages`.

## How to get to it (user POV)

- Configure Claude Code with base URL `http://<LITELLM_HOST>:4000` and a key.
- Configure OpenCode and other OpenAI-format clients with `http://<LITELLM_HOST>:4000/v1` and a key.
- Call the endpoints directly with `curl` and `Authorization: Bearer <key>`.

## Driving it with validate.sh

Preconditions:

- Launch and doctor passed.

- **No key.** `validate.sh drive "$OUT" gateway-api` sends `GET /v1/models` without a key. Check `rejects-missing-key` passes on HTTP 401.
- **Models.** It sends `GET /v1/models` with the master key. Checks `lists-models-200` and `lists-<model>` for each of the four Bedrock model names pass.
- **Mock key.** It mints `validate-mock-<epoch>` through `POST /key/generate` with metadata `allow_client_mock_response: true`. Check `mock-key-minted` passes when the response has a key.
- **OpenAI format.** It sends `POST /v1/chat/completions` for `claude-sonnet-4-6-bedrock` with `"mock_response": "pong"` and the mock key. Check `openai-chat-completions` passes when `choices[0].message.content` is `pong`.
- **Anthropic format.** It sends `POST /v1/messages` with the same mock and key. Check `anthropic-messages` passes when `content[0].text` is `pong`.
- **Proof.** `evidence/gateway-api/*.txt` hold each request and response.

## Gotchas

- LiteLLM ignores a client's `mock_response` unless the key's metadata sets `allow_client_mock_response`. The master key does not qualify. Without it the request goes to Bedrock, fails auth, and puts the model in a cooldown that turns later calls into HTTP 429.
- `mock_response` never reaches Bedrock. A pass proves auth, routing, and format handling, not upstream credentials.
- The model list is hardcoded in `validate.sh` as `MODELS`. Update it when the template's model list changes.
- LiteLLM rejects a duplicate key alias with HTTP 400. The mock key's alias carries a timestamp so the feature can be driven again on the same instance.
