#!/usr/bin/env bash
# Claude Code statusline: emits one line showing active rule count and
# turns-until-next-reminder.
#
# Statusline hook JSON on stdin. Fields read:
#   .session_id             (for turn counter lookup)
#   .workspace.current_dir  (for scope resolution)
#
# Silent if ~/vault/rules/ doesn't exist (not yet set up).
set -u

VAULT="${VAULT_DIR:-$HOME/vault}"
RULES_DIR="$VAULT/rules"
CONFIG="$RULES_DIR/.config.yml"
[[ -d "$RULES_DIR" ]] || exit 0

# Read config (grep-based — avoids python dep in statusline)
statusline_enabled=$(grep -E '^\s*statusline_enabled:' "$CONFIG" 2>/dev/null | awk '{print $2}')
[[ "$statusline_enabled" == "false" ]] && exit 0

interval=$(grep -E '^\s*reminder_interval:' "$CONFIG" 2>/dev/null | awk '{print $2}')
interval=${interval:-10}

payload="$(cat)"
session_id=$(printf '%s' "$payload" | jq -r '.session_id // "default"' 2>/dev/null)
cwd=$(printf '%s' "$payload" | jq -r '.workspace.current_dir // empty' 2>/dev/null)

# Active scopes for this cwd: always "global"; add "vault" if inside vault;
# add group if ./CLAUDE.md in cwd has a `group:` field matching ~/vault/.groups
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

# Count rule files whose scope frontmatter matches any active scope
active_count=0
shopt -s nullglob
for f in "$RULES_DIR"/*.md; do
  case "$(basename "$f")" in
    README.md|rules.md) continue ;;
  esac
  raw=$(awk '/^---$/{c++; next} c==1 && /^scope:/{print; exit}' "$f")
  # raw looks like "scope: vault" or "scope: [global, vault]"
  for s in "${scopes[@]}"; do
    if printf '%s' "$raw" | grep -qE "(^|[ ,\[])$s(\$|[ ,\]])"; then
      active_count=$((active_count + 1))
      break
    fi
  done
done

# Turn counter: read, don't increment (reminder hook does that)
counter_file="$HOME/.claude/.rules-turn-counter-$session_id"
counter=0
[[ -f "$counter_file" ]] && counter=$(cat "$counter_file" 2>/dev/null || echo 0)
turns_left=$(( interval - (counter % interval) ))
[[ "$turns_left" == "$interval" ]] && turns_left=0

printf '📋 %d rules · next reminder in %d turns\n' "$active_count" "$turns_left"
