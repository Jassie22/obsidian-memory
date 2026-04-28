#!/usr/bin/env bash
# SessionStart hook: `git pull --ff-only` in every registered vault plus
# ~/obsidian-memory itself. Throttle is per-repo (timestamp file under
# ~/.claude/.last-pull-<slug>) so a slow personal-vault pull doesn't
# starve the company-vault pull on the next session.
#
# Throttle:
#   - shared (company) vaults: 1h — multiple teammates push, want fresh.
#   - private (personal) vaults: 12h — only one writer, slower drift.
#   - obsidian-memory: 12h — scripts rarely change.
#
# Hook JSON contract (stdin): unused — SessionStart carries no tool context.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/vault_registry.sh"

mkdir -p "$HOME/.claude" 2>/dev/null || true
NOW=$(date +%s)

slug() { printf '%s' "$1" | tr '/.~' '___' | tr -cd 'A-Za-z0-9_-'; }

throttle_seconds() {
  case "$1" in
    shared)  echo 3600 ;;
    private) echo 43200 ;;
    *)       echo 43200 ;;
  esac
}

pull_one() {
  local repo="$1" role="${2:-private}"
  [[ -d "$repo/.git" ]] || return 0
  local ts="$HOME/.claude/.last-pull-$(slug "$repo")"
  local prev=0
  [[ -f "$ts" ]] && prev=$(cat "$ts" 2>/dev/null || echo 0)
  local throttle; throttle=$(throttle_seconds "$role")
  if (( NOW - prev < throttle )); then return 0; fi
  git -C "$repo" pull --ff-only --quiet 2>/dev/null || true
  echo "$NOW" > "$ts"
}

while IFS=$'\t' read -r vname vpath vrole; do
  pull_one "$vpath" "$vrole"
done < <(vault_list_rows)

pull_one "$HOME/obsidian-memory" "private"

exit 0
