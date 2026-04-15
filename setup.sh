#!/usr/bin/env bash
# Bootstrap the Claude Code + Obsidian memory setup.
# Idempotent: safe to re-run on an existing machine / vault.
#
# Usage:
#   ./setup.sh                  # default install
#   ./setup.sh --no-pip         # skip graphifyy + claude-conversation-extractor
#   ./setup.sh --cron           # also install the daily chat-sync cron job
#   ./setup.sh --vault ~/mybrain  # use a custom vault location
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="${VAULT_DIR:-$HOME/vault}"
CLAUDE_DIR="$HOME/.claude"
SCRIPTS_DIR="$HOME/scripts"
EXPORT_DIR="$HOME/claude-exports"

INSTALL_PIP=1
INSTALL_CRON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-pip) INSTALL_PIP=0 ;;
    --cron)   INSTALL_CRON=1 ;;
    --vault)  VAULT_DIR="$2"; shift ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'
      exit 0
      ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m  !\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Vault tree
# ---------------------------------------------------------------------------
say "Creating vault at $VAULT_DIR"
mkdir -p "$VAULT_DIR"/{permanent,inbox,fleeting,templates,references,logs}
mkdir -p "$VAULT_DIR"/chats/{code,web}
for group in arc truenode cinesynth; do
  mkdir -p "$VAULT_DIR/$group"/{architecture,features,data,pipeline,logs}
  moc="$VAULT_DIR/$group/_MOC.md"
  if [[ ! -f "$moc" ]]; then
    {
      echo "---"
      echo "title: ${group^} — Map of Contents"
      echo "group: $group"
      echo "tags: [$group, moc]"
      echo "type: moc"
      echo "---"
      echo
      echo "# ${group^} — Map of Contents"
      echo
      echo "## Architecture"
      echo
      echo "## Features"
      echo
      echo "## Recent logs"
      echo
    } > "$moc"
    ok "seeded $moc"
  fi
  mkdir -p "$VAULT_DIR/graphify/$group"
done
ok "vault tree ready"

# ---------------------------------------------------------------------------
# 2. Vault CLAUDE.md + note template (don't overwrite if the user edited them)
# ---------------------------------------------------------------------------
if [[ ! -f "$VAULT_DIR/CLAUDE.md" ]]; then
  cp "$REPO_DIR/vault-template/CLAUDE.md" "$VAULT_DIR/CLAUDE.md"
  ok "installed $VAULT_DIR/CLAUDE.md"
else
  warn "$VAULT_DIR/CLAUDE.md already exists — leaving it alone"
fi

if [[ ! -f "$VAULT_DIR/templates/default-note.md" ]]; then
  cp "$REPO_DIR/vault-template/templates/default-note.md" "$VAULT_DIR/templates/default-note.md"
  ok "installed default note template"
fi

# ---------------------------------------------------------------------------
# 3. Global Claude Code instructions — THIS is what makes memory auto-popup.
# ---------------------------------------------------------------------------
say "Installing global ~/.claude/CLAUDE.md"
mkdir -p "$CLAUDE_DIR"
if [[ -f "$CLAUDE_DIR/CLAUDE.md" && ! -f "$CLAUDE_DIR/CLAUDE.md.obsidian-memory.bak" ]]; then
  cp "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.obsidian-memory.bak"
  warn "existing ~/.claude/CLAUDE.md backed up to CLAUDE.md.obsidian-memory.bak"
fi
cp "$REPO_DIR/claude-global/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
ok "memory commands are now loaded in every Claude Code session on this machine"

# ---------------------------------------------------------------------------
# 4. Scripts
# ---------------------------------------------------------------------------
say "Installing scripts to $SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR" "$EXPORT_DIR"/{code,web}
cp "$REPO_DIR/scripts/claude_to_obsidian.py"    "$SCRIPTS_DIR/"
cp "$REPO_DIR/scripts/sync_claude_obsidian.sh"  "$SCRIPTS_DIR/"
chmod +x "$SCRIPTS_DIR/sync_claude_obsidian.sh" "$SCRIPTS_DIR/claude_to_obsidian.py"
ok "scripts installed"

# ---------------------------------------------------------------------------
# 5. Optional pip installs
# ---------------------------------------------------------------------------
if [[ $INSTALL_PIP -eq 1 ]]; then
  if command -v pip3 >/dev/null 2>&1; then
    say "Installing Python tools (graphifyy, claude-conversation-extractor)"
    pip3 install --user --upgrade graphifyy claude-conversation-extractor \
      || warn "pip install failed — you can retry manually"
  else
    warn "pip3 not found — skipping Python tool install"
  fi
else
  warn "--no-pip set, skipping Python tools"
fi

# ---------------------------------------------------------------------------
# 6. Optional cron
# ---------------------------------------------------------------------------
if [[ $INSTALL_CRON -eq 1 ]]; then
  say "Installing daily chat-sync cron (22:00)"
  line="0 22 * * * $SCRIPTS_DIR/sync_claude_obsidian.sh"
  ( crontab -l 2>/dev/null | grep -v -F "$SCRIPTS_DIR/sync_claude_obsidian.sh" ; echo "$line" ) | crontab -
  ok "cron installed"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
cat <<EOF

Setup complete.

Next steps:
  1. Open Obsidian → "Open folder as vault" → $VAULT_DIR
  2. (optional) Make the vault a git repo so memory syncs across devices:
       cd $VAULT_DIR && git init && git add -A && git commit -m "initial vault"
       git remote add origin <your-private-repo-url>
       git push -u origin main
  3. In any Arc / TrueNode / CineSynth repo, drop in the matching CLAUDE.md:
       cp $REPO_DIR/projects/arc/CLAUDE.md       /path/to/arc-repo/CLAUDE.md
       cp $REPO_DIR/projects/truenode/CLAUDE.md  /path/to/truenode-repo/CLAUDE.md
       cp $REPO_DIR/projects/cinesynth/CLAUDE.md /path/to/cinesynth-repo/CLAUDE.md
  4. Start a Claude Code session anywhere and run /resume to try it.

EOF
