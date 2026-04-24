#!/usr/bin/env bash
# PreToolUse hook: block Write/Edit/MultiEdit into ~/vault/ if the incoming
# content contains a suspected secret. Hook JSON comes in on stdin.
#
# On match: emit a JSON deny decision (exit 0) so Claude sees a structured
# block message and can retry with redacted content.
#
# Hook JSON contract (stdin):
#   .tool_name                       "Write" | "Edit" | "MultiEdit"
#   .tool_input.file_path            target path (Write, Edit)
#   .tool_input.notebook_path        fallback
#   .tool_input.content              new content (Write)
#   .tool_input.new_string           new content (Edit)
#   .tool_input.edits[].new_string   per-edit content (MultiEdit)
#
# Return contract:
#   exit 0 + empty stdout        → allow
#   exit 0 + JSON deny on stdout → block with structured reason
set -u

payload="$(cat)"

target=$(printf '%s' "$payload" | jq -r '
  .tool_input.file_path //
  .tool_input.filePath //
  .tool_input.notebook_path //
  empty' 2>/dev/null)

# only guard writes landing inside the vault
case "$target" in
  "$HOME/vault/"*) ;;
  *) exit 0 ;;
esac

# candidate content: new_string for Edit, content for Write, joined edits for MultiEdit
content=$(printf '%s' "$payload" | jq -r '
  (.tool_input.content // "") + "\n" +
  (.tool_input.new_string // "") + "\n" +
  ((.tool_input.edits // []) | map(.new_string // "") | join("\n"))
' 2>/dev/null)

[[ -z "$content" ]] && exit 0

# secret patterns — tuned for low false-positives, not a silver bullet
patterns=(
  'sk-[A-Za-z0-9_-]{20,}'                 # Anthropic/OpenAI-ish
  'ghp_[A-Za-z0-9]{30,}'                  # GitHub personal token
  'gho_[A-Za-z0-9]{30,}'                  # GitHub OAuth
  'github_pat_[A-Za-z0-9_]{40,}'          # GitHub fine-grained PAT
  'AKIA[0-9A-Z]{16}'                      # AWS access key
  'ASIA[0-9A-Z]{16}'                      # AWS STS key
  'AIza[0-9A-Za-z_-]{35}'                 # Google API key
  'xox[aboprs]-[0-9A-Za-z-]{10,}'         # Slack token
  'glpat-[0-9A-Za-z_-]{20,}'              # GitLab PAT
  'hf_[A-Za-z0-9]{30,}'                   # HuggingFace token
  'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'  # JWT
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'    # PEM key
  '(password|passwd|pwd)[[:space:]]*[:=][[:space:]]*["'"'"']?[^[:space:]"'"'"']{8,}'
  'postgres(ql)?://[^:]+:[^@]+@'          # pg conn string with inline password
  'mongodb(\+srv)?://[^:]+:[^@]+@'        # mongo conn string with inline password
)

matched=""
for re in "${patterns[@]}"; do
  if printf '%s' "$content" | grep -Eoq -e "$re" 2>/dev/null; then
    # capture a short excerpt for the error (first match, truncated)
    excerpt=$(printf '%s' "$content" | grep -Eom1 -e "$re" 2>/dev/null | head -c 80)
    matched="pattern \`${re}\` → \`${excerpt}…\`"
    break
  fi
done

if [[ -n "$matched" ]]; then
  jq -n --arg reason "Secret detected in vault write (${matched}). Redact (replace with [REDACTED]) and retry. If this is a false positive, tell the user before overriding." '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
fi

exit 0
