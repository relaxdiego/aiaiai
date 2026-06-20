# aiaiai

Configuration repo that wires **Claude Code** and **pi.dev** to a **LiteLLM** model gateway for unified spend tracking and routing. Nothing sensitive lives here.

## Prerequisites

Install these yourself before cloning:

- [devbox](https://www.jetify.com/devbox/docs/installing_devbox/) — manages per-repo tooling (Python, uv, direnv)
- [direnv](https://direnv.net/docs/installation.html) — loads `.envrc` on `cd`
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — Anthropic's AI coding CLI
- [pi.dev](https://pi.dev/) — minimal AI agent harness

## Quick start

```bash
git clone <this-repo> aiaiai
cd aiaiai
make setup      # interactive wizard: asks mode, writes .envrc.local, installs LiteLLM (full mode)
direnv allow    # load env into current shell (wizard does this, but re-run after new clones)
```

On a **full-mode** machine (the one that runs the gateway):

```bash
make serve      # starts LiteLLM on http://127.0.0.1:4000
```

## Two modes

| Mode | What runs here | When to use |
|------|---------------|-------------|
| **full** | LiteLLM gateway + clients | Your Mac, primary workstation |
| **client** | Clients only (Claude Code, pi.dev) | A VM or secondary machine that points at the Mac |

`make setup` asks which mode this machine is, then configures everything. The same repo works for both — only `.envrc.local` differs per machine.

### Client-only example (VM → Mac host)

On the Mac, run `make serve`. Then on the VM:

```bash
git clone <this-repo> aiaiai && cd aiaiai
make setup
# When prompted:
#   Mode: client
#   Gateway URL: http://<mac-ip>:4000
#   Master key: <the same key set on the Mac>
```

## How secrets work

All sensitive values live **only** in `.envrc.local`, which is git-ignored. See `.envrc.local.example` for the full list. Never put actual keys in any committed file.

`.envrc` derives `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` from `.envrc.local` so both Claude Code and pi.dev pick them up automatically.

## Repo layout

```
litellm/config.yaml       LiteLLM gateway config (model list, routing, budget)
pi/models.json.example    Template for ~/.pi/agent/models.json
scripts/setup.sh          Setup wizard (run via make setup)
.envrc                    Loads devbox env + sources .envrc.local
.envrc.local.example      Template — copy and fill in for your machine
```
