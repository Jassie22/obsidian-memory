# Global Claude Code Instructions (auto-loaded)

> This file lives at `~/.claude/CLAUDE.md` and is read at the start of **every** Claude Code session on this machine.
> It makes the Obsidian memory system available in every project without per-repo configuration.

## Persistent memory — multi-vault model

The user may have **one or two** vaults registered in `~/.claude/vaults.json`:

- **Personal vault** (always present, `role: private`) — typically `~/vault`. Yours alone. Holds logs, captures, personal rules, half-formed proactive notes, side-project groups.
- **Company vault** (optional, `role: shared`) — typically `~/company-vault`. Same git remote across all teammates. Holds team-wide decisions, runbooks, gotchas, cross-group permanent notes.

Read `~/.claude/vaults.json` at session start. If it doesn't exist, treat the personal vault at `~/vault` as the only vault (legacy single-vault mode).

Each vault has its own `CLAUDE.md` rulebook (`<vault>/CLAUDE.md`) — read it on first memory-command use per session for that vault.

The author name (`.author` field in the registry) is stamped into every note's `author:` frontmatter field. Resolve via `~/scripts/vault_author.sh`. Don't make up authors.

## Detecting the current project group

At the start of every session, determine the active group via `~/scripts/vault_resolve_group.sh`:

1. If `./CLAUDE.md` exists in the repo and has a `group:` field, use that.
2. If the company vault has `.repo-map.json` and it matches the current git remote, use that mapping (with optional path overrides).
3. If the personal vault has `.repo-map.json` and it matches, use that (covers personal forks / side projects).
4. If the repo path matches `*/<group>/*` where `<group>` is in any vault's `.groups`, use that.
5. Ask the user once and cache the answer to `~/vault/.repo-map.json` so the next session in the same repo is silent.
6. If no group can be determined, tag with `shared` and treat the active vault as the user's default destination per routing rules below.

Expose the resolved group as `$GROUP` and the active vault root as `$VAULT_DIR` for the rest of this document.

## Routing — which vault does a note land in?

Default destinations by note kind (override only when the user is explicit):

| Note kind                                    | Default vault            |
|----------------------------------------------|--------------------------|
| `/save` session log                          | personal                 |
| `/capture` raw drop                          | personal (`inbox/`)      |
| Personal rule (`/add-rule`)                  | personal (`rules/`)      |
| Proactive note — half-formed / debug / draft | personal (`inbox/`)      |
| Proactive note — durable team-wide decision  | company                  |
| Proactive note — runbook / gotcha / ADR      | company                  |
| Cross-group permanent atomic note            | company if shared exists, else personal `permanent/` |
| Ambiguous proactive note                     | **personal** (safer; promote later via `/promote --to company`) |

When the user says "save this for the team" / "write this up for the team" / "add to the runbook", route to company. When they say "remember that" / "save for next time" / no audience hint, route to personal.

If only the personal vault is registered, all notes land there — the table collapses.

## Session-start sync (auto-pull)

Before running any memory command or answering the user, iterate every registered vault plus the obsidian-memory repo:

```bash
for vp in $(jq -r '.vaults[].path' ~/.claude/vaults.json | sed "s|^~|$HOME|"); do
  ( cd "$vp" && git pull --ff-only --quiet 2>/dev/null ) || true
done
( cd ~/obsidian-memory && git pull --ff-only --quiet 2>/dev/null ) || true
```

- Silent on success, one-line note on failure; never block the session.
- Throttle per-vault via timestamps in `~/.claude/.last-pull`:
  - Personal vault: once per 12h.
  - Shared/company vault: **once per 1h** (5 teammates push frequently — staler than 1h means you risk an `/add-rule`-equivalent collision or out-of-date runbook).
- On merge conflict: stop and surface — never auto-resolve.
- If `~/.claude/CLAUDE.md` or any vault's `CLAUDE.md` changed after the pull, tell the user to restart.

## Memory commands (available in every project)

### Auto-commit & push (memory-system files)

After **any** change to a vault or to `~/obsidian-memory/`:

```bash
git add -A && git commit -m "<type>(<author>): <short msg>" && git push
```

