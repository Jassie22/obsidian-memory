# Rules System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a user-authored Obsidian rules layer that gets surfaced to Claude Code via hooks, plus fold in the repo-shareability fixes so teammates can `git clone + ./setup.sh` into a working system.

**Architecture:** Per-rule files in `~/vault/rules/` with scope frontmatter. A Python rebuilder regenerates `~/vault/rules.md` from sources. Three shell hooks surface rules to Claude: `UserPromptSubmit` every-N-turns reminder, `PreToolUse` scope-matched injection, `statusLine` persistent counter. Config lives in `~/vault/rules/.config.yml` so teammates tune independently.

**Tech Stack:** Bash (hooks, setup.sh), Python 3 (rebuilder, using existing `~/.venvs/vault/bin/python3` shebang like `vault_rebuild_mocs.py`), `jq` for hook JSON parsing, PyYAML for the Python-side config read.

**Spec reference:** `docs/superpowers/specs/2026-04-21-rules-system-design.md`

**Testing approach:** This repo has no unit-test framework. Verification is integration-style: run the script with real inputs, check real output. Every task ends with a verification step using actual commands. Follow this pattern — don't scaffold pytest unless explicitly required.

**Important conventions:**
- Python scripts: shebang `#!/home/jas/.venvs/vault/bin/python3` (matches `vault_rebuild_mocs.py`).
- Shell scripts: `#!/usr/bin/env bash` + `set -u` (read-only / non-destructive) or `set -euo pipefail` (destructive).
- Hook JSON arrives on stdin; parse with `jq`. Fields used by existing hooks: `.tool_input.file_path`, `.tool_input.content`, `.tool_input.new_string`, `.tool_response.filePath`, `.session_id`, `.prompt`. For UserPromptSubmit, the prompt text is in `.prompt`.
- Injecting context from a hook: write to stdout on exit 0. Claude Code picks it up as a system-reminder for `UserPromptSubmit` / `PreToolUse`.
- Commit style: `<type>(<scope>): <msg>` matches existing history (`feat(hooks): ...`, `feat(commands): ...`).

---

## File Structure

### New files in this repo

| Path | Responsibility |
|------|----------------|
| `scripts/rules_rebuild.py` | Read `~/vault/rules/*.md`, emit `~/vault/rules.md` index |
| `scripts/rules_rebuild_if_rule_changed.sh` | PostToolUse wrapper: calls rebuilder only when a rule file changed |
| `scripts/rules-reminder.sh` | UserPromptSubmit hook: every-N-turns scope-filtered rule injection |
| `scripts/rules-preguard.sh` | PreToolUse hook: scope-matched injection before Write/Edit/Bash |
| `scripts/rules-statusline.sh` | Claude Code statusline: `📋 N rules · next reminder in K turns` |
| `claude-global/commands/add-rule.md` | `/add-rule` slash command definition |
| `vault-template/.groups.template` | Sample groups file for first-install prompt |
| `vault-template/rules/.config.example.yml` | Rules config defaults with inline comments |
| `vault-template/rules/README.md` | "How to author a rule" quick-start |
| `vault-template/rules/_example-global.md` | Seed rule: terse responses (scope: global) |
| `vault-template/rules/_example-vault.md` | Seed rule: no secrets in vault (scope: vault) |
| `vault-template/rules/vault-dates.md` | Seed rule: resolve relative dates (scope: vault) — migrates the auto-memory rule |
| `docs/superpowers/plans/2026-04-21-rules-system.md` | THIS plan |

### Modified files

| Path | Reason |
|------|--------|
| `claude-global/settings.json` | Wire new hooks + statusLine |
| `claude-global/CLAUDE.md` | New "Rules system" section; trim duplicative guidance |
| `vault-template/CLAUDE.md` | New "Rules system" section pointing at `~/vault/rules/` |
| `setup.sh` | `--scripts-dir` flag; template SCRIPTS_DIR into settings.json; `--dry-run`; copy `vault-template/rules/` → `~/vault/rules/`; `.groups.template` handling |
| `README.md` | Three new sections: rules system, tuning interval, teammate onboarding |
| `scripts/vault-secret-guard.sh` | Add hook JSON-contract header comment |
| `scripts/vault-sync-commit.sh` | Add hook JSON-contract header comment |
| `scripts/vault-sync-pull.sh` | Add hook JSON-contract header comment |
| `scripts/vault-note-trigger-reminder.sh` | Add hook JSON-contract header comment |

### Files to delete (migration)

| Path | Reason |
|------|--------|
| `~/.claude/projects/-home-jas-obsidian-memory/memory/feedback_resolve_relative_dates.md` | Migrated to `~/vault/rules/vault-dates.md`, now cross-project |
| `~/.claude/projects/-home-jas-obsidian-memory/memory/MEMORY.md` | Only entry was the migrated rule |

