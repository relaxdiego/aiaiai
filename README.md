# aiaiai

Sets up a **LiteLLM** model gateway for unified spend tracking and routing. Optionally wires Claude Code to it.

## Prerequisites

- [devbox](https://www.jetify.com/devbox/docs/installing_devbox/) — manages per-repo tooling (Python, uv, direnv)
- [direnv](https://direnv.net/docs/installation.html) — loads `.envrc` on `cd`
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — Anthropic's AI coding CLI
- [pi.dev](https://pi.dev/) — minimal AI agent harness

## Quick start

```bash
git clone https://github.com/relaxdiego/aiaiai.git
cd aiaiai
make setup      # interactive wizard: asks mode, writes .envrc.local, installs LiteLLM (full mode)
direnv allow    # load env into current shell (wizard does this, but re-run after new clones)
```

## Two modes

| Mode | What runs here | When to use |
|------|---------------|-------------|
| **full** | LiteLLM gateway + clients | Your Mac, primary workstation |
| **client** | Clients only (Claude Code, pi.dev) | A VM or secondary machine that points at the Mac |

`make setup` asks which mode this machine is, then configures everything. The same repo works for both — only `.envrc.local` differs per machine.

## Launch the gateway

On a **full-mode** machine (the one that runs the gateway):

```bash
make serve      # starts LiteLLM on http://127.0.0.1:4000
```

### Client-only example (VM → Mac host)

On the Mac, run `make serve`. Then on the VM:

```bash
git clone https://github.com/relaxdiego/aiaiai.git
cd aiaiai
make setup
```

To use pi.dev on the VM, also follow [Connecting pi.dev](#connecting-pidev).

## How secrets work

All sensitive values live **only** in `.envrc.local`, which is git-ignored. See `.envrc.local.example` for the full list. Never put actual keys in any committed file.

`make setup` writes `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` into your global `~/.claude/settings.json`, so Claude Code reaches the gateway from any directory — not just inside this repo. Re-run `make setup` after rotating the master key to update it.

## Connecting pi.dev

pi.dev connects through the [`pi-provider-litellm`](https://github.com/balcsida/pi-provider-litellm) extension, which auto-discovers the gateway's full model set. Run these once inside pi.dev, on whichever machine or VM runs it:

```
pi install npm:pi-provider-litellm
/login litellm
```

When prompted, give the gateway base URL and your `LITELLM_MASTER_KEY` (`make show-key` on the gateway machine). Credentials persist to that machine's `~/.pi/agent/auth.json`, so pi.dev reaches the gateway from any directory. **From a VM, use a host IP from `make show-base-url` — not `127.0.0.1`.**
