# AI Sessions for the Arc Team — Design Spec

**Date:** 2026-04-22
**Status:** Draft — awaiting user review
**Author:** Jas (with Claude)
**Target delivery:** 2026-04-24 (Fri)
**Version:** 0.2

> This document is expected to change. Bump **Version** and append to the `## Revision log` at the bottom on every update. Every section that contains the cookbook content is dated inline so it's obvious when an item was last refreshed.

---

## Problem

Henry (Arc CTO) asked Jas to run two short sessions on "how to use AI" for the Arc team on 2026-04-24. One for software engineering, one for general business use. Jas will present both and hand over this repo as the engineering leave-behind.

Three concrete constraints shape the work:

- **Jas is not a demo presenter.** Format is a discussion / structured walk-through, not a live demo.
- **The leave-behind must do the heavy lifting.** Spoken script is thin; the handout carries the real content and survives past the session.
- **The content will date.** Tools, skills, MCPs, and Claude features evolve weekly. Everything is dated and versioned so it's obvious when it last got a refresh.

## Goals

### Engineering session
- **Primary:** leverage. The Arc engineers are mixed baseline (some power users, some copy-pasting into chat.ai) — everyone leaves with at least two new techniques they'll try next week.
- **Outcome artifact:** this repo (`obsidian-memory`), extended with `sessions/engineering/` — they clone, run `./setup.sh`, have a working Claude Code setup with hooks, memory, `/recall`, and a starter skill set.

### Business session
- **Primary:** leverage + evaluation. Mike, Henry (CEO-mode), and non-engineering operators are intermediate (prompts and chats, no structure). They leave knowing what Claude Projects ("Claude Design"), scheduled jobs, and a handful of MCPs can do, and with a shortlist of where these plug into Arc workflows.
- **Outcome artifact:** a printable cookbook + one or two pre-built Claude Projects shared to their claude.ai accounts.

Out of scope for v0.1: training on API-level usage, building MCPs from scratch, agent architecture deep-dives.

## Audience

| Session | Audience | Baseline | Notes |
|---|---|---|---|
| Engineering | Arc engineers (small, technical) | Mixed — some daily Claude Code / Cursor, some still in web chat | Jas is peer, not lecturer |
| Business | Mike (CEO), Henry (CTO-in-CEO-mode), non-eng operators | Intermediate — already uses ChatGPT/Claude casually, no structured workflows | Lighter on jargon |

## Format

- **Discussion / walk-through**, not a live demo. Jas reads the cookbook at the audience while they follow along on the handout.
- **No slide deck as a separate artifact** — the handout is the deck. If projected, it's the handout scrolled on a screen.
- **Duration: 20–25 min each**, 30 min hard cap. Short and takeaway-dense.
- **Scope: Claude-primary, alternatives named in passing** (e.g. Cursor for inline fixes, Perplexity as a research alternative). Not tool-agnostic.

## Deliverables

| # | Deliverable | Path | For |
|---|---|---|---|
| D1 | Engineering cookbook | `sessions/engineering/2026-04-22-cookbook.md` | Engineering handout |
| D2 | Engineering starter guide | `sessions/engineering/README.md` | "Start here when you clone this repo" |
| D3 | Business cookbook | `sessions/business/2026-04-22-cookbook.md` | Business handout (printable PDF source) |
| D4 | Business Claude Project exports | `sessions/business/projects/*.md` | System-prompt + knowledge-file starters they can paste into claude.ai → Projects |
| D5 | Link pack | `sessions/shared/2026-04-22-links.md` | Shared bookmarks: docs, MCPs, tutorials, follow-up reading |
| D6 | One-pager cheatsheet (each session) | `sessions/<audience>/2026-04-22-cheatsheet.md` | Fridge-magnet version — single page, most common commands / workflows |

Every artifact filename carries `YYYY-MM-DD`. Every artifact has frontmatter with `created:`, `updated:`, `version:`. When Jas revises, the date + version move forward; old versions stay in git.

## Engineering session — content outline

**Duration target:** 25 min. ~3 min per use case + 4 min intro/outro.

**Structure:** one-line framing ("here's how I stopped copy-pasting into chat.ai") → 8 use cases → handout walk-through → Q&A.

