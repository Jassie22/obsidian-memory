---
description: List or delete empty vault notes (frontmatter only, no body) older than 24h.
argument-hint: [--delete]
---

# /clean-empty

List empty notes in `~/vault/`. By default dry-runs — shows candidates only. With `--delete`, actually removes them.

## Steps

1. If the user passed `--delete` as the argument, run:
   ```
   ~/scripts/vault_clean_empty.py --delete
   ```
2. Otherwise run a dry scan:
   ```
   ~/scripts/vault_clean_empty.py
   ```
3. Summarise the output to the user. If dry-run and candidates exist, ask if they want to delete.
4. If the user says yes, re-run with `--delete`.
5. After any deletion, auto-commit + push the vault per global rules.

## Safety

- Protected paths (never deleted): `templates/`, `rules/`, `_MOC.md`, `rules.md`, `README.md`.
- Age gate: only files with mtime ≥ 24h are eligible for deletion. Fresher empty files stay alone.
- The cleaner is idempotent and safe to run anytime.
