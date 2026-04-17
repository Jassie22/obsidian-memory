#!/usr/bin/env python3
"""
Semantic search over the Obsidian vault.
Chunked embeddings (one vector per H2/H3 section) + incremental upsert.

Commands:
  python vault_search.py index           rebuild/update the index
  python vault_search.py search "<q>"   top-5 semantic matches (per chunk)
  python vault_search.py stats           show index stats
  python vault_search.py find-similar "<title-or-path>"
                                         top-3 notes closest to an existing one
                                         (used for dedupe before creating notes)

Env:
  VAULT_DIR     override vault path (default ~/vault)
  RECALL_K      override top-k for search (default 5)
  RECALL_MODEL  override embedding model (default BAAI/bge-large-en-v1.5)
"""
from __future__ import annotations
import os, sys, json, re, sqlite3, pathlib, hashlib, struct

VAULT = pathlib.Path(os.environ.get("VAULT_DIR", pathlib.Path.home() / "vault"))
DB = VAULT / ".index.db"
MODEL = os.environ.get("RECALL_MODEL", "BAAI/bge-large-en-v1.5")
_MODEL_DIMS = {
    "BAAI/bge-large-en-v1.5": 1024,
    "BAAI/bge-base-en-v1.5": 768,
    "BAAI/bge-small-en-v1.5": 384,
}
DIM = _MODEL_DIMS.get(MODEL, 1024)
DEFAULT_K = int(os.environ.get("RECALL_K", "5"))

SCHEMA_VERSION = "2"  # bump on schema change to force full reindex
MIN_CHUNK_CHARS = 200
MAX_CHUNK_CHARS = 4000

SKIP_DIRS = {".git", ".obsidian", "templates", "graphify"}


def iter_notes():
    for p in VAULT.rglob("*.md"):
        rel_parts = p.relative_to(VAULT).parts
        if any(part in SKIP_DIRS or part.startswith(".") for part in rel_parts[:-1]):
            continue
        yield p


def vec_to_blob(vec):
    return struct.pack(f"{DIM}f", *vec)


def title_of(content: str, fallback: str) -> str:
    in_fm = False
    for i, line in enumerate(content.splitlines()[:30]):
        s = line.strip()
        if i == 0 and s == "---":
            in_fm = True
            continue
        if in_fm and s == "---":
            in_fm = False
            continue
        if in_fm and s.startswith("title:"):
            return s.split(":", 1)[1].strip().strip('"\'')
        if not in_fm and s.startswith("# "):
            return s[2:].strip()
    return fallback


def strip_frontmatter(content: str) -> str:
    lines = content.splitlines()
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return "\n".join(lines[i + 1:])
    return content


def chunk_note(content: str, title: str):
    """Yield (heading, chunk_text). Splits on H2/H3 headings.
    Title is prepended to every chunk so vectors have topical context.
    Small chunks merge forward; oversized chunks are truncated."""
    body = strip_frontmatter(content)
    heading_re = re.compile(r"^(#{2,3})\s+(.+?)\s*$", re.MULTILINE)
    parts = []
    last = 0
    last_heading = None
    for m in heading_re.finditer(body):
        section = body[last:m.start()].strip()
        if section:
            parts.append((last_heading, section))
        last_heading = m.group(2).strip()
        last = m.end()
    tail = body[last:].strip()
    if tail:
        parts.append((last_heading, tail))
    if not parts:
        parts = [(None, body.strip() or title)]

    # merge small chunks forward
    merged = []
    buf_h, buf_t = None, ""
    for h, t in parts:
        if buf_t and len(buf_t) < MIN_CHUNK_CHARS:
            buf_t = f"{buf_t}\n\n{t}"
            buf_h = buf_h or h
        else:
            if buf_t:
                merged.append((buf_h, buf_t))
            buf_h, buf_t = h, t
    if buf_t:
        merged.append((buf_h, buf_t))

    for h, t in merged:
        prefix = f"{title}"
        if h:
            prefix = f"{title} — {h}"
        yield h, f"{prefix}\n\n{t[:MAX_CHUNK_CHARS]}"


def get_db():
    import sqlite_vec
    first_time = not DB.exists()
    conn = sqlite3.connect(DB)
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)
    conn.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")
    row = conn.execute("SELECT value FROM meta WHERE key='schema_version'").fetchone()
    current = row[0] if row else None
    if current != SCHEMA_VERSION and not first_time:
        # drop everything — forces full reindex under the new schema
        conn.executescript("""
            DROP TABLE IF EXISTS chunks;
            DROP TABLE IF EXISTS notes;
            DROP TABLE IF EXISTS note_vec;
        """)
    conn.executescript(f"""
        CREATE TABLE IF NOT EXISTS notes (
            path TEXT PRIMARY KEY,
            mtime REAL,
            content_hash TEXT,
            title TEXT
        );
        CREATE TABLE IF NOT EXISTS chunks (
            rowid INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL,
            heading TEXT,
            vec_rowid INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_chunks_path ON chunks(path);
        CREATE VIRTUAL TABLE IF NOT EXISTS note_vec USING vec0(
            embedding float[{DIM}]
        );
    """)
    conn.execute(
        "INSERT OR REPLACE INTO meta(key, value) VALUES ('schema_version', ?)",
        (SCHEMA_VERSION,),
    )
    conn.commit()
    return conn


