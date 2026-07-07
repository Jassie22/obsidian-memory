#!/usr/bin/env bash
# PreToolUse hook (Bash): block `git push` against the *shared* (company) vault
# unless a fresh consent file is present. Closes the bash bypass around the
# Write/Edit consent gate (vault-arc-consent-guard.sh).
#
# The shared-vault path is resolved from the registry (~/.claude/vaults.json,
# the entry with role=="shared"), NOT hardcoded — so this ships unmodified.
# If no shared vault is registered, the guard is inert (exits 0).
#
# Triggers ONLY when:
#   - command contains `git ... push` (as a standalone subcommand)
#   AND
#   - the operation targets the shared vault, detected by either:
#       * `-C <shared-vault-path>` in the command, OR
#       * the hook's cwd resolves under the shared vault
#
# Innocuous git ops (status, log, pull, diff, fetch) NEVER trigger.
# Personal vault git push is NEVER blocked.
#
# Hook JSON contract (stdin):
#   .tool_input.command   the bash command string
#   .cwd                  current working directory
#
# Return contract:
#   exit 0 silently  → allow
#   exit 2 + stderr  → block
#
# Fail open on parse failure.
set -u

REGISTRY="$HOME/.claude/vaults.json"
CONSENT_FILE="$HOME/.claude/.arc-vault-consent"
CONSENT_TTL=60

# Resolve the shared vault path from the registry. No shared vault → nothing
# to guard.
SHARED_VAULT=""
if [[ -f "$REGISTRY" ]] && command -v jq >/dev/null 2>&1; then
  SHARED_VAULT="$(jq -r '.vaults[]? | select(.role=="shared") | .path' "$REGISTRY" 2>/dev/null | head -n1)"
  SHARED_VAULT="${SHARED_VAULT/#\~/$HOME}"
fi
[[ -z "$SHARED_VAULT" ]] && exit 0
SHARED_TILDE="${SHARED_VAULT/#$HOME/~}"

payload="$(cat)"

cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)

[[ -z "$cmd" ]] && exit 0

# Must contain `git` and a standalone `push` subcommand (so `pushd`, `pushed`
# don't trigger). We don't try to perfectly parse pipelines / `&&` chains —
# false negatives there are acceptable; false positives on innocuous git ops
# are not.
if ! printf '%s' "$cmd" | grep -Eq '\bgit\b'; then
  exit 0
fi
if ! printf '%s' "$cmd" | grep -Eq '(^|[[:space:]])push([[:space:]]|$)'; then
  exit 0
fi

# Determine if this push targets the shared vault.
targets_shared=0

# 1) Explicit `-C <path>` flag pointing into the shared vault (absolute or ~).
esc_abs=$(printf '%s' "$SHARED_VAULT" | sed 's/[.[\*^$/]/\\&/g')
esc_tilde=$(printf '%s' "$SHARED_TILDE" | sed 's/[.[\*^$/]/\\&/g')
if printf '%s' "$cmd" | grep -Eq '\-C[[:space:]]+("?'"$esc_abs"'"?|"?'"$esc_tilde"'"?)(/|[[:space:]]|$)'; then
  targets_shared=1
fi

# 2) cwd is inside the shared vault.
if [[ "$targets_shared" -eq 0 && -n "$cwd" ]]; then
  resolved_cwd=$(realpath -m -- "$cwd" 2>/dev/null || printf '%s' "$cwd")
  shared_resolved=$(realpath -m -- "$SHARED_VAULT" 2>/dev/null || printf '%s' "$SHARED_VAULT")
  case "$resolved_cwd" in
    "$shared_resolved"|"$shared_resolved"/*) targets_shared=1 ;;
  esac
fi

[[ "$targets_shared" -eq 0 ]] && exit 0

# This is a `git push` against the shared vault. Check consent.
if [[ -f "$CONSENT_FILE" ]]; then
  now=$(date +%s)
  mtime=$(stat -c %Y "$CONSENT_FILE" 2>/dev/null || echo 0)
  age=$(( now - mtime ))
  if (( age >= 0 && age <= CONSENT_TTL )); then
    rm -f "$CONSENT_FILE" 2>/dev/null || true
    exit 0
  fi
  rm -f "$CONSENT_FILE" 2>/dev/null || true
fi

cat >&2 <<EOF
\`git push\` to the shared vault ($SHARED_VAULT) blocked. This vault is shared with the team — pushes must be explicitly approved by the user.

To proceed:
  (1) ask the user inline with a one-line summary of what's being pushed;
  (2) wait for their explicit 'yes';
  (3) only foreground Claude (NOT a background agent) may then run:
        touch $CONSENT_FILE
      and immediately retry the push within ${CONSENT_TTL}s.

If you only need to commit locally, that's allowed — just drop the push.
EOF

exit 2
