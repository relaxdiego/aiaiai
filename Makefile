.PHONY: setup serve show-key show-base-url

setup:
	@bash scripts/setup.sh

show-base-url:
	@echo "Possible base URLs (pick the one reachable from your client):"
	@ifconfig | awk '/^[^ \t]/{split($$1,a,":");iface=a[1]} /inet / && $$2!~/^127\./{printf "  http://%s:4000\t(%s)\n",$$2,iface}'
	@echo ""
	@echo "Tip: from a VM, run 'ip route' on the VM — the default gateway is usually this host."

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
	@test -f litellm/config.yaml || { echo "Error: litellm/config.yaml not found (generated from litellm/config.yaml.example). Run 'make setup' first."; exit 1; }
	@test -f searxng/settings.yml || { echo "Error: searxng/settings.yml not found (generated from searxng/settings.yml.example). Run 'make setup' first."; exit 1; }
	@mkdir -p logs
	process-compose up --config process-compose.yaml
