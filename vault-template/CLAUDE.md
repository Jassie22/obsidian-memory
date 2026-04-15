# Vault — Instructions for Claude Code

> This file lives at `~/vault/CLAUDE.md` and is the **global rulebook** for everything Claude Code does inside the vault.

## What this vault is

A single centralized knowledge base for all my projects. Persistent memory across Claude Code sessions on every device.

## Project groups

All projects fall into exactly one of three groups. Claude Code picks the group based on the repo's own `CLAUDE.md` (`group:` field) or the path.

| Group      | Vault folder        | Tag          | Typical stack (adjust as you learn it) |
|------------|---------------------|--------------|----------------------------------------|
| Arc        | `arc/`              | `#arc`       | _fill in as projects grow_             |
| TrueNode   | `truenode/`         | `#truenode`  | _fill in as projects grow_             |
| CineSynth  | `cinesynth/`        | `#cinesynth` | _fill in as projects grow_             |

Each group folder contains: `architecture/`, `features/`, `data/`, `pipeline/`, `logs/`, and an `_MOC.md` map‑of‑contents.

## Zettelkasten rules

### Note creation
- Wikilinks only for internal notes: `[[note-name]]`, never markdown links.
- YAML frontmatter is mandatory on every permanent note.
- Filenames in `kebab-case`: `auth-flow.md`, not `Auth Flow.md`.
- One concept per permanent note (atomicity).
- Minimum 2 wikilinks per note (dense linking).
- Always tag notes with the group they belong to (`#arc` / `#truenode` / `#cinesynth`), plus any topic tags.

### Standard frontmatter

```yaml
---
title: Note Name
group: arc            # arc | truenode | cinesynth | shared
tags: [arc, topic]
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: active
type: permanent       # permanent | fleeting | log | chat
---
```

### Never do
- Don't delete notes without asking.
- Don't use markdown links for internal notes (use wikilinks).
- Don't create notes without frontmatter.
- Don't change the group folder structure without documenting it in `architecture/`.

## Session commands

### `/resume`
1. Detect the current project group (from repo `CLAUDE.md` `group:` field, or ask).
2. Read the 3 most recent session logs in `~/vault/<group>/logs/`.
3. Read `~/vault/<group>/architecture/decisions.md` if it exists.
4. Read `~/vault/<group>/_MOC.md` to orient on structure.
5. Summarise: current state, open TODOs, last commit, next step.

### `/save`
1. Write `~/vault/<group>/logs/YYYY-MM-DD-<slug>.md` with:
   - What was done (bullets)
   - Decisions made (bullets, link to or create notes in `architecture/`)
   - Open items / next steps
   - Wikilinks to every note touched or created
2. Add the log filename to `~/vault/<group>/_MOC.md` under a "Recent logs" section.
3. If the current repo is a git repo, `git add . && git commit -m "session: <slug>"`.
4. If `~/vault` is a git repo, `cd ~/vault && git add . && git commit -m "memory: <slug>" && git push`.

### `/promote <note-name>`
Move a note from `inbox/` or `fleeting/` into `permanent/` (or the right group folder), add full frontmatter, and ensure it has at least 2 wikilinks.

## Chat import pipeline
- `chats/code/` → imported Claude Code conversations.
- `chats/web/` → imported Claude Web/App conversations.
- Every imported chat has `type: chat` + `chat-import` tag.
- The importer auto‑tags with `#arc` / `#truenode` / `#cinesynth` when matching keywords appear.

Graph view filters:
- `tag:chat-import` → chats only
- `-path:chats` → hide chats
- `tag:arc` / `tag:truenode` / `tag:cinesynth` → one group at a time

## Graphify (codebase maps)
- `graphify/arc/<repo>/` → graph for one Arc repo.
- `graphify/truenode/<repo>/` → same for TrueNode.
- `graphify/cinesynth/<repo>/` → same for CineSynth.
- Graph notes are auto‑generated — never edit them by hand.

Graph view:
- `path:graphify` → only code nodes
- `-path:graphify` → only human‑written notes
