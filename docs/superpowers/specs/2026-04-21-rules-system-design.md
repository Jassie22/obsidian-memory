# Rules System — Design Spec

**Date:** 2026-04-21
**Status:** Approved for planning
**Author:** Jas (with Claude)

## Problem

Rules governing Claude's behavior currently live in four places: global `~/.claude/CLAUDE.md`, per-repo `CLAUDE.md`, vault `~/vault/CLAUDE.md`, and project-scoped auto-memory at `~/.claude/projects/<slug>/memory/`. Three concrete failures result:

- **Discovery** — "is there a rule for this?" has no single answer.
- **Enforcement** — Claude forgets rules exist mid-session, especially past the initial context load.
- **Authoring/routing** — when the user dictates a new rule, it lands in the wrong scope (e.g. project-scoped auto-memory for a rule that should apply globally).

The user's stated priority is enforcement: "Claude forgets the rule exists."

## Goal

A user-facing rules layer in the Obsidian vault, surfaced to Claude through hooks, that:

1. Gives the user **one authoring surface** for all durable behavior rules.
2. Reminds Claude of active rules **every N turns** (N configurable) so rules don't fall out of context.
3. Injects **scope-matched rules before risky tool actions** (vault writes, shell commands).
4. Displays rule status in the **Claude Code statusline** so the user sees drift coming.
5. Ships end-to-end in the `obsidian-memory` repo so teammates can `git clone + ./setup.sh` and get the same system.

Existing CLAUDE.md files and auto-memory remain; this layers on top.

## Architecture

### Vault directory layout

```
~/vault/
  rules/                          # NEW — authoring surface
    .config.yml                   # runtime config (human-edited)
    vault-dates.md                # one rule per file
    terse-responses.md
    no-secrets-in-vault.md
    arc-design-first.md
  rules.md                        # auto-generated index (H2 per scope). Read-only.
```

One rule per file. `rules.md` is regenerated from the per-file sources — never hand-edited.

### Rule file format

```markdown
---
title: Resolve relative dates in vault notes
scope: vault                    # see scope values below
priority: high                  # high | normal | low — orders rules in the index
enforcement: advise             # advise | block — only used by the PreToolUse hook
created: 2026-04-20
updated: 2026-04-21
status: active                  # active | superseded | archived
---

**Rule:** When the user says "Friday" / "tomorrow" in content destined for the vault,
resolve to absolute YYYY-MM-DD before writing. Include both weekday and date.

**Why:** Vault notes get read weeks later — bare weekdays become ambiguous.

**How to apply:** Any Write/Edit into `~/vault/`. Use today's date from session context.
```

### Scope values (closed set)

- `global` — always active.
- `<group-slug>` — only when the session's active group matches (`arc`, `truenode`, `cinesynth`, …).
- `vault` — only when the tool target is inside `~/vault/`.
- `tool:<ToolName>` — only before that specific tool fires (e.g. `tool:Write`, `tool:Bash`).

Multiple scopes via list: `scope: [global, vault]`.

### Components

**`~/scripts/rules_rebuild.py`**
- Reads all `~/vault/rules/*.md` (excluding `.config.yml` and `rules.md`).
- Emits `~/vault/rules.md`: H1 title, H2 per scope, rules ordered by priority, body quoted.
- Runs on rule-file change (PostToolUse hook) and on `/add-rule`.

**`~/scripts/rules-reminder.sh`** (UserPromptSubmit hook)
- Reads `~/vault/rules/.config.yml` for `reminder_interval` (N).
- Increments session turn counter at `~/.claude/.rules-turn-counter-<session_id>`.
- If `counter % N == 0`: resolves active scopes (`global` always + current group + `vault` if cwd is `~/vault`), filters rule files by frontmatter `scope`, injects matched rules' Rule + How-to-apply as a system-reminder on the current turn.
- Otherwise silent.

