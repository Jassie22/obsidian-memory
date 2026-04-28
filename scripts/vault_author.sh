#!/usr/bin/env bash
# Resolve the active author name for vault frontmatter (`author:` field).
#
# Order (first non-empty wins):
#   1. $VAULT_AUTHOR       — explicit env override.
#   2. ~/.claude/vaults.json `.author` field — set once at setup time.
#   3. git config --global user.name
#   4. $USER (last resort).
#
# Always exits 0; emits "unknown" if nothing matches so callers can still write
# the frontmatter without a conditional.
#
# Why this matters: in the company vault, 5 teammates are writing notes into
# the same git history. `git blame` is too low-level for "who decided X" —
# `author:` in frontmatter surfaces it directly in the note body.
set -u

REGISTRY="${VAULT_REGISTRY:-$HOME/.claude/vaults.json}"

if [[ -n "${VAULT_AUTHOR:-}" ]]; then
  printf '%s\n' "$VAULT_AUTHOR"
  exit 0
fi

if [[ -f "$REGISTRY" ]] && command -v jq >/dev/null 2>&1; then
  a=$(jq -r '.author // empty' "$REGISTRY" 2>/dev/null)
  if [[ -n "$a" && "$a" != "null" ]]; then
    printf '%s\n' "$a"
    exit 0
  fi
fi

if command -v git >/dev/null 2>&1; then
  a=$(git config --global user.name 2>/dev/null || true)
  if [[ -n "$a" ]]; then
    printf '%s\n' "$a"
    exit 0
  fi
fi

printf '%s\n' "${USER:-unknown}"
