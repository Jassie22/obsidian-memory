#!/usr/bin/env bash
# PostToolUse hook: if an edit happened inside ~/vault, commit + push.
# Reads hook JSON from stdin.
set -u
f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)
case "$f" in
  "$HOME/vault/"*)
    cd "$HOME/vault" || exit 0
    git diff --quiet && git diff --cached --quiet && exit 0
    git add -A >/dev/null 2>&1
    git commit -m "vault: auto-sync $(basename "$f")" --quiet 2>/dev/null || exit 0
    git push --quiet 2>/dev/null || true
    ;;
esac
exit 0
