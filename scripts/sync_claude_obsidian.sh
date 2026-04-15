#!/usr/bin/env bash
# Sync Claude chats (Code + Web exports) into the Obsidian vault.
# Designed to be run from cron. Idempotent and safe to re-run.
set -euo pipefail

EXPORT_DIR="${CLAUDE_EXPORT_DIR:-$HOME/claude-exports}"
VAULT_DIR="${VAULT_DIR:-$HOME/vault}"
SCRIPT_DIR="${SCRIPT_DIR:-$HOME/scripts}"
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/sync.log}"

mkdir -p "$EXPORT_DIR/code" "$EXPORT_DIR/web" "$SCRIPT_DIR"

{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] sync started"

  # 1. Pull Claude Code chats into the staging dir (if the extractor is installed).
  if command -v claude-extract >/dev/null 2>&1; then
    claude-extract --all --output "$EXPORT_DIR/code" || echo "  claude-extract failed (continuing)"
  else
    echo "  claude-extract not installed — skipping Code export"
  fi

  # 2. Claude Web chats are dropped into $EXPORT_DIR/web manually via the browser extension.

  # 3. Process everything into the vault.
  python3 "$SCRIPT_DIR/claude_to_obsidian.py" \
      --export-dir "$EXPORT_DIR" \
      --vault-dir  "$VAULT_DIR" \
      --move

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] sync complete"
} >> "$LOG_FILE" 2>&1
