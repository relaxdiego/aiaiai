# Services

`make start` runs Postgres, SearXNG, and LiteLLM in the background under process-compose. `make serve` runs the same in the foreground with its dashboard. `make status` lists them and `make stop` stops them. LiteLLM listens only on the address chosen in setup. SearXNG and Postgres stay on loopback.

## Sub-features

- `svc-status` lists all three processes as running.
- `svc-binding` binds LiteLLM to the listen address and the other two to `127.0.0.1`.
- `svc-stop` stops everything and frees the ports.
- `svc-restart` starts again and keeps data, like minted keys.

## How to get to it (user POV)

- Run `make start`, `make status`, `make stop`, or `make serve` in the repo root.

## Driving it with validate.sh

Preconditions:

- `agent-keys` passed, so a minted key exists.

- **Status and binding.** `validate.sh doctor "$OUT"` covers `postgres-running`, `searxng-running`, `litellm-running`, `litellm-bound-to-listen-address`, `searxng-loopback-only`, and `postgres-loopback-only`.
- **Loopback closed.** `validate.sh drive "$OUT" services` connects to `127.0.0.1:4000` when the listen address is not loopback. Check `loopback-not-listening` passes when the connection fails.
- **Stop.** It runs `make stop`. Checks `stop-exits-0` and `ports-freed-after-stop` pass.
- **Restart.** It runs `make start`. Checks `restart-exits-0` and `ready-after-restart` pass.
- **Persistence.** It sends `GET /v1/models` with the key minted before the restart. Check `agent-key-survives-restart` passes on HTTP 200.
- **Proof.** `evidence/doctor/status.txt`, `evidence/doctor/listeners.txt`, and `evidence/services/*.txt`.

## Gotchas

- `make serve` holds the terminal with a TUI. Automation uses `make start`.
- The control socket is `/tmp/aiaiai-<uid>.sock`. `make stop` in any clone stops whichever instance owns it.
- LiteLLM's first start runs Prisma migrations and can take minutes. Wait on liveliness, not a fixed sleep.
