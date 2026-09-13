---
name: validate-aiaiai
description: Validate the aiaiai backend (LiteLLM gateway, SearXNG, Postgres under process-compose) end to end the way its user does, from make setup through the HTTP APIs coding agents call. Use after any change to setup, Makefile, process-compose, templates, or scripts, before committing, or when asked to validate, verify, or prove the gateway works.
---

# Validate aiaiai

aiaiai runs the model backend on a workstation (Linux or macOS). Coding agents in a VM reach it over HTTP. The user's surface is `make` targets plus the gateway's HTTP API on port 4000. This skill drives both against a disposable copy of the working tree, never the user's live instance.

Everything goes through one helper: `.agent/skills/validate-aiaiai/scripts/validate.sh`. Run it from anywhere inside the repo.

## Launch

```bash
.agent/skills/validate-aiaiai/scripts/validate.sh run "$OUT"
```

`run` does preflight, launch, doctor, every feature in [`features/`](features/README.md), and cleanup, then exits non-zero if any check failed. Omit `OUT` to get `~/.cache/aiaiai-validate/<timestamp>`. A run needs about 2 GB of disk. Keep `OUT` off `/tmp` on Linux, where it is often RAM-backed tmpfs and a run can exhaust memory.

To drive step by step instead:

```bash
V=.agent/skills/validate-aiaiai/scripts/validate.sh
$V launch "$OUT"                 # copy working tree to $OUT/repo, make setup, make start
$V doctor "$OUT"
$V drive "$OUT" gateway-api      # any feature ID from features/README.md
$V cleanup "$OUT"
```

Launch copies tracked and untracked-but-not-ignored files, so uncommitted edits are what gets validated. It answers the setup wizard on stdin with the machine's default-route IPv4 as the listen address (override with `VALIDATE_LISTEN=<ip>`, required on a host with no default route) and a budget of 5. Piped stdin also makes setup skip the Copilot sign-in. `gateway-api` and `agent-keys` can be driven again on the same instance; each drive mints a new key with a timestamped alias. Ready means `GET http://<listen>:4000/health/liveliness` returns 200. First launch on a machine can take several minutes because devbox, uv, and Prisma download packages.

Every `make` call runs under `env -i` with only `HOME`, `USER`, `TERM`, and a PATH holding devbox. That proves the targets work without direnv.

## Copilot without an account

The validator never signs in to GitHub. Before `make start`, launch writes a fixture `data/github_copilot/api-key.json` in the copy. It is valid until 2100 and names `http://127.0.0.1:9` as the Copilot API base. LiteLLM then loads every model without running the device flow, and any request that reaches Copilot fails. So:

- Chat checks send `"mock_response": "pong"`, which exercises auth, routing, and the OpenAI and Anthropic request formats inside LiteLLM without an upstream call.
- The web-search interception check gets HTTP 200 only when LiteLLM answered from SearXNG, since Copilot is unreachable.
- A real Copilot completion is never verified. Do not report one as verified.

## Doctor

`validate.sh doctor "$OUT"` is read-only. It requires `postgres`, `searxng`, and `litellm` to show `Running` in `make status`, liveliness 200, readiness reporting `"db": "connected"`, LiteLLM listening on the configured address, and SearXNG and Postgres on loopback only. Run it first whenever a later check fails for no obvious reason.

## Isolation

Ports 4000, 8888, and 5439 and the process-compose socket `/tmp/aiaiai-<uid>.sock` are fixed. Only one instance can run per machine. Preflight refuses to start when any of those ports is busy. Never stop or drive an instance this run did not start. On the user's workstation that is probably their live backend.

## Evidence

- `$OUT/report.tsv` has one row per check with `PASS`, `FAIL`, or `SKIP` and the evidence path.
- `$OUT/evidence/<feature>/` holds request, status, and body for each HTTP call, plus make output. `$OUT/evidence/logs/` holds the process-compose logs. Every file is passed through a redactor that replaces the master key, SearXNG secret, Postgres password, Copilot access token when one exists, and minted agent keys with `<redacted>`. The `secret-hygiene` feature fails if any of those values leaked into evidence, logs included. Cleanup refreshes the logs after that scan, so only log lines from the final stop go unscanned.
- A `SKIP` names why the path could not be driven. Do not report a skipped path as verified.

## Cleanup

`validate.sh cleanup "$OUT"` runs `make stop` in the copy, waits for the ports to free, revokes the `direnv allow` grant that setup gave the copy, and deletes `$OUT/repo`, which includes its Postgres data, secrets, and the Copilot fixture. It also deletes `$OUT/cache`, about 300 MB of Prisma and npm downloads. `$OUT/evidence` and `$OUT/report.tsv` stay. `run` cleans up on exit, including after failures. After a crash, run cleanup by hand before the next launch.

## Maintaining the map

When a change adds or alters a user-facing target, endpoint, or setup prompt, update the matching file in `features/` and the helper in the same commit. Feature entries follow the contract in `features/README.md`.
