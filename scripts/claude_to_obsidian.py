#!/usr/bin/env python3
"""
claude_to_obsidian.py — turn Claude chat exports into Obsidian vault notes.

Reads exported `.md` files from a staging directory (`--export-dir`), adds YAML
frontmatter, auto-tags by keyword (with special handling for the Arc / TrueNode
/ CineSynth project groups), inserts wikilinks to existing vault notes, and
drops the result into `<vault>/chats/code/` or `<vault>/chats/web/`.

Usage:
    python3 claude_to_obsidian.py \
        --export-dir ~/claude-exports \
        --vault-dir  ~/vault \
        [--move]   # move instead of copy
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from datetime import date
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Project groups — these drive both tagging and Obsidian graph-view filters.
GROUP_KEYWORDS: dict[str, list[str]] = {
    "arc":       ["arc"],
    "truenode":  ["truenode", "true node", "true-node"],
    "cinesynth": ["cinesynth", "cine synth", "cine-synth"],
}

# Generic topic keywords → tag.
KEYWORD_TAG_MAP: dict[str, str] = {
    "python":    "python",
    "typescript":"typescript",
    "javascript":"javascript",
    "react":     "react",
    "next.js":   "nextjs",
    "nextjs":    "nextjs",
    "supabase":  "supabase",
    "postgres":  "postgres",
    "docker":    "docker",
    "deploy":    "deploy",
    "bug":       "debugging",
    "refactor":  "refactoring",
    "test":      "testing",
    "api":       "api",
}

SLUG_RE = re.compile(r"[^a-z0-9]+")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def slugify(text: str) -> str:
    return SLUG_RE.sub("-", text.lower()).strip("-")[:80] or "untitled"


def detect_groups(text: str) -> list[str]:
    lower = text.lower()
    found = []
    for group, needles in GROUP_KEYWORDS.items():
        if any(n in lower for n in needles):
            found.append(group)
    return found


def detect_topic_tags(text: str) -> list[str]:
    lower = text.lower()
    return sorted({tag for kw, tag in KEYWORD_TAG_MAP.items() if kw in lower})


def existing_vault_notes(vault_dir: Path) -> set[str]:
    notes: set[str] = set()
    for p in vault_dir.rglob("*.md"):
        # Skip anything under chats/ — we don't link chats to other chats.
        if "chats" in p.relative_to(vault_dir).parts:
            continue
        notes.add(p.stem)
    return notes


def insert_wikilinks(body: str, notes: set[str]) -> str:
    """Very conservative wikilink insertion — only replaces the first whole-word
    match of each note stem to avoid mangled text."""
    if not notes:
        return body
    # Sort longest first so "auth-flow" wins over "auth".
    for stem in sorted(notes, key=len, reverse=True):
        # Turn kebab-case into a loose pattern: "auth-flow" matches
        # "auth-flow" or "auth flow" (case-insensitive), whole word.
        tokens = stem.split("-")
        pattern = r"\b" + r"[\s\-]+".join(map(re.escape, tokens)) + r"\b"
        replacement = f"[[{stem}]]"
        body, n = re.subn(pattern, replacement, body, count=1, flags=re.IGNORECASE)
        if n:
            continue
    return body


def build_frontmatter(
    title: str,
    origin: str,
    groups: list[str],
    topic_tags: list[str],
) -> str:
    today = date.today().isoformat()
    tags = ["chat-import", origin, *groups, *topic_tags]
    # primary group drives the `group:` field; fall back to shared
    primary = groups[0] if groups else "shared"
    tag_yaml = ", ".join(sorted(set(tags)))
    return (
        "---\n"
        f"title: {title}\n"
        f"group: {primary}\n"
        f"tags: [{tag_yaml}]\n"
        f"created: {today}\n"
        f"updated: {today}\n"
        "status: active\n"
        "type: chat\n"
        f"source: {origin}\n"
        "---\n\n"
    )


def process_file(
    src: Path,
    origin: str,
    vault_dir: Path,
    existing: set[str],
    move: bool,
) -> Path:
    raw = src.read_text(encoding="utf-8", errors="replace")

    # Drop any existing frontmatter.
    body = re.sub(r"\A---\n.*?\n---\n", "", raw, count=1, flags=re.DOTALL)

    title = src.stem.replace("_", " ").replace("-", " ").strip() or "Chat"
    groups = detect_groups(raw)
    tags = detect_topic_tags(raw)

    fm = build_frontmatter(title, origin, groups, tags)
    body = insert_wikilinks(body, existing)

    out_dir = vault_dir / "chats" / origin
    out_dir.mkdir(parents=True, exist_ok=True)
    out_name = f"{date.today().isoformat()}-{slugify(title)}.md"
    out_path = out_dir / out_name

    out_path.write_text(fm + body, encoding="utf-8")

    if move:
        src.unlink(missing_ok=True)

    return out_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--export-dir", required=True, type=Path)
    parser.add_argument("--vault-dir",  required=True, type=Path)
    parser.add_argument("--move", action="store_true",
                        help="Delete the source file after processing.")
    args = parser.parse_args()

    export_dir: Path = args.export_dir.expanduser().resolve()
    vault_dir:  Path = args.vault_dir.expanduser().resolve()

    if not vault_dir.is_dir():
        print(f"Vault not found: {vault_dir}", file=sys.stderr)
        return 2

    existing = existing_vault_notes(vault_dir)

    total = 0
    for origin in ("code", "web"):
        src_dir = export_dir / origin
        if not src_dir.is_dir():
            continue
        for md in src_dir.glob("*.md"):
            out = process_file(md, origin, vault_dir, existing, args.move)
            print(f"[{origin}] {md.name} -> {out.relative_to(vault_dir)}")
            total += 1

    print(f"Processed {total} file(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