This deletion is Task 16 (run on the user's machine). Not committed to the repo.

---

## Task 1: Add the vault-template/rules/ scaffolding

**Files:**
- Create: `vault-template/rules/.config.example.yml`
- Create: `vault-template/rules/README.md`
- Create: `vault-template/rules/_example-global.md`
- Create: `vault-template/rules/_example-vault.md`
- Create: `vault-template/rules/vault-dates.md`

- [ ] **Step 1: Create `vault-template/rules/.config.example.yml`**

```yaml
# Rules-system config. Edit freely — hooks re-read on every fire; no restart needed.
#
# Lives at ~/vault/rules/.config.yml (not in the shared repo).
# Each teammate tunes independently.

# UserPromptSubmit hook fires every N turns. 1 = every turn (expensive).
# Lower  = more reliable, higher token cost per conversation.
# Higher = cheaper, more drift. Default 10 is a reasonable middle.
reminder_interval: 10

# Show rule count + turns-until-next-reminder in the Claude Code statusline.
statusline_enabled: true

# Inject scope-matched rules before Write/Edit/Bash. Cheap, targeted.
preguard_enabled: true

# Temporarily disable scopes without deleting rule files.
# Example: ["arc"] silences every arc-scoped rule.
blocked_scopes: []
```

- [ ] **Step 2: Create `vault-template/rules/README.md`**

```markdown
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
```

- [ ] **Step 3: Create `vault-template/rules/_example-global.md`**

```markdown
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
```

- [ ] **Step 4: Create `vault-template/rules/_example-vault.md`**

```markdown
---
title: No secrets in vault notes
scope: vault
priority: high
enforcement: advise
created: 2026-04-21
updated: 2026-04-21
status: active
---

**Rule:** Never write API keys, tokens, passwords, connection strings, private URLs, `.env` contents, or long hex/base64 blobs into any file under `~/vault/`. Replace with `[REDACTED]`.

**Why:** Vault is plaintext-searchable and synced to git — treat as public-visible even if the repo is private. The `vault-secret-guard.sh` PreToolUse hook enforces this structurally, but the rule exists so Claude redacts proactively before triggering the block.

**How to apply:** Any Write/Edit/MultiEdit into `~/vault/`. Scan the content for secret patterns (`sk-…`, `ghp_…`, `AKIA…`, `Bearer …`, `password=`, `-----BEGIN …PRIVATE KEY-----`) before submitting the tool call.
```

- [ ] **Step 5: Create `vault-template/rules/vault-dates.md`**

```markdown
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
```

- [ ] **Step 6: Verify**

Run: `ls vault-template/rules/`
Expected: `.config.example.yml`, `README.md`, `_example-global.md`, `_example-vault.md`, `vault-dates.md` listed.

- [ ] **Step 7: Commit**

```bash
git add vault-template/rules/
git commit -m "feat(rules): scaffold vault-template/rules with seed rules + README"
```

---

## Task 2: Write `scripts/rules_rebuild.py` (the index generator)

**Files:**
- Create: `scripts/rules_rebuild.py`

- [ ] **Step 1: Write the script**

```python
#!/home/jas/.venvs/vault/bin/python3
"""
Rebuild ~/vault/rules.md from per-rule files in ~/vault/rules/*.md.

Reads every *.md in ~/vault/rules/ (excluding README.md and rules.md itself),
parses frontmatter (title, scope, priority, status), emits a single index
file with H2 sections per scope, rules sorted by priority (high → normal → low)
then alphabetically.

Excludes rules with status: archived or status: superseded.

Env:
  VAULT_DIR   override vault path (default ~/vault)

Exit codes:
  0 on success, non-zero on parse error.
"""
from __future__ import annotations
import os, re, sys, pathlib, datetime

VAULT = pathlib.Path(os.environ.get("VAULT_DIR", pathlib.Path.home() / "vault"))
RULES_DIR = VAULT / "rules"
INDEX = VAULT / "rules.md"
TODAY = datetime.date.today().isoformat()

FM_RE = re.compile(r"\A---\n(.*?)\n---\n?(.*)\Z", re.DOTALL)
PRIORITY_ORDER = {"high": 0, "normal": 1, "low": 2}
SKIP_FILES = {"README.md", "rules.md", ".config.yml", ".config.example.yml"}


def parse_frontmatter(text: str):
    m = FM_RE.match(text)
    if not m:
        return {}, text
    fm = {}
    for line in m.group(1).splitlines():
        mm = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if mm:
            fm[mm.group(1)] = mm.group(2).strip()
    return fm, m.group(2)


def parse_scope(raw: str) -> list[str]:
    raw = raw.strip()
    if raw.startswith("[") and raw.endswith("]"):
        return [s.strip().strip('"\'') for s in raw[1:-1].split(",") if s.strip()]
    return [raw.strip('"\'')] if raw else ["global"]


def load_rules():
    rules = []
    if not RULES_DIR.is_dir():
        return rules
    for f in sorted(RULES_DIR.glob("*.md")):
        if f.name in SKIP_FILES or f.name.startswith("."):
            continue
        try:
            text = f.read_text(encoding="utf-8")
        except OSError as e:
            print(f"warn: cannot read {f}: {e}", file=sys.stderr)
            continue
        fm, body = parse_frontmatter(text)
        if fm.get("status", "active") in ("archived", "superseded"):
            continue
        rules.append({
            "path": f,
            "title": fm.get("title", f.stem).strip('"\''),
            "scopes": parse_scope(fm.get("scope", "global")),
            "priority": fm.get("priority", "normal"),
            "body": body.strip(),
        })
    return rules


def render(rules):
    by_scope: dict[str, list] = {}
    for r in rules:
        for s in r["scopes"]:
            by_scope.setdefault(s, []).append(r)

    scope_order = sorted(
        by_scope.keys(),
        key=lambda s: (s != "global", s.startswith("tool:"), s),
    )

    lines = [
        "---",
        "title: Rules — Map of Active Behaviors",
        f"updated: {TODAY}",
        "type: moc",
        "---",
        "",
        "# Rules — Map of Active Behaviors",
        "",
        "> Auto-generated by `~/scripts/rules_rebuild.py`. Do not hand-edit — edit the per-rule files in `~/vault/rules/` instead.",
        "",
    ]

    for scope in scope_order:
        lines.append(f"## scope: {scope}")
        lines.append("")
        entries = sorted(
            by_scope[scope],
            key=lambda r: (PRIORITY_ORDER.get(r["priority"], 1), r["title"].lower()),
        )
        for r in entries:
            lines.append(f"### [[{r['path'].stem}|{r['title']}]]")
            lines.append(f"*priority: {r['priority']}*")
            lines.append("")
            lines.append(r["body"])
            lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def main():
    rules = load_rules()
    out = render(rules)
    INDEX.parent.mkdir(parents=True, exist_ok=True)
    INDEX.write_text(out, encoding="utf-8")
    print(f"wrote {INDEX} ({len(rules)} rules across {len({s for r in rules for s in r['scopes']})} scopes)")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/rules_rebuild.py`

- [ ] **Step 3: Verify end-to-end with the seed rules**

Run:
```bash
mkdir -p /tmp/rules-test/rules
cp vault-template/rules/*.md /tmp/rules-test/rules/
VAULT_DIR=/tmp/rules-test python3 scripts/rules_rebuild.py
cat /tmp/rules-test/rules.md
```

Expected output contains:
- `## scope: global` section with `Be terse in responses`
- `## scope: vault` section with both `No secrets in vault notes` AND `Resolve relative dates in vault notes`
- Priority ordering: `high` before `normal` within each scope (so `No secrets` + `Resolve dates` both come before `Be terse` would, if terse were in the same scope)
- Auto-generated warning line.

- [ ] **Step 4: Clean up test**

Run: `rm -rf /tmp/rules-test`

- [ ] **Step 5: Commit**

```bash
git add scripts/rules_rebuild.py
git commit -m "feat(rules): rebuild ~/vault/rules.md from per-rule files"
```

---

## Task 3: Write `scripts/rules_rebuild_if_rule_changed.sh` (PostToolUse wrapper)

**Files:**
- Create: `scripts/rules_rebuild_if_rule_changed.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# PostToolUse hook: if a Write/Edit/MultiEdit touched ~/vault/rules/*.md,
# regenerate ~/vault/rules.md. Silent no-op otherwise.
#
# Hook JSON arrives on stdin. Fields read:
#   .tool_input.file_path      (Write, Edit)
#   .tool_response.filePath    (fallback)
#   .tool_input.edits[].file_path  (MultiEdit — any edit into rules/ triggers)
set -u

f=$(jq -r '
  .tool_input.file_path //
  .tool_response.filePath //
  (.tool_input.edits // [] | .[0].file_path // empty) //
  empty' 2>/dev/null)

case "$f" in
  "$HOME/vault/rules/"*.md)
    # Don't rebuild on edits to rules.md itself or to config files
    case "$(basename "$f")" in
      rules.md|.config.yml|.config.example.yml|README.md) exit 0 ;;
    esac
    "$HOME/scripts/rules_rebuild.py" >/dev/null 2>&1 || true
    ;;
esac
exit 0
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/rules_rebuild_if_rule_changed.sh`

- [ ] **Step 3: Verify**

Run:
```bash
echo '{"tool_input":{"file_path":"/tmp/nothing.md"}}' | ./scripts/rules_rebuild_if_rule_changed.sh
echo "exit: $?"
```
Expected: exit 0, no output.

- [ ] **Step 4: Commit**

```bash
git add scripts/rules_rebuild_if_rule_changed.sh
git commit -m "feat(hooks): auto-rebuild rules index on rule-file change"
```

---

## Task 4: Write `scripts/rules-statusline.sh`

**Files:**
- Create: `scripts/rules-statusline.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Claude Code statusline: emits one line showing active rule count and
# turns-until-next-reminder.
#
# Statusline hook JSON on stdin. Fields read:
#   .session_id             (for turn counter lookup)
#   .workspace.current_dir  (for scope resolution)
#
# Silent if ~/vault/rules/ doesn't exist (not yet set up).
set -u

VAULT="${VAULT_DIR:-$HOME/vault}"
RULES_DIR="$VAULT/rules"
CONFIG="$RULES_DIR/.config.yml"
[[ -d "$RULES_DIR" ]] || exit 0

# Read config (grep-based — avoids python dep in statusline)
statusline_enabled=$(grep -E '^\s*statusline_enabled:' "$CONFIG" 2>/dev/null | awk '{print $2}')
[[ "$statusline_enabled" == "false" ]] && exit 0

interval=$(grep -E '^\s*reminder_interval:' "$CONFIG" 2>/dev/null | awk '{print $2}')
interval=${interval:-10}

payload="$(cat)"
session_id=$(printf '%s' "$payload" | jq -r '.session_id // "default"' 2>/dev/null)
cwd=$(printf '%s' "$payload" | jq -r '.workspace.current_dir // empty' 2>/dev/null)

# Active scopes for this cwd: always "global"; add "vault" if inside vault;
# add group if ./CLAUDE.md in cwd has a `group:` field matching ~/vault/.groups
scopes=("global")
case "$cwd" in
  "$VAULT"*) scopes+=("vault") ;;
esac
if [[ -f "$cwd/CLAUDE.md" && -f "$VAULT/.groups" ]]; then
  group=$(grep -E '^group:' "$cwd/CLAUDE.md" 2>/dev/null | head -1 | awk '{print $2}')
  if [[ -n "${group:-}" ]] && grep -qxF "$group" "$VAULT/.groups"; then
    scopes+=("$group")
  fi
fi

# Count rule files whose scope frontmatter matches any active scope
active_count=0
shopt -s nullglob
for f in "$RULES_DIR"/*.md; do
  case "$(basename "$f")" in
    README.md|rules.md) continue ;;
  esac
  raw=$(awk '/^---$/{c++; next} c==1 && /^scope:/{print; exit}' "$f")
  # raw looks like "scope: vault" or "scope: [global, vault]"
  for s in "${scopes[@]}"; do
    if printf '%s' "$raw" | grep -qE "(^|[ ,\[])$s(\$|[ ,\]])"; then
      active_count=$((active_count + 1))
      break
    fi
  done
done

# Turn counter: read, don't increment (reminder hook does that)
counter_file="$HOME/.claude/.rules-turn-counter-$session_id"
counter=0
[[ -f "$counter_file" ]] && counter=$(cat "$counter_file" 2>/dev/null || echo 0)
turns_left=$(( interval - (counter % interval) ))
[[ "$turns_left" == "$interval" ]] && turns_left=0

printf '📋 %d rules · next reminder in %d turns\n' "$active_count" "$turns_left"
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/rules-statusline.sh`

- [ ] **Step 3: Verify with a fake vault**

Run:
```bash
mkdir -p /tmp/rules-test/rules
cp vault-template/rules/*.md vault-template/rules/.config.example.yml /tmp/rules-test/rules/
mv /tmp/rules-test/rules/.config.example.yml /tmp/rules-test/rules/.config.yml
echo "arc" > /tmp/rules-test/.groups
VAULT_DIR=/tmp/rules-test \
  echo '{"session_id":"s1","workspace":{"current_dir":"/tmp/rules-test"}}' \
  | VAULT_DIR=/tmp/rules-test ./scripts/rules-statusline.sh
```
Expected: `📋 3 rules · next reminder in 0 turns` (or similar — 3 rules active because all are global/vault and cwd is the vault). If the count is wrong, debug the scope-matching awk/grep.

- [ ] **Step 4: Clean up**

Run: `rm -rf /tmp/rules-test`

- [ ] **Step 5: Commit**

```bash
git add scripts/rules-statusline.sh
git commit -m "feat(hooks): rules statusline (active count + turns-until-reminder)"
```

---

## Task 5: Write `scripts/rules-reminder.sh` (UserPromptSubmit, every-N-turns)

**Files:**
- Create: `scripts/rules-reminder.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# UserPromptSubmit hook: every Nth turn, inject scope-matched rules as
# a system-reminder. Silent on other turns.
#
# Hook JSON on stdin. Fields read:
#   .session_id             (per-session turn counter)
#   .cwd                    (current working directory)
#
# Injection is stdout — Claude Code attaches it as additional context for
# this turn. Keep the footprint small.
set -u

VAULT="${VAULT_DIR:-$HOME/vault}"
RULES_DIR="$VAULT/rules"
CONFIG="$RULES_DIR/.config.yml"
[[ -d "$RULES_DIR" ]] || exit 0

interval=$(grep -E '^\s*reminder_interval:' "$CONFIG" 2>/dev/null | awk '{print $2}')
interval=${interval:-10}

payload="$(cat)"
session_id=$(printf '%s' "$payload" | jq -r '.session_id // "default"' 2>/dev/null)
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)

# Increment counter
counter_file="$HOME/.claude/.rules-turn-counter-$session_id"
mkdir -p "$(dirname "$counter_file")"
counter=0
[[ -f "$counter_file" ]] && counter=$(cat "$counter_file" 2>/dev/null || echo 0)
counter=$((counter + 1))
printf '%d' "$counter" > "$counter_file"

# Only fire every Nth turn (turn 1 also fires, so rules show up right away)
if (( counter != 1 )) && (( counter % interval != 0 )); then
  exit 0
fi

# Active scopes: global + (vault if cwd in vault) + (group if ./CLAUDE.md group matches)
scopes=("global")
case "$cwd" in
  "$VAULT"*) scopes+=("vault") ;;
esac
if [[ -f "$cwd/CLAUDE.md" && -f "$VAULT/.groups" ]]; then
  group=$(grep -E '^group:' "$cwd/CLAUDE.md" 2>/dev/null | head -1 | awk '{print $2}')
  if [[ -n "${group:-}" ]] && grep -qxF "$group" "$VAULT/.groups"; then
    scopes+=("$group")
  fi
fi

# Check blocked_scopes — simple grep, skip whole block if any match
blocked_raw=$(grep -E '^\s*blocked_scopes:' "$CONFIG" 2>/dev/null | head -1)

rules_to_inject=()
shopt -s nullglob
for f in "$RULES_DIR"/*.md; do
  case "$(basename "$f")" in
    README.md|rules.md) continue ;;
  esac
  # extract scope line from frontmatter
  raw=$(awk '/^---$/{c++; next} c==1 && /^scope:/{print; exit}' "$f")
  for s in "${scopes[@]}"; do
    # skip if scope is in blocked list
    if printf '%s' "$blocked_raw" | grep -qE "[ ,\[]$s[ ,\]]"; then
      continue
    fi
    if printf '%s' "$raw" | grep -qE "(^|[ ,\[])$s(\$|[ ,\]])"; then
      rules_to_inject+=("$f")
      break
    fi
  done
done

(( ${#rules_to_inject[@]} == 0 )) && exit 0

# Emit the system-reminder
printf '<rules-reminder>\n'
printf 'Active rules (turn %d, reminder every %d turns). These are your standing orders — apply them this turn:\n\n' "$counter" "$interval"
for f in "${rules_to_inject[@]}"; do
  title=$(awk '/^title:/{sub(/^title: */,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit}' "$f")
  scope=$(awk '/^---$/{c++; next} c==1 && /^scope:/{sub(/^scope: */,""); print; exit}' "$f")
  rule_line=$(awk '/^\*\*Rule:\*\*/{sub(/^\*\*Rule:\*\* */,""); print; exit}' "$f")
  printf '- **[%s]** %s — %s\n' "$scope" "$title" "${rule_line:-see $(basename "$f")}"
done
printf '\nFull rule bodies: ~/vault/rules/ · edit config at ~/vault/rules/.config.yml\n'
printf '</rules-reminder>\n'

exit 0
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/rules-reminder.sh`

- [ ] **Step 3: Verify on turn 1 fires + unrelated turn silent**

```bash
mkdir -p /tmp/rules-test/rules
cp vault-template/rules/*.md vault-template/rules/.config.example.yml /tmp/rules-test/rules/
mv /tmp/rules-test/rules/.config.example.yml /tmp/rules-test/rules/.config.yml
rm -f ~/.claude/.rules-turn-counter-testsession

# Turn 1 — should output a reminder
VAULT_DIR=/tmp/rules-test \
  echo '{"session_id":"testsession","cwd":"/tmp/rules-test"}' \
  | VAULT_DIR=/tmp/rules-test ./scripts/rules-reminder.sh
```
Expected: `<rules-reminder>...</rules-reminder>` block with at least 2 rules listed (vault-scoped).

```bash
# Turn 2 — should be silent (interval=10, not divisible)
VAULT_DIR=/tmp/rules-test \
  echo '{"session_id":"testsession","cwd":"/tmp/rules-test"}' \
  | VAULT_DIR=/tmp/rules-test ./scripts/rules-reminder.sh
```
Expected: no output.

```bash
# Turns 3-10 — silent. Turn 11 — fires again.
for i in 3 4 5 6 7 8 9; do
  VAULT_DIR=/tmp/rules-test \
    echo '{"session_id":"testsession","cwd":"/tmp/rules-test"}' \
    | VAULT_DIR=/tmp/rules-test ./scripts/rules-reminder.sh
done
# 10th increment — counter == 10, fires
VAULT_DIR=/tmp/rules-test \
  echo '{"session_id":"testsession","cwd":"/tmp/rules-test"}' \
  | VAULT_DIR=/tmp/rules-test ./scripts/rules-reminder.sh
```
Expected: last invocation outputs another rules-reminder block.

- [ ] **Step 4: Clean up**

```bash
rm -rf /tmp/rules-test
rm -f ~/.claude/.rules-turn-counter-testsession
```

- [ ] **Step 5: Commit**

```bash
git add scripts/rules-reminder.sh
git commit -m "feat(hooks): UserPromptSubmit every-N-turns rules reminder"
```

---

## Task 6: Write `scripts/rules-preguard.sh` (PreToolUse scope-matched injection)

**Files:**
- Create: `scripts/rules-preguard.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# PreToolUse hook: inject scope-matched rules as context before Write/Edit/Bash.
#
# Hook JSON on stdin. Fields read:
#   .tool_name
#   .tool_input.file_path  (Write, Edit)
#   .tool_input.command    (Bash)
#
# Injects via stdout — a block containing any rules whose `scope:` matches
# "vault" (if target path is inside ~/vault/) or "tool:<ToolName>".
set -u

VAULT="${VAULT_DIR:-$HOME/vault}"
RULES_DIR="$VAULT/rules"
CONFIG="$RULES_DIR/.config.yml"
[[ -d "$RULES_DIR" ]] || exit 0

# Respect the global preguard toggle
enabled=$(grep -E '^\s*preguard_enabled:' "$CONFIG" 2>/dev/null | awk '{print $2}')
[[ "$enabled" == "false" ]] && exit 0

payload="$(cat)"
tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)
target=$(printf '%s' "$payload" | jq -r '
  .tool_input.file_path //
  .tool_input.filePath //
  empty' 2>/dev/null)

scopes=("tool:$tool_name")
case "$target" in
  "$HOME/vault/"*) scopes+=("vault") ;;
esac

blocked_raw=$(grep -E '^\s*blocked_scopes:' "$CONFIG" 2>/dev/null | head -1)

rules_to_inject=()
shopt -s nullglob
for f in "$RULES_DIR"/*.md; do
  case "$(basename "$f")" in
    README.md|rules.md) continue ;;
  esac
  raw=$(awk '/^---$/{c++; next} c==1 && /^scope:/{print; exit}' "$f")
  for s in "${scopes[@]}"; do
    if printf '%s' "$blocked_raw" | grep -qE "[ ,\[]$s[ ,\]]"; then
      continue
    fi
    if printf '%s' "$raw" | grep -qE "(^|[ ,\[])$s(\$|[ ,\]])"; then
      rules_to_inject+=("$f")
      break
    fi
  done
done

(( ${#rules_to_inject[@]} == 0 )) && exit 0

printf '<rules-preguard tool="%s">\n' "$tool_name"
printf 'Rules applicable to this %s call:\n\n' "$tool_name"
for f in "${rules_to_inject[@]}"; do
  title=$(awk '/^title:/{sub(/^title: */,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit}' "$f")
  rule_line=$(awk '/^\*\*Rule:\*\*/{sub(/^\*\*Rule:\*\* */,""); print; exit}' "$f")
  how_line=$(awk '/^\*\*How to apply:\*\*/{sub(/^\*\*How to apply:\*\* */,""); print; exit}' "$f")
  printf -- '- **%s** — %s\n' "$title" "${rule_line:-}"
  [[ -n "$how_line" ]] && printf '  *How:* %s\n' "$how_line"
done
printf '</rules-preguard>\n'

exit 0
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/rules-preguard.sh`

- [ ] **Step 3: Verify vault Write triggers vault rules**

```bash
mkdir -p /tmp/rules-test/rules
cp vault-template/rules/*.md vault-template/rules/.config.example.yml /tmp/rules-test/rules/
mv /tmp/rules-test/rules/.config.example.yml /tmp/rules-test/rules/.config.yml

VAULT_DIR=/tmp/rules-test \
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$HOME"'/vault/test.md"}}' \
  | VAULT_DIR=/tmp/rules-test ./scripts/rules-preguard.sh
```
Expected: `<rules-preguard tool="Write">` block with `No secrets in vault notes` and `Resolve relative dates in vault notes` listed.

```bash
# Non-vault Write → only tool:Write rules (none in seed)
VAULT_DIR=/tmp/rules-test \
  echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/somewhere-else.md"}}' \
  | VAULT_DIR=/tmp/rules-test ./scripts/rules-preguard.sh
```
Expected: silent (no tool:Write scoped rules in the seed set).

- [ ] **Step 4: Clean up**

Run: `rm -rf /tmp/rules-test`

- [ ] **Step 5: Commit**

```bash
git add scripts/rules-preguard.sh
git commit -m "feat(hooks): PreToolUse scope-matched rules injection"
```

---

## Task 7: Wire new hooks + statusline into `claude-global/settings.json`

**Files:**
- Modify: `claude-global/settings.json`

- [ ] **Step 1: Replace the file with the full updated version**

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/scripts/rules-statusline.sh"
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/scripts/vault-sync-pull.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "~/scripts/vault-sync-commit.sh",
            "timeout": 30
          },
          {
            "type": "command",
            "command": "~/scripts/rules_rebuild_if_rule_changed.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/scripts/vault-note-trigger-reminder.sh",
            "timeout": 5
          },
          {
            "type": "command",
            "command": "~/scripts/rules-reminder.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "~/scripts/vault-secret-guard.sh",
            "timeout": 5
          },
          {
            "type": "command",
            "command": "~/scripts/rules-preguard.sh",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/scripts/rules-preguard.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Verify JSON validity**

Run: `jq . claude-global/settings.json >/dev/null && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add claude-global/settings.json
git commit -m "feat(hooks): wire rules-system hooks + statusline"
```

---

## Task 8: Create `/add-rule` slash command

**Files:**
- Create: `claude-global/commands/add-rule.md`

- [ ] **Step 1: Create the directory**

Run: `mkdir -p claude-global/commands`

- [ ] **Step 2: Write the command definition**

```markdown
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
```

- [ ] **Step 3: Verify it's valid markdown**

Run: `head -4 claude-global/commands/add-rule.md`
Expected: starts with `---` frontmatter block.

- [ ] **Step 4: Commit**

```bash
git add claude-global/commands/
git commit -m "feat(commands): /add-rule scaffolds rule files + rebuilds index"
```

---

## Task 9: Add `.groups.template` to vault-template

**Files:**
- Create: `vault-template/.groups.template`

- [ ] **Step 1: Write the template**

```
# Project groups — one slug per line, kebab-case.
# Uncomment or edit to match your projects. `setup.sh` reads this on first
# install; you can also edit ~/vault/.groups directly at any time.
#
# Examples:
# work
# personal
# research
# client-acme
```

- [ ] **Step 2: Verify**

Run: `cat vault-template/.groups.template | head -3`
Expected: file exists with commented examples.

- [ ] **Step 3: Commit**

```bash
git add vault-template/.groups.template
git commit -m "feat(setup): ship .groups template for first-install prompt"
```

---

## Task 10: `setup.sh` — add `--scripts-dir` flag and template paths into `settings.json`

**Files:**
- Modify: `setup.sh`

- [ ] **Step 1: Add the flag parser and templating logic**

Edit `setup.sh`:

**After the `SCRIPTS_DIR="$HOME/scripts"` line (around line 18), add nothing (keep default). The default stays `~/scripts`.**

**Modify the argument parsing loop (around lines 26-40) to add `--scripts-dir`:**

Change:
```bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-pip)   INSTALL_PIP=0 ;;
    --no-embed) INSTALL_EMBED=0 ;;
    --cron)     INSTALL_CRON=1 ;;
    --vault)    VAULT_DIR="$2"; shift ;;
    --groups)   MEM_GROUPS="$2"; shift ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'
      exit 0
      ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done
```

To:
```bash
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-pip)      INSTALL_PIP=0 ;;
    --no-embed)    INSTALL_EMBED=0 ;;
    --cron)        INSTALL_CRON=1 ;;
    --vault)       VAULT_DIR="$2"; shift ;;
    --groups)      MEM_GROUPS="$2"; shift ;;
    --scripts-dir) SCRIPTS_DIR="$2"; shift ;;
    --dry-run)     DRY_RUN=1 ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'
      exit 0
      ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done
```

**Update the header comment block (lines 4-11) to document the new flags:**

Change:
```bash
# Usage:
#   ./setup.sh                                 # prompts for groups
#   ./setup.sh --groups work,personal          # non-interactive
#   ./setup.sh --no-pip                        # skip all Python tools
#   ./setup.sh --no-embed                      # skip semantic search deps only
#   ./setup.sh --cron                          # daily chat-sync cron (Linux/macOS)
#   ./setup.sh --vault ~/mybrain               # custom vault location
```

To:
```bash
# Usage:
#   ./setup.sh                                 # prompts for groups
#   ./setup.sh --groups work,personal          # non-interactive
#   ./setup.sh --no-pip                        # skip all Python tools
#   ./setup.sh --no-embed                      # skip semantic search deps only
#   ./setup.sh --cron                          # daily chat-sync cron (Linux/macOS)
#   ./setup.sh --vault ~/mybrain               # custom vault location
#   ./setup.sh --scripts-dir ~/bin/claude      # custom scripts dir (default ~/scripts)
#   ./setup.sh --dry-run                       # print planned actions, write nothing
```

**Modify the "Hooks in ~/.claude/settings.json" block (around lines 125-142) to template SCRIPTS_DIR into the written settings.json:**

Change:
```bash
# 4b. Hooks in ~/.claude/settings.json
say "Wiring hooks into $CLAUDE_DIR/settings.json"
if command -v jq >/dev/null 2>&1; then
  target="$CLAUDE_DIR/settings.json"
  src="$REPO_DIR/claude-global/settings.json"
  if [[ -f "$target" ]]; then
    cp "$target" "$target.obsidian-memory.bak"
    jq -s '.[0].hooks = .[1].hooks | .[0]' "$target" "$src" > "$target.tmp" \
      && mv "$target.tmp" "$target" \
      && ok "merged hooks into existing settings.json (backup: settings.json.obsidian-memory.bak)"
  else
    cp "$src" "$target"
    ok "installed fresh settings.json with hooks"
  fi
  warn "Restart Claude Code for hook changes to take effect"
else
  warn "jq not installed — skipping settings.json merge. Install jq and re-run, or copy hooks block manually from claude-global/settings.json"
fi
```

To:
```bash
# 4b. Hooks + statusLine in ~/.claude/settings.json
say "Wiring hooks + statusline into $CLAUDE_DIR/settings.json (scripts dir: $SCRIPTS_DIR)"
if command -v jq >/dev/null 2>&1; then
  target="$CLAUDE_DIR/settings.json"
  src="$REPO_DIR/claude-global/settings.json"
  # Template the scripts dir into the source JSON (uses ~/scripts by default in repo).
  tmp_src="$(mktemp)"
  sed "s|~/scripts|${SCRIPTS_DIR/#$HOME/~}|g; s|\$HOME/scripts|$SCRIPTS_DIR|g" "$src" > "$tmp_src"

  if [[ $DRY_RUN -eq 1 ]]; then
    warn "DRY RUN — would merge these hooks into $target:"
    jq . "$tmp_src"
  elif [[ -f "$target" ]]; then
    cp "$target" "$target.obsidian-memory.bak"
    jq -s '.[0].hooks = .[1].hooks | .[0].statusLine = .[1].statusLine | .[0]' "$target" "$tmp_src" > "$target.tmp" \
      && mv "$target.tmp" "$target" \
      && ok "merged hooks + statusline into existing settings.json (backup: settings.json.obsidian-memory.bak)"
  else
    cp "$tmp_src" "$target"
    ok "installed fresh settings.json with hooks + statusline"
  fi
  rm -f "$tmp_src"
  [[ $DRY_RUN -eq 0 ]] && warn "Restart Claude Code for hook changes to take effect"
else
  warn "jq not installed — skipping settings.json merge. Install jq and re-run, or copy hooks block manually from claude-global/settings.json"
fi
```

**Note on the sed templating:** The source file uses literal `~/scripts/...` paths. When `SCRIPTS_DIR == $HOME/scripts`, the sed rewrite is a no-op. When it's different, the sed swaps them to the custom path (expanding the home-relative form back to tilde for cleanliness where possible).

- [ ] **Step 2: Verify syntax**

Run: `bash -n setup.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Test the dry-run flag**

Run: `./setup.sh --dry-run --scripts-dir /tmp/fakescripts --groups test 2>&1 | grep -i "dry run\|would" | head -5`
Expected: at least one `DRY RUN` line.

Note: `--dry-run` in THIS task only affects the settings.json merge. Fuller dry-run coverage is Task 11.

- [ ] **Step 4: Commit**

```bash
git add setup.sh
git commit -m "feat(setup): --scripts-dir flag + template SCRIPTS_DIR into settings.json"
```

---

## Task 11: `setup.sh` — flesh out `--dry-run` to cover all destructive steps

**Files:**
- Modify: `setup.sh`

- [ ] **Step 1: Add a `run` helper that respects DRY_RUN, and use it at every destructive step**

Edit `setup.sh` — after the `say`/`ok`/`warn` helpers (around line 44), add:

```bash
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '\033[1;35m dry\033[0m %s\n' "$*"
  else
    eval "$@"
  fi
}
```

- [ ] **Step 2: Replace destructive calls with `run`-wrapped versions at these sites:**

1. Vault tree creation (`mkdir -p`, `: > .groups`, `mkdir`) — wrap each.
2. Scripts copy (`cp ...*.py`, `cp ...*.sh`, `chmod +x`) — wrap each.
3. Pip installs (`"$PIP" install ...`) — wrap each.
4. Cron install (`crontab -` pipeline) — wrap.
5. The settings.json merge block from Task 10 already has dry-run handling — leave it.

For each such line, change e.g.:
```bash
mkdir -p "$VAULT_DIR"/{permanent,inbox,fleeting,templates,references,logs}
```
to:
```bash
run "mkdir -p \"$VAULT_DIR\"/{permanent,inbox,fleeting,templates,references,logs}"
```

Use your judgment for quoting: any `eval`-ed line must correctly escape paths. If a line has complex subshells or pipes, prefer wrapping the whole statement in a function call rather than inline.

- [ ] **Step 3: Verify dry-run makes no filesystem changes**

```bash
tmp_home=$(mktemp -d)
HOME="$tmp_home" ./setup.sh --dry-run --groups test --no-pip --vault "$tmp_home/vault" --scripts-dir "$tmp_home/scripts" 2>&1 | tail -20
echo "---"
ls "$tmp_home"
```
Expected: `--dry-run` prints `dry` lines for every operation; `ls "$tmp_home"` shows nothing (no vault created).

- [ ] **Step 4: Clean up**

Run: `rm -rf "$tmp_home"`

- [ ] **Step 5: Commit**

```bash
git add setup.sh
git commit -m "feat(setup): --dry-run covers all destructive steps"
```

---

## Task 12: `setup.sh` — install `vault-template/rules/` into `~/vault/rules/` on first run; handle `.groups.template`

**Files:**
- Modify: `setup.sh`

- [ ] **Step 1: Update the groups detection block (around lines 46-56) to read the template**

Change:
```bash
# 0. Groups
if [[ -z "$MEM_GROUPS" ]]; then
  if [[ -f "$VAULT_DIR/.groups" ]]; then
    MEM_GROUPS="$(tr '\n' ',' < "$VAULT_DIR/.groups")"
    MEM_GROUPS="${MEM_GROUPS%,}"
    ok "reusing existing groups: $MEM_GROUPS"
  else
    read -rp "Project groups (comma-separated, e.g. work,personal,research): " MEM_GROUPS
    [[ -z "$MEM_GROUPS" ]] && MEM_GROUPS="work,personal"
  fi
