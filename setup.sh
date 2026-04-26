#!/usr/bin/env bash
# Bootstrap the Claude Code + Obsidian memory setup.
# Idempotent: safe to re-run on an existing machine / vault.
#
# Usage:
#   ./setup.sh                                 # prompts for groups
#   ./setup.sh --groups work,personal          # non-interactive
#   ./setup.sh --no-pip                        # skip all Python tools
#   ./setup.sh --no-embed                      # skip semantic search deps only
#   ./setup.sh --vault ~/mybrain               # custom vault location
#   ./setup.sh --scripts-dir ~/bin/claude      # custom scripts dir (default ~/scripts)
#   ./setup.sh --dry-run                       # print planned actions, write nothing
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="${VAULT_DIR:-$HOME/vault}"
CLAUDE_DIR="$HOME/.claude"
SCRIPTS_DIR="$HOME/scripts"

INSTALL_PIP=1
INSTALL_EMBED=1
MEM_GROUPS=""

DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-pip)      INSTALL_PIP=0 ;;
    --no-embed)    INSTALL_EMBED=0 ;;
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

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '\033[1;35m dry\033[0m %s\n' "$*"
  else
    eval "$@"
  fi
}

# Best-effort jq install across macOS / Linux / Windows (Git Bash, MSYS).
# Returns 0 if jq is already present or successfully installed, 1 otherwise.
ensure_jq() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '\033[1;35m dry\033[0m would install jq via OS package manager\n'
    return 0
  fi
  say "jq not found — attempting auto-install"
  local uname_s
  uname_s="$(uname -s 2>/dev/null || echo unknown)"
  case "$uname_s" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        brew install jq && return 0
      else
        warn "brew not found on macOS — install Homebrew or jq manually"
      fi
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y && sudo apt-get install -y jq && return 0
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y jq && return 0
      elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y jq && return 0
      elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm jq && return 0
      elif command -v apk >/dev/null 2>&1; then
        sudo apk add --no-cache jq && return 0
      else
        warn "no recognised Linux package manager — install jq manually"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      # Windows under Git Bash / MSYS2. Try scoop (per-user, no admin) first,
      # then winget, then choco. Each tool may need an absolute or cmd.exe call.
      if command -v scoop >/dev/null 2>&1; then
        scoop install jq && return 0
      fi
      if command -v winget >/dev/null 2>&1 || command -v winget.exe >/dev/null 2>&1; then
        winget install -e --id jqlang.jq --accept-source-agreements --accept-package-agreements && return 0
      elif cmd.exe //c "where winget" >/dev/null 2>&1; then
        cmd.exe //c "winget install -e --id jqlang.jq --accept-source-agreements --accept-package-agreements" && return 0
      fi
      if command -v choco >/dev/null 2>&1; then
        choco install jq -y && return 0
      fi
      warn "no winget / scoop / choco found — install jq manually (https://jqlang.github.io/jq/download/)"
      ;;
    *)
      warn "unknown OS '$uname_s' — install jq manually"
      ;;
  esac
  return 1
}

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
IFS=',' read -ra MEM_GROUP_ARR <<< "$MEM_GROUPS"

