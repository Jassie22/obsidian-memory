# Vault — Instructions for Claude Code

> This file lives at `~/vault/CLAUDE.md` and is the **global rulebook** for everything Claude Code does inside the vault.

## What this vault is

A centralized knowledge base for all your projects. Persistent memory across Claude Code sessions on every device.

## Project groups

Groups are user-defined. The active list lives in `~/vault/.groups` (one slug per line). Each group has its own folder under the vault root.

Claude Code picks the group for a given repo based on:
1. `group:` field in the repo's own `CLAUDE.md`.
2. Path match: `.../<group>/...` where `<group>` is listed in `.groups`.
3. Prompting the user once and remembering for the session.

Add a new group:

```bash
echo "client-xyz" >> ~/vault/.groups
mkdir -p ~/vault/client-xyz/{architecture,features,data,pipeline,logs}
```

Each group folder should contain: `architecture/`, `features/`, `data/`, `pipeline/`, `logs/`, and an `_MOC.md` map-of-contents.

## Zettelkasten rules

### Note creation
- Wikilinks only for internal notes: `[[note-name]]`.
- YAML frontmatter mandatory on every permanent note.
- Filenames in `kebab-case`.
- One concept per permanent note (atomicity).
- Minimum 2 wikilinks per note.
- Tag notes with their group (`#<group>`) plus topic tags.

### Standard frontmatter

```yaml
---
title: Note Name
group: <group>          # must match a line in ~/vault/.groups, or "shared"
tags: [<group>, topic]
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: active          # active | superseded | archived
---
```

### Folder semantics

| Folder               | Purpose                                              |
|----------------------|------------------------------------------------------|
| `<group>/architecture/` | Long-lived decisions, diagrams, system maps       |
| `<group>/features/`     | Per-feature specs, design notes                   |
| `<group>/data/`         | Schemas, datasets, reference tables               |
| `<group>/pipeline/`     | Build / deploy / CI notes                         |
| `<group>/logs/`         | Dated session logs (one per `/save`)              |
| `permanent/`            | Cross-group atomic notes                          |
| `inbox/`                | Raw captures, unsorted                            |
| `fleeting/`             | Scratch, low-commitment                           |
| `references/`           | External material (papers, docs)                  |
| `chats/code/`           | Imported Claude Code conversations                |
| `chats/web/`            | Imported Claude Web conversations                 |
| `graphify/<group>/`     | Codebase graphs, per repo                         |

### MOC (Map of Contents)

Each `<group>/_MOC.md` is the index page for that group. It auto-grows via `/save`, which prepends new logs under "Recent logs". Architecture and feature notes should be hand-linked under their H2 sections.

## Semantic search

`/recall <query>` (defined in `~/.claude/CLAUDE.md`) runs vector search over every `.md` file in this vault. The index lives at `~/vault/.index.db` and is gitignored — each device rebuilds it on first use.

Keep notes **dense and atomic** so embeddings discriminate well. A single 3KB note on one topic retrieves better than a 20KB note covering five.

## Redaction (non-negotiable)

This vault is a git repo pushed to a remote. Even if the remote is private, assume plaintext exposure.

- No secrets in notes — ever.
- If you see a secret, replace with `[REDACTED]` and tell the user to rotate.
- `.gitignore` ships with the index DB and Obsidian workspace state excluded — don't remove those lines.
