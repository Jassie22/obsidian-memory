#!/usr/bin/env bash
# Bootstrap the Claude Code + Obsidian memory setup.
# Idempotent: safe to re-run on an existing machine / vault.
#
# Usage:
#   ./setup.sh                                       # prompts for groups + author
#   ./setup.sh --groups work,personal                # non-interactive groups
#   ./setup.sh --no-pip                              # skip all Python tools
#   ./setup.sh --no-embed                            # skip semantic search deps only
#   ./setup.sh --vault ~/mybrain                     # custom personal vault location
#   ./setup.sh --company-vault ~/co-brain            # also seed a shared company vault
#   ./setup.sh --no-company-vault                    # skip the company-vault prompt
#   ./setup.sh --author "Jassie"                     # name for the `author:` frontmatter field
#   ./setup.sh --scripts-dir ~/bin/claude            # custom scripts dir (default ~/scripts)
#   ./setup.sh --dry-run                             # print planned actions, write nothing
#
# Multi-vault model (since v0.4):
#   - Personal vault (~/vault, role: private) — yours alone. Logs, captures,
#     personal rules, half-formed proactive notes.
#   - Company vault (~/company-vault, role: shared) — same git remote as
#     teammates. Decisions, runbooks, gotchas, cross-group permanent notes.
#   The registry at ~/.claude/vaults.json drives both. Author name is set
#   once here and stamped into every note's `author:` frontmatter field.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="${VAULT_DIR:-$HOME/vault}"
COMPANY_VAULT_DIR="${COMPANY_VAULT_DIR:-}"
INSTALL_COMPANY_VAULT=auto       # auto | yes | no
AUTHOR_NAME="${VAULT_AUTHOR:-}"
CLAUDE_DIR="$HOME/.claude"
SCRIPTS_DIR="$HOME/scripts"

INSTALL_PIP=1
INSTALL_EMBED=1
INSTALL_OBSIDIAN=1
MEM_GROUPS=""

DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-pip)            INSTALL_PIP=0 ;;
    --no-embed)          INSTALL_EMBED=0 ;;
    --no-obsidian)       INSTALL_OBSIDIAN=0 ;;
    --vault)             VAULT_DIR="$2"; shift ;;
    --company-vault)     COMPANY_VAULT_DIR="$2"; INSTALL_COMPANY_VAULT=yes; shift ;;
    --no-company-vault)  INSTALL_COMPANY_VAULT=no ;;
    --author)            AUTHOR_NAME="$2"; shift ;;
    --groups)            MEM_GROUPS="$2"; shift ;;
    --scripts-dir)       SCRIPTS_DIR="$2"; shift ;;
    --dry-run)           DRY_RUN=1 ;;
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

# Best-effort Obsidian desktop install. Returns 0 if already present or
# successfully installed, 1 otherwise. Headless servers should opt out
# via --no-obsidian.
ensure_obsidian() {
  local uname_s
  uname_s="$(uname -s 2>/dev/null || echo unknown)"
  # Detect existing install across OSes.
  case "$uname_s" in
    Darwin)
      [[ -d "/Applications/Obsidian.app" || -d "$HOME/Applications/Obsidian.app" ]] && return 0
      ;;
    Linux)
      command -v obsidian >/dev/null 2>&1 && return 0
      flatpak info md.obsidian.Obsidian >/dev/null 2>&1 && return 0
      snap list obsidian >/dev/null 2>&1 && return 0
      ;;
    MINGW*|MSYS*|CYGWIN*)
      [[ -f "$HOME/AppData/Local/Obsidian/Obsidian.exe" || -f "$LOCALAPPDATA/Obsidian/Obsidian.exe" || -f "/c/Program Files/Obsidian/Obsidian.exe" ]] && return 0
      ;;
  esac

  if [[ $DRY_RUN -eq 1 ]]; then
    printf '\033[1;35m dry\033[0m would install Obsidian via OS package manager\n'
    return 0
  fi
  say "Obsidian not found — attempting auto-install (skip with --no-obsidian)"
  case "$uname_s" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        brew install --cask obsidian && return 0
      else
        warn "brew not found — download Obsidian from https://obsidian.md/download"
      fi
      ;;
    Linux)
      if command -v flatpak >/dev/null 2>&1; then
        flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
        flatpak install -y --user flathub md.obsidian.Obsidian && return 0
      elif command -v snap >/dev/null 2>&1; then
        sudo snap install obsidian --classic && return 0
      else
        warn "no flatpak/snap — grab the AppImage from https://obsidian.md/download"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      if command -v scoop >/dev/null 2>&1; then
        scoop bucket add extras 2>/dev/null || true
        scoop install obsidian && return 0
      fi
      if command -v winget >/dev/null 2>&1 || command -v winget.exe >/dev/null 2>&1; then
        winget install -e --id Obsidian.Obsidian --accept-source-agreements --accept-package-agreements && return 0
      elif cmd.exe //c "where winget" >/dev/null 2>&1; then
        cmd.exe //c "winget install -e --id Obsidian.Obsidian --accept-source-agreements --accept-package-agreements" && return 0
      fi
      if command -v choco >/dev/null 2>&1; then
        choco install obsidian -y && return 0
      fi
      warn "no winget / scoop / choco — download from https://obsidian.md/download"
      ;;
    *)
      warn "unknown OS '$uname_s' — install Obsidian from https://obsidian.md/download"
      ;;
  esac
  return 1
}

