#!/usr/bin/env bash
# PreToolUse hook: inject scope-matched rules as context before Write/Edit/Bash.
#
# Hook JSON on stdin. Fields read:
#   .tool_name
#   .tool_input.file_path  (Write, Edit)
#   .tool_input.command    (Bash)
#
# Injects via stdout — a block containing any rules whose `scope:` matches
# "vault" (if target path is inside ~/vault/) or "tool:<ToolName>".
set -u

VAULT="${VAULT_DIR:-$HOME/vault}"
RULES_DIR="$VAULT/rules"
CONFIG="$RULES_DIR/.config.yml"
[[ -d "$RULES_DIR" ]] || exit 0

# Respect the global preguard toggle
enabled=$(grep -E '^\s*preguard_enabled:' "$CONFIG" 2>/dev/null | awk '{print $2}')
[[ "$enabled" == "false" ]] && exit 0

payload="$(cat)"
tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)
target=$(printf '%s' "$payload" | jq -r '
  .tool_input.file_path //
  .tool_input.filePath //
  empty' 2>/dev/null)

scopes=("tool:$tool_name")
case "$target" in
  "$HOME/vault/"*) scopes+=("vault") ;;
esac

blocked_raw=$(grep -E '^\s*blocked_scopes:' "$CONFIG" 2>/dev/null | head -1)

rules_to_inject=()
shopt -s nullglob
for f in "$RULES_DIR"/*.md; do
  case "$(basename "$f")" in
    README.md|rules.md) continue ;;
  esac
  raw=$(awk '/^---$/{c++; next} c==1 && /^scope:/{print; exit}' "$f")
  for s in "${scopes[@]}"; do
    if printf '%s' "$blocked_raw" | grep -qE "[ ,\[]$s[ ,\]]"; then
      continue
    fi
    if printf '%s' "$raw" | grep -qE "(^|[ ,\[])$s(\$|[ ,\]])"; then
      rules_to_inject+=("$f")
      break
    fi
  done
done

(( ${#rules_to_inject[@]} == 0 )) && exit 0

printf '<rules-preguard tool="%s">\n' "$tool_name"
printf 'Rules applicable to this %s call:\n\n' "$tool_name"
for f in "${rules_to_inject[@]}"; do
  title=$(awk '/^title:/{sub(/^title: */,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit}' "$f")
  rule_line=$(awk '/^\*\*Rule:\*\*/{sub(/^\*\*Rule:\*\* */,""); print; exit}' "$f")
  how_line=$(awk '/^\*\*How to apply:\*\*/{sub(/^\*\*How to apply:\*\* */,""); print; exit}' "$f")
  printf -- '- **%s** — %s\n' "$title" "${rule_line:-}"
  [[ -n "$how_line" ]] && printf '  *How:* %s\n' "$how_line"
done
printf '</rules-preguard>\n'

exit 0
