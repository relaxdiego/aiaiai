#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── helpers ──────────────────────────────────────────────────────────────────

print_header() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
print_info()   { printf '    \033[0;32m%s\033[0m\n' "$1"; }
print_warn()   { printf '    \033[0;33m%s\033[0m\n' "$1"; }
print_err()    { printf '    \033[0;31m%s\033[0m\n' "$1" >&2; }

ask() {
  local prompt="$1" default="${2:-}"
  local display_default="${default:+ [$default]}"
  printf '  %s%s: ' "$prompt" "$display_default"
  read -r REPLY
  REPLY="${REPLY:-$default}"
}

ask_secret() {
  local prompt="$1"
  printf '  %s: ' "$prompt"
  read -rs REPLY
  printf '\n'
}

# Show first 6 chars of a secret followed by "..." for verification
mask_value() {
  local val="$1" n=6
  if [[ ${#val} -lt $n ]]; then n=${#val}; fi
  printf '%s...' "${val:0:$n}"
}

# Like ask_secret but shows a masked hint and keeps existing value on Enter
ask_secret_with_default() {
  local prompt="$1" existing="$2"
  local hint=""
  if [[ -n "$existing" ]]; then hint=" [$(mask_value "$existing"), Enter to keep]"; fi
  printf '  %s%s: ' "$prompt" "$hint"
  read -rs REPLY
  printf '\n'
  if [[ -z "$REPLY" && -n "$existing" ]]; then REPLY="$existing"; fi
}

# Read a variable's value from .envrc.local (strips quotes)
read_envrc_var() {
  local var="$1"
  [[ -f "$REPO_ROOT/.envrc.local" ]] || return 0
  grep -E "^export ${var}=" "$REPO_ROOT/.envrc.local" | cut -d= -f2- | tr -d "'\"" || true
}

confirm() {
  printf '  %s [y/N]: ' "$1"
  read -r REPLY
  [[ "${REPLY,,}" == "y" || "${REPLY,,}" == "yes" ]]
}

# ── prerequisites ─────────────────────────────────────────────────────────────

print_header "Checking prerequisites"
command -v devbox >/dev/null 2>&1 || {
  print_err "devbox is not installed. Install it from https://www.jetify.com/devbox/docs/installing_devbox/"
  exit 1
}
print_info "devbox found."

# ── mode selection ────────────────────────────────────────────────────────────

print_header "Machine mode"
printf '  Choose the mode for this machine:\n'
printf '    1) full   — runs LiteLLM locally AND the clients (Claude Code, pi.dev)\n'
printf '    2) client — runs only the clients, connecting to a LiteLLM gateway elsewhere\n'
ask "Mode (1/full or 2/client)" "1"

case "${REPLY,,}" in
  1|full)   MACHINE_MODE=full   ;;
  2|client) MACHINE_MODE=client ;;
  *)
    print_err "Invalid choice: $REPLY"
    exit 1
    ;;
esac
print_info "Mode: $MACHINE_MODE"

# ── collect config values ─────────────────────────────────────────────────────

print_header "Gateway configuration"

if [[ "$MACHINE_MODE" == "full" ]]; then
  GATEWAY_BASE_URL="http://127.0.0.1:4000"
  print_info "Gateway URL: $GATEWAY_BASE_URL (fixed for full mode)"

  EXISTING_KEY="$(read_envrc_var LITELLM_MASTER_KEY)"

  if [[ -n "$EXISTING_KEY" ]]; then
    LITELLM_MASTER_KEY="$EXISTING_KEY"
    print_info "Reusing existing master key from .envrc.local"
  else
    LITELLM_MASTER_KEY="sk-$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
    print_info "Generated new master key."
  fi
else
  ask "LiteLLM gateway base URL"
  GATEWAY_BASE_URL="$REPLY"
  if [[ -z "$GATEWAY_BASE_URL" ]]; then
    print_err "Gateway URL is required."
    exit 1
  fi

  printf '\n'
  print_info "To find your master key, run 'make show-key' on the gateway machine."
  printf '\n'
  ask_secret "LiteLLM master key"
  LITELLM_MASTER_KEY="$REPLY"
  if [[ -z "$LITELLM_MASTER_KEY" ]]; then
    print_err "LiteLLM master key is required."
    exit 1
  fi
fi

DATABASE_URL=""

if [[ "$MACHINE_MODE" == "full" ]]; then
  EXISTING_ANTHROPIC_API_KEY="$(read_envrc_var ANTHROPIC_API_KEY)"
  EXISTING_AWS_BEARER_TOKEN="$(read_envrc_var AWS_BEARER_TOKEN_BEDROCK)"
  EXISTING_AWS_REGION="$(read_envrc_var AWS_REGION)"
  EXISTING_DATABASE_URL="$(read_envrc_var DATABASE_URL)"

  print_header "Upstream provider keys (written to .envrc.local only — never committed)"
  printf '  Press Enter to skip any provider you are not using.\n'

  printf '\n'
  ask_secret_with_default "Anthropic API key (optional, Enter to skip)" "$EXISTING_ANTHROPIC_API_KEY"
  ANTHROPIC_API_KEY="$REPLY"

  printf '\n'
  printf '  AWS Bedrock (press Enter on both to skip)\n'
  ask_secret_with_default "AWS Bearer Token (optional, Enter to skip)" "$EXISTING_AWS_BEARER_TOKEN"
  AWS_BEARER_TOKEN_BEDROCK="$REPLY"
  ask "AWS Region" "${EXISTING_AWS_REGION:-us-east-1}"
  AWS_REGION="$REPLY"

  if [[ -z "$ANTHROPIC_API_KEY" && -z "$AWS_BEARER_TOKEN_BEDROCK" ]]; then
    print_warn "No provider credentials entered — models won't be callable until you add them to .envrc.local."
  fi

  printf '\n'
  ask_secret_with_default "PostgreSQL database URL (optional, Enter to skip)" "$EXISTING_DATABASE_URL"
  # Strip GUI-tool query params (e.g. ?statusColor=...&name=...) — keep only the DSN
  DATABASE_URL="${REPLY%%\?*}"