# 1. Vault tree
say "Creating vault at $VAULT_DIR"
run "mkdir -p \"$VAULT_DIR\"/{permanent,inbox,fleeting,templates,references,logs}"
run "mkdir -p \"$VAULT_DIR\"/chats/{code,web}"
run ": > \"$VAULT_DIR/.groups\""
for g in "${MEM_GROUP_ARR[@]}"; do
  g="$(echo "$g" | xargs)"
  [[ -z "$g" ]] && continue
  run "printf '%s\n' \"$g\" >> \"$VAULT_DIR/.groups\""
  run "mkdir -p \"$VAULT_DIR/$g\"/{architecture,features,data,pipeline,logs}"
  run "mkdir -p \"$VAULT_DIR/graphify/$g\""
  moc="$VAULT_DIR/$g/_MOC.md"
  if [[ ! -f "$moc" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '\033[1;35m dry\033[0m %s\n' "would seed $moc"
    else
      cap="$(printf '%s' "${g:0:1}" | tr '[:lower:]' '[:upper:]')${g:1}"
      {
        echo "---"
        echo "title: $cap — Map of Contents"
        echo "group: $g"
        echo "tags: [$g, moc]"
        echo "type: moc"
        echo "---"
        echo; echo "# $cap — Map of Contents"; echo
        echo "## Architecture"; echo
        echo "## Features"; echo
        echo "## Recent logs"; echo
      } > "$moc"
      ok "seeded $moc"
    fi
  fi
done
if [[ $DRY_RUN -eq 0 ]]; then
  ok "vault tree ready (groups: $(tr '\n' ',' < "$VAULT_DIR/.groups" | sed 's/,$//'))"
else
  ok "vault tree ready [dry-run] (groups: $MEM_GROUPS)"
fi

# 2. Vault CLAUDE.md, template, .gitignore
if [[ ! -f "$VAULT_DIR/CLAUDE.md" ]]; then
  run "cp \"$REPO_DIR/vault-template/CLAUDE.md\" \"$VAULT_DIR/CLAUDE.md\""
  ok "installed $VAULT_DIR/CLAUDE.md"
else
  warn "$VAULT_DIR/CLAUDE.md already exists — leaving it alone"
fi
if [[ ! -f "$VAULT_DIR/templates/default-note.md" ]]; then
  run "cp \"$REPO_DIR/vault-template/templates/default-note.md\" \"$VAULT_DIR/templates/default-note.md\""
  ok "installed default note template"
fi
if [[ ! -f "$VAULT_DIR/.gitignore" && -f "$REPO_DIR/vault-template/.gitignore" ]]; then
  run "cp \"$REPO_DIR/vault-template/.gitignore\" \"$VAULT_DIR/.gitignore\""
  ok "installed vault .gitignore"
fi

# 2b. Rules system — ~/vault/rules/
if [[ ! -d "$VAULT_DIR/rules" ]]; then
  run "mkdir -p \"$VAULT_DIR/rules\""
  run "cp \"$REPO_DIR/vault-template/rules/\"*.md \"$VAULT_DIR/rules/\""
  run "cp \"$REPO_DIR/vault-template/rules/.config.example.yml\" \"$VAULT_DIR/rules/.config.yml\""
  ok "installed rules scaffold into $VAULT_DIR/rules (edit .config.yml to tune reminder interval)"
else
  warn "$VAULT_DIR/rules already exists — leaving rule files alone. Update .config.yml manually if needed."
fi

# 3. Global Claude Code instructions
say "Installing global ~/.claude/CLAUDE.md"
run "mkdir -p \"$CLAUDE_DIR\""
if [[ -f "$CLAUDE_DIR/CLAUDE.md" && ! -f "$CLAUDE_DIR/CLAUDE.md.obsidian-memory.bak" ]]; then
  run "cp \"$CLAUDE_DIR/CLAUDE.md\" \"$CLAUDE_DIR/CLAUDE.md.obsidian-memory.bak\""
  warn "existing ~/.claude/CLAUDE.md backed up to CLAUDE.md.obsidian-memory.bak"
fi
run "cp \"$REPO_DIR/claude-global/CLAUDE.md\" \"$CLAUDE_DIR/CLAUDE.md\""
ok "memory commands loaded in every Claude Code session on this machine"

# 4. Scripts
say "Installing scripts to $SCRIPTS_DIR"
run "mkdir -p \"$SCRIPTS_DIR\""
run "cp \"$REPO_DIR/scripts/\"*.py \"$SCRIPTS_DIR/\""
run "cp \"$REPO_DIR/scripts/\"*.sh \"$SCRIPTS_DIR/\""
run "chmod +x \"$SCRIPTS_DIR\"/*.sh \"$SCRIPTS_DIR\"/*.py 2>/dev/null || true"
ok "scripts installed ($(ls "$REPO_DIR/scripts" | wc -l) files)"

# 4b. Hooks + statusLine in ~/.claude/settings.json
say "Wiring hooks + statusline into $CLAUDE_DIR/settings.json (scripts dir: $SCRIPTS_DIR)"
ensure_jq || true
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

# 4c. Seed ~/vault/rules.md
if [[ -x "$SCRIPTS_DIR/rules_rebuild.py" ]]; then
  run "VAULT_DIR=\"$VAULT_DIR\" \"$SCRIPTS_DIR/rules_rebuild.py\" || true"
fi

# 5. pip installs
PIP=""
if command -v pip3 >/dev/null 2>&1; then PIP=pip3
elif command -v pip  >/dev/null 2>&1; then PIP=pip
fi
if [[ $INSTALL_PIP -eq 1 ]]; then
  if [[ -n "$PIP" ]]; then
    say "Installing Python tools (graphifyy, claude-conversation-extractor)"
    run "\"$PIP\" install --user --upgrade graphifyy claude-conversation-extractor \
      || warn 'graphify/extractor install failed — retry manually'"
  else
    warn "pip not found — skipping Python tools"
  fi
  if [[ $INSTALL_EMBED -eq 1 && -n "$PIP" ]]; then
    say "Installing semantic search deps (fastembed, sqlite-vec) — ~150MB"
    run "\"$PIP\" install --user --upgrade fastembed sqlite-vec \
      || warn 'embedding deps install failed — /recall will not work until fixed'"
  elif [[ $INSTALL_EMBED -eq 0 ]]; then
    warn "semantic search deps skipped (--no-embed)"
  fi
else
  warn "--no-pip set, skipping all Python tools"
fi

if [[ $DRY_RUN -eq 0 ]]; then
cat <<EOF

Setup complete.

Groups: $(tr '\n' ',' < "$VAULT_DIR/.groups" | sed 's/,$//')

Next steps:
  1. Open Obsidian → "Open folder as vault" → $VAULT_DIR
  2. Make the vault a private git repo:
       cd $VAULT_DIR && git init && git add -A && git commit -m "initial vault"
       git remote add origin <your-private-repo-url>
       git push -u origin main
  3. Drop the project template into any repo:
       cp $REPO_DIR/projects/example-group/CLAUDE.md /path/to/repo/CLAUDE.md
       # then edit the group: field to match one of your groups
  4. Build the semantic index:
       python $SCRIPTS_DIR/vault_search.py index
  5. Start a Claude Code session and try /resume, /recall, /save.

EOF
fi
