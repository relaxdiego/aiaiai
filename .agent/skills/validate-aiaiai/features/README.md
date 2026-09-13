# aiaiai verification map

This directory is the maintained source for verifying what the aiaiai user can do. Read this index before driving, then use the matching feature file as the recipe. The harness is `.agent/skills/validate-aiaiai/scripts/validate.sh`, written `validate.sh` below.

## Baseline preconditions

- devbox is installed and on `PATH`. Nothing else from the repo's toolchain is assumed.
- Ports 4000, 8888, and 5439 are free.
- `validate.sh launch "$OUT"` completed with every `setup` row `PASS`.
- `validate.sh doctor "$OUT"` passes.
- Never drive an instance that this run did not launch.

## Driving conventions

- Drive a feature with `validate.sh drive "$OUT" <feature-id>`.
- `make` targets run inside `$OUT/repo` under a scrubbed environment. Do not source `.envrc.local` into your own shell.
- HTTP calls go to `http://<LITELLM_HOST>:4000`, the address the wizard saved.
- `agent-keys` mints the key that `web-search` and `services` reuse. Drive in index order when driving by hand.

## Proof and skip reporting

- Every check writes one row to `$OUT/report.tsv` and points at a file under `$OUT/evidence/<feature>/`.
- HTTP proof includes the method, URL, request body, status, and response body.
- Make proof includes the full output with secrets redacted.
- A state change is proven by a second read, like a key used after a restart.
- A `SKIP` row states the unmet precondition. Never count it as verified.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order.

1. `Sub-features` lists short IDs with one line for each behavior.
2. `How to get to it (user POV)` lists every user entry point.
3. `Driving it with validate.sh` starts with `Preconditions:` and uses labeled bullets that pair each user action with the check name and observable result.
4. `Gotchas` lists traps that can waste or invalidate a verification run.

## Features

- [Setup wizard](./setup.md) (`setup`) covers first run, re-run, and the refusal to start before setup.
- [Connection info](./connection-info.md) (`connection-info`) covers the base URL and master key the user hands to agents.
- [Gateway API](./gateway-api.md) (`gateway-api`) covers auth, model listing, per-model pricing, and the OpenAI and Anthropic chat formats.
- [Per-agent keys](./agent-keys.md) (`agent-keys`) covers minting a virtual key with an alias and budget.
- [Web search](./web-search.md) (`web-search`) covers the search endpoint backed by SearXNG and the interception of Claude Code's `web_search` request.
- [Services](./services.md) (`services`) covers binding, stop, restart, and persistence.
- [Secret hygiene](./secret-hygiene.md) (`secret-hygiene`) covers ignored files, pattern scans, the in-repo Copilot token directory, and redacted evidence.
