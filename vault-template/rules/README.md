# Vault rules — how to author

This directory is the authoring surface for Claude's behavior rules. One file per rule. The index at `~/vault/rules.md` is auto-generated from these files — do not hand-edit it.

## Add a rule the easy way

In any Claude Code session:

    /add-rule "resolve relative dates in vault notes"

The slash command scaffolds a new file here with the right frontmatter, prompts for scope, and regenerates the index.

## Add a rule by hand

Create a file named `<kebab-case-slug>.md` with this frontmatter:

```yaml
---
title: Human-readable rule title
scope: global               # see "Scope values" below
priority: normal            # high | normal | low
enforcement: advise         # advise | block (block reserved for future)
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: active              # active | superseded | archived
---
```

Body sections (all three recommended):

- **Rule:** the directive in one paragraph.
- **Why:** the reason — often a past incident or constraint.
- **How to apply:** when/where Claude should apply it.

Then run `~/scripts/rules_rebuild.py` to refresh `~/vault/rules.md`.

## Scope values (closed set)

- `global` — always active, every session, every project.
- `<group-slug>` — active only when the session's group matches (arc, truenode, etc.).
- `vault` — active only when the tool target is inside `~/vault/`.
- `tool:<ToolName>` — active only before that tool fires (e.g. `tool:Write`, `tool:Bash`).

Multiple scopes allowed: `scope: [global, vault]`.

## Config

Runtime config lives at `.config.yml` in this directory. See `.config.example.yml` for defaults and inline comments.
