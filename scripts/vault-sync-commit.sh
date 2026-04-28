#!/usr/bin/env bash
# PostToolUse hook: if an edit landed inside any registered vault, commit
# + push that vault. Reads hook JSON from stdin.
#
# Hook JSON contract (stdin):
#   .tool_input.file_path     target path (Write, Edit)
#   .tool_response.filePath   fallback (some tools set this after success)
#
# Resolution: longest-prefix match against the vault registry, so a personal
# vault nested inside the company vault (rare but legal) routes correctly.
# No-op if the target is outside every registered vault.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/vault_registry.sh"

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)
[[ -z "$f" ]] && exit 0

if ! match=$(vault_for_path "$f"); then
  exit 0
fi
vname="${match%%	*}"
vpath="${match#*	}"

cd "$vpath" || exit 0
git diff --quiet && git diff --cached --quiet && exit 0
git add -A >/dev/null 2>&1
git commit -m "${vname}: auto-sync $(basename "$f")" --quiet 2>/dev/null || exit 0
git push --quiet 2>/dev/null || true
exit 0
