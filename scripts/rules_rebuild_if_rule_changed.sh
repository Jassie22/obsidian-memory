#!/usr/bin/env bash
# PostToolUse hook: if a Write/Edit/MultiEdit touched <personal-vault>/rules/*.md,
# regenerate <personal-vault>/rules.md. Silent no-op otherwise.
#
# Hook JSON arrives on stdin. Fields read:
#   .tool_input.file_path      (Write, Edit)
#   .tool_response.filePath    (fallback)
#   .tool_input.edits[].file_path  (MultiEdit — any edit into rules/ triggers)
#
# Rules only ever live in the personal vault, so this hook resolves that
# vault from the registry and only rebuilds when an edit lands inside its
# rules/ directory.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/vault_registry.sh"

PERSONAL="$(vault_personal_path)"
[[ -z "$PERSONAL" ]] && PERSONAL="${VAULT_DIR:-$HOME/vault}"
RULES_DIR="$PERSONAL/rules"

f=$(jq -r '
  .tool_input.file_path //
  .tool_response.filePath //
  (.tool_input.edits // [] | .[0].file_path // empty) //
  empty' 2>/dev/null)

[[ -z "$f" ]] && exit 0

case "$f" in
  "$RULES_DIR/"*.md)
    case "$(basename "$f")" in
      rules.md|.config.yml|.config.example.yml|README.md) exit 0 ;;
    esac
    VAULT_DIR="$PERSONAL" "$SCRIPT_DIR/rules_rebuild.py" >/dev/null 2>&1 || true
    ;;
esac
exit 0
