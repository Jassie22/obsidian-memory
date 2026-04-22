---
title: AI for Software Engineering
audience: Arc engineers
kind: living-cookbook
started: 2026-04-22
updated: 2026-04-22
current_version: 0.1
author: Jas
---

# AI for Software Engineering

A living cookbook for the Arc engineering team. One entry per "situation you hit → tool that flattens it." Read end-to-end, skim, or jump to whatever sounds familiar.

This doc grows. Every new session (or thing I figure out between sessions) gets appended with its own date, so you can tell what's fresh and what's foundational. The **Sessions log** and **Revision log** at the bottom track the history.

> **How this doc gets used:** The Markdown here is the source of truth. Slide decks and printable handouts are generated from it on demand by a Claude Project ("Claude Design") — so if you're reading the slides and something looks off, check this doc first.

---

## Overview

### Why this matters

The ceiling on engineer productivity has shifted in the last 18 months. The difference between people who compose AI tools well and people who paste into chat.ai is **not 20% — it's closer to 3–10×** on the things that were always the boring middle (reading codebases, drafting PRs, triaging issues, reformatting data, writing tests). The whole point of this session is to collapse that gap for the Arc team.

### The landscape at a glance

Six things sit behind almost every useful AI workflow for engineers. This doc covers all of them.

| Layer | What it is | Why you care |
|---|---|---|
| **Claude Code** | The CLI that runs Claude in your actual repo. | Replaces copy-pasting between editor and web chat. |
| **MCPs** (Model Context Protocol servers) | Plug-ins that let Claude talk to external systems — Figma, GitHub, Supabase, Gmail, Fly, Netlify. | Claude stops being "trapped in chat" and starts taking real actions. |
| **Skills** | Small reusable instruction packs Claude loads on trigger. | Stop retyping the same guidance every session. |
| **Memory** | A persistent vault (this repo) Claude reads from + writes to across sessions. | Claude stops forgetting what you decided last week. |
| **Scheduling / Cron** | Run Claude on a cron or one-shot delay, inside or across sessions. | Credits and attention are finite — delegate the work you don't need to watch. |
| **Cursor / in-editor AI** | Inline completions + spot fixes, as a companion to Claude Code. | Pick the tool by the size of the change. |

### What's in this session

The eight entries below, in order:

1. **Give Claude a brain that lasts longer than one session** *(headline — the repo you're taking home)*
2. **Run it later / overnight** — schedule or cron Claude
3. **Claude Code, not a web chat** — repo-native workflow
4. **Figma → code** — Figma MCP
5. **GitHub-native PR work** — GitHub MCP
6. **Subagents for parallel work** — dispatch multiple Claudes at once
7. **Skills for repetitive patterns** — writing your own + the ones that ship
8. **Cursor for inline fixes** — companion, not replacement

### How to use this doc

- **Right now (in the session):** follow along. Each section has a one-line **Takeaway**. If nothing else sticks, those are the eight lines worth remembering.
- **Tomorrow morning:** pick one. Install it. Try it on something real. Don't try to roll out all eight.
- **Later:** treat this as a reference. Search for the use case, not the tool name.

---

## Sessions log

| Date | Session | New / updated content | Duration |
|---|---|---|---|
| 2026-04-24 | **Session 1 — first run** | Overview + entries 1–8 below (initial set) | ~25 min |

---

## Setup (one-time, ~10 min)

```bash
git clone https://github.com/Jassie22/obsidian-memory ~/obsidian-memory
cd ~/obsidian-memory
./setup.sh --groups arc,personal
```

What that does:

1. Creates `~/vault/` with one folder per group.
2. Installs `claude-global/CLAUDE.md` → `~/.claude/CLAUDE.md` — auto-loaded in every Claude Code session.
3. Installs hook scripts to `~/scripts/` (auto-pull, auto-commit, secret guard, proactive-note reminder).
4. Installs the semantic-search layer (`fastembed` + `sqlite-vec`) that powers `/recall`.

After that: open any repo, run `claude`, type `/resume`, and you have a Claude that remembers.

Full setup details in the repo `README.md`.

---

## 1. Give Claude a brain that lasts longer than one session

*First covered: 2026-04-24 · Headline topic*

**The problem.** Every new chat starts from zero. You re-explain what Charlie decided in the meeting, why you picked n8n over Netlify Functions, what the three agent prompts actually look like.

**The fix.** An Obsidian vault + hooks that Claude reads and writes to. Persistent. Semantic-searchable. Auto-commits on every change.

**Four commands you'll use every day:**

- **`/recall <query>`** — semantic search over the vault. "What did we decide about the hero pill?" Claude reads the top 3 notes before answering. Beats grep. Beats Slack search.
- **`/capture <thought>`** — drop an idea into `inbox/` with no ceremony. Use it mid-flow when you don't want to break context.
- **`/save`** — end-of-session log: what you did, decisions, open items, next step. Dropped into the right group folder, wikilinked to every note you touched.
- **`/resume`** — start a new session with the last 3 logs + decisions already loaded.

**Four things running in the background:**

- **Proactive note-writer** — a hook injects a reminder every turn to capture durable context (decisions, gotchas, corrections). Claude writes notes *while* you work.
- **Auto-commit + auto-pull** — the vault syncs across machines without you thinking about it.
- **Secret guard** — a `PreToolUse` hook blocks writes to `~/vault/` if a secret pattern is detected (`sk-...`, `ghp_...`, long hex blobs, `-----BEGIN PRIVATE KEY-----`).
- **Groups** — top-level categories (`arc`, `personal`, `research`). Keeps work and side projects from bleeding into each other.

**Also in the box:** Graphify — generates a codebase knowledge graph (`graphify-out/graph.json`) Claude reads before diving into source. Install once, re-run on commit.

**Try it today:** clone the repo, run setup, open a Claude Code session, type `/capture test — installed the memory system`. Check `~/vault/inbox/`. There's your first note.

**Takeaway:** every engineer has their own rolodex of "what did X decide about Y" in their head. This externalises it. The repo is the rolodex.

---

## 2. Run it later / overnight

*First covered: 2026-04-24*

**The problem.** You want to kick off a long plan, but you're mid-day in meetings. Or out of credits. Or you'd like a weekly "what changed in staging" summary without remembering to ask.

**The fix.** Schedule Claude.

- **`/schedule`** — create, list, update, or one-shot scheduled agent. Cron-style or one-off date.
- **`CronCreate`** — the underlying tool. Drive it directly from inside a session.
- **`/loop`** — recurring execution in the *current* session. "Babysit this deploy for the next hour, check every 5 min."

**When to use what:**
- One-shot "do this at 3pm" → `/schedule` with a date.
- Recurring job → `/schedule` with a cron string.
- Polling inside an active session → `/loop`.

**Example.** "Every Monday 08:00, read the last week of `arc/logs/`, write a one-paragraph team status, post it to Slack." Ten seconds to set up. Runs forever.

**Takeaway:** your credits and your attention are both finite. Schedule the work you don't need to watch happen.

---

## 3. Claude Code, not a web chat

*First covered: 2026-04-24*

**The problem.** Paste a file into chat.ai → Claude suggests a change → paste back into editor → lose surrounding context. Repeat 10 times. This is the 2× productivity ceiling.

**The fix.** Claude Code in the actual repo.

- Drop a `CLAUDE.md` at the repo root. Describe the shape, conventions, gotchas. Every session in that directory auto-loads it.
- For sub-projects or clients, drop a `CLAUDE.md` in that sub-directory. Nearest-up wins.
- Use `/init` to have Claude draft the initial `CLAUDE.md` based on the repo.

**Takeaway:** if you copy-paste between editor and chat more than twice in one task, you're in the wrong tool.

---

## 4. Figma → code (Figma MCP)

*First covered: 2026-04-24*

**The problem.** Translating a design to a component takes 20 minutes of eyeballing, and you still miss three tokens.

**The fix.** Figma MCP server. Paste a Figma URL → Claude gets the actual node tree, design tokens, and a screenshot → generates a scaffold matching the design system.

- `get_design_context` — returns React + Tailwind by default, plus Code Connect mappings if set up. Adapt to your stack.
- `get_screenshot` — when you want Claude to "look at" a frame without the full node tree.
- `generate_diagram` — create a FigJam diagram from a description.

**Setup.** Install the Figma MCP in Claude Code (see Link pack). Authenticate once. Paste any `figma.com/design/...` URL into your prompt.

*Relevant to the Arc corp-site work Charlie is leading now.*

**Takeaway:** treat designs as a data source, not a reference image.

---

## 5. GitHub-native PR work (GitHub MCP)

*First covered: 2026-04-24*

**The problem.** PR review = tab-switching between editor and github.com. Context lost each time.

**The fix.** GitHub MCP. Claude reads PRs, adds comments, triages issues, checks CI — without leaving the terminal.

- `review this PR` → reads diff + description, posts line-level comments.
- `triage issues labelled 'bug'` → reads them, proposes priorities and duplicates.
- `what's red on main right now` → checks CI.

**Setup note.** Hosted OAuth can be flaky. Easiest route: a Personal Access Token over HTTP — see the repo's `github-mcp-pat-workaround` note.

**Takeaway:** bring GitHub into the editor, not the other way around.

---

## 6. Subagents for parallel work

*First covered: 2026-04-24*

**The problem.** Before you can make a change you need to understand the codebase. That's half a day of reading. You can't usefully parallelise it in your head.

**The fix.** Dispatch subagents. Multiple at once, running in parallel.

- **`Explore`** — fast, read-only, for "find all the places we do X." Thoroughness levels: quick / medium / very thorough.
- **`Plan`** — for "design me an approach to Y." Returns a step-by-step plan.
- **`general-purpose`** — open-ended research, wide searches, any multi-step task.
- **`feature-dev:*`** — specialist agents for architecture, exploration, and review inside a feature workflow.

**The trick.** Dispatch multiple agents **in parallel** in a single message. Each chews on its own slice. You get N results in the time of the slowest one. Great for "I need to understand 3 subsystems before I touch any of them."

**Takeaway:** parallel agents collapse half a day of reading into a coffee.

---

## 7. Skills for repetitive patterns

*First covered: 2026-04-24*

**The problem.** You keep retyping the same instructions: "write tests first," "match existing conventions," "commit with a conventional prefix."

**The fix.** Write a skill. Claude loads it on trigger and follows without you retyping.

**Built-in skills worth using now:**
- `superpowers:brainstorming` — scopes features before code.
- `superpowers:test-driven-development` — TDD flow.
- `superpowers:systematic-debugging` — for any bug.
- `simplify` — review + refactor changed code.
- `claude-md-management:*` — CLAUDE.md maintenance.

**Write your own** with `skill-creator`. One skill per repeated workflow. Example: a "ship-feature" skill that runs brainstorm → spec → TDD → commit → PR in sequence.

**Start simple.** Pick the three sentences you retype most often to Claude. That's your first skill.

**Takeaway:** if you're telling Claude the same thing a third time, that's a skill.

---

## 8. Cursor for inline fixes

*First covered: 2026-04-24*

**The problem.** Full Claude Code sessions have overhead. Sometimes you just want to fix the one typo or rename the one variable, in-editor.

**The fix.** Cursor (or Zed, or Copilot) stays in your editor. **Companion, not replacement** to Claude Code.

**Rule of thumb.**
- **Claude Code** when the task spans >1 file, needs long context, or benefits from memory/skills.
- **Cursor** when the edit is visible on screen and the change is <10 lines.

**Takeaway:** pick the tool by the size of the change, not by habit.

---

## Link pack

- **Claude Code docs:** https://docs.claude.com/claude-code
- **Anthropic MCP directory:** https://modelcontextprotocol.io
- **Figma MCP setup:** https://help.figma.com/hc/en-us/articles/mcp-server
- **This repo (Obsidian memory):** https://github.com/Jassie22/obsidian-memory
- **Cursor:** https://cursor.com
- **If your stack uses them:** Supabase, Fly.io, Netlify, Gmail / Drive / Calendar — all MCP-directory installable.

---

## Revision log

- **2026-04-22 — v0.1** — First draft ahead of the 2026-04-24 session. Overview added at top: why AI-for-engineering matters, landscape table (Claude Code / MCPs / Skills / Memory / Scheduling / Cursor), what's in the session, how to use the doc. Headline entry: Obsidian memory (~5 min airtime). Seven follow-ups at ~2 min each: scheduled Claude, Claude Code workflow, Figma MCP, GitHub MCP, subagents, skills, Cursor as companion. Filename switched from `2026-04-22-cookbook.md` → `cookbook.md` to signal this is an evergreen living doc — new content will be appended under new dates rather than creating new files.
