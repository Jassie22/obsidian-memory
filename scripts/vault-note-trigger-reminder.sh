#!/bin/bash
# UserPromptSubmit hook: injects a system-reminder telling Claude to scan the
# previous exchange for proactive-note triggers (per ~/.claude/CLAUDE.md)
# before responding. Runs once per user turn; ~70 tokens of reminder.
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"Proactive-note check (per ~/.claude/CLAUDE.md): before responding, scan the previous exchange for vault-note triggers — gotchas/workarounds not derivable from code, non-obvious decisions, user corrections that imply a durable rule, external context shared by the user, completed milestones, or explicit remember-this. If any trigger fired AND no similar note exists in the vault (verify via: ~/scripts/vault_search.py find-similar \"<title + summary>\"), dispatch a background Agent to write it. If none fired, proceed normally."}}
JSON