# 0a. Author name — stamped into every note's `author:` frontmatter field.
# Critical when the company vault is shared with teammates: makes provenance
# visible inline rather than requiring `git blame`.
REGISTRY="$CLAUDE_DIR/vaults.json"
if [[ -z "$AUTHOR_NAME" ]]; then
  if [[ -f "$REGISTRY" ]] && command -v jq >/dev/null 2>&1; then
    AUTHOR_NAME="$(jq -r '.author // empty' "$REGISTRY" 2>/dev/null)"
  fi
  if [[ -z "$AUTHOR_NAME" ]]; then
    git_name="$(git config --global user.name 2>/dev/null || true)"
    default_name="${git_name:-$USER}"
    read -rp "Author name (used in note frontmatter, will be visible to teammates if you have a company vault) [$default_name]: " AUTHOR_NAME
    AUTHOR_NAME="${AUTHOR_NAME:-$default_name}"
  else
    ok "reusing author from registry: $AUTHOR_NAME"
  fi
fi

# 0b. Company vault prompt (only on fresh installs without an existing decision).
if [[ "$INSTALL_COMPANY_VAULT" == "auto" ]]; then
  if [[ -f "$REGISTRY" ]] && command -v jq >/dev/null 2>&1; then
    existing_co="$(jq -r '.vaults[]? | select(.role=="shared") | .path' "$REGISTRY" 2>/dev/null | head -n1)"
    if [[ -n "$existing_co" ]]; then
      INSTALL_COMPANY_VAULT=yes
      COMPANY_VAULT_DIR="${COMPANY_VAULT_DIR:-${existing_co/#\~/$HOME}}"
      ok "reusing existing company vault from registry: $COMPANY_VAULT_DIR"
    fi
  fi
fi
if [[ "$INSTALL_COMPANY_VAULT" == "auto" ]]; then
  echo
  echo "Company vault (optional) — a second, *shared* vault for team-wide notes:"
  echo "  · Same git remote across all teammates (5-person team typical)."
  echo "  · Holds decisions, runbooks, gotchas, cross-group permanent notes."
  echo "  · Personal vault stays for logs, captures, half-formed thoughts."
  read -rp "Set up a company vault now? [y/N]: " yn
  case "$yn" in
    y|Y|yes|YES) INSTALL_COMPANY_VAULT=yes ;;
    *)           INSTALL_COMPANY_VAULT=no  ;;
  esac
fi
if [[ "$INSTALL_COMPANY_VAULT" == "yes" && -z "$COMPANY_VAULT_DIR" ]]; then
  read -rp "Company vault path [\$HOME/company-vault]: " COMPANY_VAULT_DIR
  COMPANY_VAULT_DIR="${COMPANY_VAULT_DIR:-$HOME/company-vault}"
fi

# 0c. Groups
if [[ -z "$MEM_GROUPS" ]]; then
  if [[ -f "$VAULT_DIR/.groups" ]]; then
    MEM_GROUPS="$(tr '\n' ',' < "$VAULT_DIR/.groups")"
    MEM_GROUPS="${MEM_GROUPS%,}"
    ok "reusing existing personal-vault groups: $MEM_GROUPS"
  else
    template="$REPO_DIR/vault-template/.groups.template"
    if [[ -f "$template" ]]; then
      echo "Personal-vault groups live in ~/vault/.groups — one slug per line. Examples:"
      grep -v '^#' "$template" | grep -v '^$' | sed 's/^/  /'
      echo "(none shown if the template has only commented examples)"
    fi
    read -rp "Personal-vault groups (comma-separated, e.g. journal,side-projects): " MEM_GROUPS
    [[ -z "$MEM_GROUPS" ]] && MEM_GROUPS="personal"
  fi