**`~/scripts/rules-preguard.sh`** (PreToolUse hook on Write, Edit, Bash)
- Inspects tool input to determine target (path / command).
- If target path is inside `~/vault/` → loads `scope: vault` rules.
- Always loads `scope: tool:<ToolName>` rules for the firing tool.
- Injects matched rules as system-reminder.
- If any matched rule has `enforcement: block` AND the tool input violates a pattern declared in the rule (future extension — v1 treats `block` same as `advise` and surfaces a warning), deny the tool call with a redact-and-retry hint.
- v1 default behavior: `enforcement: advise` for all rules (no hard blocks). `block` is the extension path; framework is in place.

**`~/scripts/rules-statusline.sh`** (statusline renderer)
- Wired via Claude Code's statusline mechanism (`statusLine` in `settings.json`).
- Resolves active scopes and counts matching rule files.
- Reads the turn counter.
- Emits one line: `📋 {active_count} rules · next reminder in {turns_left}`.
- Cheap — executes per statusline refresh, not per token.

**`/add-rule <title>` slash command** (`claude-global/commands/add-rule.md`)
- Slugifies title → filename.
- Scaffolds `~/vault/rules/<slug>.md` with frontmatter template and empty Rule/Why/How-to-apply sections.
- Prompts user (via AskUserQuestion or inline) for `scope` from the closed set.
- Calls `rules_rebuild.py` on save.
- Opens the file for user to fill in.

### Config

`~/vault/rules/.config.yml`:

```yaml
# Rules-system config. Edit freely — no restart required (hooks re-read every fire).
reminder_interval: 10          # UserPromptSubmit hook fires every N turns.
                               # Lower = more reliable, higher token cost.
                               # Higher = cheaper, more drift.
statusline_enabled: true       # Show rule count + turns-until-reminder in statusline.
preguard_enabled: true         # Inject scope-matched rules before Write/Edit/Bash.
blocked_scopes: []             # Temporarily disable scopes without deleting rule files.
                               # Example: [arc] silences all arc-scoped rules.
```

Lives in the **vault** (not the repo) so teammates tune independently. Repo ships `vault-template/rules/.config.example.yml` with identical content; `setup.sh` copies it on first install if the live file is absent.

### Settings.json wiring

```jsonc
{
  "hooks": {
    "UserPromptSubmit": [
      // existing proactive-note reminder stays
      { "command": "<SCRIPTS_DIR>/rules-reminder.sh" }
    ],
    "PreToolUse": [
      // existing secret-guard stays
      { "matcher": "Write|Edit|Bash", "command": "<SCRIPTS_DIR>/rules-preguard.sh" }
    ],
    "PostToolUse": [
      { "matcher": "Write|Edit", "command": "<SCRIPTS_DIR>/rules_rebuild_if_rule_changed.sh" }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "<SCRIPTS_DIR>/rules-statusline.sh"
  }
}
```

`<SCRIPTS_DIR>` is templated by `setup.sh` at install time (default `~/scripts`, overridable via `--scripts-dir`).

## Repo-shareability changes (bundled)

Alongside the rules system, fix the audit gaps that block teammate onboarding.

### New files

```
obsidian-memory/
  scripts/
    rules-reminder.sh
    rules-preguard.sh
    rules-statusline.sh
    rules_rebuild.py
    rules_rebuild_if_rule_changed.sh   # PostToolUse wrapper
  claude-global/
    commands/
      add-rule.md                       # slash command definition
    settings.json                       # updated with new hooks + statusline
  vault-template/
    .groups.template                    # sample groups, commented
    rules/
      .config.example.yml
      README.md                         # how to author a rule
      _example-global.md
      _example-vault.md
  docs/
    superpowers/specs/2026-04-21-rules-system-design.md  # this doc
```

### `setup.sh` changes

- Accept `--scripts-dir <path>` (default `~/scripts`). Template the chosen path into `settings.json` before writing.
- Copy `vault-template/rules/` → `~/vault/rules/` only if absent (never overwrite).
- Copy `.config.example.yml` → `.config.yml` if absent.
- Copy `.groups.template` → `~/vault/.groups` on first install; prompt user to edit.
- Run `rules_rebuild.py` once to seed `~/vault/rules.md`.
- Add `--dry-run` flag (audit item) — prints planned actions, writes nothing.

### Audit punch-list items folded in

