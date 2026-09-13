#!/usr/bin/env bash
# Mints a LiteLLM virtual key for one coding agent and prints it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() { printf 'Error: %s\n' "$1" >&2; exit 1; }

name="${1:-}"
budget="${2:-}"
[[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || fail "usage: make new-key NAME=<agent> [BUDGET=<usd>]  (NAME: letters, digits, . _ -)"
[[ -z "$budget" || "$budget" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail "BUDGET must be a number of USD, like 20 or 7.5."
[[ -f .envrc.local ]] || fail ".envrc.local not found. Run 'make setup' first."

# shellcheck disable=SC1091
. ./.envrc.local
host="$LITELLM_HOST"
[[ "$host" == "0.0.0.0" ]] && host=127.0.0.1

body="{\"key_alias\":\"$name\""
[[ -n "$budget" ]] && body="$body,\"max_budget\":$budget,\"budget_duration\":\"30d\""
body="$body}"

response="$(curl -sS -w '\n%{http_code}' -X POST "http://$host:4000/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H 'Content-Type: application/json' -d "$body")" \
  || fail "could not reach LiteLLM at http://$host:4000. Is it running? Try 'make status'."
status="${response##*$'\n'}"
response="${response%$'\n'*}"
[[ "$status" == 200 ]] || fail "LiteLLM refused to mint the key (HTTP $status): $response"

printf '%s\n' "$response" | sed -n 's/.*"key": *"\([^"]*\)".*/\1/p'
