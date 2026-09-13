# Secret hygiene

The repo is public. Generated secrets live only in `.envrc.local`, and Copilot tokens only in `data/github_copilot`. Those, the rendered configs, and logs must stay git-ignored. Nothing committed, now or in history, may carry a key. LiteLLM must keep its Copilot tokens inside the repo, not in `~/.config/litellm`.

## Sub-features

- `secrets-ignored` keeps `.envrc.local`, rendered configs, Postgres data, the Copilot token, and logs out of git.
- `secrets-worktree` finds no key-shaped strings in tracked or untracked files.
- `secrets-history` finds no key-shaped strings in any commit.
- `secrets-token-dir` confirms the run did not create `~/.config/litellm`.
- `secrets-evidence` confirms validator evidence is redacted.

## How to get to it (user POV)

- Run `git status` and `git log -p` before pushing.
- Look for `data/github_copilot/access-token` after `make copilot-login`, and no `~/.config/litellm`.

## Driving it with validate.sh

Preconditions:

- Launch passed, so real throwaway secrets exist in the copy.
- Every other feature has run, so LiteLLM has loaded its models and served requests.

- **Ignored paths.** `validate.sh drive "$OUT" secret-hygiene` runs `git check-ignore` in the source repo. Checks `gitignored-<path>` pass for each generated path, `data/github_copilot/access-token` included.
- **Worktree scan.** It runs `git grep` with the pattern in `SECRET_PATTERN`, excluding `requirements.txt` and `devbox.lock`, whose hashes look like secrets. Check `no-secret-patterns-in-worktree` passes on no hits and a clean exit, so a git or regex error fails it.
- **History scan.** It greps `git log --all -p` with the same pattern and exclusions. Check `no-secret-patterns-in-history` passes on no hits, and only when `git log` itself succeeded.
- **Token directory.** Check `copilot-token-dir-in-repo` passes when `~/.config/litellm` existed before launch or does not exist now.
- **Evidence.** It first copies the redacted process logs into `evidence/logs/`. Then it searches `$OUT/evidence` for the master key, SearXNG secret, Postgres password, Copilot access token when one exists, and every minted key. Check `evidence-is-redacted` passes on no hits.
- **Proof.** `evidence/secret-hygiene/*-hits.txt`, `config-litellm.txt`, and `evidence-leaks.txt`.

## Gotchas

- The pattern covers this repo's key shapes: the master key (`sk-` plus 32 hex), minted agent keys (`sk-` plus 22 base64url characters), GitHub tokens (`gho_`, `ghp_`, `ghs_`, `ghu_`, `ghr_` plus 36 characters), passwords inside Postgres URLs, the 48-character hex Postgres password, and 64-character hex secrets. It keeps Bedrock `ABSK` tokens and AWS access key IDs because older history used Bedrock. A new provider needs its key shape added.
- The validator never signs in, so the copy has no access token and the evidence check covers it only on a signed-in copy. The fixture's placeholder key is not a secret.
- `copilot-token-dir-in-repo` cannot tell the run's writes apart from a `~/.config/litellm` that already existed. On such a machine it passes without proving anything. Check the directory's mtime by hand.
- The scans read the source repo, not the copy. The copy has no `.git`. Only the evidence check uses the live throwaway values.
- A history hit cannot be fixed by a new commit. Stop and tell the user. Rewriting published history needs their decision.
