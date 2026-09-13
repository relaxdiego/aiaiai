# Secret hygiene

The repo is public. Real secrets live only in `.envrc.local`. It, the rendered configs, Postgres data, and logs must stay git-ignored. Nothing committed, now or in history, may carry a key.

## Sub-features

- `secrets-ignored` keeps `.envrc.local`, rendered configs, Postgres data, and logs out of git.
- `secrets-worktree` finds no key-shaped strings in tracked or untracked files.
- `secrets-history` finds no key-shaped strings in any commit.
- `secrets-evidence` confirms validator evidence is redacted.

## How to get to it (user POV)

- Run `git status` and `git log -p` before pushing.

## Driving it with validate.sh

Preconditions:

- Launch passed, so real throwaway secrets exist in the copy.

- **Ignored paths.** `validate.sh drive "$OUT" secret-hygiene` runs `git check-ignore` in the source repo. Checks `gitignored-<path>` pass for each generated path.
- **Worktree scan.** It runs `git grep` with the pattern in `SECRET_PATTERN`, excluding `requirements.txt` and `devbox.lock`, whose hashes look like secrets. Check `no-secret-patterns-in-worktree` passes on no hits and a clean exit, so a git or regex error fails it.
- **History scan.** It greps `git log --all -p` with the same pattern and exclusions. Check `no-secret-patterns-in-history` passes on no hits, and only when `git log` itself succeeded.
- **Evidence.** It first copies the redacted process logs into `evidence/logs/`. Then it searches `$OUT/evidence` for the master key, SearXNG secret, Postgres password, Bedrock token, and every minted key. Check `evidence-is-redacted` passes on no hits.
- **Proof.** `evidence/secret-hygiene/*-hits.txt` and `evidence-leaks.txt` list any hits.

## Gotchas

- The pattern covers this repo's key shapes: the master key (`sk-` plus 32 hex), minted agent keys (`sk-` plus 22 base64url characters), Bedrock `ABSK` tokens, AWS access key IDs, passwords inside Postgres URLs, the 48-character hex Postgres password, and 64-character hex secrets. A new provider needs its key shape added.
- The scans read the source repo, not the copy. The copy has no `.git`. Only the evidence check uses the live throwaway values.
- A history hit cannot be fixed by a new commit. Stop and tell the user. Rewriting published history needs their decision.
