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

## Repo layout

```
litellm/config.yaml.example   LiteLLM gateway config template (model list, routing, budget)
searxng/settings.yml.example  SearXNG web-search backend config template
scripts/setup.sh              Setup wizard (run via make setup; renders the templates)
.envrc                        Loads devbox env + sources .envrc.local
.envrc.local.example          Template — copy and fill in for your machine

The live litellm/config.yaml and searxng/settings.yml are generated from the
*.example templates by `make setup` and are git-ignored. Edit the templates,
not the generated files.
```
