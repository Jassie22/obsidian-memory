#!/usr/bin/env python3
"""
Semantic search over the Obsidian vault.
Incremental upsert: re-embeds only notes whose content hash changed.

Commands:
  python vault_search.py index           rebuild/update the index
  python vault_search.py search "<q>"   top-5 semantic matches
  python vault_search.py stats           show index stats
  python vault_search.py find-similar "<title-or-path>"
                                         top-3 notes closest to an existing one
                                         (used for dedupe before creating notes)

Env:
  VAULT_DIR     override vault path (default ~/vault)
  RECALL_K      override top-k for search (default 5)
"""
from __future__ import annotations
import os, sys, json, sqlite3, pathlib, hashlib, struct

VAULT = pathlib.Path(os.environ.get("VAULT_DIR", pathlib.Path.home() / "vault"))
DB = VAULT / ".index.db"
MODEL = os.environ.get("RECALL_MODEL", "BAAI/bge-large-en-v1.5")
# Known fastembed models + dims. Override with RECALL_MODEL env var on
# low-RAM devices (e.g. set to BAAI/bge-small-en-v1.5 for 4GB machines).
_MODEL_DIMS = {
    "BAAI/bge-large-en-v1.5": 1024,
    "BAAI/bge-base-en-v1.5": 768,
    "BAAI/bge-small-en-v1.5": 384,
}
DIM = _MODEL_DIMS.get(MODEL, 1024)
DEFAULT_K = int(os.environ.get("RECALL_K", "5"))

# folders inside vault to skip entirely
SKIP_DIRS = {".git", ".obsidian", "templates", "graphify"}


def iter_notes():
    for p in VAULT.rglob("*.md"):
        rel_parts = p.relative_to(VAULT).parts
        if any(part in SKIP_DIRS or part.startswith(".") for part in rel_parts[:-1]):
            continue
        yield p


def get_db():
    import sqlite_vec
    conn = sqlite3.connect(DB)
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)
    conn.executescript(f"""
        CREATE TABLE IF NOT EXISTS notes (
            path TEXT PRIMARY KEY,
            mtime REAL,
            content_hash TEXT,
            title TEXT,
            vec_rowid INTEGER
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS note_vec USING vec0(
            embedding float[{DIM}]
        );
    """)
    return conn


def vec_to_blob(vec):
    return struct.pack(f"{DIM}f", *vec)


def title_of(content: str, fallback: str) -> str:
    for line in content.splitlines()[:20]:
        s = line.strip()
        if s.startswith("title:"):
            return s.split(":", 1)[1].strip().strip('"\'')
        if s.startswith("# "):
            return s[2:].strip()
    return fallback


def cmd_index():
    from fastembed import TextEmbedding
    embedder = TextEmbedding(MODEL)
    conn = get_db()

    existing = {
        row[0]: (row[1], row[2], row[3])  # path -> (mtime, hash, vec_rowid)
        for row in conn.execute("SELECT path, mtime, content_hash, vec_rowid FROM notes")
    }

    to_embed = []  # (rel, mtime, hash, content, old_vec_rowid)
    untouched = 0
    for p in iter_notes():
        rel = str(p.relative_to(VAULT)).replace("\\", "/")
        mtime = p.stat().st_mtime
        prev = existing.get(rel)
        if prev and abs(prev[0] - mtime) < 0.001:
            untouched += 1
            continue
        content = p.read_text(encoding="utf-8", errors="ignore")
        h = hashlib.sha1(content.encode("utf-8")).hexdigest()
        if prev and prev[1] == h:
            # mtime touched but content identical (e.g. git checkout)
            conn.execute("UPDATE notes SET mtime=? WHERE path=?", (mtime, rel))
            untouched += 1
            continue
        to_embed.append((rel, mtime, h, content, prev[2] if prev else None))

    # removed notes
    live = {str(p.relative_to(VAULT)).replace("\\", "/") for p in iter_notes()}
    removed = [r for r in existing if r not in live]
    for r in removed:
        old_rowid = existing[r][2]
        if old_rowid is not None:
            conn.execute("DELETE FROM note_vec WHERE rowid=?", (old_rowid,))
        conn.execute("DELETE FROM notes WHERE path=?", (r,))

    if to_embed:
        texts = [
            f"{title_of(t[3], t[0])}\n\n{t[3][:4000]}"  # title + first 4KB
            for t in to_embed
        ]
        vecs = list(embedder.embed(texts))
        for (rel, mtime, h, content, old_rowid), vec in zip(to_embed, vecs):
            if old_rowid is not None:
                conn.execute("DELETE FROM note_vec WHERE rowid=?", (old_rowid,))
            cur = conn.execute(
                "INSERT INTO note_vec(embedding) VALUES (?)",
                (vec_to_blob(vec.tolist()),),
            )
            new_rowid = cur.lastrowid
            title = title_of(content, rel)
            conn.execute(
                """
                INSERT INTO notes(path, mtime, content_hash, title, vec_rowid)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET
                    mtime=excluded.mtime,
                    content_hash=excluded.content_hash,
                    title=excluded.title,
                    vec_rowid=excluded.vec_rowid
                """,
                (rel, mtime, h, title, new_rowid),
            )

    conn.commit()
    print(json.dumps({
        "embedded": len(to_embed),
        "removed": len(removed),
        "untouched": untouched,
        "total": len(live),
    }, indent=2))


def cmd_search(query: str, k: int = DEFAULT_K):
    from fastembed import TextEmbedding
    embedder = TextEmbedding(MODEL)
    conn = get_db()
    qvec = next(iter(embedder.embed([query])))
    rows = conn.execute(
        """
        SELECT n.path, n.title, v.distance
        FROM note_vec v
        JOIN notes n ON n.vec_rowid = v.rowid
        WHERE v.embedding MATCH ? AND k = ?
        ORDER BY v.distance
        """,
        (vec_to_blob(qvec.tolist()), k),
    ).fetchall()
    if not rows:
        print("(no results — is the index empty? run: vault_search.py index)")
        return
    for path, title, dist in rows:
        print(f"{dist:.3f}\t{path}\t{title}")


def cmd_find_similar(title_or_path: str, k: int = 3):
    """Dedupe helper: given a prospective note title or an existing path,
    return top-k semantically-closest existing notes."""
    cmd_search(title_or_path, k=k)


def cmd_stats():
    conn = get_db()
    n = conn.execute("SELECT COUNT(*) FROM notes").fetchone()[0]
    v = conn.execute("SELECT COUNT(*) FROM note_vec").fetchone()[0]
    size = DB.stat().st_size if DB.exists() else 0
    print(json.dumps({
        "notes_indexed": n,
        "vectors_stored": v,
        "db_size_bytes": size,
        "db_path": str(DB),
        "model": MODEL,
    }, indent=2))


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "stats"
    if cmd == "index":
        cmd_index()
    elif cmd == "search":
        if len(sys.argv) < 3:
            sys.exit("usage: vault_search.py search \"<query>\"")
        cmd_search(" ".join(sys.argv[2:]))
    elif cmd == "find-similar":
        if len(sys.argv) < 3:
            sys.exit("usage: vault_search.py find-similar \"<title>\"")
        cmd_find_similar(" ".join(sys.argv[2:]))
    elif cmd == "stats":
        cmd_stats()
    else:
        sys.exit(f"unknown command: {cmd}")


if __name__ == "__main__":
    main()