fi
```

To:
```bash
# 0. Groups
if [[ -z "$MEM_GROUPS" ]]; then
  if [[ -f "$VAULT_DIR/.groups" ]]; then
    MEM_GROUPS="$(tr '\n' ',' < "$VAULT_DIR/.groups")"
    MEM_GROUPS="${MEM_GROUPS%,}"
    ok "reusing existing groups: $MEM_GROUPS"
  else
    template="$REPO_DIR/vault-template/.groups.template"
    if [[ -f "$template" ]]; then
      echo "Groups live in ~/vault/.groups — one slug per line. Examples from template:"
      grep -v '^#' "$template" | grep -v '^$' | sed 's/^/  /'
      echo "(none shown if the template has only commented examples)"
    fi
    read -rp "Project groups (comma-separated, e.g. work,personal,research): " MEM_GROUPS
    [[ -z "$MEM_GROUPS" ]] && MEM_GROUPS="work,personal"
  fi
fi
```

- [ ] **Step 2: Add a new block after the "Vault CLAUDE.md" step (around line 104) — install the rules dir**

Insert after line 104 (before `# 3. Global Claude Code instructions`):

```bash
# 2b. Rules system — ~/vault/rules/
if [[ ! -d "$VAULT_DIR/rules" ]]; then
  run "mkdir -p \"$VAULT_DIR/rules\""
  run "cp \"$REPO_DIR/vault-template/rules/\"*.md \"$VAULT_DIR/rules/\""
  run "cp \"$REPO_DIR/vault-template/rules/.config.example.yml\" \"$VAULT_DIR/rules/.config.yml\""
  ok "installed rules scaffold into $VAULT_DIR/rules (edit .config.yml to tune reminder interval)"
else
  warn "$VAULT_DIR/rules already exists — leaving rule files alone. Update .config.yml manually if needed."
fi

# Seed ~/vault/rules.md by running the rebuilder once
if command -v "$SCRIPTS_DIR/rules_rebuild.py" >/dev/null 2>&1 || [[ -x "$SCRIPTS_DIR/rules_rebuild.py" ]]; then
  run "VAULT_DIR=\"$VAULT_DIR\" \"$SCRIPTS_DIR/rules_rebuild.py\" || true"
fi
```