### Use cases (v0.2 — 2026-04-22)

**Headline item (the repo itself):**

1. **Give Claude a brain that lasts longer than one session** — this is the repo they're being handed. Covers the full Obsidian-memory setup:
   - **`/recall`** — semantic search across a vault of past notes ("what did we decide about X three months ago"). Claude reads the top hits before answering.
   - **`/save`** — end-of-session log with decisions + open items, dropped into the group's `logs/`.
   - **`/capture`** — quick free-form thought drop into `inbox/` without ceremony.
   - **`/resume`** — opens a new session with the last 3 logs + decisions loaded.
   - **Proactive note-writer** — a hook that reminds Claude to capture durable context (decisions, gotchas, corrections) every turn, so knowledge doesn't evaporate between chats.
   - **Auto-commit + auto-pull** across devices — the vault stays in sync without thinking about it.
   - **Secret guard** — a `PreToolUse` hook that blocks any Write/Edit into `~/vault/` if a secret pattern is detected, so plaintext memory stays safe.
   - **Groups** — top-level project categories (one per client or concern), so "work" and "personal" memory don't bleed into each other.
   - **One-command setup** — `git clone + ./setup.sh` and a teammate is running the same system.
   - Why this matters for the Arc team: every engineer has their own "what did Charlie decide about the hero" rolodex right now, in Slack or memory. This externalises it.

**Other use cases:**

2. **"Run it later / overnight"** — schedule a plan with Claude. Out of credits? Big refactor? Run it at 2 a.m. Tools: `/schedule`, `CronCreate`, `/loop`. *Jas's example: the scenario Henry mentioned — "I want to kick off a plan but save my credits for later."*
3. **Claude Code, not web chat** — the repo-native workflow. Per-repo `CLAUDE.md` pins context. Tool: Claude Code + `CLAUDE.md`.
4. **Figma → code** — paste a Figma URL, get a scaffold that respects the actual design tokens. Tool: `plugin:figma` MCP (`get_design_context`, `get_screenshot`). *Relevant to Arc's current corp-site rebuild with Charlie.*
5. **GitHub-native PR work** — review, comment, triage without leaving the terminal. Tool: `plugin:github` MCP.
6. **Subagents for parallel work** — dispatch `Explore` for a wide codebase search, `Plan` for a design pass, multiple at once. Tool: Agent tool + parallel dispatch.
7. **Skills for repetitive patterns** — write once, Claude runs it on trigger. Live example: `superpowers`, `simplify`, custom skills per team. Tool: skill-creator + user skills dir.
8. **Cursor for inline fixes** — when a full Claude Code session is overkill, stay in-editor. Positioned as a companion, not a replacement.

*Use case 1 (Obsidian memory) gets roughly 2× the airtime of the others — ~5 min, because it's the thing in their hand. The remaining 7 are ~2 min each.*

### Deliberately held back (v0.1)
- TDD / systematic-debugging skills — powerful but deep; 25 min won't do them justice.
- Building your own MCP — Part 2 material.
- Hooks / secret-guard / auto-commit — these ship with the repo, mentioned in the README walk-through but not a cookbook entry.
- Arc-specific MCPs (Supabase, Fly, Netlify) — pending confirmation of Arc's current stack (see Open questions).

## Business session — content outline

**Duration target:** 20 min. ~2 min per use case + 4 min intro/outro.

**Structure:** 3-min Claude landscape map ("Projects vs chats vs scheduled jobs vs Artifacts") → 7 use cases → Q&A.

### Use cases (v0.1 — 2026-04-22)

