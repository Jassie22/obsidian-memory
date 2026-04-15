# Obsidian Memory for Claude Code — Arc · TrueNode · CineSynth

> Persistent long‑term memory for Claude Code across every device you work on.
> Adapted from [lucasrosati/claude-code-memory-setup](https://github.com/lucasrosati/claude-code-memory-setup) (MIT) and tailored for my three project groups: **Arc**, **TrueNode**, and **CineSynth**.

This repo is the portable "source of truth" for my Claude Code memory setup. Clone it on any machine, run `./setup.sh`, and every Claude Code session — in any of my three project groups — will automatically pick up the vault, the skills, and the `/resume` · `/save` commands.

---

## Table of Contents

1. [What this repo gives you](#what-this-repo-gives-you)
2. [Quick start (new device)](#quick-start-new-device)
3. [Repo layout](#repo-layout)
4. [How the three project groups work](#how-the-three-project-groups-work)
5. [Auto‑popup across all projects](#auto-popup-across-all-projects)
6. [The vault structure](#the-vault-structure)
7. [Chat import pipeline](#chat-import-pipeline)
8. [Graphify (codebase knowledge graph)](#graphify-codebase-knowledge-graph)
9. [Daily workflow](#daily-workflow)
10. [Syncing memory between devices](#syncing-memory-between-devices)
11. [Troubleshooting](#troubleshooting)
12. [Credits](#credits)

---

## What this repo gives you

| Piece | Purpose |
|-------|---------|
| `claude-global/CLAUDE.md` | Installed to `~/.claude/CLAUDE.md` — loads automatically in **every** Claude Code session on the machine. This is how memory "auto‑popups" in all projects. |
| `vault-template/` | Boilerplate for the Obsidian vault (folder tree, global `CLAUDE.md`, note template). |
| `projects/arc/CLAUDE.md` | Drop into any **Arc** repo to give Claude Code project‑specific context + Graphify nav. |
| `projects/truenode/CLAUDE.md` | Same, for **TrueNode** repos. |
| `projects/cinesynth/CLAUDE.md` | Same, for **CineSynth** repos. |
| `scripts/claude_to_obsidian.py` | Turns Claude chat exports into tagged, wikilinked Obsidian notes. |
| `scripts/sync_claude_obsidian.sh` | Cron‑friendly daily sync of Code + Web chats into the vault. |
| `setup.sh` | One command that wires it all up on a fresh machine. |

---

## Quick start (new device)

Prerequisites: `git`, `python3` (3.9+), [Claude Code](https://docs.anthropic.com), [Obsidian](https://obsidian.md).

```bash
# 1. Clone this repo anywhere you like
git clone https://github.com/jassie22/obsidian-memory.git ~/obsidian-memory
cd ~/obsidian-memory

# 2. Run the bootstrap — it is idempotent and safe to re-run
./setup.sh
```

The script will:

1. Create `~/vault/` with the folder structure for **Arc**, **TrueNode**, **CineSynth**.
2. Copy `vault-template/CLAUDE.md` to `~/vault/CLAUDE.md` (only if missing).
3. Copy `claude-global/CLAUDE.md` to `~/.claude/CLAUDE.md` so every Claude Code session loads it.
4. Copy scripts to `~/scripts/` and make them executable.
5. Install `graphifyy` + `claude-conversation-extractor` via pip (optional, skip with `--no-pip`).
6. Print the next manual steps (open the vault in Obsidian, opt‑in to the cron sync, etc.).

When it finishes, **open Obsidian** and "Open folder as vault" → `~/vault`. Claude Code is now ready.

---

## Repo layout

```
obsidian-memory/
├── README.md                     ← this file
├── LICENSE                       ← MIT (inherits from upstream)
├── setup.sh                      ← one-command bootstrap
│
├── claude-global/
│   └── CLAUDE.md                 ← goes to ~/.claude/CLAUDE.md  (auto-loads everywhere)
│
├── vault-template/
│   ├── CLAUDE.md                 ← goes to ~/vault/CLAUDE.md    (vault-wide rules)
│   └── templates/
│       └── default-note.md       ← Obsidian note template
│
├── projects/
│   ├── arc/CLAUDE.md             ← drop into any Arc repo root
│   ├── truenode/CLAUDE.md        ← drop into any TrueNode repo root
│   └── cinesynth/CLAUDE.md       ← drop into any CineSynth repo root
│
└── scripts/
    ├── claude_to_obsidian.py     ← chat → Obsidian note processor
    └── sync_claude_obsidian.sh   ← daily export + process (cron)
```

---

## How the three project groups work

The vault is **one** Obsidian vault with three top‑level group folders. Each group holds all the individual repos that belong to it.

```
~/vault/
├── arc/
│   ├── _MOC.md                   ← Arc map-of-contents (links to all Arc notes)
│   ├── architecture/
│   ├── features/
│   └── logs/                     ← session logs for any Arc repo
├── truenode/
│   ├── _MOC.md
│   ├── architecture/
│   ├── features/
│   └── logs/
└── cinesynth/
    ├── _MOC.md
    ├── architecture/
    ├── features/
    └── logs/
```

The global `~/.claude/CLAUDE.md` teaches Claude Code to detect which group the current repo belongs to (by matching the repo path/name or by the `group:` field inside the project‑level `CLAUDE.md`), and to:

- read/write logs in `~/vault/<group>/logs/`
- look up decisions in `~/vault/<group>/architecture/`
- link notes with the group tag (`#arc`, `#truenode`, `#cinesynth`)

Add a new repo to a group:

```bash
# from the repo root
cp ~/obsidian-memory/projects/arc/CLAUDE.md ./CLAUDE.md       # or truenode / cinesynth
```

That single file tells Claude Code, for this repo, "you belong to Arc — use `~/vault/arc/` for memory."

---

## Auto‑popup across all projects

Claude Code automatically reads, in order:

1. `~/.claude/CLAUDE.md` — **user‑level, applies to every session on this device**.
2. `<repo>/CLAUDE.md` — **project‑level, applies only inside the repo**.

`setup.sh` installs (1) so memory features light up in every project without any per‑repo work. Per‑repo `CLAUDE.md` files are optional and only needed when you want project‑specific rules (Arc/TrueNode/CineSynth templates cover that).

The global file defines the commands:

| Command | Effect |
|---------|--------|
| `/resume` | Load the 3 most recent logs for the current project group, plus group architecture notes, and summarise state. |
| `/save`   | Write a dated session log to `~/vault/<group>/logs/`, wikilink touched notes, offer to commit. |
| `/promote` | Promote a fleeting/inbox note to `~/vault/permanent/` with frontmatter. |

---

## The vault structure

```
~/vault/
├── CLAUDE.md                     ← global rules (from vault-template/)
├── permanent/                    ← consolidated atomic notes (cross-group)
├── inbox/                        ← raw captures
├── fleeting/                     ← quick scratch
├── templates/
│   └── default-note.md
├── references/                   ← external reference material
├── logs/                         ← cross-project / general logs
│
├── arc/          { architecture/  features/  data/  logs/  _MOC.md }
├── truenode/     { architecture/  features/  data/  logs/  _MOC.md }
├── cinesynth/    { architecture/  features/  data/  logs/  _MOC.md }
│
├── chats/
│   ├── code/                     ← imported Claude Code conversations
│   └── web/                      ← imported Claude Web/App conversations
│
└── graphify/
    ├── arc/                      ← codebase graphs for Arc repos
    ├── truenode/
    └── cinesynth/
```

`setup.sh` creates this tree automatically.

### Note conventions

- Wikilinks `[[like-this]]`, not markdown links, for internal notes.
- Filenames in `kebab-case`.
- YAML frontmatter on every permanent note (template in `vault-template/templates/default-note.md`).
- Tag each note with its group: `#arc`, `#truenode`, or `#cinesynth`.

---

## Chat import pipeline

Turns Claude Code + Claude Web chats into searchable vault notes.

```
~/claude-exports/                 ← staging, outside the vault
├── code/                         ← filled by `claude-extract`
└── web/                          ← drop Web exports here manually (browser extension)
```

### Run once

```bash
pip install claude-conversation-extractor
mkdir -p ~/claude-exports/code ~/claude-exports/web
```

### Automate (cron)

`setup.sh` can install this for you with `--cron`. Manually:

```bash
chmod +x ~/scripts/sync_claude_obsidian.sh
(crontab -l 2>/dev/null; echo "0 22 * * * $HOME/scripts/sync_claude_obsidian.sh") | crontab -
```

The Python processor auto‑detects Arc/TrueNode/CineSynth keywords in each chat and tags the resulting note accordingly, so imported chats show up under the right group in Obsidian's graph view.

Filters in Obsidian graph view:

| Filter | Shows |
|--------|-------|
| `tag:arc` | Everything related to Arc |
| `tag:truenode` | Everything related to TrueNode |
| `tag:cinesynth` | Everything related to CineSynth |
| `tag:chat-import` | Only imported chats |
| `-path:chats` | Hide chats |

---

## Graphify (codebase knowledge graph)

[Graphify](https://github.com/safishamsi/graphify) maps a codebase into a graph Claude Code can query instead of re‑reading every file. `setup.sh` installs it.

In any repo:

```bash
# pick the right group directory
graphify . --obsidian --obsidian-dir ~/vault/graphify/arc/<repo-name>
# …or truenode / cinesynth
```

The `projects/<group>/CLAUDE.md` templates already contain the "3‑layer query rule" (graph → vault → raw files) so Claude Code uses the graph first.

Useful:

```bash
graphify . --update     # only modified files
graphify . --watch      # auto-rebuild on save
graphify hook install   # rebuild on every git commit
```

---

## Daily workflow

```
cd ~/code/arc/some-repo
claude                          # start Claude Code
> /resume                        # pulls recent logs + decisions for Arc
> …do work…
> /save                          # writes a dated log to ~/vault/arc/logs/
git commit -m "…"                # hook rebuilds the Graphify graph
```

Across devices: `git pull` in `~/vault` and `~/obsidian-memory`, and you're caught up.

---

## Syncing memory between devices

Two things need to travel with you:

1. **This repo** (`~/obsidian-memory`) — already on GitHub, `git pull` to update the scripts + `CLAUDE.md` templates.
2. **The vault** (`~/vault`) — your actual memory. Pick one of:
   - Make the vault a **private git repo**: `cd ~/vault && git init && git remote add origin git@github.com:<you>/vault.git`. Commit + push on `/save`.
   - Use **Obsidian Sync** (paid, E2EE).
   - Use **iCloud / Dropbox / Syncthing** pointed at `~/vault`.

The `/save` command in `claude-global/CLAUDE.md` automatically runs `git commit && git push` in the vault if it is a git repo, so memory propagates the moment a session ends.

To re‑bootstrap on a new machine:

```bash
git clone git@github.com:jassie22/obsidian-memory.git ~/obsidian-memory
git clone git@github.com:<you>/vault.git ~/vault       # if you put the vault on git
cd ~/obsidian-memory && ./setup.sh
```

You're back in business.

---

## Troubleshooting

**`/resume` does nothing.** Confirm `~/.claude/CLAUDE.md` exists and mentions the vault path. Re‑run `./setup.sh`.

**Obsidian can't see notes written by scripts.** Make sure Obsidian's vault is pointed at `~/vault` (not a subfolder). Cmd+Q and reopen to force reindex.

**Graphify notes missing from graph view.** Disable "Orphans" and "Existing files only" in the Obsidian graph filters.

**Cron not firing on macOS.** System Settings → Privacy → Full Disk Access → add your terminal.

**Filenames with `()` from Graphify.** Rename in bulk:
```bash
cd ~/vault/graphify/arc/<project>
for f in *"("*; do mv "$f" "$(echo "$f" | sed 's/[()]//g')"; done
```

---

## Credits

- Original concept & documentation: [lucasrosati/claude-code-memory-setup](https://github.com/lucasrosati/claude-code-memory-setup) (MIT)
- [Graphify](https://github.com/safishamsi/graphify) — codebase knowledge graphs
- [Obsidian](https://obsidian.md) — PKM / second brain
- [Claude Code](https://docs.anthropic.com) — Anthropic's coding agent

MIT — see [`LICENSE`](./LICENSE).