Note: the rebuilder call may happen before the scripts are copied (step 4 is later). Move the rebuilder call to AFTER the scripts-install section — put it right after section 4b.

- [ ] **Step 3: Move the rebuilder invocation to after scripts are installed**

Remove the rebuilder lines from section 2b, and add at the end of section 4b (after the settings.json merge, before pip installs):

```bash
# 4c. Seed ~/vault/rules.md
if [[ -x "$SCRIPTS_DIR/rules_rebuild.py" ]]; then
  run "VAULT_DIR=\"$VAULT_DIR\" \"$SCRIPTS_DIR/rules_rebuild.py\" || true"
fi
```

- [ ] **Step 4: Verify with a fresh temp home**

```bash
tmp_home=$(mktemp -d)
HOME="$tmp_home" ./setup.sh --groups test --no-pip --vault "$tmp_home/vault" --scripts-dir "$tmp_home/scripts" 2>&1 | tail -20
echo "---"
ls "$tmp_home/vault/rules/"
echo "---"
cat "$tmp_home/vault/rules.md" | head -20
```
Expected: `rules/` directory contains README.md + seed rule files + `.config.yml`; `rules.md` has H2 scope sections.

- [ ] **Step 5: Clean up**

Run: `rm -rf "$tmp_home"`

- [ ] **Step 6: Commit**

