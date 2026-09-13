# Setup wizard

`make setup` turns a fresh clone into a runnable backend. It asks for a listen address, a budget, and optional Bedrock credentials. It writes `.envrc.local`, renders the service configs, installs LiteLLM, and initializes Postgres. Re-running it keeps existing secrets and answers.

## Sub-features

- `setup-guard` makes `make start` fail with a pointer to `make setup` on a fresh clone.
- `setup-fresh` completes a first run and writes every required variable with mode 600.
- `setup-render` renders the budget into `litellm/config.yaml`.
- `setup-postgres` creates `data/postgres` with a `litellm` database.
- `setup-rerun` keeps secrets and answers, keeps lines the user added, drops retired variables, and reuses the database.

## How to get to it (user POV)

- Run `make setup` in the repo root and answer the prompts.
- Run `make setup` again later to change the budget, listen address, or Bedrock credentials.

## Driving it with validate.sh

Preconditions:

- Ports 4000, 8888, and 5439 are free.
- `$OUT/repo` does not exist.

- **Copy.** `validate.sh launch "$OUT"` stops before copying when it finds no default-route IPv4 and `VALIDATE_LISTEN` is unset. Otherwise it copies the working tree and records `copy-working-tree`.
- **Guard.** Launch runs `make start` before setup. Check `start-refused-before-setup` passes when the exit code is non-zero and the output mentions `make setup`.
- **First run.** Launch pipes `<listen-ip>`, `5`, and two blank lines into `make setup`. Checks `fresh-setup-exits-0`, `envrc-has-<VAR>` for each required variable, `envrc-mode-600`, and `listen-address-saved` pass.
- **Render.** Check `budget-rendered` finds `max_budget: 5` in `litellm/config.yaml`.
- **Postgres.** Check `postgres-initialized` finds `data/postgres/PG_VERSION`.
- **Start.** Launch runs `make start`. Checks `start-exits-0` and `gateway-ready-within-300s` pass when liveliness returns 200 within 300 seconds.
- **Re-run.** `validate.sh drive "$OUT" setup` appends `VALIDATE_CUSTOM=kept` and a retired `MACHINE_MODE` line, then pipes four blank lines into `make setup`. Checks `rerun-exits-0`, `rerun-keeps-secrets-and-answers`, `rerun-keeps-custom-lines`, `rerun-drops-retired-vars`, and `rerun-reuses-database` pass. The secrets-and-answers check compares the listen address, master key, budget, SearXNG secret, Postgres password, and AWS region before and after.
- **Proof.** `evidence/setup/fresh-setup.txt`, `rerun-setup.txt`, and `envrc-vars.txt` show the wizard output and variable names, with values redacted.

## Gotchas

- The wizard reads answers from stdin in a fixed order. A new prompt shifts every later answer, so update the `printf` in `cmd_launch` and `drive_setup` in the same change.
- The Bedrock token prompt hides input. A blank answer keeps the existing token, so piped blank lines skip it and the wizard cannot clear a token.
- Launch starts the services right after the first run. The re-run happens while they are up. It must not touch `data/postgres`, but it does re-render both configs and reinstall into `.venv`. Run doctor if a later check fails.
- When direnv is installed, setup runs `direnv allow` on the copy. Cleanup revokes that grant.
