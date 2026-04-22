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
