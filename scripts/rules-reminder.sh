#!/usr/bin/env bash
# UserPromptSubmit hook: every Nth turn, inject scope-matched rules as
# a system-reminder. Silent on other turns.
#
# Hook JSON on stdin. Fields read:
#   .session_id             (per-session turn counter)
#   .cwd                    (current working directory)
#
# Injection is stdout — Claude Code attaches it as additional context for
# this turn. Keep the footprint small.
set -u

VAULT="${VAULT_DIR:-$HOME/vault}"
RULES_DIR="$VAULT/rules"
CONFIG="$RULES_DIR/.config.yml"
[[ -d "$RULES_DIR" ]] || exit 0

interval=$(grep -E '^\s*reminder_interval:' "$CONFIG" 2>/dev/null | awk '{print $2}')
interval=${interval:-10}

payload="$(cat)"
session_id=$(printf '%s' "$payload" | jq -r '.session_id // "default"' 2>/dev/null)
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)

# Increment counter
counter_file="$HOME/.claude/.rules-turn-counter-$session_id"
mkdir -p "$(dirname "$counter_file")"
counter=0
[[ -f "$counter_file" ]] && counter=$(cat "$counter_file" 2>/dev/null || echo 0)
counter=$((counter + 1))
printf '%d' "$counter" > "$counter_file"

# Only fire every Nth turn (turn 1 also fires, so rules show up right away)
if (( counter != 1 )) && (( counter % interval != 0 )); then
  exit 0
fi

# Active scopes: global + (vault if cwd in vault) + (group if ./CLAUDE.md group matches)
scopes=("global")
case "$cwd" in
  "$VAULT"*) scopes+=("vault") ;;
esac
if [[ -f "$cwd/CLAUDE.md" && -f "$VAULT/.groups" ]]; then
  group=$(grep -E '^group:' "$cwd/CLAUDE.md" 2>/dev/null | head -1 | awk '{print $2}')
  if [[ -n "${group:-}" ]] && grep -qxF "$group" "$VAULT/.groups"; then
    scopes+=("$group")
  fi
fi

# Check blocked_scopes — simple grep, skip whole block if any match
blocked_raw=$(grep -E '^\s*blocked_scopes:' "$CONFIG" 2>/dev/null | head -1)

rules_to_inject=()
shopt -s nullglob
for f in "$RULES_DIR"/*.md; do
  case "$(basename "$f")" in
    README.md|rules.md) continue ;;
  esac
  # extract scope line from frontmatter
  raw=$(awk '/^---$/{c++; next} c==1 && /^scope:/{print; exit}' "$f")
  for s in "${scopes[@]}"; do
    # skip if scope is in blocked list
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

# Emit the system-reminder
printf '<rules-reminder>\n'
printf 'Active rules (turn %d, reminder every %d turns). These are your standing orders — apply them this turn:\n\n' "$counter" "$interval"
for f in "${rules_to_inject[@]}"; do
  title=$(awk '/^title:/{sub(/^title: */,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit}' "$f")
  scope=$(awk '/^---$/{c++; next} c==1 && /^scope:/{sub(/^scope: */,""); print; exit}' "$f")
  rule_line=$(awk '/^\*\*Rule:\*\*/{sub(/^\*\*Rule:\*\* */,""); print; exit}' "$f")
  printf -- '- **[%s]** %s — %s\n' "$scope" "$title" "${rule_line:-see $(basename "$f")}"
done
printf '\nFull rule bodies: ~/vault/rules/ · edit config at ~/vault/rules/.config.yml\n'
printf '</rules-reminder>\n'

exit 0