```bash
git add setup.sh
git commit -m "feat(setup): install vault-template/rules → ~/vault/rules on first run"
```

---

## Task 13: Add hook JSON-contract header comments to existing vault-*.sh scripts

**Files:**
- Modify: `scripts/vault-secret-guard.sh`
- Modify: `scripts/vault-sync-commit.sh`
- Modify: `scripts/vault-sync-pull.sh`
- Modify: `scripts/vault-note-trigger-reminder.sh`

- [ ] **Step 1: `vault-secret-guard.sh` — already has a header, just add JSON-contract section**

After the existing header block (before `set -u`), add:

```bash
# Hook JSON contract (stdin):
#   .tool_name                       "Write" | "Edit" | "MultiEdit"
#   .tool_input.file_path            target path (Write, Edit)
#   .tool_input.notebook_path        fallback
#   .tool_input.content              new content (Write)
#   .tool_input.new_string           new content (Edit)
#   .tool_input.edits[].new_string   per-edit content (MultiEdit)
#
# Return contract:
#   exit 0 + empty stdout        → allow
#   exit 0 + JSON deny on stdout → block with structured reason
```

- [ ] **Step 2: `vault-sync-commit.sh` — add hook contract docs**

After the existing header comment, add:

```bash
# Hook JSON contract (stdin):
#   .tool_input.file_path     target path (Write, Edit)
#   .tool_response.filePath   fallback (some tools set this after success)
#
# Scope: fires on PostToolUse for Write|Edit|MultiEdit; no-op if target is
# outside ~/vault/.
```

- [ ] **Step 3: `vault-sync-pull.sh` — add hook contract docs**

At the top (after shebang), add:

```bash
# SessionStart hook: `git pull --ff-only` in ~/vault and ~/obsidian-memory,
# throttled to once per 12h per repo (timestamp in ~/.claude/.last-pull).
#
# Hook JSON contract (stdin): unused — SessionStart carries no tool context.
```

- [ ] **Step 4: `vault-note-trigger-reminder.sh` — add hook contract docs**

At the top (after shebang), add:

```bash
# UserPromptSubmit hook: injects the proactive-note-writer trigger checklist
# as a system-reminder every user turn.
#
# Hook JSON contract (stdin):
#   .prompt     the user's message text
#   .cwd        working directory (unused here)
#
# Output: writes a <system-reminder>…</system-reminder> block to stdout;
# Claude Code attaches it to the current turn's context.
```