1. **Claude Projects ("Claude Design")** — build a preset for a recurring task (meeting debrief, sales-enquiry triage). System prompt + knowledge files + sharing with the team. Tool: claude.ai Projects. *This is the anchor topic for this session. Conceptual parallel to the engineering "Obsidian memory" item — Projects are how non-engineers give Claude persistent context: a system prompt + knowledge docs that stay loaded across chats.*
2. **Schedule Claude for weekly jobs** — Monday inbox digest, Friday sales summary, overnight research. Tool: `/schedule` (non-engineer framing).
3. **"Answer from this doc"** — upload a contract/brief, ask questions without reading end-to-end. Tool: Claude.ai file upload, or Drive MCP for recurring docs.
4. **Draft emails with your voice** — a Project with tone samples + Gmail MCP for draft generation. Tool: Gmail MCP.
5. **Artifacts / mini-tools** — build a calculator, a form, a decision tree *inside a chat*. No code. Tool: Claude Artifacts.
6. **Research mode** — long-form deep-dive (competitor scans, market sizing) with citations. Tool: Claude research mode, Perplexity as alternative.
7. **Prompt patterns that actually help** — three patterns: Role/Task/Context, ask-for-structure, critique-your-own-answer.
8. **Guardrails** — what not to paste in (client data, auth tokens, unreleased info) and when not to use AI (binding legal/medical, final-customer-facing without review).

### Pre-built Claude Projects to ship in D4
- **"Arc meeting debrief"** — transcript → decisions, actions, open items, wikilink-style cross-refs.
- **"Arc sales enquiry triage"** — inbound → classified (support vs. sales), draft reply in the right tone. *Relevant to the dual-agent work Jas and Charlie are already scoping.*

One or two, not more. Each is a system-prompt + 1–2 knowledge files, small enough that Mike/Henry can fork and adapt.

## Repo changes required

```
obsidian-memory/
  sessions/                                       # NEW
    engineering/
      README.md                                   # D2 — start-here for engineers
      2026-04-22-cookbook.md                      # D1
      2026-04-22-cheatsheet.md                    # D6
    business/
      2026-04-22-cookbook.md                      # D3
      2026-04-22-cheatsheet.md                    # D6
      projects/
        arc-meeting-debrief/
          system-prompt.md
          knowledge/example-transcript.md
        arc-sales-enquiry-triage/
          system-prompt.md
          knowledge/tone-examples.md
    shared/
      2026-04-22-links.md                         # D5
  README.md                                       # add a "Sessions" section pointing at sessions/
```

No changes to the existing memory system, scripts, or hooks. Session content is additive.

## Maintenance plan

- **Versioning:** every cookbook and cheatsheet has frontmatter with `version:` and `updated:`. When Jas refreshes, both move; the dated filename stays as a snapshot and a new file with a newer date is added alongside. Old snapshots stay in git history AND on disk for "here's what I taught in April."
- **Revision log:** at the bottom of this spec and each cookbook, a running list of `YYYY-MM-DD — Vx.y — what changed`.
- **Cadence:** no hard schedule. Expected trigger points: a major Claude feature lands, a new MCP proves useful, a session is re-run for a different audience.

## Open questions

- **Arc's current stack for the engineering cookbook** — do we list Supabase / Fly / Netlify MCPs? (Depends on what Arc actually uses in prod.)
- **Privacy of this repo** — the README implies it's shareable / open-sourceable. Is `sessions/` OK to live in the same public repo, or does Arc-specific content need a private fork?
- **Henry/Mike's own Claude accounts** — do they already have claude.ai Pro, so we can share the Projects directly? Or do we hand over the system-prompt markdown for them to paste?
- **Projector / screenshare setup** — is this in a room with a screen, or remote over Zoom / Meet?
- **Recording** — is this being recorded for people who miss it? Affects how much Jas reads aloud vs. just points at the handout.

## Next steps

1. User reviews this spec. Edit in place; bump Version.
2. Keep iterating the spec (user prefers brainstorm over a separate implementation plan).
3. When the use-case lists and repo-layout feel settled, start drafting the deliverables (D1–D6) directly from this spec.

## Revision log

- **2026-04-22 — v0.2** — Promoted the Obsidian-memory system to engineering use case 1 ("give Claude a brain that lasts longer than one session") with 2× airtime — it's the actual repo being handed over, so it earns the headline slot. Other eng use cases renumbered 2–8. Business use case 1 (Claude Projects) reframed as the non-engineer parallel to persistent memory. Removed the "hand off to writing-plans" next-step — user prefers spec iteration over formal plans.
- **2026-04-22 — v0.1** — Initial draft after scoping conversation on 2026-04-22. Audience (B), goals (eng=leverage, biz=leverage+evaluation), duration (~25 min each), format (discussion + handout, no demo), scope (Claude-primary), content outline (8 use cases each). Open questions not yet resolved.