fi
IFS=',' read -ra MEM_GROUP_ARR <<< "$MEM_GROUPS"

# Company-vault groups are tracked separately and committed into the shared
# repo, so they're a deliberate team decision rather than a per-machine setup
# detail. We don't prompt — teammates pull `.groups` from the company-vault
# remote and inherit whatever the team has agreed on.
COMPANY_GROUPS=""
if [[ "$INSTALL_COMPANY_VAULT" == "yes" && -f "$COMPANY_VAULT_DIR/.groups" ]]; then
  COMPANY_GROUPS="$(tr '\n' ',' < "$COMPANY_VAULT_DIR/.groups" | sed 's/,$//')"
fi

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
# Rules are *personal* (per-user behavior preferences). They never live in the
# shared company vault — what one teammate wants Claude to do isn't what the
# whole team wants.
if [[ ! -d "$VAULT_DIR/rules" ]]; then
  run "mkdir -p \"$VAULT_DIR/rules\""
  run "cp \"$REPO_DIR/vault-template/rules/\"*.md \"$VAULT_DIR/rules/\""
  run "cp \"$REPO_DIR/vault-template/rules/.config.example.yml\" \"$VAULT_DIR/rules/.config.yml\""
  ok "installed rules scaffold into $VAULT_DIR/rules (edit .config.yml to tune reminder interval)"
else
  warn "$VAULT_DIR/rules already exists — leaving rule files alone. Update .config.yml manually if needed."
fi

# 2c. Company vault scaffold — only if the user opted in.
if [[ "$INSTALL_COMPANY_VAULT" == "yes" ]]; then
  say "Creating company vault at $COMPANY_VAULT_DIR"
  run "mkdir -p \"$COMPANY_VAULT_DIR\"/{permanent,templates}"
  if [[ ! -f "$COMPANY_VAULT_DIR/.groups" ]]; then
    if [[ -f "$REPO_DIR/company-vault-template/.groups.template" ]]; then
      run "cp \"$REPO_DIR/company-vault-template/.groups.template\" \"$COMPANY_VAULT_DIR/.groups\""
      warn "$COMPANY_VAULT_DIR/.groups created from template — edit it and commit, then teammates clone the repo and inherit the same group list"
    else
      run ": > \"$COMPANY_VAULT_DIR/.groups\""
    fi
  fi
  if [[ ! -f "$COMPANY_VAULT_DIR/CLAUDE.md" ]]; then
    run "cp \"$REPO_DIR/company-vault-template/CLAUDE.md\" \"$COMPANY_VAULT_DIR/CLAUDE.md\""
    ok "installed $COMPANY_VAULT_DIR/CLAUDE.md"
  else
    warn "$COMPANY_VAULT_DIR/CLAUDE.md already exists — leaving it alone"
  fi
  if [[ ! -f "$COMPANY_VAULT_DIR/.gitignore" ]]; then
    run "cp \"$REPO_DIR/company-vault-template/.gitignore\" \"$COMPANY_VAULT_DIR/.gitignore\""
    ok "installed company-vault .gitignore (ignores _MOC.md to avoid 5-way merge conflicts)"
  fi
  if [[ ! -f "$COMPANY_VAULT_DIR/templates/default-note.md" ]]; then
    run "cp \"$REPO_DIR/company-vault-template/templates/default-note.md\" \"$COMPANY_VAULT_DIR/templates/default-note.md\""
  fi
  if [[ ! -f "$COMPANY_VAULT_DIR/.repo-map.json" && -f "$REPO_DIR/company-vault-template/.repo-map.json.template" ]]; then
    run "cp \"$REPO_DIR/company-vault-template/.repo-map.json.template\" \"$COMPANY_VAULT_DIR/.repo-map.json\""
    warn "$COMPANY_VAULT_DIR/.repo-map.json seeded from template — edit it with your real GitHub remotes (e.g. github.com/yourorg/arc-*) so Claude can auto-detect groups"
  fi
fi