- [ ] **Step 5: Verify all scripts still parse**

Run: `for f in scripts/vault-*.sh; do bash -n "$f" && echo "ok $f"; done`
Expected: all four scripts emit `ok`.

- [ ] **Step 6: Commit**

```bash
git add scripts/vault-secret-guard.sh scripts/vault-sync-commit.sh scripts/vault-sync-pull.sh scripts/vault-note-trigger-reminder.sh
git commit -m "docs(hooks): document hook JSON contract for existing vault scripts"
```

---

## Task 14: Update `vault-template/CLAUDE.md` with the rules-system section

**Files:**
- Modify: `vault-template/CLAUDE.md`

- [ ] **Step 1: Read the existing file to find the right insertion point**

Run: `grep -n '^## ' vault-template/CLAUDE.md`

- [ ] **Step 2: Insert a "Rules system" section near the top (after "Project groups" section)**

Add this block (use the grep output to find the exact anchor — insert right before the `## Zettelkasten rules` header):

```markdown
## Rules system

Behavior rules live in `~/vault/rules/`. One file per rule; filenames are kebab-case slugs. The index at `~/vault/rules.md` is auto-generated by `~/scripts/rules_rebuild.py` — do not hand-edit it.

**Authoring:** easiest path is `/add-rule <title>` from any Claude Code session. Alternatively, create a file manually and run the rebuilder. See `~/vault/rules/README.md` for frontmatter format.

**Enforcement:** three hooks wired in `~/.claude/settings.json` (installed by `obsidian-memory/setup.sh`):

1. `UserPromptSubmit` → `rules-reminder.sh` — every Nth turn, injects scope-matched rules as a system-reminder.
2. `PreToolUse` on Write/Edit/Bash → `rules-preguard.sh` — injects rules whose scope matches the target.
3. `statusLine` → `rules-statusline.sh` — shows `📋 N rules · next reminder in K turns`.

**Tuning:** edit `~/vault/rules/.config.yml` — change `reminder_interval` (default 10), toggle `statusline_enabled` / `preguard_enabled`, or list scopes in `blocked_scopes` to silence them temporarily.

**Scope values:** `global` · `<group-slug>` · `vault` · `tool:<ToolName>`. Multiple scopes via list: `scope: [global, vault]`.
```

- [ ] **Step 3: Verify**

Run: `grep -c '## Rules system' vault-template/CLAUDE.md`
Expected: `1`.

- [ ] **Step 4: Commit**

```bash
git add vault-template/CLAUDE.md
git commit -m "docs(vault): document rules system in vault CLAUDE.md"
```

---

## Task 15: Update `claude-global/CLAUDE.md` with the rules-system section

**Files:**
- Modify: `claude-global/CLAUDE.md`

- [ ] **Step 1: Find the "Writing rules inside the vault" section and replace it**

The current file (verified at `/home/jas/obsidian-memory/claude-global/CLAUDE.md`) has this section near the end (search for `## Writing rules inside the vault`):

```markdown
## Writing rules inside the vault

- Wikilinks `[[like-this]]`, not markdown links.
- Kebab-case filenames.
- YAML frontmatter on every permanent note.
- Tag with the group (`#<group>`).
- Minimum two wikilinks per permanent note.
```

This section is about **writing vault notes**, not rules-system rules. Keep it but rename the heading to avoid ambiguity:

Rename to:
```markdown
## Vault note conventions
```

- [ ] **Step 2: Add a NEW "Rules system" section BEFORE `## Safety`**

Insert this block:

```markdown
## Rules system (behavior rules, authored by user)

Behavior rules that modify Claude's actions live in `~/vault/rules/` (one file per rule). The index at `~/vault/rules.md` is auto-generated.

**You (Claude) do not write to `~/vault/rules/` directly.** Rules are authored by the user via `/add-rule` or manual edits. The `rules-reminder.sh` UserPromptSubmit hook and `rules-preguard.sh` PreToolUse hook inject scope-matched rules into context at runtime — treat those injected blocks as standing orders for the current turn.

**When the user dictates a new rule** ("always do X" / "from now on Y"):
1. Confirm the rule wording with the user.
2. Ask for `scope` (global / group / vault / tool:<Name>).
3. Invoke `/add-rule` or scaffold the file directly at `~/vault/rules/<slug>.md`.
4. Do NOT save as auto-memory feedback — that's scoped to one project and defeats cross-project reuse.

**Precedence** when rules from multiple sources conflict: user's direct message this turn > `~/vault/rules/` > per-repo `CLAUDE.md` > this file > model defaults.

**Tuning:** the user changes reminder cadence in `~/vault/rules/.config.yml` (`reminder_interval`). Don't edit that file unless the user explicitly asks.
```

- [ ] **Step 3: Verify**

Run: `grep -c '^## Rules system' claude-global/CLAUDE.md`
Expected: `1`.

- [ ] **Step 4: Commit**

```bash
git add claude-global/CLAUDE.md
git commit -m "docs(global): document rules system + auto-memory routing guidance"
```

---

## Task 16: Migrate the date-resolution rule and clean up auto-memory

**Files:**
- Delete (off-repo): `~/.claude/projects/-home-jas-obsidian-memory/memory/feedback_resolve_relative_dates.md`
- Delete (off-repo): `~/.claude/projects/-home-jas-obsidian-memory/memory/MEMORY.md`

This task runs on the user's machine. No repo changes — the vault-template already ships `vault-dates.md` as part of Task 1.

- [ ] **Step 1: Confirm the vault-dates rule is installed at `~/vault/rules/vault-dates.md`**

Run: `test -f ~/vault/rules/vault-dates.md && echo OK || echo MISSING`

If `MISSING`: re-run `./setup.sh` or manually `cp vault-template/rules/vault-dates.md ~/vault/rules/ && ~/scripts/rules_rebuild.py`.

- [ ] **Step 2: Verify the rule appears in the generated index**

Run: `grep -c 'Resolve relative dates' ~/vault/rules.md`
Expected: at least `1`.

- [ ] **Step 3: Delete the superseded auto-memory files**

Run:
```bash
rm -f ~/.claude/projects/-home-jas-obsidian-memory/memory/feedback_resolve_relative_dates.md
rm -f ~/.claude/projects/-home-jas-obsidian-memory/memory/MEMORY.md
rmdir ~/.claude/projects/-home-jas-obsidian-memory/memory 2>/dev/null || true
```

- [ ] **Step 4: Auto-commit + push the vault**

Run:
```bash
cd ~/vault
git add -A
git commit -m "feat(rules): migrate date-resolution rule from auto-memory" 2>/dev/null || true
git push 2>/dev/null || true
cd -
```

Expected: either "nothing to commit" (vault already committed during Task 12) or a new commit pushed.

No repo commit — nothing changed in the repo for this task.

---

## Task 17: Update top-level `README.md` with three new sections

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Inspect the current README structure**

Run: `grep -n '^##' README.md`

- [ ] **Step 2: Add "Rules system (author → enforce)" section**

Choose an insertion point right before the existing `## Credential hygiene` or `## Troubleshooting` section (whichever comes first — use the grep output to decide). Add:

```markdown
## Rules system (author → enforce)

Durable behavior rules for Claude live in `~/vault/rules/` — one file per rule, kebab-case slug, YAML frontmatter. The index at `~/vault/rules.md` is auto-generated.

### Author a rule

Easiest: in any Claude Code session, run

    /add-rule "resolve relative dates in vault notes"

The slash command scaffolds the file, prompts for scope + priority, and regenerates the index. Alternatively, create `~/vault/rules/<slug>.md` by hand — see `~/vault/rules/README.md` for the format.

### Scope values (closed set)

| scope | active when |
|-------|-------------|
| `global` | every session, every project |
| `<group>` | active group in `~/vault/.groups` matches |
| `vault` | tool target is inside `~/vault/` |
| `tool:<Name>` | before that specific tool fires (e.g. `tool:Write`, `tool:Bash`) |

Multiple scopes: `scope: [global, vault]`.

### Enforcement mechanisms

- **UserPromptSubmit hook** — `rules-reminder.sh` injects scope-matched rules every N turns.
- **PreToolUse hook** — `rules-preguard.sh` injects rules matching `vault` or `tool:<Name>` before Write/Edit/Bash.
- **Statusline** — `rules-statusline.sh` renders `📋 N rules · next reminder in K turns` persistently.
```

- [ ] **Step 3: Add "Tuning the rules reminder" section (directly after the above)**

```markdown
## Tuning the rules reminder

Config lives in `~/vault/rules/.config.yml` (not in this repo — so teammates tune independently). Change one line:

```yaml
reminder_interval: 10    # change to 5 for more reliable, more expensive
```

Tradeoff: lower N = Claude forgets less + higher token cost per conversation. Higher N = cheaper + more drift between reminders. Start at 10, adjust as needed.

Other fields:

- `statusline_enabled: true|false` — toggle the `📋 …` statusline.
- `preguard_enabled: true|false` — toggle scope-matched injection before Write/Edit/Bash.
- `blocked_scopes: [arc, research]` — silence whole scopes temporarily without deleting rule files.

Hooks re-read the config on every fire. No restart needed.
```

- [ ] **Step 4: Add "For teammates: getting set up" section**