| # | Item | Resolution |
|---|------|------------|
| 1 | No `.groups` template | `vault-template/.groups.template` shipped; `setup.sh` prompts. |
| 2 | Hardcoded `~/scripts/` path | `setup.sh --scripts-dir`; templates paths into `settings.json`. |
| 3 | Vault-portability undocumented | README section: "Making your vault portable" (`git init` + private remote). |
| 4 | Hook JSON contract undocumented | Every hook script (new + existing `vault-*.sh`) gets a header comment documenting the JSON input shape Claude Code passes on stdin. |
| 5 | Scripts not version-controlled | Document the flow: edit repo copy → re-run `setup.sh` → changes propagate. Scripts already live under `scripts/` in the repo. |

### README updates

Top-level `README.md` gets three new sections:

1. **Rules system (author → enforce)** — per-rule files, scopes, auto-generated index, `/add-rule`, one copy-pasteable example.
2. **Tuning the rules reminder** — the one-line edit in `~/vault/rules/.config.yml` to change `reminder_interval`. Explains the tradeoff (lower = more reliable + more tokens).
3. **For teammates: getting set up** — clone, run `./setup.sh`, point vault at own private remote, edit `.config.yml` to taste. Three-minute onboarding.

`~/vault/CLAUDE.md` gets a short "Rules system" section pointing at `~/vault/rules/` as the authoring surface and noting `rules.md` is auto-generated.

`~/.claude/CLAUDE.md` gets a short "Rules system" section replacing the current scattered routing guidance — points Claude at the rules reminder hook as the enforcement mechanism and at `~/vault/rules/` for authoritative content.

## Non-goals (v1)

- Programmatic `enforcement: block` patterns — framework is present (frontmatter field), but v1 treats all rules as `advise`. Extension is a future spec.
- Rule versioning / history beyond git — superseded rules get `status: superseded` + a wikilink to the replacement, as with other vault notes.
- Per-rule token-cost metering — a global `reminder_interval` is enough for v1.
- Team-shared rule content — the repo ships *mechanism* only. Each teammate's rule bodies are in their own vault.
- Rule authoring UI beyond `/add-rule` — direct file editing in Obsidian is fine for v1.
- Subagent enforcement — Claude Code's PreToolUse hooks fire on the main session's tool calls, not on tool calls inside subagents dispatched via the `Agent` tool. Subagents inherit context (so the UserPromptSubmit reminder is visible), but targeted PreToolUse guards only cover main-session actions. Accepted limitation for v1.

## Open questions

None at spec approval. If any surface during planning, they become planning-phase issues.

## Seed rules to migrate on first install

To validate the system end-to-end, migrate two existing rules into `~/vault/rules/` as part of setup:

1. **`vault-dates.md`** — scope `vault`, the rule we saved yesterday. Today it lives in project-scoped auto-memory (`~/.claude/projects/-home-jas-obsidian-memory/memory/feedback_resolve_relative_dates.md`) and won't fire outside that project. Migration fixes that.
2. **`no-secrets-in-vault.md`** — scope `vault`, restates the credential-hygiene rule currently in `~/.claude/CLAUDE.md`. Global file keeps a summary; detailed version lives here.

Auto-memory feedback file gets removed on migration; `~/.claude/CLAUDE.md` stays but its "where rules go" section gets trimmed to one line pointing at `~/vault/rules/`.

## Success criteria

1. Teammate clones the repo, runs `./setup.sh --scripts-dir ~/bin/claude-scripts`, points vault at their own remote — working memory system in under 5 minutes.
2. Claude receives a rule reminder every 10 turns by default; user can change to 5 by editing one line in `~/vault/rules/.config.yml`.
3. Writing to a vault note without resolving a weekday → PreToolUse hook injects the `vault-dates` rule; Claude applies it without user prompting.
4. Statusline shows `📋 N rules · next reminder in K turns` at all times.
5. `/add-rule "be terse in responses"` scaffolds `~/vault/rules/be-terse-in-responses.md`, user fills in, `rules.md` auto-regenerates.

## Next step

After user approval of this spec: invoke the `superpowers:writing-plans` skill to produce an implementation plan covering both the rules-system build-out and the repo-shareability punch list.