# 2d. Vault registry — single source of truth for which vaults Claude knows
# about, where they live, and which is shared vs. private. Lives at
# ~/.claude/vaults.json so Claude Code (which already reads this dir) can find
# it without env-var coordination across shells.
say "Writing vault registry to $REGISTRY"
if [[ $DRY_RUN -eq 1 ]]; then
  printf '\033[1;35m dry\033[0m would write %s with author=%s, vaults=[personal:%s%s]\n' \
    "$REGISTRY" "$AUTHOR_NAME" "$VAULT_DIR" \
    "$([[ "$INSTALL_COMPANY_VAULT" == "yes" ]] && echo ", company:$COMPANY_VAULT_DIR")"
else
  mkdir -p "$CLAUDE_DIR"
  if command -v jq >/dev/null 2>&1; then
    # Build the JSON via jq so paths with quotes/spaces are handled correctly
    # and the file stays valid even if the user re-runs setup with new args.
    if [[ "$INSTALL_COMPANY_VAULT" == "yes" ]]; then
      jq -n \
        --arg author "$AUTHOR_NAME" \
        --arg pp "$VAULT_DIR" \
        --arg cp "$COMPANY_VAULT_DIR" \
        '{
          author: $author,
          schema_version: 1,
          vaults: [
            {name: "personal", path: $pp, role: "private", default_for: ["log","capture","rule","draft"]},
            {name: "company",  path: $cp, role: "shared",  default_for: ["decision","runbook","gotcha","permanent"]}
          ]
        }' > "$REGISTRY"
    else
      jq -n \
        --arg author "$AUTHOR_NAME" \
        --arg pp "$VAULT_DIR" \
        '{
          author: $author,
          schema_version: 1,
          vaults: [
            {name: "personal", path: $pp, role: "private", default_for: ["all"]}
          ]
        }' > "$REGISTRY"
    fi
    ok "registry written: author=$AUTHOR_NAME, $(jq '.vaults | length' "$REGISTRY") vault(s)"
  else
    warn "jq missing — writing minimal registry without jq (re-run after installing jq for a cleaner file)"
    cat > "$REGISTRY" <<JSON
{
  "author": "$AUTHOR_NAME",
  "schema_version": 1,
  "vaults": [
    {"name": "personal", "path": "$VAULT_DIR", "role": "private"}
  ]
}
JSON
  fi
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

# 4d. Obsidian desktop app (optional GUI — skip with --no-obsidian for headless)
if [[ $INSTALL_OBSIDIAN -eq 1 ]]; then
  ensure_obsidian || true
else
  warn "--no-obsidian set, skipping Obsidian install"
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

Author:           $AUTHOR_NAME
Personal vault:   $VAULT_DIR  (groups: $(tr '\n' ',' < "$VAULT_DIR/.groups" | sed 's/,$//'))
EOF
if [[ "$INSTALL_COMPANY_VAULT" == "yes" ]]; then
cat <<EOF
Company vault:    $COMPANY_VAULT_DIR  (groups: $(tr '\n' ',' < "$COMPANY_VAULT_DIR/.groups" 2>/dev/null | sed 's/,$//'))
EOF
fi
cat <<EOF
Registry:         $REGISTRY

Next steps:
  1. Open Obsidian → "Open folder as vault" → $VAULT_DIR
$(if [[ "$INSTALL_COMPANY_VAULT" == "yes" ]]; then
echo "     Then add a second vault: $COMPANY_VAULT_DIR"
fi)
  2. Make the personal vault a private git repo (yours alone):
       cd $VAULT_DIR && git init && git add -A && git commit -m "initial vault"
       git remote add origin <your-private-repo-url>
       git push -u origin main
$(if [[ "$INSTALL_COMPANY_VAULT" == "yes" ]]; then
cat <<EOC
  2b. Initialize the company vault and point it at the *team* remote:
       cd $COMPANY_VAULT_DIR && git init && git add -A && git commit -m "initial company vault"
       git remote add origin <team-shared-repo-url>
       git push -u origin main
       # Teammates: skip the init/commit, just \`git clone <team-shared-repo-url> $COMPANY_VAULT_DIR\`,
       # then run setup.sh --company-vault $COMPANY_VAULT_DIR --author "Your Name"
       # to register it locally.
EOC
fi)
  3. Drop the project template into any repo (or skip if you wired the repo
     into $COMPANY_VAULT_DIR/.repo-map.json — auto-detection means no
     per-repo CLAUDE.md drop-in is needed):
       cp $REPO_DIR/projects/example-group/CLAUDE.md /path/to/repo/CLAUDE.md
  4. Build the semantic index (covers all registered vaults):
       python $SCRIPTS_DIR/vault_search.py index
  5. Start a Claude Code session and try /resume, /recall, /save, /promote.

EOF
fi
