.PHONY: setup serve start stop status new-key show-key show-base-url

# The process-compose control socket. Every target that talks to the running
# services finds it through this variable.
export PC_SOCKET_PATH := /tmp/aiaiai-$(shell id -u).sock

DEVBOX_ENV = eval "$$(devbox shellenv)"
REQUIRE_ENVRC = test -f .envrc.local || { echo "Error: .envrc.local not found. Run 'make setup' first."; exit 1; }

setup:
	@bash scripts/setup.sh

serve:
	@scripts/serve.sh

start:
	@scripts/serve.sh --detached

stop:
	@$(DEVBOX_ENV) && process-compose down --use-uds

status:
	@$(DEVBOX_ENV) && process-compose process list --use-uds --output wide

new-key:
	@scripts/new-key.sh "$(NAME)" "$(BUDGET)"

show-key:
	@$(REQUIRE_ENVRC)
	@. ./.envrc.local && echo "$$LITELLM_MASTER_KEY"

show-base-url:
	@$(REQUIRE_ENVRC)
	@. ./.envrc.local && echo "http://$$LITELLM_HOST:4000"
