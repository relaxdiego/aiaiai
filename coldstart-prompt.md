# Cold-start prompt: configure this repo for pi.dev + Claude Code + LiteLLM

Paste everything below into a fresh session running in this repo
(`/Users/mark/src/github.com/relaxdiego/aiaiai`).

---

You are setting up this repository (`aiaiai`) to hold the **non-sensitive**
configuration that wires my AI **clients** — the **pi.dev** agent harness and
**Claude Code** — to a **LiteLLM** model gateway. The repo's job is
*configuration*, not installing the clients: I install pi.dev and Claude Code
myself. The repo *does* own LiteLLM's config and (in full mode) running it
locally. I maintain multiple workstations, so cloning this repo + running a
couple of commands should get a machine configured.

## Ground rules (follow these strictly)

- **Do not assume anything.** If a requirement is ambiguous, the right
  config mechanism is unclear, or there are multiple reasonable approaches,
  **stop and ask me** before writing files. Surface tradeoffs rather than
  picking silently.
- **No secrets in the repo, ever.** All sensitive values (provider API keys,
  LiteLLM master/virtual keys, etc.) live in a git-ignored `.envrc.local`. The
  repo only ever contains non-sensitive config plus a committed
  `.envrc.local.example` template.
- **Simplicity first.** Minimum config that works. No speculative abstractions,
  no flexibility I didn't ask for. A senior engineer should look at the result
  and find nothing overcomplicated.
- **Surgical.** Only create what's needed for the deliverables below.

## Context about the tools (verify before relying on it)

- **pi.dev** — a minimal agent harness. https://pi.dev/ — **I install this
  myself**; the repo only configures it to talk to LiteLLM.
- **Claude Code** — Anthropic's CLI. I install it myself; the repo only
  configures it to route through LiteLLM (LiteLLM exposes an Anthropic-compatible
  endpoint; Claude Code is pointed at it via env vars such as
  `ANTHROPIC_BASE_URL` and an auth token — **confirm the exact variables and
  endpoint path against current Claude Code and LiteLLM docs**).
- **LiteLLM** — a model gateway I use to track and control model spending.
  https://www.litellm.ai/ — This repo holds LiteLLM's `config.yaml` (model list,
  routing, budget/spend controls) with **environment variable references** for
  any secret values, never the secret values themselves. In full mode LiteLLM is
  run locally from this repo.

## Two deployment modes (must support both)

The setup must support a per-machine choice between two modes:

1. **Full / host mode** — this machine runs LiteLLM locally (from this repo)
   *and* runs the clients (pi.dev, Claude Code) pointed at that local gateway.
   (e.g., my Mac.)
2. **Client-only mode** — this machine runs **only the clients**, connecting to
   a LiteLLM gateway running on **another machine** (e.g., a VM whose pi.dev /
   Claude Code talk to LiteLLM on the Mac host).

Design implications:
- Both clients read the gateway location from a single base-URL env var (e.g.
  `http://host.example:4000`) plus the connecting key. The gateway URL and key
  live in `.envrc.local` so each machine sets its own — the URL is non-sensitive
  but machine-specific; the key is sensitive. The same in-repo client config
  therefore works in both modes; only the env vars differ per machine.
- In client-only mode, **do not** install/start LiteLLM or require Python/uv for
  it. The devbox config and setup wizard must make the LiteLLM tooling skippable
  for this mode.
- **The user does not pick the mode by hand-editing files.** The setup wizard
  (deliverable below) asks which mode this machine is, then configures
  accordingly.
- The default base URL for full mode is the local gateway
  (e.g. `http://127.0.0.1:4000`); confirm LiteLLM's default port from its docs.

Before writing any install/config steps, **check the current official docs** for
each tool (web docs and/or `--help`). Don't hardcode commands, env-var names, or
endpoint paths from memory — confirm them.

## Toolchain

