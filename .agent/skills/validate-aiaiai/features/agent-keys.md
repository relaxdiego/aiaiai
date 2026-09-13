# Per-agent keys

Each coding agent gets its own LiteLLM virtual key, so spend is tracked per agent and a leaked key can be revoked without rotating the master key. `make new-key` mints one with an alias and an optional budget.

## Sub-features

- `keys-mint` prints a new `sk-` key for `NAME`.
- `keys-name-required` fails without `NAME`.
- `keys-metadata` stores the alias, budget, and 30-day budget period on the key.
- `keys-auth` accepts the minted key and rejects an unknown one.

## How to get to it (user POV)

- Run `make new-key NAME=<agent>` while the services are running.
- Run `make new-key NAME=<agent> BUDGET=<usd>` to cap that agent's spend every 30 days.

## Driving it with validate.sh

Preconditions:

- Launch and doctor passed.

- **Mint.** `validate.sh drive "$OUT" agent-keys` runs `make new-key NAME=validate-agent-<epoch> BUDGET=1`. Check `new-key-prints-key` passes on exit 0 with an `sk-` line.
- **Name required.** It runs `make new-key` with no name. Check `new-key-requires-name` passes on a non-zero exit with `usage: make new-key` in the output.
- **Metadata.** It sends `GET /key/info?key=<key>` with the master key. Checks `key-has-alias`, `key-has-budget`, and `key-has-30d-budget-duration` pass on the alias, `1.0`, and `30d`.
- **Use the key.** It sends `GET /v1/models` with the new key. Check `agent-key-authenticates` passes on HTTP 200.
- **Unknown key.** It sends the same request with `sk-validate-unknown`. Check `unknown-key-rejected` passes on HTTP 401.
- **Proof.** `evidence/agent-keys/*.txt`, with keys redacted.

## Gotchas

- Minting needs the services up and Postgres connected. Without a database LiteLLM refuses to create keys.
- The minted key is kept in `$OUT/repo/.validate-agent-key` for later features and deleted by cleanup.
- LiteLLM rejects a duplicate alias with HTTP 400. The alias carries a timestamp so the feature can be driven again on the same instance.
- No make target revokes a key. The user calls `POST /key/delete` with the master key. The harness does not drive revocation.
- The proxy-wide `max_budget` in `litellm/config.yaml` still caps every key. A `BUDGET` above it does not raise the limit.
- Agent keys cannot send `mock_response`, so a chat call with one would go to Copilot. Chat formats are proven in `gateway-api` with a dedicated mock key.