fi

# ── write .envrc.local ────────────────────────────────────────────────────────

print_header "Writing .envrc.local"
ENVRC_LOCAL="$REPO_ROOT/.envrc.local"
SKIP_ENVRC=0

if [[ -f "$ENVRC_LOCAL" ]]; then
  print_warn ".envrc.local already exists."
  confirm "Overwrite it?" || SKIP_ENVRC=1
fi

if [[ "$SKIP_ENVRC" -eq 0 ]]; then
  {
    printf '# Generated by scripts/setup.sh — do not commit this file\n'
    printf 'export MACHINE_MODE=%s\n' "$MACHINE_MODE"
    printf 'export GATEWAY_BASE_URL=%s\n' "$GATEWAY_BASE_URL"
    printf 'export LITELLM_MASTER_KEY=%s\n' "$LITELLM_MASTER_KEY"
    if [[ "$MACHINE_MODE" == "full" ]]; then
      [[ -n "$ANTHROPIC_API_KEY" ]] && printf 'export ANTHROPIC_API_KEY=%s\n' "$ANTHROPIC_API_KEY"
      if [[ -n "$AWS_BEARER_TOKEN_BEDROCK" ]]; then
        printf 'export AWS_BEARER_TOKEN_BEDROCK=%s\n' "$AWS_BEARER_TOKEN_BEDROCK"
        printf 'export AWS_REGION=%s\n' "$AWS_REGION"
      fi
      [[ -n "$DATABASE_URL" ]] && printf 'export DATABASE_URL=%s\n' "$DATABASE_URL"
    fi
  } > "$ENVRC_LOCAL"
  print_info "Wrote $ENVRC_LOCAL"
fi

# ── devbox install ────────────────────────────────────────────────────────────

print_header "Installing devbox packages"
(cd "$REPO_ROOT" && devbox install)

# Source devbox-managed tools (uv, direnv, python) into the current shell
eval "$(cd "$REPO_ROOT" && devbox shellenv)"

# ── direnv allow ─────────────────────────────────────────────────────────────

print_header "Enabling direnv"
(cd "$REPO_ROOT" && direnv allow)

# ── pi.dev models.json ────────────────────────────────────────────────────────

print_header "Configuring pi.dev"
PI_CONFIG_DIR="$HOME/.pi/agent"
PI_MODELS_JSON="$PI_CONFIG_DIR/models.json"
SKIP_PI=0

# pi.dev's anthropic provider appends /messages to baseUrl, so include /v1
PI_BASE_URL="${GATEWAY_BASE_URL%/}/v1"

if [[ -f "$PI_MODELS_JSON" ]]; then
  print_warn "$PI_MODELS_JSON already exists."
  confirm "Overwrite it?" || SKIP_PI=1
fi

if [[ "$SKIP_PI" -eq 0 ]]; then
  mkdir -p "$PI_CONFIG_DIR"
  cat > "$PI_MODELS_JSON" <<EOF
{
  "providers": {
    "anthropic": {
      "baseUrl": "${PI_BASE_URL}",
      "apiKey": "\$LITELLM_MASTER_KEY"
    }
  }
}
EOF
  print_info "Wrote $PI_MODELS_JSON"
fi

# ── LiteLLM install (full mode only) ─────────────────────────────────────────

if [[ "$MACHINE_MODE" == "full" ]]; then
  print_header "Installing LiteLLM into .venv"
  (
    cd "$REPO_ROOT"
    uv venv .venv --quiet
    uv pip install --python .venv/bin/python --require-hashes -r requirements.txt --quiet
  )
  print_info "LiteLLM installed at .venv/bin/litellm"

  if [[ -n "$DATABASE_URL" ]]; then
    print_header "Generating Prisma client"
    LITELLM_SCHEMA="$REPO_ROOT/.venv/lib/python3.12/site-packages/litellm/proxy/schema.prisma"
    (cd "$REPO_ROOT" && PATH="$REPO_ROOT/.venv/bin:$PATH" .venv/bin/prisma generate --schema "$LITELLM_SCHEMA")
    print_info "Prisma client generated."

    print_header "Applying database schema (prisma db push)"
    (cd "$REPO_ROOT" && DATABASE_URL="$DATABASE_URL" PATH="$REPO_ROOT/.venv/bin:$PATH" .venv/bin/prisma db push --schema "$LITELLM_SCHEMA")
    print_info "Database schema applied."
  fi
fi

# ── done ─────────────────────────────────────────────────────────────────────

print_header "Setup complete"
if [[ "$MACHINE_MODE" == "full" ]]; then
  print_info "Run 'make serve' to start the LiteLLM gateway."
else
  print_info "Clients configured to reach gateway at $GATEWAY_BASE_URL."
fi
print_info "Open a new shell in this directory (direnv will load the environment automatically)."
