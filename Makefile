.PHONY: setup serve show-key

setup:
	@bash scripts/setup.sh

show-key:
	@if [ ! -f .envrc.local ]; then \
	  echo "Error: .envrc.local not found. Run 'make setup' first."; exit 1; \
	fi
	@grep -E '^export LITELLM_MASTER_KEY=' .envrc.local | cut -d= -f2-

serve:
	@if [ "$${MACHINE_MODE:-}" != "full" ]; then \
	  echo "Error: 'make serve' requires MACHINE_MODE=full."; \
	  echo "If you just ran 'make setup', open a new shell (direnv loads the env on cd)."; \
	  exit 1; \
	fi
	@test -x .venv/bin/litellm || { echo "Error: LiteLLM not installed. Run 'make setup' first."; exit 1; }
	.venv/bin/litellm --config litellm/config.yaml
