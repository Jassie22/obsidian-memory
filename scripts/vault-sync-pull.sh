#!/usr/bin/env bash
# Session-start: pull vault + obsidian-memory. Throttled 12h. Silent on success.
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
