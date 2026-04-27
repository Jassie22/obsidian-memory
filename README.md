# Obsidian Memory for Claude Code

> Persistent long-term memory for Claude Code across every device you work on.
> Adapted from [lucasrosati/claude-code-memory-setup](https://github.com/lucasrosati/claude-code-memory-setup) (MIT).

Portable "source of truth" for a Claude Code memory setup. Clone on any machine, run `./setup.sh`, and every Claude Code session picks up the vault, the commands (`/resume`, `/save`, `/recall`, `/promote`), and a semantic search layer.

---

## Table of contents

1. [What you get](#what-you-get)
2. [Quick start](#quick-start)
3. [Repo layout](#repo-layout)
4. [Groups — your top-level project categories](#groups--your-top-level-project-categories)
5. [Memory commands](#memory-commands)
6. [Semantic search (RAG layer)](#semantic-search-rag-layer)
7. [Graphify (codebase knowledge graph)](#graphify-codebase-knowledge-graph)
8. [Daily workflow](#daily-workflow)
9. [Syncing across devices](#syncing-across-devices)
10. [Rules system (author → enforce)](#rules-system-author--enforce)
11. [Tuning the rules reminder](#tuning-the-rules-reminder)
12. [For teammates: getting set up](#for-teammates-getting-set-up)
13. [Troubleshooting](#troubleshooting)
14. [Credits](#credits)

---

## What you get

| Piece | Purpose |
|-------|---------|
| `claude-global/CLAUDE.md` | Installed to `~/.claude/CLAUDE.md` — auto-loads in **every** Claude Code session on the machine. |
| `claude-global/settings.json` | Hook wiring — merged into `~/.claude/settings.json` to enable auto-pull, auto-commit, proactive-note reminder, and secret guard. |
| `vault-template/` | Boilerplate for the Obsidian vault (folder tree, rules, note template, `.gitignore`). |
| `projects/example-group/CLAUDE.md` | Drop into any repo to route memory into the right group. |
| `scripts/vault_search.py` | Semantic search (fastembed + sqlite-vec) powering `/recall`. |
| `scripts/vault_rebuild_mocs.py` | Regenerates `_MOC.md` for every group from frontmatter. |
| `scripts/vault-sync-pull.sh` | SessionStart hook — `git pull` vault + repo, 12h-throttled. |
| `scripts/vault-sync-commit.sh` | PostToolUse hook — auto-commit+push when a tool edits a file under `~/vault/`. |
| `scripts/vault-note-trigger-reminder.sh` | UserPromptSubmit hook — injects the proactive-note trigger checklist every turn. |
| `scripts/vault-secret-guard.sh` | PreToolUse hook — blocks Write/Edit to the vault if a secret pattern is detected. |
| `setup.sh` | Idempotent bootstrap for a fresh machine. |

---

## Quick start

Prereqs: `git`, `python3` (3.9+), [Claude Code](https://docs.anthropic.com), [Obsidian](https://obsidian.md).

```bash
git clone https://github.com/<you>/obsidian-memory ~/obsidian-memory
cd ~/obsidian-memory
./setup.sh --groups work,personal,research
```

The script:

1. Creates `~/vault/` with one folder per group.
2. Writes `~/vault/.groups` (plain text — the source of truth for groups).
3. Copies `vault-template/CLAUDE.md` → `~/vault/CLAUDE.md`.
4. Copies `claude-global/CLAUDE.md` → `~/.claude/CLAUDE.md` so every Claude session loads it.
5. Installs scripts to `~/scripts/` and makes them executable.
6. `pip install --user` the extras: `graphifyy`, `claude-conversation-extractor`, `fastembed`, `sqlite-vec` (skip with `--no-pip` / `--no-embed`).
7. Prints next steps.

Skip semantic search on low-RAM devices: `./setup.sh --no-embed`.

---

## Repo layout

```
obsidian-memory/
├── README.md
├── LICENSE                          MIT (inherits from upstream)
├── setup.sh                         one-command bootstrap
│
├── claude-global/
│   └── CLAUDE.md                    → ~/.claude/CLAUDE.md  (auto-loads everywhere)
│
├── vault-template/
│   ├── CLAUDE.md                    → ~/vault/CLAUDE.md    (vault-wide rules)
│   ├── .gitignore                   → ~/vault/.gitignore   (excludes index + workspace)
│   └── templates/
│       └── default-note.md          note template
│
├── projects/
│   └── example-group/CLAUDE.md      generic per-repo template (edit `group:`)
│
└── scripts/
    ├── vault_search.py              semantic search (/recall)
```

---

## Groups — your top-level project categories

"Groups" are the top-level buckets your projects fall into — e.g. `work`, `personal`, `research`, `client-acme`. Each group gets its own subfolder in the vault, its own MOC, its own tag.

The canonical list lives in `~/vault/.groups` (one slug per line). Add a group later:

```bash
echo "client-xyz" >> ~/vault/.groups
mkdir -p ~/vault/client-xyz/{architecture,features,data,pipeline,logs}
```

Tell Claude which group a repo belongs to by dropping `projects/example-group/CLAUDE.md` in the repo root and editing `group: <slug>`.

---

## Memory commands

Defined in `claude-global/CLAUDE.md` and available in every Claude Code session:

| Command | Effect |
|---------|--------|
| `/resume` | Load the 3 most recent logs + architecture for the current group; summarise state. |
| `/save` | Write a dated session log; update MOC; re-index; commit + push the vault. |
| `/recall <query>` | Semantic search across the whole vault; read top-3 hits. |
| `/capture <text>` | Quick-drop a thought into `inbox/` — user-triggered, no ceremony, no dedupe. |
| `/promote <note>` | Lift an inbox/fleeting note into `permanent/` with proper frontmatter. |

Claude also **proactively writes notes** (background, via subagent) when it encounters decisions, gotchas, external context, or corrections — and dedupes against existing notes using `vault_search.py find-similar` before creating.

> **You don't have to literally type these as slash commands.** Only `/add-rule` and `/clean-empty` are wired as Claude Code slash commands (under `claude-global/commands/`). The five above are *procedures* documented in `claude-global/CLAUDE.md` (which setup.sh symlinks/copies to `~/.claude/CLAUDE.md`, auto-loaded every session). So **"can you check the vault for what we decided about X"** runs the same code path as `/recall X`, and **"log this session and push"** = `/save`. Use whichever phrasing feels natural — Claude reads the rules and follows them.

---

## Semantic search (RAG layer)

The vault is indexed into `~/vault/.index.db` (sqlite-vec, gitignored). `/recall` runs vector search over every `.md` in the vault.

Stack:
- **fastembed** (onnxruntime under the hood — no PyTorch)
- **BGE-large-en-v1.5** (1024-dim, ~1.3GB, top-tier English retrieval)
- **sqlite-vec** for storage + ANN search

Override model on low-RAM devices:

```bash
RECALL_MODEL=BAAI/bge-small-en-v1.5 python ~/scripts/vault_search.py index
```

Commands:

```bash
python ~/scripts/vault_search.py index                   # incremental upsert
python ~/scripts/vault_search.py search "auth decisions" # top-5 matches
python ~/scripts/vault_search.py find-similar "title"    # dedupe helper
python ~/scripts/vault_search.py stats                   # index health
```

The indexer is **incremental** — only re-embeds notes whose content hash changed. Deletes stale rows for removed notes. Safe to run on every `/save`.

---

## Graphify (codebase knowledge graph)

[Graphify](https://github.com/safishamsi/graphify) maps a codebase into a graph so Claude can navigate structure without reading every file. Installed by `setup.sh`.

In any repo:

```bash
graphify update .
```

This writes `graphify-out/graph.json` + `GRAPH_REPORT.md`. Add `graphify-out/` to your repo's `.gitignore` — it's build output.

Useful:

```bash
graphify update .       # incremental
graphify watch .        # auto-rebuild on save
graphify hook install   # rebuild on every git commit
```

Claude Code checks for `graphify-out/graph.json` at session start. If missing, it prompts you to set it up; if present, it queries the graph before touching source files.

---

## Daily workflow

```
cd ~/code/<some-repo>
claude
> /resume                                pulls recent logs + decisions for this group
> …do work…
> /recall <anything you half-remember>   semantic hits across the whole vault
> /save                                  writes a dated log, re-indexes, pushes vault
git commit -m "…"                         Graphify hook rebuilds the code graph
```

---

## Syncing across devices

Two things travel with you:

1. **This repo** (`~/obsidian-memory`) — `git pull` to update scripts + rules.
2. **Your vault** (`~/vault`) — the actual memory. Make it a **private** git repo.

```bash
cd ~/vault
git init && git add -A && git commit -m "initial vault"
git remote add origin <your-private-repo-url>
git push -u origin main
```

`/save` auto-commits and pushes. The global `CLAUDE.md` has a session-start hook that does `git pull --ff-only` on both repos, throttled to once per 12h.

New machine:

```bash
git clone <obsidian-memory-url> ~/obsidian-memory
git clone <your-vault-url>      ~/vault
cd ~/obsidian-memory && ./setup.sh
python ~/scripts/vault_search.py index   # rebuilds the index locally
```

---

## Rules system (author → enforce)

Durable behavior rules for Claude live in `~/vault/rules/` — one file per rule, kebab-case slug, YAML frontmatter. The index at `~/vault/rules.md` is auto-generated.

### Author a rule

Easiest: in any Claude Code session, run

    /add-rule "resolve relative dates in vault notes"

The slash command scaffolds the file, prompts for scope + priority, and regenerates the index. Alternatively, create `~/vault/rules/<slug>.md` by hand — see `~/vault/rules/README.md` for the format.

### Scope values (closed set)

| scope | active when |
|-------|-------------|
| `global` | every session, every project |
| `<group>` | active group in `~/vault/.groups` matches |
| `vault` | tool target is inside `~/vault/` |
| `tool:<Name>` | before that specific tool fires (e.g. `tool:Write`, `tool:Bash`) |

Multiple scopes: `scope: [global, vault]`.

### Enforcement mechanisms

- **UserPromptSubmit hook** — `rules-reminder.sh` injects scope-matched rules every N turns.
- **PreToolUse hook** — `rules-preguard.sh` injects rules matching `vault` or `tool:<Name>` before Write/Edit/Bash.
- **Statusline** — `rules-statusline.sh` renders `📋 N rules · next reminder in K turns` persistently.

---

## Tuning the rules reminder

Config lives in `~/vault/rules/.config.yml` (not in this repo — so teammates tune independently). Change one line:

```yaml
reminder_interval: 10    # change to 5 for more reliable, more expensive
```

Tradeoff: lower N = Claude forgets less + higher token cost per conversation. Higher N = cheaper + more drift between reminders. Start at 10, adjust as needed.

Other fields:

- `statusline_enabled: true|false` — toggle the `📋 …` statusline.
- `preguard_enabled: true|false` — toggle scope-matched injection before Write/Edit/Bash.
- `blocked_scopes: [work, research]` — silence whole scopes temporarily without deleting rule files.

Hooks re-read the config on every fire. No restart needed.

---

## For teammates: getting set up

Three minutes, five steps:

1. **Clone this repo:**
   ```bash
   git clone https://github.com/Jassie22/obsidian-memory.git
   cd obsidian-memory
   ```

2. **Run setup:**
   ```bash
   ./setup.sh --groups work,personal     # or --groups <yours>
   ```
   Flags: `--scripts-dir <path>` for a custom scripts location (default `~/scripts`), `--dry-run` to preview, `--vault <path>` for a custom vault location (default `~/vault`).

3. **Make your vault a private git repo** (each teammate has their own vault — notes are personal):
   ```bash
   cd ~/vault
   git init && git add -A && git commit -m "initial vault"
   git remote add origin <your-private-remote-url>   # MUST be private
   git push -u origin main
   ```

4. **Edit `~/vault/rules/.config.yml`** if you want a different reminder cadence (default 10).

5. **Restart Claude Code** — hooks take effect only on next session.

That's it. `/resume`, `/save`, `/recall`, `/capture`, `/promote`, `/add-rule` are all available in every project.

---

## Troubleshooting

**`/recall` returns nothing.** Run `python ~/scripts/vault_search.py stats` — if `notes_indexed` is 0, run `index`.

**First index build is slow.** Expected — fastembed downloads the model (~1.3GB for BGE-large) on first use. Cached after.

**`~/.claude/CLAUDE.md` not loading.** Restart Claude Code. Still nothing — re-run `./setup.sh`.

**Obsidian doesn't see notes written by scripts.** Make sure Obsidian's vault root is `~/vault` (not a subfolder). Cmd/Ctrl+Q and reopen.

**Secrets accidentally committed.** Rotate the secret immediately. Use `git filter-repo` or BFG to purge history.

---

## Credits

- Original concept: [lucasrosati/claude-code-memory-setup](https://github.com/lucasrosati/claude-code-memory-setup) (MIT)
- [Graphify](https://github.com/safishamsi/graphify) — codebase knowledge graphs
- [fastembed](https://github.com/qdrant/fastembed) — ONNX-based local embeddings
- [sqlite-vec](https://github.com/asg017/sqlite-vec) — vector search in SQLite
- [Obsidian](https://obsidian.md), [Claude Code](https://docs.anthropic.com)

MIT — see [`LICENSE`](./LICENSE).
