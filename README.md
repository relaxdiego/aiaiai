# aiaiai (Ayayay!)

Runs the model backend for your coding agents on your workstation. Agents such as Claude Code, OpenCode, and pi.dev run in an isolated VM and reach it over HTTP.

```
 coding-agent VM                      workstation (Linux or macOS)
┌──────────────────┐                ┌─────────────────────────────────────────┐
│ Claude Code      │  HTTP :4000    │ LiteLLM ──► GitHub Copilot              │
│ OpenCode         │ ─────────────► │   │  ├──► SearXNG   127.0.0.1:8888      │
│ pi.dev ...       │  per-agent key │   │  └──► Postgres  127.0.0.1:5439      │
└──────────────────┘                └─────────────────────────────────────────┘
```

- **LiteLLM** is the gateway. It serves Claude models from your GitHub Copilot subscription, enforces a spend cap, and speaks both the OpenAI and Anthropic APIs.
- **SearXNG** gives agents web search with no paid API. Only LiteLLM talks to it.
- **Postgres** stores per-agent keys and spend logs.

process-compose supervises all three. devbox provides every tool, so nothing is installed system-wide.

**Account risk.** LiteLLM's `github_copilot` provider signs in as the VS Code Copilot client and calls GitHub's Copilot API directly. GitHub has suspended Copilot access for accounts that used that API from scripts. Running this gateway puts your GitHub account's Copilot access at that risk.

## Prerequisites

- [devbox](https://www.jetify.com/devbox/docs/installing_devbox/)
- `make`, `git`, `curl`, and `openssl`, which ship with macOS and most Linux distributions
- A GitHub account with a Copilot subscription
- [direnv](https://direnv.net/docs/installation.html) (optional) loads the environment when you `cd` into the repo

## Quick start

```bash
git clone https://github.com/relaxdiego/aiaiai.git
cd aiaiai
make setup                    # asks for a listen address and budget, then signs in to Copilot
make start                    # starts the backend in the background
make new-key NAME=opencode    # one key per agent
make show-base-url            # the URL to give your agents
```

`make setup` signs in to GitHub Copilot with a device code. It prints a URL and a code. Open the URL, enter the code, and approve. The tokens stay in `data/github_copilot`. Run `make copilot-login` to sign in again, for example when setup ran without a terminal. To use a different GitHub account, stop the backend, delete `data/github_copilot`, run `make copilot-login`, and start again.

## Choose the listen address

LiteLLM listens on the single address you give `make setup`. Pick the workstation's address on the network your VM uses. Then only the VM, and not your whole LAN, can reach the gateway.

The wizard lists this machine's addresses. Common choices:

- libvirt or virt-manager on Linux uses `virbr0`, usually `192.168.122.1`.
- On macOS, VM apps create a bridge interface such as `bridge100`. Its address is the one the VM sees as its default gateway.
- `127.0.0.1` works when agents run on the workstation itself.
- `0.0.0.0` listens on every interface. Only the keys protect it then.

To check from inside the VM, run `ip route`. The default gateway is usually the workstation. Then `curl http://<address>:4000/health/liveliness` should print `"I'm alive!"`. If it can't connect, allow port 4000 on that interface in the workstation's firewall.

Re-run `make setup` any time to change the address or budget. It keeps generated secrets, your Copilot sign-in, and any lines you added to `.envrc.local`.

## Commands

| Command | What it does |
|---|---|
| `make setup` | Writes `.envrc.local`, renders service configs, installs LiteLLM, initializes Postgres, and signs in to Copilot. Safe to re-run. |
| `make copilot-login` | Signs in to GitHub Copilot, or refreshes the sign-in if one exists. |
| `make start` | Starts all services in the background. |
| `make serve` | Starts them in the foreground with the process-compose dashboard. |
| `make status` | Lists the services and their health. |
| `make stop` | Stops all services. |
| `make new-key NAME=<agent> [BUDGET=<usd>]` | Mints a key for one agent, optionally with its own 30-day budget. |
| `make show-base-url` | Prints `http://<listen address>:4000`. |
| `make show-key` | Prints the master key. Keep it on the workstation. |

Logs go to `logs/process-compose.log` and rotate at 10 MB.

## Models and spend

The gateway serves four models. Each name is the model ID Claude Code uses, mapped to the matching Copilot model:

| Model | Copilot model |
|---|---|
| `claude-fable-5-1` | `claude-fable-5.1` |
| `claude-opus-5` | `claude-opus-5` |
| `claude-sonnet-5` | `claude-sonnet-5` |
| `claude-haiku-4-5-20251001` | `claude-haiku-4.5` |

Each model carries GitHub's [published per-token price](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing). The budget from `make setup` and each key's `BUDGET` therefore measure Copilot spend in US dollars. To add a model, add an entry with its prices to `litellm/config.yaml.example` and re-run `make setup`.

## Connect your agents

Give each agent its own key from `make new-key`. You can then see spend per agent and revoke one key without touching the others. The examples use `http://192.168.122.1:4000`. Replace it with the output of `make show-base-url`.

**Claude Code.** Add this to `~/.claude/settings.json` in the VM:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://192.168.122.1:4000",
    "ANTHROPIC_AUTH_TOKEN": "<key from make new-key NAME=claude-code>",
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1"
  }
}
```

If you previously ran `/login`, log out first. A stored login takes precedence over `ANTHROPIC_AUTH_TOKEN`. The gateway's model names are Claude Code's own model IDs, so its built-in model choices work unchanged. Claude Code's `web_search` tool works too. The gateway answers it from SearXNG.

**OpenCode.** Add a provider to `opencode.json` and export `AIAIAI_KEY` in the VM:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "aiaiai": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "aiaiai",
      "options": {
        "baseURL": "http://192.168.122.1:4000/v1",
        "apiKey": "{env:AIAIAI_KEY}"
      },
      "models": {
        "claude-sonnet-5": { "name": "Claude Sonnet 5" }
      }
    }
  }
}
```

**pi.dev.** Install the [`pi-provider-litellm`](https://github.com/balcsida/pi-provider-litellm) extension, which discovers the gateway's models:

```
pi install npm:pi-provider-litellm
/login litellm
```

Enter the base URL and the agent's key when prompted.

**Web search from any agent.** `POST /v1/search/local-search` with `{"query": "..."}` and the agent's key returns SearXNG results. Clients that don't use Claude's built-in `web_search` tool can call it from a tool or MCP server.

## Secrets

Secrets live only in `.envrc.local`, which is git-ignored and created with mode 600. The Copilot tokens live in `data/github_copilot`, a mode 700 directory. `data/`, the rendered configs, and `logs/` are git-ignored too. `.envrc.local.example` lists every variable.

## Validating changes

The repo ships a `validate-aiaiai` agent skill in `.agent/skills/`, linked into `.claude/skills` and `.pi/skills`. It copies the working tree to a scratch directory, runs `make setup` and `make start` there, and drives every feature in its [feature map](.agent/skills/validate-aiaiai/features/README.md). To run it by hand:

```bash
.agent/skills/validate-aiaiai/scripts/validate.sh run
```

It needs ports 4000, 8888, and 5439 free, so stop your own instance first.
