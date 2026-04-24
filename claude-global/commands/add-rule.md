---
description: Scaffold a new rule file in ~/vault/rules/ and regenerate the index.
argument-hint: <one-line rule title>
---

# /add-rule

Scaffold a new behavior rule in `~/vault/rules/` and regenerate `~/vault/rules.md`.

**Argument:** The rule title as a one-line description (e.g. `/add-rule resolve relative dates in vault notes`).

## Steps

1. Take the user's argument as `$TITLE`. If the argument is empty, ask the user for the title and wait for their reply.
2. Compute `$SLUG` by lowercasing `$TITLE`, replacing any run of non-alphanumeric characters with `-`, stripping leading/trailing `-`, and truncating to 60 chars.
3. Check `~/vault/rules/$SLUG.md` does not already exist. If it does, append a `-N` suffix where N is the smallest integer that makes the path free.
4. Ask the user for the **scope** — present the closed set and wait for their choice:
   - `global` — applies everywhere
   - `<group>` — only when active group matches (list groups from `~/vault/.groups`)
   - `vault` — only when writing to `~/vault/`
   - `tool:<Name>` — only before a specific tool fires (ask for tool name)
   - Multiple scopes — comma-separated list
5. Ask for **priority** (`high` / `normal` / `low`, default `normal`).
6. Write `~/vault/rules/$SLUG.md` with this frontmatter:
   ```yaml
   ---
   title: $TITLE
   scope: <from step 4>
   priority: <from step 5>
   enforcement: advise
   created: <today YYYY-MM-DD>
   updated: <today YYYY-MM-DD>
   status: active
   ---

   **Rule:** <placeholder — user will fill in>

   **Why:** <placeholder — user will fill in>

   **How to apply:** <placeholder — user will fill in>
   ```
7. Run `~/scripts/rules_rebuild.py` to refresh the index.
8. Show the user the file contents and ask them to fill in the Rule/Why/How-to-apply sections. Stay conversational — don't write the body for them unless they give you the content.
9. When the user provides content, write it into the file via Edit, then run `~/scripts/rules_rebuild.py` once more.
10. Auto-commit + push the vault per the global rule.

## Notes

- Do NOT invent the Rule/Why/How-to-apply content. The user owns rule wording.
- If the user's argument clearly contains the rule wording (e.g. `/add-rule always commit after editing settings.json because the hook auto-reloads`), use that as the **Rule:** line draft and confirm with the user before committing.
- After scaffolding, remind the user they can edit `~/vault/rules/.config.yml` to change the reminder interval.
