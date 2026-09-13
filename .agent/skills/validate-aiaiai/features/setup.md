# Setup wizard

`make setup` turns a fresh clone into a runnable backend. It asks for a listen address and a budget. It writes `.envrc.local`, renders the service configs, installs LiteLLM, initializes Postgres, and signs in to GitHub Copilot when stdin is a terminal. Re-running it keeps existing secrets, answers, and the Copilot sign-in. `make copilot-login` runs the sign-in on its own.

## Sub-features

- `setup-guard` makes `make start` fail with a pointer to `make setup` on a fresh clone.
- `setup-fresh` completes a first run and writes every required variable with mode 600.
- `setup-copilot` skips the device flow when stdin is not a terminal and points at `make copilot-login`.
- `setup-render` renders the budget into `litellm/config.yaml`.
- `setup-postgres` creates `data/postgres` with a `litellm` database.
- `setup-start-warning` makes `make start` warn, but still start, when Copilot is not signed in.
- `setup-rerun` keeps secrets and answers, keeps lines the user added, drops retired variables, and reuses the database.

## How to get to it (user POV)

- Run `make setup` in the repo root, answer the prompts, and enter the device code GitHub shows.
- Run `make setup` again later to change the budget or listen address.
- Run `make copilot-login` to sign in after a setup that could not, or after deleting `data/github_copilot`.

## Driving it with validate.sh

Preconditions:

- Ports 4000, 8888, and 5439 are free.
- `$OUT/repo` does not exist.

- **Copy.** `validate.sh launch "$OUT"` stops before copying when it finds no default-route IPv4 and `VALIDATE_LISTEN` is unset. Otherwise it records whether `~/.config/litellm` exists, copies the working tree, and records `copy-working-tree`.
- **Guard.** Launch runs `make start` before setup. Check `start-refused-before-setup` passes when the exit code is non-zero and the output mentions `make setup`.
- **First run.** Launch pipes `<listen-ip>` and `5` into `make setup`. Checks `fresh-setup-exits-0`, `envrc-has-<VAR>` for each required variable, `envrc-mode-600`, and `listen-address-saved` pass.
- **Copilot skipped.** Check `setup-skips-copilot-login-without-tty` passes when the fresh setup output says `Not signed in to GitHub Copilot` and has no `Please visit` device-flow line.
- **Render.** Check `budget-rendered` finds `max_budget: 5` in `litellm/config.yaml`.
- **Postgres.** Check `postgres-initialized` finds `data/postgres/PG_VERSION`.
- **Start.** Launch writes the Copilot key fixture described in `SKILL.md`, then runs `make start`. Checks `start-exits-0`, `start-warns-without-copilot-login` (the output mentions `make copilot-login`), and `gateway-ready-within-300s` pass.
- **Re-run.** `validate.sh drive "$OUT" setup` appends `VALIDATE_CUSTOM=kept` and a retired `MACHINE_MODE` line, then pipes two blank lines into `make setup`. Checks `rerun-exits-0`, `rerun-keeps-secrets-and-answers`, `rerun-keeps-custom-lines`, `rerun-drops-retired-vars`, and `rerun-reuses-database` pass. The secrets-and-answers check compares the listen address, master key, budget, SearXNG secret, and Postgres password before and after.
- **Proof.** `evidence/setup/fresh-setup.txt`, `start.txt`, `rerun-setup.txt`, and `envrc-vars.txt` show the wizard and start output and the variable names, with values redacted.

## Gotchas

- The wizard reads answers from stdin in a fixed order. A new prompt shifts every later answer, so update the `printf` in `cmd_launch` and `drive_setup` in the same change.
- The Copilot sign-in runs only when stdin is a terminal. Piped setup never signs in, so the device flow itself is not driven. It needs a person and a GitHub account.
- `AWS_BEARER_TOKEN_BEDROCK` and `AWS_REGION` are retired. A re-run removes them from an old `.envrc.local` with a warning.
- Launch starts the services right after the first run. The re-run happens while they are up. It must not touch `data/postgres` or `data/github_copilot`, but it does re-render both configs and reinstall into `.venv`. Run doctor if a later check fails.
- When direnv is installed, setup runs `direnv allow` on the copy. Cleanup revokes that grant.
