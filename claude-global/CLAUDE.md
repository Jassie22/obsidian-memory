# Global Claude Code Instructions (auto‑loaded)

> This file lives at `~/.claude/CLAUDE.md` and is read at the start of **every** Claude Code session on this machine.
> It makes the Obsidian memory system available in every project without any per‑repo configuration.

## Persistent memory — Obsidian vault

- Vault location: `~/vault`
- Vault rulebook: `~/vault/CLAUDE.md` (read this at session start when memory commands are used)
- Memory is organised into three project groups: **arc**, **truenode**, **cinesynth**.

## Detecting the current project group

At the start of every session, determine the active group:

1. If `./CLAUDE.md` exists in the repo and has a `group:` field (`arc`, `truenode`, or `cinesynth`), use that.
2. Otherwise, if the repo path matches `*/arc/*`, `*/truenode/*`, or `*/cinesynth/*`, use that segment.
3. Otherwise, ask the user once: "Which group is this project — Arc, TrueNode, or CineSynth?" and remember the answer for the rest of the session.
4. If no group can be determined, default to the shared vault root (`~/vault/`) and tag notes with `shared`.

Expose the resolved group as `$GROUP` for the rest of this document.

## Memory commands (available in every project)

### `/resume`
1. Read `~/vault/$GROUP/logs/` and load the 3 most recent log files.
2. Read `~/vault/$GROUP/architecture/decisions.md` if present.
3. Read `~/vault/$GROUP/_MOC.md` if present.
4. Summarise concisely:
   - Current state of the project.
   - Open TODOs / unfinished work.
   - Recent decisions worth remembering.
   - Suggested next step.

### Auto‑commit & push (memory-system files)

After **any** change to `~/vault/` or `~/obsidian-memory/`, immediately:

```bash
git add -A && git commit -m "<type>: <short msg>" && git push
```

This applies to every edit (new log, MOC update, template tweak, setup.sh change, global `CLAUDE.md` edit, etc.) — not just `/save`. The goal is that memory never diverges between devices. If the remote rejects (non‑fast‑forward), pull/rebase and retry; do not force‑push.

For **code repos** (Arc / TrueNode / CineSynth etc.), keep the normal workflow — commit when a logical change is done, push only when the user asks.

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
   …and sections for "Done", "Decisions", "Open items", "Next step", and a wikilink list of every note touched.
2. Update `~/vault/$GROUP/_MOC.md` — add the log to a "Recent logs" list.
3. If the current repo is a git repo, `git add -A && git commit -m "session: <slug>"` (do not push unless the user asks).
4. If `~/vault` is a git repo, `cd ~/vault && git add -A && git commit -m "memory: $GROUP <slug>" && git push` so memory syncs across devices.

### `/promote <note-name>`
- Move a note from `~/vault/inbox/` or `~/vault/fleeting/` into `~/vault/permanent/` or the right group folder.
- Ensure frontmatter + at least 2 wikilinks.

## Context navigation (Graphify) — when inside a code repo

At session start, check whether Graphify is set up for the current repo by testing for `graphify-out/graph.json` (or a matching folder under `~/vault/graphify/$GROUP/<repo-name>/`).

**If the graph exists** — use it **before** reading source files:

1. First layer → `graphify-out/graph.json` / `graphify-out/wiki/index.md`.
2. Second layer → `~/vault/$GROUP/` for decisions & context.
3. Third layer → raw source files, only when editing or when layers 1–2 don't answer the question.

Never re‑read the entire codebase if the graph already has the information.

**If the graph does NOT exist** — tell the user once, early in the session:

> "Graphify isn't set up for this repo yet. Want me to wire it up? It builds a codebase knowledge graph so I can navigate the repo without re‑reading every file."

If they agree, run the setup:

1. Confirm `graphify` is on PATH (`command -v graphify`). If missing, install: `pip install --user --upgrade graphifyy` and remind the user to add `%APPDATA%\Python\Python313\Scripts` to PATH on Windows.
2. Build the graph (writes `graphify-out/graph.json` + `GRAPH_REPORT.md` in the repo):
   ```bash
   graphify update .
   ```
3. Add `graphify-out/` to `.gitignore` — it's build output, not source.
4. Offer to install the git hook for auto‑rebuild on commit: `graphify hook install`.
5. Offer `graphify watch .` in a background terminal during active dev.
6. To mirror the graph into Obsidian for cross‑repo browsing, symlink (or copy on each rebuild): `~/vault/graphify/$GROUP/<repo-name>/` → `<repo>/graphify-out/`.

After setup, proceed with the 3‑layer query rule above.

## Writing rules inside the vault

- Wikilinks `[[like-this]]`, never markdown links for internal notes.
- Kebab‑case filenames.
- YAML frontmatter on every permanent note.
- Always tag with the group (`#arc` / `#truenode` / `#cinesynth`).
- Minimum two wikilinks per permanent note.

## Safety

- Never delete vault notes without asking.
- Never force‑push the vault repo.
- Never run destructive git commands in the current repo without confirmation.

### Credential hygiene (vault + logs + graph)

The vault, session logs, chat imports, and Graphify output are all plaintext and may be pushed to a remote git repo — treat them as public.

- **Never** write API keys, tokens, passwords, private URLs, `.env` contents, connection strings, cookies, session IDs, JWTs, or any secret the user pastes into a chat to a vault note, log, MOC, or any file under `~/vault/`.
- When `/save` runs, scan the draft log for anything matching secret patterns (`sk-…`, `ghp_…`, `AKIA…`, `Bearer …`, `password=`, `-----BEGIN …PRIVATE KEY-----`, long hex/base64 blobs) and redact with `[REDACTED]` before writing.
- If a chat export (`~/claude-exports/`) contains secrets, redact them in the resulting Obsidian note — store the fact that a secret existed, not the secret itself.
- Graphify: before running, check `.gitignore` / `.env*` patterns and pass `--exclude` for any file that may contain secrets. Never commit `graphify-out/` blobs that include resolved env values.
- If the vault is a git repo, verify it is **private** before the first push. Refuse to `git push` the vault if the remote is public.
- If a secret is discovered already in the vault, stop, tell the user, and help rotate + purge (git filter-repo / BFG) — don't silently delete.
