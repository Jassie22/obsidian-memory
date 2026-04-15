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

If `graphify-out/graph.json` exists, use it **before** reading source files:

1. First layer → `graphify-out/graph.json` / `graphify-out/wiki/index.md`.
2. Second layer → `~/vault/$GROUP/` for decisions & context.
3. Third layer → raw source files, only when editing or when layers 1–2 don't answer the question.

Never re‑read the entire codebase if the graph already has the information.

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
