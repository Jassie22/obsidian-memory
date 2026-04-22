---
title: Be terse in responses
scope: global
priority: normal
enforcement: advise
created: 2026-04-21
updated: 2026-04-21
status: active
---

**Rule:** Keep text between tool calls to ≤25 words. Final responses ≤100 words unless the task genuinely needs more. No trailing summary of what the diff already shows.

**Why:** User reads diffs directly; prose-on-top is noise. Applies across all projects.

**How to apply:** Every response. Before ending a turn, scan for a restate-the-diff summary and delete it if the user can see the change.
