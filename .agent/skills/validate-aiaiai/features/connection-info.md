# Connection info

The user needs two values to point a coding agent at the gateway, the base URL and a key. `make show-base-url` prints the URL built from the saved listen address. `make show-key` prints the master key.

## Sub-features

- `info-base-url` prints `http://<LITELLM_HOST>:4000` and nothing else.
- `info-master-key` prints the master key stored in `.envrc.local`.

## How to get to it (user POV)

- Run `make show-base-url` in the repo root.
- Run `make show-key` in the repo root.

## Driving it with validate.sh

Preconditions:

- Launch passed.

- **Base URL.** `validate.sh drive "$OUT" connection-info` runs `make show-base-url`. Check `show-base-url` passes when the only line is `http://<listen-ip>:4000`.
- **Master key.** It runs `make show-key`. Check `show-key-matches-master-key` passes when the output equals `LITELLM_MASTER_KEY`.
- **Proof.** `evidence/connection-info/show-base-url.txt` and `show-key.txt`, with the key redacted.

## Gotchas

- Both targets read `.envrc.local` only. They work while the services are stopped.
- Give agents a key from `make new-key` rather than the master key. The master key can mint and delete keys.
