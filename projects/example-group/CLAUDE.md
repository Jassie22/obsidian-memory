# Project — <GROUP-NAME>

> Drop this file at the root of any repo that belongs to the **<GROUP-NAME>** group.
> Claude Code reads it at session start and routes memory to `~/vault/<group-name>/`.

```yaml
---
group: <group-name>
---
```

Replace `<group-name>` with the slug you used when you ran `./setup.sh --groups ...` (e.g. `work`, `personal`, `research`). The slug must match one of the lines in `~/vault/.groups`.

## What Claude Code does in this repo

1. **Memory routing.** All session logs, decisions, and feature notes live in `~/vault/<group-name>/`.
   - Logs → `~/vault/<group-name>/logs/YYYY-MM-DD-<slug>.md`
   - Architecture & decisions → `~/vault/<group-name>/architecture/`
   - Feature specs → `~/vault/<group-name>/features/`
   - Every note tagged with `#<group-name>`.

2. **Session commands** (defined globally in `~/.claude/CLAUDE.md`):
   - `/resume` — load recent logs + architecture for this group, summarise state.
   - `/save` — write a dated log, commit + push the vault.
   - `/recall <query>` — semantic search across the whole vault.
   - `/promote <note>` — lift a fleeting/inbox note into permanent.

3. **Graphify (codebase graph).** If `graphify-out/graph.json` exists, Claude queries it before reading source files. If it doesn't, Claude will prompt you to set it up (`graphify update .`).

## Query order (3-layer rule)

1. `graphify-out/graph.json` — code structure.
2. `~/vault/<group-name>/` — decisions and history.
3. Raw source — only when 1 and 2 don't answer, or when editing.

Never re-read the whole codebase if the graph or vault already has the answer.
