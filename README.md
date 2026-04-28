# Obsidian Memory for Claude Code

> Persistent long-term memory for Claude Code across every device you work on — and across every teammate, when you opt into the shared **company vault**.
> Adapted from [lucasrosati/claude-code-memory-setup](https://github.com/lucasrosati/claude-code-memory-setup) (MIT).

Portable "source of truth" for a Claude Code memory setup. Clone on any machine, run `./setup.sh`, and every Claude Code session picks up the vault(s), the commands (`/resume`, `/save`, `/recall`, `/promote`), and a semantic search layer.

## The two-vault model (since v0.4)

You can run with **one** vault (personal-only — original behavior) or **two**:

| Vault | Path (default) | Git remote | What lives here |
|-------|----------------|------------|-----------------|
| **Personal** (`role: private`) | `~/vault` | yours alone | Logs (`/save`), captures (`/capture`), personal rules (`~/vault/rules/`), half-formed proactive notes, side-project groups |
| **Company** (`role: shared`) | `~/company-vault` | shared with all teammates (~5 people typical) | Architecture decisions, runbooks, gotchas, cross-group permanent atomic notes, team conventions |

Claude reads `~/.claude/vaults.json` (the registry) at session start to discover which vaults exist. Routing is automatic: logs/captures always personal; decisions/runbooks/gotchas default to company; ambiguous notes default to **personal** (lower-risk default — promote to company later via `/promote --to company` once they prove durable).

Every note carries an `author:` frontmatter field stamped from the registry, so when 5 teammates push to the company vault, "who decided X" is visible inline without needing `git blame`.

If you don't opt into a company vault, behavior collapses to single-vault mode and matches v0.3.

---

## Table of contents

1. [The two-vault model](#the-two-vault-model-since-v04)
2. [What you get](#what-you-get)
3. [Quick start](#quick-start)
4. [Repo layout](#repo-layout)
5. [Groups — your top-level project categories](#groups--your-top-level-project-categories)
6. [Memory commands](#memory-commands)
7. [Semantic search (RAG layer)](#semantic-search-rag-layer)
8. [Graphify (codebase knowledge graph)](#graphify-codebase-knowledge-graph)
9. [Daily workflow](#daily-workflow)
10. [Syncing across devices and teammates](#syncing-across-devices-and-teammates)
11. [Rules system (author → enforce) — always personal](#rules-system-author--enforce--always-personal)
12. [Tuning the rules reminder](#tuning-the-rules-reminder)
13. [For teammates: getting set up](#for-teammates-getting-set-up)
14. [Troubleshooting](#troubleshooting)
15. [Credits](#credits)

---

## What you get

| Piece | Purpose |
|-------|---------|
| `claude-global/CLAUDE.md` | Installed to `~/.claude/CLAUDE.md` — auto-loads in **every** Claude Code session on the machine. Multi-vault aware. |
| `claude-global/settings.json` | Hook wiring — merged into `~/.claude/settings.json` to enable auto-pull, auto-commit, proactive-note reminder, and secret guard. |
| `vault-template/` | Boilerplate for the **personal** Obsidian vault (folder tree, rules, note template, `.gitignore`). |
| `company-vault-template/` | Boilerplate for the **shared** company vault (template + `.repo-map.json` for team-wide auto-routing). |
| `~/.claude/vaults.json` | Registry written by setup — single source of truth for which vaults exist, their roles, and the user's `author` name. |
| `projects/example-group/CLAUDE.md` | Drop into a repo to override auto-routing for a single project. |
| `scripts/vault_author.sh` | Resolves the `author:` field for note frontmatter (env → registry → git config → `$USER`). |
| `scripts/vault_resolve_group.sh` | Resolves `$GROUP` for the current repo (per-repo CLAUDE.md → company `.repo-map.json` → personal `.repo-map.json` → path heuristic → prompt). |
| `scripts/vault_search.py` | Semantic search (fastembed + sqlite-vec) powering `/recall`. Multi-vault: indexes every registered vault. |
| `scripts/vault_rebuild_mocs.py` | Regenerates `_MOC.md` for every group from frontmatter. Skipped in company vault (MOCs are gitignored there). |
| `scripts/vault-sync-pull.sh` | SessionStart hook — `git pull` every registered vault + this repo. Throttled per role: 12h personal, 1h company. |
| `scripts/vault-sync-commit.sh` | PostToolUse hook — auto-commit+push when a tool edits a file under any registered vault. |
| `scripts/vault-note-trigger-reminder.sh` | UserPromptSubmit hook — injects the proactive-note trigger checklist + routing decision every turn. |
| `scripts/vault-secret-guard.sh` | PreToolUse hook — blocks Write/Edit to any registered vault if a secret pattern is detected (stricter rejection on company). |
| `setup.sh` | Idempotent bootstrap. Flags: `--company-vault`, `--no-company-vault`, `--author`. |

---

## Quick start

Prereqs: `git`, `jq`, `python3` (3.9+), [Claude Code](https://docs.anthropic.com), [Obsidian](https://obsidian.md).

**Single-vault (personal only):**
```bash
git clone https://github.com/<you>/obsidian-memory ~/obsidian-memory
cd ~/obsidian-memory
./setup.sh --groups journal,side-projects --author "Your Name" --no-company-vault
```

**Two-vault (personal + shared with teammates):**
```bash
git clone https://github.com/<you>/obsidian-memory ~/obsidian-memory
cd ~/obsidian-memory
./setup.sh \
  --groups journal,side-projects \
  --company-vault ~/company-vault \
  --author "Your Name"
# ...then point ~/company-vault at the shared team git remote (see "Syncing").
```

If you skip flags, the script prompts interactively for groups, the author name, and whether to set up a company vault.

The script:

1. Resolves your author name (env / registry / git config / prompt).
2. Creates `~/vault/` with one folder per personal group, plus `rules/`, `inbox/`, `fleeting/`, `<group>/logs/`.
3. If `--company-vault` (or you said yes to the prompt): creates the company vault with its own `CLAUDE.md`, `.gitignore` (ignores `_MOC.md` to avoid 5-way merge conflicts), `.groups`, and `.repo-map.json` template.
4. Writes `~/.claude/vaults.json` — the registry that drives everything else.
5. Copies `claude-global/CLAUDE.md` → `~/.claude/CLAUDE.md` so every Claude session loads it.
6. Installs scripts to `~/scripts/` and makes them executable.
7. `pip install --user` the extras: `graphifyy`, `claude-conversation-extractor`, `fastembed`, `sqlite-vec` (skip with `--no-pip` / `--no-embed`).
8. Prints next steps.

Skip semantic search on low-RAM devices: `./setup.sh --no-embed`.

---

## Repo layout

```
obsidian-memory/
├── README.md
├── LICENSE                          MIT (inherits from upstream)
├── setup.sh                         one-command bootstrap (multi-vault aware)
│
├── claude-global/
│   ├── CLAUDE.md                    → ~/.claude/CLAUDE.md  (auto-loads everywhere)
│   └── settings.json                hooks (auto-pull, secret-guard, rules reminder, etc.)
│
├── vault-template/                  → ~/vault   (PERSONAL vault)
│   ├── CLAUDE.md                    personal-vault rulebook (logs, captures, rules)
│   ├── .gitignore                   excludes index + Obsidian workspace
│   ├── .groups.template             example personal groups
│   ├── rules/                       behavior rules — always personal, never shared
│   └── templates/default-note.md
│
├── company-vault-template/          → ~/company-vault   (SHARED vault, optional)
│   ├── CLAUDE.md                    company-vault rulebook (decisions, runbooks, gotchas)
│   ├── .gitignore                   excludes index + _MOC.md (avoids 5-way merges)
│   ├── .groups.template             example team-wide project groups
│   ├── .repo-map.json.template      git-remote → group mapping (committed, team-wide)
│   └── templates/default-note.md    includes `author:` field (mandatory here)
│
├── projects/
│   └── example-group/CLAUDE.md      generic per-repo template (edit `group:`)
│
└── scripts/
    ├── vault_author.sh              resolves the `author:` field for frontmatter
    ├── vault_resolve_group.sh       resolves $GROUP for the current repo (multi-vault)
    ├── vault_search.py              semantic search (/recall) across all registered vaults
    └── vault-*.sh                   hooks (sync, secret-guard, reminder, statusline)
```

---

## Groups — your top-level project categories

"Groups" are the top-level buckets your projects fall into — e.g. `arc`, `truenode`, `cinesynth` (team), or `journal`, `side-projects` (personal). Each group gets its own flat subfolder in the relevant vault, its own MOC, its own tag.

Each vault has its own `.groups` list:

- `~/vault/.groups` — your **personal** groups. Local-only.
- `~/company-vault/.groups` — **team-wide** groups. Committed to the shared repo, every teammate inherits the same list.

A group can exist in *both* vaults — e.g. `~/company-vault/arc/` holds team decisions about Arc, while `~/vault/arc/logs/` holds your personal session logs working on Arc.

Add a group:

```bash
# personal-only group
echo "weekend-hack" >> ~/vault/.groups
mkdir -p ~/vault/weekend-hack/logs

# team-wide group (then commit + push so teammates pick it up)
echo "client-xyz" >> ~/company-vault/.groups
mkdir -p ~/company-vault/client-xyz
( cd ~/company-vault && git add .groups client-xyz && git commit -m "groups: add client-xyz" && git push )
```

### Repo → group routing (auto-detection)

Instead of dropping a `CLAUDE.md` into every repo, register the repo's git remote in `~/company-vault/.repo-map.json` (committed, team-wide) or `~/vault/.repo-map.json` (personal, for forks/side-projects). Globs are supported:

```json
{
  "mappings": [
    {"remote": "github.com/yourorg/arc-*",    "group": "arc"},
    {"remote": "github.com/yourorg/truenode", "group": "truenode"}
  ]
}
```

Resolution order (`~/scripts/vault_resolve_group.sh`):
1. `./CLAUDE.md` `group:` field (per-repo override).
2. `~/company-vault/.repo-map.json` (team-wide).
3. `~/vault/.repo-map.json` (personal additions).
4. Path heuristic (`*/<group>/*`).
5. Prompt user, cache to personal `.repo-map.json`.

A new team-wide repo is a one-line PR to `company-vault/.repo-map.json` — every teammate picks it up on their next session-start pull.

---

## Memory commands

Defined in `claude-global/CLAUDE.md` and available in every Claude Code session:

| Command | Effect | Vault touched |
|---------|--------|---------------|
| `/resume` | Load the 3 most recent personal logs + architecture/decisions/runbooks for the current group; summarise state. | reads both, writes none |
| `/save` | Write a dated session log; update MOC; re-index; commit + push. If durable team-relevant insights emerged, also spawn a proactive note into the company vault. | personal log; optional company side-effect |
| `/recall <query>` | Semantic search across **all registered vaults**; results tagged with vault name. | reads all |
| `/capture <text>` | Quick-drop a thought into `~/vault/inbox/` — no ceremony, no dedupe. | personal |
| `/promote <note> [--to personal\|company]` | Lift a note into `permanent/` or a group folder, optionally crossing vaults. | source + destination |

Claude also **proactively writes notes** (background, via subagent) when it encounters decisions, gotchas, external context, or corrections — and dedupes against existing notes using `vault_search.py find-similar --vault <target>` before creating. Routing follows the table in the [two-vault model](#the-two-vault-model-since-v04) section: ambiguous notes default to **personal** (safer; promote later).

Every note carries `author:` in its frontmatter, resolved by `~/scripts/vault_author.sh` (env → registry → `git config` → `$USER`).

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

## Syncing across devices and teammates

Three things travel:

1. **This repo** (`~/obsidian-memory`) — `git pull` to update scripts + rules. Same on every device, every teammate.
2. **Your personal vault** (`~/vault`) — the actual personal memory. Make it a **private** git repo. Yours alone, syncs across *your* devices only.
3. **The company vault** (`~/company-vault`, optional) — shared with all teammates. One git remote, ~5 contributors.

```bash
# Personal vault — yours alone
cd ~/vault
git init && git add -A && git commit -m "initial vault"
git remote add origin <your-private-repo-url>
git push -u origin main

# Company vault — first teammate to set it up
cd ~/company-vault
git init && git add -A && git commit -m "initial company vault"
git remote add origin <team-shared-repo-url>
git push -u origin main
```

`/save` and proactive note-writes auto-commit and push to whichever vault they touched. The session-start hook does `git pull --ff-only` on every registered vault plus this repo, throttled to:

- **once per 12h** for the personal vault and `~/obsidian-memory` (low churn).
- **once per 1h** for the company vault (5 teammates push frequently — staler than 1h risks editing an out-of-date runbook).

### New machine

```bash
git clone <obsidian-memory-url> ~/obsidian-memory
git clone <your-vault-url>      ~/vault
git clone <team-shared-url>     ~/company-vault    # if your team uses one
cd ~/obsidian-memory && ./setup.sh --company-vault ~/company-vault --author "Your Name"
python ~/scripts/vault_search.py index   # rebuilds the local index for all vaults
```

### New teammate joining the company vault

```bash
git clone https://github.com/Jassie22/obsidian-memory ~/obsidian-memory
git clone <team-shared-url>     ~/company-vault
cd ~/obsidian-memory && ./setup.sh \
  --company-vault ~/company-vault \
  --author "Sam Mitchell" \
  --groups journal,side-projects
# (personal-vault groups; team groups come from ~/company-vault/.groups)
```

Then verify routing works on a known team repo:

```bash
cd ~/code/<some-team-repo>
~/scripts/vault_resolve_group.sh    # should print the right group from .repo-map.json
```

---

## Rules system (author → enforce) — always personal

Durable behavior rules for Claude live in `~/vault/rules/` — one file per rule, kebab-case slug, YAML frontmatter. The index at `~/vault/rules.md` is auto-generated.

> **Rules are intentionally per-user.** They never live in the company vault — what one teammate wants Claude to do isn't necessarily what the rest of the team wants. If the team needs a shared *behavioral* convention, encode it in the company vault's per-group `CLAUDE.md` file (read at session start) rather than as a rules entry.

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

Two minutes, two commands. The team's company-vault URL is committed to `claude-global/team.json` in this repo, so `setup.sh` finds it automatically — no path or URL to remember.

**Prerequisite:** your SSH key must be authorised for `arc-simulations` on GitHub. Test with `ssh -T git@github.com` — you should see your username back. If the org enforces SSO, also click "Configure SSO" next to your key under Settings → SSH and GPG keys → "Authorize for arc-simulations".

```bash
git clone https://github.com/Jassie22/obsidian-memory ~/obsidian-memory
cd ~/obsidian-memory && ./setup.sh --author "Your Name"
```

The script:

1. Reads `claude-global/team.json` and asks "Clone the team vault to `~/company-vault` now? [Y/n]" — answer Y. It clones from `git@github.com:arc-simulations/vault.git` for you.
2. Creates your **personal** vault at `~/vault` (you'll be prompted for personal-vault groups — `journal`, `side-projects`, etc. — these are yours alone, not shared).
3. Writes `~/.claude/vaults.json` so every Claude Code session knows about both vaults.
4. Wires hooks into `~/.claude/settings.json`.

Then make your personal vault a private git repo (yours alone — notes here never reach teammates):

```bash
cd ~/vault
git init && git add -A && git commit -m "initial vault"
git remote add origin <your-private-remote-url>   # MUST be private
git push -u origin main
```

Verify routing works on a known team repo:

```bash
cd ~/code/<some-arc-simulations-repo>
~/scripts/vault_resolve_group.sh    # should print the right group from company-vault/.repo-map.json
```

If it falls through to the prompt, the team's `.repo-map.json` doesn't list this remote yet — open a one-line PR against `arc-simulations/vault` to add it.

Restart Claude Code so hooks take effect, then try `/save` once and check `git log` in `~/company-vault` to confirm `author: <Your Name>` shows up correctly.

Other flags if you need them: `--no-company-vault` (skip the team vault entirely), `--vault <path>` (custom personal-vault location, default `~/vault`), `--company-vault <path>` (custom company-vault location, default `~/company-vault`), `--dry-run` to preview, `--scripts-dir <path>` (default `~/scripts`).

### `claude-global/team.json` — for the team setup-owner

One person on the team (typically whoever created the company-vault repo) maintains `claude-global/team.json`:

```json
{
  "company_vault_url": "git@github.com:arc-simulations/vault.git",
  "company_vault_default_path": "~/company-vault",
  "company_vault_default_branch": "main"
}
```

Once committed and pushed to obsidian-memory, every teammate who clones obsidian-memory after that gets one-command onboarding. The clone URL itself isn't a secret (the repo it points at is private — only authorised teammates can actually clone), so it's safe to commit.

### Daily habits when you're sharing a company vault

- **Pull before you write a long note.** The session-start hook handles 1h staleness automatically, but if you're about to write a major decision and you've been heads-down for a while, `cd ~/company-vault && git pull` first.
- **Author attribution is automatic** — your name lands in `author:` from the registry. If you edit someone else's note meaningfully, append your name (`author: Sam, Jassie`).
- **Use `/promote --to company`** to lift personal notes that prove durable. Don't write directly into the company vault unless the note is clearly team-relevant from the start.
- **Don't add personal rules to the company vault.** Rules are per-user. Team behavioral conventions go in the company vault's per-group `CLAUDE.md`.

---

## Troubleshooting

**`/recall` returns nothing.** Run `python ~/scripts/vault_search.py stats` — if `notes_indexed` is 0, run `index`.

**First index build is slow.** Expected — fastembed downloads the model (~1.3GB for BGE-large) on first use. Cached after.

**`~/.claude/CLAUDE.md` not loading.** Restart Claude Code. Still nothing — re-run `./setup.sh`.

**Obsidian doesn't see notes written by scripts.** Make sure Obsidian's vault root is `~/vault` (not a subfolder). Cmd/Ctrl+Q and reopen.

**Secrets accidentally committed.** Rotate the secret immediately. Use `git filter-repo` or BFG to purge history. If it was the company vault, also tell your teammates so they stop pulling that ref until it's purged.

**Notes landing in the wrong vault.** Check `~/.claude/vaults.json` is the registry Claude is reading. If a proactive note went to personal that should have been company, `/promote --to company <slug>` lifts it across. If the routing keeps picking wrong, the trigger words in your message likely lacked the team-relevant signals — say "save this for the team" / "add to runbook" / "team decision" explicitly to bias toward company.

**Routing prompts every session.** The prompt fires when no `.repo-map.json` mapping matches the current repo. Either drop a `CLAUDE.md` with `group:` into the repo, or open a one-line PR adding the remote glob to `~/company-vault/.repo-map.json` (team-wide) or just edit `~/vault/.repo-map.json` (personal-only fix).

**`author:` keeps showing the wrong name.** Check `jq -r '.author' ~/.claude/vaults.json`. Override with `~/obsidian-memory/setup.sh --author "Correct Name"` (idempotent — re-running rewrites just the registry without touching vaults).

**Company-vault `_MOC.md` merge conflict.** Shouldn't happen — `_MOC.md` is gitignored in the company vault for exactly this reason. If you see one, the gitignore was removed. Restore from `company-vault-template/.gitignore` and `git rm --cached **/_MOC.md`.

---

## Credits

- Original concept: [lucasrosati/claude-code-memory-setup](https://github.com/lucasrosati/claude-code-memory-setup) (MIT)
- [Graphify](https://github.com/safishamsi/graphify) — codebase knowledge graphs
- [fastembed](https://github.com/qdrant/fastembed) — ONNX-based local embeddings
- [sqlite-vec](https://github.com/asg017/sqlite-vec) — vector search in SQLite
- [Obsidian](https://obsidian.md), [Claude Code](https://docs.anthropic.com)

MIT — see [`LICENSE`](./LICENSE).