- Use **`devbox.json`** for reproducible per-machine tooling and **`direnv`**
  for environment loading. Provision at least: `direnv`, and **Python + uv** for
  LiteLLM (needed only in full/host mode — make this skippable for client-only
  mode). Do **not** provision pi.dev or Claude Code via devbox; I install those.
- `.envrc` should load the devbox environment and source `.envrc.local` if
  present. `.envrc.local` is git-ignored and holds all secrets (and the
  machine-specific gateway URL) as env vars.

## Deliverables

1. **`devbox.json`** — provisioning the tools above.
2. **`.envrc`** — devbox + direnv glue; sources `.envrc.local` when present.
3. **`.envrc.local.example`** — committed template listing every required env var
   (secrets + gateway URL) with placeholder values and a one-line comment each.
   The real `.envrc.local` is git-ignored.
4. **`.gitignore`** — ignores `.envrc.local` and any other local/secret/state
   artifacts (devbox/direnv local dirs, etc.).
5. **LiteLLM `config.yaml`** — non-sensitive gateway config (model list,
   routing, budget/spend controls), with secrets expressed as `os.environ/...`
   style env-var references. Confirm the exact reference syntax against
   LiteLLM's docs.
6. **pi.dev client config** — configured to reach the LiteLLM gateway via the
   base-URL/key env vars (works in both modes). Determine the correct config
   location/format from pi.dev's docs; if pi.dev reads config from `~/.config`,
   have the bootstrap script link or copy the repo's version there rather than
   committing machine state.
7. **Claude Code client config** — configured to route through LiteLLM's
   Anthropic-compatible endpoint via the appropriate env vars / settings, again
   reading the gateway URL and key from `.envrc.local`. Confirm the exact
   mechanism (env vars vs `settings.json`) against current docs; keep any
   committed settings non-sensitive.
8. **Interactive setup wizard** — the single thing the user runs on a fresh
   machine. By the end of one run the machine is fully configured. It should:
   - Ask which **mode** this machine is (full/host vs client-only).
   - Run devbox install and direnv allow.
   - Collect the values it needs and **write `.envrc.local`** for the user
     (gateway URL + key always; in full mode, the provider keys / LiteLLM master
     key that `config.yaml` references). Prompt interactively; do not require the
     user to hand-edit `.envrc.local` afterward. Never echo secrets back or write
     them anywhere git-tracked.
   - Link client config into `~/.config` (or wherever each client expects) if
     needed.
   - In **full mode** also install LiteLLM via uv; in **client-only mode** skip
     all LiteLLM tooling.
   - Be **idempotent / re-runnable** — safe to run again to reconfigure or
     change mode, without clobbering an existing `.envrc.local` without warning.
   - It does **not** install pi.dev or Claude Code.
9. **`Makefile`** — the user's entry points. Required targets:
   - **`make setup`** — runs the interactive setup wizard (deliverable 8).
   - **`make serve`** — starts LiteLLM locally with this repo's `config.yaml`
     (full mode only; if run on a client-only machine it should fail with a clear
     message).
   Keep targets minimal — don't add ones I didn't ask for.
10. **`README.md`** — brief. Cover: (a) the repo's purpose, (b) prerequisites
   (pi.dev and Claude Code are installed separately — link to pi.dev for its
   install), (c) the flow: `make setup` once (it asks the mode and configures
   everything), then `make serve` to start LiteLLM on a full-mode machine;
   include the client-only VM→host example, (d) where secrets go and that nothing
   sensitive belongs in the repo. Keep it tight.

## Success criteria

- A clean clone contains **no secrets** (grep/verify before finishing).
- `direnv allow` loads the environment; with a populated `.envrc.local`,
  full mode can start LiteLLM locally and both clients reach it, and client-only
  mode runs the clients against a remote gateway without any LiteLLM tooling
  present.
- Following the README on a fresh machine reproduces the configuration.
- The README accurately matches the files you actually created.

## Working style

State a short plan with verification checks before you start, then implement.
When something is genuinely unclear or under-specified, **ask me** — don't guess.
Don't add Claude/Anthropic attribution to any git commits or messages.
