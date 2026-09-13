#!/usr/bin/env bash
# Signs LiteLLM in to GitHub Copilot with the device flow and keeps the tokens in
# data/github_copilot. When a token already exists it only refreshes the
# short-lived Copilot key, so it is safe to re-run.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() { printf 'Error: %s\n' "$1" >&2; exit 1; }

[[ -x .venv/bin/litellm ]] || fail "LiteLLM is not installed. Run 'make setup' first."

umask 077
mkdir -p data/github_copilot
chmod 700 data/github_copilot
export GITHUB_COPILOT_TOKEN_DIR=data/github_copilot
# Importing litellm otherwise fetches its cost map from GitHub.
export LITELLM_LOCAL_MODEL_COST_MAP=True
export LITELLM_LOG=ERROR

.venv/bin/python - <<'PY' || fail "GitHub Copilot sign-in failed. Run 'make copilot-login' to try again."
import sys

from litellm.llms.github_copilot.authenticator import Authenticator

try:
    Authenticator().get_api_key()
except Exception as e:
    print(e, file=sys.stderr)
    sys.exit(1)
PY
printf 'Signed in to GitHub Copilot. Tokens are in data/github_copilot.\n'
