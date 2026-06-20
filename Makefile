.PHONY: setup serve

setup:
	@bash scripts/setup.sh

serve:
	@if [ "$${MACHINE_MODE:-}" != "full" ]; then \
	  echo "Error: 'make serve' requires MACHINE_MODE=full."; \
	  echo "If you just ran 'make setup', open a new shell (direnv loads the env on cd)."; \
	  exit 1; \
	fi
	@test -x .venv/bin/litellm || { echo "Error: LiteLLM not installed. Run 'make setup' first."; exit 1; }
	.venv/bin/litellm --config litellm/config.yaml
