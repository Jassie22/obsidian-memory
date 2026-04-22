#!/usr/bin/env bash
# PostToolUse hook: if a Write/Edit/MultiEdit touched ~/vault/rules/*.md,
# regenerate ~/vault/rules.md. Silent no-op otherwise.
#
# Hook JSON arrives on stdin. Fields read:
#   .tool_input.file_path      (Write, Edit)
#   .tool_response.filePath    (fallback)
#   .tool_input.edits[].file_path  (MultiEdit — any edit into rules/ triggers)
set -u

f=$(jq -r '
  .tool_input.file_path //
  .tool_response.filePath //
  (.tool_input.edits // [] | .[0].file_path // empty) //
  empty' 2>/dev/null)

case "$f" in
  "$HOME/vault/rules/"*.md)
    # Don't rebuild on edits to rules.md itself or to config files
    case "$(basename "$f")" in
      rules.md|.config.yml|.config.example.yml|README.md) exit 0 ;;
    esac
    "$HOME/scripts/rules_rebuild.py" >/dev/null 2>&1 || true
    ;;
esac
exit 0