Place near the top of the README (right after the main description / before any installation section) OR at the end as an onboarding appendix — check `grep -n '^##' README.md` to see what makes sense. Add:

```markdown
## For teammates: getting set up

Three minutes, five steps:

1. **Clone this repo:**
   ```bash
   git clone https://github.com/Jassie22/obsidian-memory.git
   cd obsidian-memory
   ```

2. **Run setup:**
   ```bash
   ./setup.sh --groups work,personal     # or --groups <yours>
   ```
   Flags: `--scripts-dir <path>` for a custom scripts location (default `~/scripts`), `--dry-run` to preview, `--vault <path>` for a custom vault location (default `~/vault`).

3. **Make your vault a private git repo** (each teammate has their own vault — notes are personal):
   ```bash
   cd ~/vault
   git init && git add -A && git commit -m "initial vault"
   git remote add origin <your-private-remote-url>   # MUST be private
   git push -u origin main
   ```

4. **Edit `~/vault/rules/.config.yml`** if you want a different reminder cadence (default 10).

5. **Restart Claude Code** — hooks take effect only on next session.

That's it. `/resume`, `/save`, `/recall`, `/capture`, `/promote`, `/add-rule` are all available in every project.
```

- [ ] **Step 5: Verify all three sections are present**

Run: `grep -c '^## Rules system\|^## Tuning the rules reminder\|^## For teammates' README.md`
Expected: `3`.

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs(readme): rules system + tuning + teammate onboarding sections"
```

---

## Task 18: End-to-end smoke test

This task has no file changes — it verifies the full pipeline works after all previous tasks.

- [ ] **Step 1: Run `./setup.sh --dry-run` from a clean temp home**

```bash
tmp_home=$(mktemp -d)
HOME="$tmp_home" ./setup.sh --dry-run --groups test --no-pip \
  --vault "$tmp_home/vault" --scripts-dir "$tmp_home/scripts" 2>&1 | tail -30
```
Expected: many `dry` lines, no actual file creation. `ls "$tmp_home"` should still be empty.

- [ ] **Step 2: Run `./setup.sh` for real against the temp home**

```bash
HOME="$tmp_home" ./setup.sh --groups test --no-pip \
  --vault "$tmp_home/vault" --scripts-dir "$tmp_home/scripts" 2>&1 | tail -30
```
Expected: vault tree created, scripts installed, settings.json written, rules.md generated.

- [ ] **Step 3: Verify each component**

```bash
# Rule files installed
ls "$tmp_home/vault/rules/"
# Config installed
cat "$tmp_home/vault/rules/.config.yml" | head -5
# Index generated
head -20 "$tmp_home/vault/rules.md"
# Scripts installed
ls "$tmp_home/scripts/" | grep -E 'rules-|rules_'
# Settings.json has rules hooks
jq '.hooks.UserPromptSubmit, .hooks.PreToolUse, .statusLine' "$tmp_home/.claude/settings.json" | grep -E 'rules-'
```

Expected: rule files present, config present, index has scope sections, scripts present (at least 4: `rules_rebuild.py`, `rules_rebuild_if_rule_changed.sh`, `rules-reminder.sh`, `rules-preguard.sh`, `rules-statusline.sh`), settings.json references at least three rules-* commands.

- [ ] **Step 4: Simulate the reminder hook firing**

```bash
rm -f "$tmp_home/.claude/.rules-turn-counter-smoke"
VAULT_DIR="$tmp_home/vault" \
  echo '{"session_id":"smoke","cwd":"'"$tmp_home/vault"'"}' \
  | VAULT_DIR="$tmp_home/vault" "$tmp_home/scripts/rules-reminder.sh"
```
Expected: `<rules-reminder>` block with at least the `Be terse` + 2 vault-scoped rules.

- [ ] **Step 5: Simulate preguard firing on a vault Write**

```bash
VAULT_DIR="$tmp_home/vault" \
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$tmp_home/vault/test.md"'"}}' \
  | VAULT_DIR="$tmp_home/vault" "$tmp_home/scripts/rules-preguard.sh"
```
Expected: `<rules-preguard tool="Write">` block with `No secrets` + `Resolve relative dates`.

- [ ] **Step 6: Simulate statusline**

```bash
VAULT_DIR="$tmp_home/vault" \
  echo '{"session_id":"smoke","workspace":{"current_dir":"'"$tmp_home/vault"'"}}' \
  | VAULT_DIR="$tmp_home/vault" "$tmp_home/scripts/rules-statusline.sh"
```
Expected: `📋 N rules · next reminder in K turns` for some N ≥ 2.

- [ ] **Step 7: Clean up**

Run: `rm -rf "$tmp_home"`

- [ ] **Step 8: No commit — this is a verification-only task.**

If any step fails, go back and fix the component, then re-run.

---

## Task 19: Production install on the user's machine + final sync

- [ ] **Step 1: Run the real setup against the actual `~/vault` and `~/scripts`**

```bash
./setup.sh --groups "$(tr '\n' ',' < ~/vault/.groups | sed 's/,$//')"
```

Expected: new rule scripts appear in `~/scripts/`, `~/vault/rules/` is created with seed files, `~/vault/rules.md` is generated, `~/.claude/settings.json` has the new hooks + statusLine entries. Existing vault notes untouched.

- [ ] **Step 2: Delete the superseded auto-memory entries (Task 16)**

```bash
rm -f ~/.claude/projects/-home-jas-obsidian-memory/memory/feedback_resolve_relative_dates.md
rm -f ~/.claude/projects/-home-jas-obsidian-memory/memory/MEMORY.md
rmdir ~/.claude/projects/-home-jas-obsidian-memory/memory 2>/dev/null || true
```

- [ ] **Step 3: Push the vault**

```bash
cd ~/vault && git add -A && git commit -m "feat(rules): install rules-system scaffold" && git push
cd -
```

- [ ] **Step 4: Restart Claude Code**

Tell the user: "Restart Claude Code for the new hooks + statusline to take effect. After restart, the statusline should show `📋 N rules · next reminder in K turns`."

- [ ] **Step 5: User verifies the statusline appears**

Manual check by the user: open a new Claude Code session, confirm the statusline reads `📋 3 rules · next reminder in ...` (or similar based on seed count).

- [ ] **Step 6: No commit — production install has no repo changes beyond what previous tasks already committed.**

---

## Self-review checklist (completed during plan writing)

- ✅ Spec coverage — every section of the spec maps to at least one task:
  - Rule file format + scope values → Task 1 + rebuilder validates
  - Rebuilder → Task 2
  - PostToolUse rebuild-on-change → Task 3
  - Statusline → Task 4, wired in Task 7
  - UserPromptSubmit reminder → Task 5, wired in Task 7
  - PreToolUse preguard → Task 6, wired in Task 7
  - `/add-rule` slash command → Task 8
  - `.groups.template` → Task 9
  - `--scripts-dir` + settings templating → Task 10
  - `--dry-run` → Task 11
  - Install rules into vault on first setup → Task 12
  - Hook JSON contract comments → Task 13
  - Vault CLAUDE.md rules section → Task 14
  - Global CLAUDE.md rules section + routing guidance → Task 15
  - Seed rule migration → Task 16, re-stated in Task 19
  - README three new sections → Task 17
  - End-to-end verification → Task 18
  - Production install → Task 19
- ✅ No placeholder content — every code block is complete.
- ✅ Type consistency — hook script names, frontmatter field names, and scope values are consistent across tasks (`scope`, `priority`, `enforcement`, `status`; `rules-reminder.sh`, `rules-preguard.sh`, `rules-statusline.sh`, `rules_rebuild.py`).
- ✅ Scope check — tightly coupled (rules system + shareability). One plan is correct.

## Execution note

Tasks 1-13 are repo changes with commits. Tasks 14-17 are more repo changes with commits. Task 18 is verification-only. Tasks 16 and 19 include off-repo steps (user's `~/vault`, `~/.claude`). When running in subagent-driven mode, flag Tasks 16 and 19 as requiring the user's actual machine, not a sandbox worktree.

After each task's commit, push is optional — the repo's global rule says push after memory-system changes. Safe to batch: push once after Task 17, then one more push after Task 19 for the vault side.

---

## Task 20: Autodelete empty notes — integrate into existing rebuilders

**Context:** The user explicitly asked (2026-04-22) for empty notes to be autodeleted. "Empty" = note with frontmatter only and no body content (whitespace after the closing `---` doesn't count). Files to skip (never delete, even if empty): `_MOC.md`, `rules.md`, `README.md`, anything under `templates/`, any file with `status: active` that is less than 24h old (might be in-progress).

**Files:**
- Modify: `scripts/vault_rebuild_mocs.py`
- Modify: `scripts/rules_rebuild.py` (from T2)
- Modify: `scripts/vault_search.py`
- Create: `scripts/vault_clean_empty.py` (standalone sweep)

- [ ] **Step 1: Add `is_empty_body(body: str) -> bool` helper to `vault_rebuild_mocs.py`**

Insert near the top of `vault_rebuild_mocs.py` (after the existing `extract_tags` / `description` helpers):

```python
def is_empty_body(body: str) -> bool:
    """Return True if the body has no real content (only whitespace / blank lines)."""
    return body.strip() == ""
