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
	@test -x .venv/bin/prisma || { echo "Error: Prisma not installed. Run 'make setup' first."; exit 1; }
	@test -f .venv/lib/python3.12/site-packages/litellm/proxy/schema.prisma || { echo "Error: LiteLLM Prisma schema not found. Remove .venv and run 'make setup' again."; exit 1; }
	@test -f litellm/config.yaml || { echo "Error: litellm/config.yaml not found (generated from litellm/config.yaml.example). Run 'make setup' first."; exit 1; }
	@test -f searxng/settings.yml || { echo "Error: searxng/settings.yml not found (generated from searxng/settings.yml.example). Run 'make setup' first."; exit 1; }
	@if [ -z "$${DATABASE_URL:-}" ]; then \
	  echo "Error: DATABASE_URL is required for spend tracking and budget enforcement."; \
	  echo "Run 'make setup' to configure PostgreSQL."; \
	  exit 1; \
	fi
	@schema=".venv/lib/python3.12/site-packages/litellm/proxy/schema.prisma"; \
	if ! printf 'SELECT 1;\n' | DATABASE_URL="$${DATABASE_URL}" PATH="$$PWD/.venv/bin:$$PATH" \
	  .venv/bin/prisma db execute --stdin --schema "$$schema" >/dev/null; then \
	  echo "Error: could not connect to PostgreSQL using DATABASE_URL."; \
	  echo "Verify the server, database, credentials, and TLS options, then re-run 'make setup'."; \
	  exit 1; \
	fi
	@mkdir -p logs
	process-compose up --config process-compose.yaml
