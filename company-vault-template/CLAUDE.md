# Company Vault — Instructions for Claude Code

> This file lives at `~/company-vault/CLAUDE.md` and is the rulebook for everything Claude Code does inside the **shared** vault. All teammates pull the same git remote here.

## What this vault is

Durable, team-wide knowledge for a small group (≤10 people) working on the same projects. It pairs with each teammate's optional **personal** vault (`~/vault`, role: `private`) which holds logs, captures, rules, and half-formed thoughts.

**Only durable, team-relevant content lands here.** Logs, captures, drafts, debug notes, and personal preferences belong in the personal vault. Aim: less than half of all notes end up in this repo.

## What goes here vs. the personal vault

| Note kind | This (company) vault | Personal vault |
|-----------|----------------------|----------------|
| Architecture decisions, ADRs | ✅ | |
| Runbooks (deploy, on-call, onboarding) | ✅ | |
| Gotchas + fixes the team will rediscover | ✅ | |
| API contracts, data schemas, conventions | ✅ | |
| Cross-group permanent atomic notes | ✅ | |
| Daily session logs (`/save`) | | ✅ |
| Captures (`/capture`) — raw thoughts | | ✅ |
| Inbox (awaiting promotion) | | ✅ |
| Personal rules / preferences | | ✅ |
| Half-formed proactive notes (default) | | ✅ |
| `/promote` from inbox | user chooses | default |

When in doubt, **default to the personal vault**. Notes can always be promoted later — pulling them back is harder.

## Project groups

Groups (e.g. `arc`, `truenode`, `cinesynth`) are listed in `.groups`, one slug per line. Each group has a flat folder at the vault root.

```bash
echo "client-xyz" >> ~/company-vault/.groups
mkdir -p ~/company-vault/client-xyz
```

`.groups` is committed and shared — adding a group is a deliberate team-wide change. Personal-only groups stay in `~/vault/.groups`.

## Repo → group routing (auto-detection)

`.repo-map.json` maps git remotes to groups so Claude can detect the active group automatically — no per-repo `CLAUDE.md` drop-in needed for known repos.

```json
{
  "mappings": [
    {"remote": "github.com/yourorg/arc-frontend", "group": "arc"},
    {"remote": "github.com/yourorg/arc-*",        "group": "arc"},
    {"remote": "github.com/yourorg/monorepo",     "group": "shared",
     "path_overrides": [{"path": "services/truenode/**", "group": "truenode"}]}
  ],
  "defaults": {"vault": "company", "prompt_on_miss": true}
}
```

Resolution order (first match wins, see `~/scripts/vault_resolve_group.sh`):

1. Per-repo `./CLAUDE.md` `group:` field (explicit override).
2. `~/company-vault/.repo-map.json` (this file).
3. `~/vault/.repo-map.json` (personal additions / fork-of-fork overrides).
4. Path heuristic (`*/<group>/*` matching any `.groups` slug).
5. Prompt user, cache to personal map.

Adding a new repo to the team's mapping is a one-line PR to this file — every teammate picks it up on their next session-start pull.

## Authoring rules

### Note conventions

- Wikilinks for internal notes: `[[note-name]]`.
- YAML frontmatter mandatory on every permanent note.
- Filenames in `kebab-case`.
- One concept per permanent note (atomicity).
- Minimum 2 wikilinks per note.
- Tag with the group (`#<group>`) plus topic tags (`decision`, `gotcha`, `runbook`, `feature`, `reference`).
- `description:` field — one sentence ≤140 chars, used by the MOC renderer.

### Standard frontmatter

```yaml
---
title: Note Name
description: One-sentence hook used in the MOC.
group: <group>           # must match a slug in .groups
tags: [<group>, decision]
author: Jassie           # who wrote / last meaningfully updated this
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: active           # active | superseded | archived
---
```

`author:` is **mandatory** in the company vault — 5 people writing here means provenance matters. Resolved from `~/.claude/vaults.json` `.author` field (set once at setup time). Don't make up an author; use `~/scripts/vault_author.sh` to resolve.

When a note is meaningfully updated by someone other than the original author, append the new author to a comma-separated list: `author: Jassie, Sam`. Bump `updated:` on every edit.

### Folder semantics (company vault)

| Folder           | Purpose                                                   |
|------------------|-----------------------------------------------------------|
| `<group>/`       | Notes, specs, context — flat, one concept per file        |
| `permanent/`     | Cross-group atomic notes (no single group owner)          |
| `templates/`     | Note templates (skipped by search + MOC regen)            |

Notable absences:

- **No `rules/`** — rules are per-user, they live in the personal vault.
- **No `inbox/`** — captures are personal; promote them into a group folder when they're durable.
- **No root `logs/`** or `<group>/logs/` — logs are personal. Use `/promote` to lift specific durable bits (decisions, gotchas) into proper notes here.

### Dating rule

- `created:` set once on first write. **Never edit it.**
- `updated:` bumped on every edit (content, frontmatter, wikilinks — anything).
- `status: superseded` → also add `superseded-by: [[new-note]]`. Old `created:` untouched.

### Filename collision rule (5-writer-safe)

Notes in `<group>/` and `permanent/` use kebab-case slugs. Two teammates may try to create `arc/auth-decision.md` simultaneously. Resolution:

- Always pull (`git pull --ff-only`) before creating a new note in this vault.
- If a name collision is detected on push, rename to `<slug>-<author-initials>` (`auth-decision-js`) and add a wikilink in the original.
- The session-start hook pulls every 1h on shared vaults to keep this rare.

## MOCs

`~/scripts/vault_rebuild_mocs.py` regenerates `_MOC.md` per group. Same as the personal vault, but `_MOC.md` is **gitignored** here to avoid merge conflicts when 5 people regenerate it concurrently — each device rebuilds locally on every `/save`.

## Semantic search

`/recall` searches every registered vault (company + personal). The index `.index.db` is gitignored and rebuilt per-device.

## Redaction (non-negotiable, stricter here)

This vault is shared with 5 people. Any leaked secret is visible to all of them, immediately.

- No secrets in notes — ever.
- The `vault-secret-guard.sh` PreToolUse hook blocks Write/Edit if a secret pattern is detected. Don't override.
- If a secret is committed: stop, tell the team, rotate the secret, then purge from history with `git filter-repo`. Don't just delete.
- `.gitignore` excludes the index DB, Obsidian workspace state, and `_MOC.md`. Don't remove those lines.