```

- [ ] **Step 2: In `vault_rebuild_mocs.py`, skip empty notes and autodelete those older than 24h**

Find the loop that walks notes and builds MOC entries. Before emitting each entry, add:

```python
import time
SAFE_AGE_SECONDS = 24 * 3600
SKIP_DELETE_NAMES = {"_MOC.md", "rules.md", "README.md"}
SKIP_DELETE_PARENTS = {"templates", "rules"}  # rules dir is managed by rules_rebuild.py

def should_delete_empty(path: pathlib.Path) -> bool:
    if path.name in SKIP_DELETE_NAMES:
        return False
    if any(parent.name in SKIP_DELETE_PARENTS for parent in path.parents):
        return False
    try:
        age = time.time() - path.stat().st_mtime
    except OSError:
        return False
    return age >= SAFE_AGE_SECONDS
```

In the walk loop, when processing each note file:

```python
fm, body = parse_frontmatter(text)
if is_empty_body(body):
    if should_delete_empty(note_path):
        note_path.unlink()
        print(f"deleted empty note: {note_path.relative_to(VAULT)}", file=sys.stderr)
    # Either way, skip indexing
    continue
```

- [ ] **Step 3: Mirror the same logic in `rules_rebuild.py`**

In `load_rules()` (from T2), after parsing frontmatter:

```python
if is_empty_body(body):
    # Rule files with no body — skip. Do NOT delete; user may be about to fill in via /add-rule.
    continue
```

Do NOT autodelete rule files — they're actively authored; a freshly scaffolded rule from `/add-rule` will be empty for a few minutes.

Copy the `is_empty_body` helper into `rules_rebuild.py` directly (small, no need for shared import).

- [ ] **Step 4: Skip empty notes in `vault_search.py` indexer**

In the file-walk that feeds the embedding indexer, add an early skip:

```python
# after reading text + parsing frontmatter
if not body.strip():
    continue
```

Place this in the main `index` subcommand's walk loop. Keep `find-similar` / `search` unchanged — they read the existing index.

- [ ] **Step 5: Create `scripts/vault_clean_empty.py` — standalone sweep**

```python
#!/home/jas/.venvs/vault/bin/python3
"""
Find and delete empty vault notes (frontmatter-only, no body).

Respects safety gates: files less than 24h old, files in protected
directories (templates/, rules/), and reserved filenames (_MOC.md, rules.md,
README.md) are never deleted.

Usage:
  vault_clean_empty.py                # dry-run, lists candidates
  vault_clean_empty.py --delete       # actually delete
"""
from __future__ import annotations
import argparse, os, pathlib, re, sys, time

VAULT = pathlib.Path(os.environ.get("VAULT_DIR", pathlib.Path.home() / "vault"))
SAFE_AGE_SECONDS = 24 * 3600
SKIP_DELETE_NAMES = {"_MOC.md", "rules.md", "README.md"}
SKIP_DELETE_PARENTS = {"templates", "rules"}
FM_RE = re.compile(r"\A---\n(.*?)\n---\n?(.*)\Z", re.DOTALL)


def has_empty_body(path: pathlib.Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return False
    m = FM_RE.match(text)
    body = m.group(2) if m else text
    return body.strip() == ""


def is_protected(path: pathlib.Path) -> bool:
    if path.name in SKIP_DELETE_NAMES:
        return True
    if any(parent.name in SKIP_DELETE_PARENTS for parent in path.parents):
        return True
    return False


def old_enough(path: pathlib.Path) -> bool:
    try:
        return (time.time() - path.stat().st_mtime) >= SAFE_AGE_SECONDS
    except OSError:
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--delete", action="store_true", help="actually delete (default: dry run)")
    args = ap.parse_args()

    candidates = []
    for f in VAULT.rglob("*.md"):
        if is_protected(f):
            continue
        if not has_empty_body(f):
            continue
        if not old_enough(f):
            continue
        candidates.append(f)

    if not candidates:
        print("no empty notes to delete")
        return

    for c in candidates:
        rel = c.relative_to(VAULT)
        if args.delete:
            c.unlink()
            print(f"deleted: {rel}")
        else:
            print(f"[dry-run] would delete: {rel}")

    if not args.delete:
        print(f"\n{len(candidates)} candidates. Run with --delete to remove.")


if __name__ == "__main__":
    main()
```

- [ ] **Step 6: Make it executable**

Run: `chmod +x scripts/vault_clean_empty.py`

- [ ] **Step 7: Verify all three integrations**

```bash
# Set up test vault
tmp=$(mktemp -d)
mkdir -p "$tmp/arc"
# empty note, old → should be deleted by MOC rebuilder
cat > "$tmp/arc/empty-old.md" <<EOF
---
title: Empty old
group: arc
tags: [arc]
---
EOF
touch -d "2 days ago" "$tmp/arc/empty-old.md"
# empty note, fresh → should be skipped but NOT deleted
cat > "$tmp/arc/empty-fresh.md" <<EOF
---
title: Empty fresh
group: arc
tags: [arc]
---
EOF
# full note → should appear in MOC
cat > "$tmp/arc/real.md" <<EOF
---
title: Real note
group: arc
tags: [arc]
---

This note has content.
EOF
echo "arc" > "$tmp/.groups"

VAULT_DIR="$tmp" scripts/vault_rebuild_mocs.py 2>&1 | head -5
ls "$tmp/arc/"
```

Expected: `empty-old.md` deleted; `empty-fresh.md` remains on disk but absent from the MOC; `real.md` listed in MOC.

- [ ] **Step 8: Verify the standalone cleaner**

```bash
# dry run
VAULT_DIR="$tmp" scripts/vault_clean_empty.py
# touch fresh file backwards in time
touch -d "2 days ago" "$tmp/arc/empty-fresh.md"
VAULT_DIR="$tmp" scripts/vault_clean_empty.py --delete
ls "$tmp/arc/"
```
Expected: dry-run lists nothing (the one old file was already deleted by the MOC rebuilder); after aging + `--delete`, the fresh file also gets removed.

- [ ] **Step 9: Clean up**

Run: `rm -rf "$tmp"`

- [ ] **Step 10: Commit**

```bash
git add scripts/vault_rebuild_mocs.py scripts/rules_rebuild.py scripts/vault_search.py scripts/vault_clean_empty.py
git commit -m "feat(vault): autodelete empty notes older than 24h; skip empty in indexes"
```

---

## Task 21: Add `/clean-empty` slash command

**Files:**
- Create: `claude-global/commands/clean-empty.md`

- [ ] **Step 1: Create the command definition**

```markdown
---
description: List or delete empty vault notes (frontmatter only, no body) older than 24h.
argument-hint: [--delete]
---

# /clean-empty

List empty notes in `~/vault/`. By default dry-runs — shows candidates only. With `--delete`, actually removes them.

## Steps

1. If the user passed `--delete` as the argument, run:
   ```
   ~/scripts/vault_clean_empty.py --delete
   ```
2. Otherwise run a dry scan:
   ```
   ~/scripts/vault_clean_empty.py
   ```
3. Summarise the output to the user. If dry-run and candidates exist, ask if they want to delete.
4. If the user says yes, re-run with `--delete`.
5. After any deletion, auto-commit + push the vault per global rules.

## Safety

- Protected paths (never deleted): `templates/`, `rules/`, `_MOC.md`, `rules.md`, `README.md`.
- Age gate: only files with mtime ≥ 24h are eligible for deletion. Fresher empty files stay alone.
- The cleaner is idempotent and safe to run anytime.
```

- [ ] **Step 2: Commit**

```bash
git add claude-global/commands/clean-empty.md
git commit -m "feat(commands): /clean-empty lists/deletes empty vault notes"
```


## Run log — 2026-04-22 cron

- Executed by remote cron agent (trigger `Rules system execution — 2026-04-22`).
- Tasks completed: T5, T6, T7, T8, T9, T10, T11, T12, T13, T14, T15, T17, T20, T21, T18
- Tasks skipped: T16 (migration note — requires local machine), T19 (production install — requires local env)
- Review loops:
  - T5 (1 fix): `printf '- **[%s]**...'` in rules-reminder.sh treated the leading `-` as a flag; fixed with `printf --`. Bug in the T5 plan code block.
  - T10 (1 fix + 1 conflict): Pre-existing bug in setup.sh — `IFS=',' read -ra MEM_GROUP_ARR < <(printf '%s' "$MEM_GROUPS")` exits 1 with `set -e` because `printf '%s'` has no trailing newline; fixed to `<<< "$MEM_GROUPS"`. Merge conflict in setup.sh on rebase (remote commit `1a86aa6` removed `--cron`); resolved by keeping remote's cron removal + my T10 additions.
  - T18 (1 fix): `rules-preguard.sh` used `"$HOME/vault/"*` instead of `"$VAULT/"*` for the vault scope check — so `VAULT_DIR` env var wasn't honoured. Fixed with a follow-up commit. Bug in the T6 plan code block.
  - T20: `rules_rebuild.py` already had `is_empty_body()` helper and the empty-body skip from the T2 commit; avoided duplicate definition.
- Residual issues: none — all verification steps passed after fixes.
- Final branch state: commit 82051a2 on rules-system
