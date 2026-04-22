---
title: Resolve relative dates in vault notes
scope: vault
priority: high
enforcement: advise
created: 2026-04-20
updated: 2026-04-21
status: active
---

**Rule:** When the user references a weekday ("Friday", "Thursday") or a relative term ("tomorrow", "next week") in content destined for the vault, convert it to an absolute `YYYY-MM-DD` date and write BOTH the weekday and the resolved date (e.g. "Friday 2026-04-24"). Never leave a bare weekday in a vault note.

**Why:** Vault notes get read weeks or months later — a bare weekday becomes ambiguous or misleading once the week has passed, defeating the durability of the memory system. User explicitly requested this rule on 2026-04-20.

**How to apply:** Any Write/Edit into `~/vault/` (inbox, logs, permanent, group folders) that contains a user-provided weekday or relative date. Today's date is available in the session context; use `date -d "next friday"` to resolve if uncertain. Apply in the body and in any relevant frontmatter field (`due`, `scheduled`). Does not apply to chat/ephemeral replies — only written vault content.
