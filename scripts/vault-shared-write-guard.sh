#!/usr/bin/env bash
# PreToolUse hook: block Write/Edit/MultiEdit into a shared (company) vault
# when the target looks like personal/working content — daily logs, captures,
# fleeting/inbox/draft notes, status: inbox/draft/fleeting frontmatter, or
# tags including log/capture/draft/inbox/fleeting.
#
# Why: a shared vault is for durable team-relevant content only — decisions,
# runbooks, gotchas, permanent atomic notes. Working notes / research / daily
# logs belong in the personal vault. Without this guard, a single agent run
# can dump dozens of personal notes into the team's shared remote.
#
# Hook JSON contract: same as vault-secret-guard.sh.
# Return contract: exit 0 + empty stdout = allow; exit 0 + JSON deny = block.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/vault_registry.sh"

payload="$(cat)"

target=$(printf '%s' "$payload" | jq -r '
  .tool_input.file_path //
  .tool_input.filePath //
  .tool_input.notebook_path //
  empty' 2>/dev/null)

[[ -z "$target" ]] && exit 0

# Only fire when the target sits inside a SHARED vault.
match="$(vault_for_path "$target" 2>/dev/null)"
[[ -z "$match" ]] && exit 0

vault_name="$(printf '%s' "$match" | cut -f1)"
vault_path="$(printf '%s' "$match" | cut -f2)"

role="$(vault_list_rows | awk -F'\t' -v n="$vault_name" '$1==n{print $3; exit}')"
[[ "$role" != "shared" ]] && exit 0

rel="${target#$vault_path/}"
basename="$(basename "$rel")"
reason=""

# 1) Path-based blocks — these subdirectories are personal-only by convention.
case "$rel" in
  inbox/*|*/inbox/*)       reason="path is in 'inbox/' — captures + fleeting drafts are personal-only" ;;
  fleeting/*|*/fleeting/*) reason="path is in 'fleeting/' — fleeting notes are personal-only" ;;
  drafts/*|*/drafts/*)     reason="path is in 'drafts/' — drafts are personal-only" ;;
  logs/*|*/logs/*)         reason="path is in 'logs/' — daily session logs are personal-only" ;;
  chats/*|*/chats/*)       reason="path is in 'chats/' — chat exports are personal-only" ;;
esac

# 2) Filename pattern: YYYY-MM-DD-* almost always means a daily log.
if [[ -z "$reason" && "$basename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}- ]]; then
  reason="filename matches daily-log pattern (YYYY-MM-DD-*) — those are personal-only"
fi

# 3) Frontmatter-based block on the incoming content.
if [[ -z "$reason" ]]; then
  content=$(printf '%s' "$payload" | jq -r '
    (.tool_input.content // "") + "\n" +
    (.tool_input.new_string // "") + "\n" +
    ((.tool_input.edits // []) | map(.new_string // "") | join("\n"))
  ' 2>/dev/null)

  # Extract frontmatter block (between first two `---` lines) if present.
  fm=$(printf '%s' "$content" | awk '
    /^---[[:space:]]*$/{c++; if(c==2) exit; next}
    c==1{print}
  ')

  if [[ -n "$fm" ]]; then
    if printf '%s' "$fm" | grep -qiE '^[[:space:]]*status:[[:space:]]*(inbox|draft|fleeting)[[:space:]]*$'; then
      reason="frontmatter has status:[inbox|draft|fleeting] — personal-only states"
    elif printf '%s' "$fm" | grep -qiE '^[[:space:]]*tags:.*\b(log|capture|draft|inbox|fleeting)\b'; then
      reason="frontmatter tags include log/capture/draft/inbox/fleeting — personal-only categorisations"
    elif printf '%s' "$fm" | grep -qiE '^[[:space:]]*type:[[:space:]]*(log|capture)[[:space:]]*$'; then
      reason="frontmatter type:[log|capture] — personal-only mechanical types"
    fi
  fi
fi

if [[ -n "$reason" ]]; then
  jq -n --arg vault "$vault_name" --arg path "$vault_path" --arg rel "$rel" --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("Blocked write to shared vault \"" + $vault + "\" (" + $path + "): " + $reason + ". Personal/working content goes in ~/vault, not the shared vault. Only durable team-relevant content (decisions, runbooks, gotchas, permanent atomic notes) belongs here. If this is a genuine team-relevant note, remove the personal-style tags/status/path and retry — or write it to ~/vault first and `/promote --to company` later.")
    }
  }'
fi

exit 0
