#!/usr/bin/env bash
# SessionStart hook: `git pull --ff-only` in ~/vault and ~/obsidian-memory,
# throttled to once per 12h per repo (timestamp in ~/.claude/.last-pull).
#
# Hook JSON contract (stdin): unused — SessionStart carries no tool context.
set -u
LAST="$HOME/.claude/.last-pull"
NOW=$(date +%s)
PREV=0
[[ -f "$LAST" ]] && PREV=$(cat "$LAST" 2>/dev/null || echo 0)
if (( NOW - PREV < 43200 )); then exit 0; fi
for repo in "$HOME/vault" "$HOME/obsidian-memory"; do
  [[ -d "$repo/.git" ]] || continue
  git -C "$repo" pull --ff-only --quiet 2>/dev/null || true
done
echo "$NOW" > "$LAST"
