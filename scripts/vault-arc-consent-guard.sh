#!/usr/bin/env bash
# PreToolUse hook: gate ALL Write/Edit/MultiEdit into the *shared* (company)
# vault behind a fresh, one-shot consent file. The personal vault is unaffected.
#
# Why: the shared vault has the same git remote as your teammates. Every write
# must be deliberately approved by the user; agents (especially backgrounded
# ones) must never self-publish into the team's shared remote.
#
# The shared-vault path is resolved from the registry (~/.claude/vaults.json,
# the entry with role=="shared"), NOT hardcoded — so this ships unmodified.
# If no shared vault is registered, the guard is inert (exits 0).
#
# Consent mechanism:
#   - File:      ~/.claude/.arc-vault-consent
#   - Freshness: must have been touched in the last CONSENT_TTL seconds
#   - One-shot:  the file is deleted on the allowed write
#
# Hook JSON contract (stdin):
#   .tool_input.file_path / .tool_input.filePath / .tool_input.notebook_path
#
# Return contract:
#   exit 0 silently  → allow
#   exit 2 + stderr  → block (Claude Code surfaces stderr as the deny reason)
#
# Robustness: if no path can be parsed, fail open (exit 0). Never block
# unrelated tool calls.
set -u

REGISTRY="$HOME/.claude/vaults.json"
CONSENT_FILE="$HOME/.claude/.arc-vault-consent"
CONSENT_TTL=60  # seconds

# Resolve the shared vault path from the registry. No shared vault → nothing
# to guard, so this hook is safe to wire even on personal-only installs.
SHARED_VAULT=""
if [[ -f "$REGISTRY" ]] && command -v jq >/dev/null 2>&1; then
  SHARED_VAULT="$(jq -r '.vaults[]? | select(.role=="shared") | .path' "$REGISTRY" 2>/dev/null | head -n1)"
  SHARED_VAULT="${SHARED_VAULT/#\~/$HOME}"
fi
[[ -z "$SHARED_VAULT" ]] && exit 0

payload="$(cat)"

target=$(printf '%s' "$payload" | jq -r '
  .tool_input.file_path //
  .tool_input.filePath //
  .tool_input.notebook_path //
  empty' 2>/dev/null)

# Fail open on missing/unparseable path
[[ -z "$target" ]] && exit 0

# Resolve to an absolute, symlink-resolved path for a reliable prefix check.
# realpath -m: tolerate non-existent files (Write creates new files).
resolved=$(realpath -m -- "$target" 2>/dev/null || printf '%s' "$target")
shared_resolved=$(realpath -m -- "$SHARED_VAULT" 2>/dev/null || printf '%s' "$SHARED_VAULT")

case "$resolved" in
  "$shared_resolved"|"$shared_resolved"/*) : ;;  # inside shared vault → continue
  *) exit 0 ;;                                    # outside → no-op
esac

# Inside the shared vault. Check consent file.
if [[ -f "$CONSENT_FILE" ]]; then
  now=$(date +%s)
  mtime=$(stat -c %Y "$CONSENT_FILE" 2>/dev/null || echo 0)
  age=$(( now - mtime ))
  if (( age >= 0 && age <= CONSENT_TTL )); then
    # Fresh consent → consume it (one-shot) and allow.
    rm -f "$CONSENT_FILE" 2>/dev/null || true
    exit 0
  fi
  # Stale → fall through to deny. Clean up so it doesn't silently re-arm later.
  rm -f "$CONSENT_FILE" 2>/dev/null || true
fi

cat >&2 <<EOF
Write to the shared vault ($SHARED_VAULT) blocked. This vault is shared with the team — every write must be explicitly approved by the user.

To proceed:
  (1) ask the user IN CHAT, in plain English, whether to add the proposed content/note (give a one-line summary) to the company vault;
  (2) only after the user says yes, run:
        touch $CONSENT_FILE
  (3) retry the write within ${CONSENT_TTL}s — consent is one-shot and auto-consumed.

Background agents MUST instead surface back to the foreground — they cannot self-grant consent. The consent file gates a single subsequent write only.
EOF

exit 2