def delete_note_chunks(conn, path: str):
    rows = conn.execute("SELECT vec_rowid FROM chunks WHERE path=?", (path,)).fetchall()
    for (rid,) in rows:
        conn.execute("DELETE FROM note_vec WHERE rowid=?", (rid,))
    conn.execute("DELETE FROM chunks WHERE path=?", (path,))


def cmd_index():
    from fastembed import TextEmbedding
    embedder = TextEmbedding(MODEL)
    conn = get_db()

    existing = {
        row[0]: (row[1], row[2])  # path -> (mtime, hash)
        for row in conn.execute("SELECT path, mtime, content_hash FROM notes")
    }

    to_embed = []  # (rel, mtime, hash, title, [(heading, chunk_text), ...])
    untouched = 0
    live_paths = set()
    for p in iter_notes():
        rel = str(p.relative_to(VAULT)).replace("\\", "/")
        live_paths.add(rel)
        mtime = p.stat().st_mtime
        prev = existing.get(rel)
        if prev and abs(prev[0] - mtime) < 0.001:
            untouched += 1
            continue
        content = p.read_text(encoding="utf-8", errors="ignore")
        h = hashlib.sha1(content.encode("utf-8")).hexdigest()
        if prev and prev[1] == h:
            conn.execute("UPDATE notes SET mtime=? WHERE path=?", (mtime, rel))
            untouched += 1
            continue
        title = title_of(content, rel)
        chunks = list(chunk_note(content, title))
        to_embed.append((rel, mtime, h, title, chunks))

    removed = [r for r in existing if r not in live_paths]
    for r in removed:
        delete_note_chunks(conn, r)
        conn.execute("DELETE FROM notes WHERE path=?", (r,))

    total_chunks = 0
    if to_embed:
        flat_texts = []
        index_map = []  # (note_idx, chunk_idx)
        for ni, (_, _, _, _, chunks) in enumerate(to_embed):
            for ci, (_, text) in enumerate(chunks):
                flat_texts.append(text)
                index_map.append((ni, ci))

        vecs = list(embedder.embed(flat_texts))

        for (rel, mtime, h, title, chunks) in to_embed:
            delete_note_chunks(conn, rel)
            conn.execute(
                """
                INSERT INTO notes(path, mtime, content_hash, title)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET
                    mtime=excluded.mtime,
                    content_hash=excluded.content_hash,
                    title=excluded.title
                """,
                (rel, mtime, h, title),
            )

        for (ni, ci), vec in zip(index_map, vecs):
            rel, _, _, _, chunks = to_embed[ni]
            heading, _ = chunks[ci]
            cur = conn.execute(
                "INSERT INTO note_vec(embedding) VALUES (?)",
                (vec_to_blob(vec.tolist()),),
            )
            new_rowid = cur.lastrowid
            conn.execute(
                "INSERT INTO chunks(path, heading, vec_rowid) VALUES (?, ?, ?)",
                (rel, heading, new_rowid),
            )
            total_chunks += 1

    conn.commit()
    print(json.dumps({
        "notes_embedded": len(to_embed),
        "chunks_written": total_chunks,
        "removed": len(removed),
        "untouched": untouched,
        "total_notes": len(live_paths),
    }, indent=2))


def cmd_search(query: str, k: int = DEFAULT_K):
    from fastembed import TextEmbedding
    embedder = TextEmbedding(MODEL)
    conn = get_db()
    qvec = next(iter(embedder.embed([query])))
    rows = conn.execute(
        """
        SELECT c.path, c.heading, n.title, v.distance
        FROM note_vec v
        JOIN chunks c ON c.vec_rowid = v.rowid
        JOIN notes n ON n.path = c.path
        WHERE v.embedding MATCH ? AND k = ?
        ORDER BY v.distance
        """,
        (vec_to_blob(qvec.tolist()), k),
    ).fetchall()
    if not rows:
        print("(no results — is the index empty? run: vault_search.py index)")
        return
    for path, heading, title, dist in rows:
        loc = f"{path}#{heading}" if heading else path
        print(f"{dist:.3f}\t{loc}\t{title}")


def cmd_find_similar(title_or_path: str, k: int = 3):
    """Dedupe helper: return top-k distinct notes (not chunks)."""
    from fastembed import TextEmbedding
    embedder = TextEmbedding(MODEL)
    conn = get_db()
    qvec = next(iter(embedder.embed([title_or_path])))
    rows = conn.execute(
        """
        SELECT c.path, n.title, MIN(v.distance) as d
        FROM note_vec v
        JOIN chunks c ON c.vec_rowid = v.rowid
        JOIN notes n ON n.path = c.path
        WHERE v.embedding MATCH ? AND k = ?
        GROUP BY c.path
        ORDER BY d
        LIMIT ?
        """,
        (vec_to_blob(qvec.tolist()), k * 4, k),
    ).fetchall()
    if not rows:
        print("(no results — is the index empty? run: vault_search.py index)")
        return
    for path, title, dist in rows:
        print(f"{dist:.3f}\t{path}\t{title}")


def cmd_stats():
    conn = get_db()
    n = conn.execute("SELECT COUNT(*) FROM notes").fetchone()[0]
    c = conn.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
    v = conn.execute("SELECT COUNT(*) FROM note_vec").fetchone()[0]
    size = DB.stat().st_size if DB.exists() else 0
    print(json.dumps({
        "notes_indexed": n,
        "chunks_indexed": c,
        "vectors_stored": v,
        "db_size_bytes": size,
        "db_path": str(DB),
        "model": MODEL,
        "schema_version": SCHEMA_VERSION,
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