In the **company vault**, the commit message must include the author's name (`<type>(<author>):`) so `git log --oneline` is scannable when 5 teammates are pushing — `decision(jassie): switch arc auth to OIDC`.

Applies to every edit, not just `/save`. Memory must never diverge between devices. If the remote rejects: pull/rebase and retry; never force-push.

For **code repos**: normal workflow — commit when a logical change is done, push only when the user asks.

### `/resume`
1. Pick the active vault: company-vault if `$GROUP` is in the company-vault's `.groups`, else personal.
2. From the **personal** vault: read `~/vault/$GROUP/logs/` and load the 3 most recent logs (logs are always personal).
3. From the **active** vault (company if applicable): read `$VAULT_DIR/$GROUP/_MOC.md` and any `$GROUP/architecture/decisions.md`.
4. From the **company** vault (if it exists): read recent runbooks/decisions for `$GROUP` (last 5 by `updated:`).
5. Summarise: current state, open TODOs, recent decisions, suggested next step. Mark each item with `[personal]` or `[company]` so the user knows where it lives.

### `/save`
Logs are **always personal** (per the routing table — they're a per-person work record). The slug, however, may reference notes in either vault.

1. Create `~/vault/$GROUP/logs/YYYY-MM-DD-<slug>.md` with frontmatter:
   ```yaml
   ---
   title: <slug>
   group: $GROUP
   tags: [$GROUP, log]
   author: <name from ~/scripts/vault_author.sh>
   created: YYYY-MM-DD
   updated: YYYY-MM-DD
   type: log
   ---
   ```
   Sections: Done · Decisions · Open items · Next step · wikilinks to every note touched (in either vault — wikilinks resolve by basename, not by vault).
2. Prepend the log under "Recent logs" in `~/vault/$GROUP/_MOC.md` (personal MOC).
3. If any decision/gotcha emerged that the team would want, **also** spawn a proactive note into the **company** vault — don't bury it in a personal log.
4. Redact secrets per Credential hygiene rules.
5. Run `~/scripts/vault_search.py index` to refresh the semantic index (covers all registered vaults).
6. If the current repo is a git repo: `git add -A && git commit -m "session: <slug>"` (no push unless asked).
7. Auto-commit + push the personal vault. If a note also landed in company, auto-commit + push it too — separate commits per vault.

### `/capture <free-form text>`
Quick-drop a thought into `~/vault/inbox/` (personal) without ceremony. Captures are always personal — use `/promote --to company` to lift them into the shared vault once they're durable.

1. Slug = first 5-6 meaningful words, kebab-case.
2. Write `~/vault/inbox/YYYY-MM-DD-<slug>.md`:
   ```yaml
   ---
   title: <slug titleised>
   description: <one-sentence summary of the captured text>
   group: $GROUP        # or "shared" if no group resolved
   tags: [$GROUP, inbox, capture]
   author: <name from ~/scripts/vault_author.sh>
   created: YYYY-MM-DD
   updated: YYYY-MM-DD
   status: inbox
   ---
   ```
   Body = the user's text verbatim, then a `## Context` section with what was happening when it was captured (one line).
3. Redact secrets per Credential hygiene rules.
4. Run `~/scripts/vault_search.py index` (async / backgrounded is fine).
5. Auto-commit + push the personal vault.
6. Reply with ONE line: `captured → inbox/<slug>.md`. No summary, no follow-up questions.

Distinct from proactive note-writing: `/capture` is **user-triggered**, lands in `inbox/` regardless of triggers, and never dedupes.

### `/promote <note-name> [--to personal|company]`
Move a note from `~/vault/inbox/` or `~/vault/fleeting/` into a permanent location.

- Default destination: same vault, into `permanent/` or the right group folder.
- `--to company` (only valid if a company vault is registered): move into `~/company-vault/$GROUP/` (or `permanent/` for cross-group). Set `author:` to the original author from frontmatter (don't overwrite); if a different teammate is doing the promotion, append their name (`author: Alex, Sam`).
- `--to personal`: move from company → personal. Rare; usually means demoting a note that turned out to be a personal preference rather than a team rule.

Always ensure: frontmatter complete, ≥2 wikilinks, `description:` set, `updated:` bumped. Cross-vault promotions preserve `created:` from the source.

### `/recall <query>`
Semantic retrieval over **all registered vaults**. Backed by `~/scripts/vault_search.py` (fastembed + sqlite-vec, BGE-large by default, ~3s cold).

1. Run: `~/scripts/vault_search.py search "<query>"` (the script reads `~/.claude/vaults.json` and queries every indexed vault).
2. Read the top 3 hit files. Summarise with wikilinks — don't dump raw contents. Show the vault name in brackets: `[[arc/auth-decision]] (company)`.
3. If all distances >1.2: "no strong matches in any vault" (don't confabulate).
4. If any vault's index looks stale (note mtime newer than `.index.db` mtime), run `index` for that vault first.

**Call `/recall` unprompted** when the user references past work, "that thing we did", "the way we usually", prior projects, or "remember when". Hard trigger — run before answering.

## Proactive note-writer (background)

Capture durable knowledge **without waiting for `/save`**, using the Agent tool with `run_in_background: true`.

### Triggers (write a note when any fires)

- A non-obvious **decision** is made.
- A **gotcha / bug workaround** that won't be re-derivable from code.
- **External context** the user shares (team, legal, pricing, deadlines).
- The user **corrects** Claude in a way that implies a durable rule.
- A **milestone** is completed.
- The user says "remember that", "save this", "for future reference".

Do NOT write for: ephemeral debugging, trivial fixes visible in git, info already in the repo's `CLAUDE.md`.

### Vault-routing decision (re-checked per note)

Before spawning, decide which vault the note lands in using the routing table above. Default to **personal** when in doubt. Heuristics:

- Trigger word "for the team" / "everyone needs to know" / "deploy runbook" → company.
- Trigger is "remember next time I do X" / one-person preference → personal.
- Decision affects shared infra, shared schema, on-call → company.
- Decision affects only your dev environment, your editor setup, your local workflow → personal.
- Cross-cutting permanent atomic note (no obvious owner): if a company vault exists and the topic is project-related → company `permanent/`; else personal `permanent/`.

Stamp the chosen vault into the spawn prompt — never let the background agent re-decide.

### Update-vs-create (dedupe before writing)

1. Run `~/scripts/vault_search.py find-similar "<proposed title + summary>" --vault <chosen vault>` — searches only the target vault to avoid promoting personal notes accidentally.
2. Top distance <0.7 → **update** that note (append dated subsection or edit in place).
3. 0.7-1.0 → read the candidate; same topic → update; related → create new + cross-wikilink.
4. All >1.0 → create new.

When updating an existing note in the **company** vault that someone else originally authored: keep their name in `author:` and append yours: `author: Sam, Alex`. Bump `updated:`. Add a dated `## Update YYYY-MM-DD (Alex)` subsection rather than overwriting their prose silently.

Superseded decisions: never delete. Add `status: superseded-by [[new-note]]` to the old note.

### Background spawn pattern

```
Agent(
  description: "vault note: <slug> (<vault>)",
  subagent_type: "general-purpose",
  run_in_background: true,
  prompt: "<self-contained: fact to record, target VAULT (personal or company) and absolute path, group, author from ~/scripts/vault_author.sh, triggering event, run find-similar --vault <vault> first, redact secrets, re-index, auto-commit+push that vault only>"
)
```

The spawn prompt MUST include the resolved vault path explicitly — never let the background agent re-resolve it, since by the time it runs the user may have switched repos.

### Enforcement

A `UserPromptSubmit` hook at `~/scripts/vault-note-trigger-reminder.sh` (wired in `~/.claude/settings.json`) injects the trigger checklist as a system-reminder on every user turn. This makes the check structural rather than relying on Claude remembering. If the script is renamed/moved, update the hook path in `settings.json` too — there's no version control on `~/scripts/` yet.

## Context navigation (Graphify) — inside a code repo

At session start, check for `graphify-out/graph.json`.

**Graph exists** — use before reading source files:

1. First → `graphify-out/graph.json` / `graphify-out/wiki/index.md`.
2. Second → `~/vault/$GROUP/` for decisions & context.
3. Third → raw source, only when editing or when 1-2 don't answer.

Never re-read the whole codebase if the graph already has the info.

**Graph does NOT exist** — tell the user once:

> "Graphify isn't set up for this repo yet. Want me to wire it up? It builds a codebase knowledge graph so I can navigate the repo without re-reading every file."

If they agree:
1. `command -v graphify`; if missing: `pip install --user --upgrade graphifyy`.
2. `graphify update .`
3. Add `graphify-out/` to `.gitignore`.
4. Offer `graphify hook install` (rebuild on commit).
5. Offer `graphify watch .` during active dev.

## Vault note conventions

- Wikilinks `[[like-this]]`, not markdown links. Wikilinks resolve by basename across vaults — `[[arc-auth-decision]]` works even if the source note is in personal and the target is in company.
- Kebab-case filenames.
- YAML frontmatter on every permanent note.
- Tag with the group (`#<group>`).
- Minimum two wikilinks per permanent note.
- `author:` field stamped from `~/scripts/vault_author.sh`. Mandatory in the company vault, recommended in personal.

## Rules system (behavior rules, authored by user — personal only)

Behavior rules that modify Claude's actions live in `~/vault/rules/` (one file per rule) — **always personal, never in the company vault**. What one teammate wants Claude to do isn't what the team wants. The index at `~/vault/rules.md` is auto-generated.

**You (Claude) do not write to `~/vault/rules/` directly.** Rules are authored by the user via `/add-rule` or manual edits. The `rules-reminder.sh` UserPromptSubmit hook and `rules-preguard.sh` PreToolUse hook inject scope-matched rules into context at runtime — treat those injected blocks as standing orders for the current turn.

**When the user dictates a new rule** ("always do X" / "from now on Y"):
1. Confirm the rule wording with the user.
2. Ask for `scope` (global / group / vault / tool:<Name>).
3. Invoke `/add-rule` or scaffold the file directly at `~/vault/rules/<slug>.md` (personal vault).
4. Do NOT save as auto-memory feedback — that's scoped to one project and defeats cross-project reuse.
5. Do NOT write rule files into the company vault — even if the user says "make this a team rule". Team-wide *behavioral* preferences belong in the company vault's per-group `CLAUDE.md` files (read at session start), not in the per-user rules system.

**Precedence** when rules from multiple sources conflict: user's direct message this turn > `~/vault/rules/` > per-repo `CLAUDE.md` > company-vault `CLAUDE.md` > this file > model defaults.

**Tuning:** the user changes reminder cadence in `~/vault/rules/.config.yml` (`reminder_interval`). Don't edit that file unless the user explicitly asks.

## Safety

- Never delete vault notes without asking.
- Never force-push **any** vault repo, but be especially careful with the company vault — a force-push there overwrites teammates' work.
- Never run destructive git commands in the current repo without confirmation.
- In the company vault: never `git rebase` history that's already been pushed. Never delete notes another teammate authored without asking them first (or the user, if they're not the author).

### Credential hygiene (vault + logs + graph) — stricter for the company vault

Both vaults, session logs, chat imports, and Graphify output are plaintext — treat as **public-visible even if the repo is private**. The company vault is also visible to all teammates the moment you push, so a leaked secret has a 5x bigger blast radius.

- **Never** write API keys, tokens, passwords, private URLs, `.env` contents, connection strings, cookies, session IDs, JWTs, or any secret into vault notes / logs / MOCs.
- On `/save` and proactive note-writes, scan for secret patterns (`sk-…`, `ghp_…`, `AKIA…`, `Bearer …`, `password=`, `-----BEGIN …PRIVATE KEY-----`, long hex/base64 blobs); replace with `[REDACTED]`.
- A `PreToolUse` hook (`~/scripts/vault-secret-guard.sh`) enforces this structurally — any Write/Edit into a registered vault is blocked if a secret pattern is detected. On deny: redact and retry. Don't override unless you've told the user.
- Redact secrets in chat exports before they land in `~/vault/chats/` (chats are personal).
- Graphify: before running, check `.gitignore` / `.env*` patterns; `--exclude` secret-carrying files.
- Verify each vault's git remote is **private** before first push. Refuse if public.
- If a secret is already in a vault: stop, tell the user, help rotate + purge from history (`git filter-repo`) — don't silently delete. If it's the company vault, also tell the user to notify teammates so they can stop pulling that ref until it's purged.
