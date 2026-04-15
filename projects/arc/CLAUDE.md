# Project — Arc

> Drop this file at the root of any repo that belongs to the **Arc** group.
> Claude Code will read it automatically and route memory to `~/vault/arc/`.

```yaml
group: arc
vault: ~/vault
vault_group_path: ~/vault/arc
tag: arc
```

## What Claude Code should do in this repo

1. **Memory routing.** All session logs, decisions, and feature notes live in `~/vault/arc/`.
   - Logs → `~/vault/arc/logs/YYYY-MM-DD-<slug>.md`
   - Architecture & decisions → `~/vault/arc/architecture/`
   - Feature specs → `~/vault/arc/features/`
   - Tag every note with `#arc`.

2. **Session commands.** Follow the definitions in `~/.claude/CLAUDE.md` and `~/vault/CLAUDE.md`:
   - `/resume` → load Arc logs + architecture, summarise current state.
   - `/save`   → write a log to `~/vault/arc/logs/`, commit vault if it's a git repo.

## Context Navigation (Graphify)

Use the 3‑layer query rule, in order:

1. **First** — query `graphify-out/graph.json` or `graphify-out/wiki/index.md` for code structure and connections.
2. **Second** — query `~/vault/arc/` for decisions, progress, and project context.
3. **Third** — only read raw source files when editing, or when layers 1 and 2 don't have the answer.

### When to rebuild the graph
- After structural changes (new modules, major refactors).
- Command: `graphify . --update` (processes only modified files).
- The graph is persistent — do **not** rebuild every session.

### Do NOT
- Don't manually modify files inside `graphify-out/`.
- Don't re‑read the entire codebase if the graph already has the information.
- Don't write memory to any path other than `~/vault/arc/`.

## Regenerating Graphify notes for this repo

```bash
graphify . --obsidian --obsidian-dir ~/vault/graphify/arc/$(basename "$PWD")
```
