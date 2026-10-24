#!/usr/bin/env bash
# Starts Postgres, SearXNG, and LiteLLM under process-compose. Extra arguments
# go to `process-compose up`, e.g. --detached.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() { printf 'Error: %s\n' "$1" >&2; exit 1; }

command -v devbox >/dev/null 2>&1 || fail "devbox is not installed."
[[ -f .envrc.local ]] || fail ".envrc.local not found. Run 'make setup' first."
[[ -x .venv/bin/litellm ]] || fail "LiteLLM is not installed. Run 'make setup' first."
[[ -f litellm/config.yaml ]] || fail "litellm/config.yaml not found. Run 'make setup' first."
[[ -f searxng/settings.yml ]] || fail "searxng/settings.yml not found. Run 'make setup' first."
[[ -f data/postgres/PG_VERSION ]] || fail "data/postgres is not initialized. Run 'make setup' first."

# Without a token, LiteLLM runs the device flow inside the server for every
# model while it loads the config, and drops each model it cannot sign in.
if [[ ! -f data/github_copilot/access-token ]]; then
  printf "Warning: GitHub Copilot is not signed in, so models will not load. Run 'make copilot-login', then 'make stop' and 'make start'.\n" >&2
fi
# The server rewrites the Copilot key file here; keep the directory private.
(umask 077 && mkdir -p data/github_copilot)

eval "$(devbox shellenv)"
# shellcheck disable=SC1091
. ./.envrc.local
# LiteLLM shells out to the prisma CLI installed next to it.
export PATH="$PWD/.venv/bin:$PATH"

# LiteLLM and SearXNG otherwise trust the certifi bundle frozen into the
# lockfile, which cannot receive CA distrusts such as the 2026 eMudhra one.
# Linux distro bundles get them with system updates. macOS applies distrusts in
# trustd but leaves /etc/ssl/cert.pem stale, so use Homebrew's bundle there.
if [[ -z "${SSL_CERT_FILE:-}" ]]; then
  for bundle in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt \
    /opt/homebrew/etc/ca-certificates/cert.pem /usr/local/etc/ca-certificates/cert.pem; do
    if [[ -f "$bundle" ]]; then export SSL_CERT_FILE="$bundle"; break; fi
  done
fi
[[ -n "${SSL_CERT_FILE:-}" ]] || fail "No maintained CA bundle found. On macOS run 'brew install ca-certificates'. Otherwise set SSL_CERT_FILE in .envrc.local."

mkdir -p logs
exec process-compose up --config process-compose.yaml --use-uds \
  --log-file logs/process-compose-server.log "$@"
