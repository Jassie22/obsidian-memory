# Global Claude Code Instructions (auto-loaded)

> This file lives at `~/.claude/CLAUDE.md` and is read at the start of **every** Claude Code session on this machine.
> It makes the Obsidian memory system available in every project without per-repo configuration.

## Persistent memory — Obsidian vault

- Vault location: `~/vault`
- Vault rulebook: `~/vault/CLAUDE.md` (read on first memory-command use per session)
- Groups: user-defined. The list lives in `~/vault/.groups` (one slug per line). Examples: `work`, `personal`, `research`, `client-acme`.

## Detecting the current project group

At the start of every session, determine the active group:

1. If `./CLAUDE.md` exists in the repo and has a `group:` field, use that (must match a line in `~/vault/.groups`).
2. Otherwise, if the repo path matches any `*/<group>/*` where `<group>` is in `~/vault/.groups`, use that.
3. Otherwise, ask the user once: "Which group is this project? Options: <list from ~/vault/.groups>" and remember for the rest of the session.
4. If no group can be determined, default to the shared vault root (`~/vault/`) and tag with `shared`.

Expose the resolved group as `$GROUP` for the rest of this document.

## Session-start sync (auto-pull)

Before running any memory command or answering the user:

```bash
( cd ~/vault          && git pull --ff-only --quiet 2>/dev/null ) || true
( cd ~/obsidian-memory && git pull --ff-only --quiet 2>/dev/null ) || true
```

- Silent on success, one-line note on failure; never block the session.
- Throttle to once per 12h per repo via timestamp in `~/.claude/.last-pull`.
- On merge conflict: stop and surface — never auto-resolve.
- If `~/.claude/CLAUDE.md` changed after the pull, tell the user to restart.

## Memory commands (available in every project)

### Auto-commit & push (memory-system files)

After **any** change to `~/vault/` or `~/obsidian-memory/`:

```bash
git add -A && git commit -m "<type>: <short msg>" && git push
```

Applies to every edit, not just `/save`. Memory must never diverge between devices. If the remote rejects: pull/rebase and retry; never force-push.

For **code repos**: normal workflow — commit when a logical change is done, push only when the user asks.

### `/resume`
1. Read `~/vault/$GROUP/logs/` and load the 3 most recent logs.
2. Read `~/vault/$GROUP/architecture/decisions.md` if present.
3. Read `~/vault/$GROUP/_MOC.md` if present.
4. Summarise: current state, open TODOs, recent decisions, suggested next step.

### `/save`
1. Create `~/vault/$GROUP/logs/YYYY-MM-DD-<slug>.md` with frontmatter:
   ```yaml
   ---
   title: <slug>
   group: $GROUP
   tags: [$GROUP, log]
   created: YYYY-MM-DD
   updated: YYYY-MM-DD
   type: log
   ---
   ```
   Sections: Done · Decisions · Open items · Next step · wikilinks to every note touched.
2. Prepend the log under "Recent logs" in `~/vault/$GROUP/_MOC.md`.
3. Redact secrets per Credential hygiene rules.
4. Run `~/scripts/vault_search.py index` to refresh the semantic index.
5. If the current repo is a git repo: `git add -A && git commit -m "session: <slug>"` (no push unless asked).
6. Auto-commit + push the vault.

### `/promote <note-name>`
Move a note from `~/vault/inbox/` or `~/vault/fleeting/` into `~/vault/permanent/` or the right group folder. Ensure frontmatter + at least 2 wikilinks.

### `/recall <query>`
Semantic retrieval over the vault. Backed by `~/scripts/vault_search.py` (fastembed + sqlite-vec, BGE-large by default, ~3s cold).

1. Run: `~/scripts/vault_search.py search "<query>"`
2. Read the top 3 hit files. Summarise with wikilinks — don't dump raw contents.
3. If all distances >1.2: "no strong matches in vault" (don't confabulate).
4. If the index looks stale (any note mtime newer than `.index.db` mtime), run `index` first.

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

### Update-vs-create (dedupe before writing)

1. Run `~/scripts/vault_search.py find-similar "<proposed title + summary>"` — returns top-3.
2. Top distance <0.7 → **update** that note (append dated subsection or edit in place).
3. 0.7-1.0 → read the candidate; same topic → update; related → create new + cross-wikilink.
4. All >1.0 → create new.

Superseded decisions: never delete. Add `status: superseded-by [[new-note]]` to the old note.

### Background spawn pattern

```
Agent(
  description: "vault note: <slug>",
  subagent_type: "general-purpose",
  run_in_background: true,
  prompt: "<self-contained: fact to record, group, triggering event, run find-similar first, redact secrets, re-index, auto-commit+push>"
)
```

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

## Writing rules inside the vault

- Wikilinks `[[like-this]]`, not markdown links.
- Kebab-case filenames.
- YAML frontmatter on every permanent note.
- Tag with the group (`#<group>`).
- Minimum two wikilinks per permanent note.

## Safety

- Never delete vault notes without asking.
- Never force-push the vault repo.
- Never run destructive git commands in the current repo without confirmation.

### Credential hygiene (vault + logs + graph)

The vault, session logs, chat imports, and Graphify output are plaintext — treat as **public-visible even if the repo is private**.

- **Never** write API keys, tokens, passwords, private URLs, `.env` contents, connection strings, cookies, session IDs, JWTs, or any secret into vault notes / logs / MOCs.
- On `/save` and proactive note-writes, scan for secret patterns (`sk-…`, `ghp_…`, `AKIA…`, `Bearer …`, `password=`, `-----BEGIN …PRIVATE KEY-----`, long hex/base64 blobs); replace with `[REDACTED]`.
- Redact secrets in chat exports before they land in `~/vault/chats/`.
- Graphify: before running, check `.gitignore` / `.env*` patterns; `--exclude` secret-carrying files.
- Verify the vault's git remote is **private** before first push. Refuse if public.
- If a secret is already in the vault, stop, tell the user, help rotate + purge — don't silently delete.
