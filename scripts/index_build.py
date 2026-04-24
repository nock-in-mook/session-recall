#!/usr/bin/env python3
"""
session-recall インデックス構築スクリプト (Phase 4)

全プロジェクトの SESSION_HISTORY.md / HANDOFF.md / DEVLOG.md を読み込み、
Markdown 見出し単位で段落分割 → multilingual-e5-small で埋め込み →
SQLite + sqlite-vec に保存。

使い方:
  python index_build.py              # 既存 DB は差分更新、無ければ初期構築
  python index_build.py --force      # 既存 DB を削除して全再構築
  python index_build.py --db <path>  # DB パス指定（デフォ ~/.claude/session-recall-index.db）

DB 配置: PC ローカル（Drive 同期しない）。各 PC で独立に構築。
"""

import argparse
import re
import sqlite3
import sys
import time
from pathlib import Path

import sqlite_vec
from sentence_transformers import SentenceTransformer

# 検索対象ルート（Mac/Win 両対応、存在する方を採用）
ROOTS_CANDIDATES = [
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_Apps2026",
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_other-projects",
    "/g/マイドライブ/_Apps2026",
    "/g/マイドライブ/_other-projects",
    "/G/マイドライブ/_Apps2026",
    "/G/マイドライブ/_other-projects",
]

TARGET_FILES = ["SESSION_HISTORY.md", "HANDOFF.md", "DEVLOG.md"]

DEFAULT_DB_PATH = Path.home() / ".claude" / "session-recall-index.db"
MODEL_NAME = "intfloat/multilingual-e5-small"
EMBED_DIM = 384

# 1 chunk の最大行数（強制分割の閾値）。長すぎる段落は意味的 unit を保ちつつ切る
MAX_CHUNK_LINES = 40


def get_roots() -> list[Path]:
    return [Path(p) for p in ROOTS_CANDIDATES if Path(p).is_dir()]


def find_target_files(roots: list[Path]) -> list[Path]:
    """全プロジェクトから対象ファイルを列挙（直下 1 階層のプロジェクトのみ）"""
    files = []
    for root in roots:
        for proj_dir in sorted(root.iterdir()):
            if not proj_dir.is_dir():
                continue
            for fname in TARGET_FILES:
                p = proj_dir / fname
                if p.is_file():
                    files.append(p)
    return files


def split_into_chunks(content: str) -> list[tuple[int, int, str]]:
    """
    Markdown を見出し（^#{1,4} ）単位で分割。
    1 chunk が MAX_CHUNK_LINES を超えたら強制分割。
    返り値: [(line_start, line_end, chunk_text), ...]  line は 1-based
    """
    lines = content.split("\n")
    chunks: list[tuple[int, int, str]] = []
    current_start = 1
    current: list[str] = []

    def flush(end_line: int) -> None:
        if current:
            text = "\n".join(current).strip()
            if text:
                chunks.append((current_start, end_line, text))

    for i, line in enumerate(lines, start=1):
        is_heading = bool(re.match(r"^#{1,4} ", line))

        if is_heading and current:
            flush(i - 1)
            current_start = i
            current = [line]
        else:
            current.append(line)

        if len(current) >= MAX_CHUNK_LINES:
            flush(i)
            current_start = i + 1
            current = []

    flush(len(lines))
    return chunks


def init_db(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)

    conn.execute("""
        CREATE TABLE IF NOT EXISTS chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project TEXT NOT NULL,
            file_path TEXT NOT NULL,
            line_start INTEGER NOT NULL,
            line_end INTEGER NOT NULL,
            content TEXT NOT NULL,
            file_mtime INTEGER NOT NULL,
            indexed_at INTEGER NOT NULL
        )
    """)
    conn.execute(f"""
        CREATE VIRTUAL TABLE IF NOT EXISTS vec_chunks USING vec0(
            embedding float[{EMBED_DIM}]
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_chunks_file ON chunks(file_path)")
    conn.commit()
    return conn


def get_indexed_mtime(conn: sqlite3.Connection, file_path: str) -> int | None:
    cur = conn.execute(
        "SELECT MAX(file_mtime) FROM chunks WHERE file_path = ?",
        (file_path,),
    )
    row = cur.fetchone()
    return row[0] if row and row[0] is not None else None


def delete_file_chunks(conn: sqlite3.Connection, file_path: str) -> int:
    cur = conn.execute("SELECT id FROM chunks WHERE file_path = ?", (file_path,))
    ids = [r[0] for r in cur.fetchall()]
    for chunk_id in ids:
        conn.execute("DELETE FROM vec_chunks WHERE rowid = ?", (chunk_id,))
    if ids:
        placeholders = ",".join("?" * len(ids))
        conn.execute(f"DELETE FROM chunks WHERE id IN ({placeholders})", ids)
        conn.commit()
    return len(ids)


def relpath_for(file_path: Path, roots: list[Path]) -> str:
    for root in roots:
        try:
            return str(file_path.relative_to(root))
        except ValueError:
            continue
    return str(file_path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true",
                        help="既存 DB を削除して再構築")
    parser.add_argument("--db", type=str, default=str(DEFAULT_DB_PATH),
                        help=f"DB パス (default: {DEFAULT_DB_PATH})")
    parser.add_argument("--quiet", action="store_true",
                        help="進捗を抑制")
    args = parser.parse_args()

    db_path = Path(args.db)

    if args.force and db_path.exists():
        print(f"既存 DB を削除: {db_path}")
        db_path.unlink()

    if not args.quiet:
        print(f"DB     : {db_path}")
        print(f"モデル : {MODEL_NAME}")

    print("モデル読み込み中（初回はダウンロード数百MB）...", flush=True)
    t0 = time.time()
    model = SentenceTransformer(MODEL_NAME)
    print(f"  完了 ({time.time() - t0:.1f}s)")

    conn = init_db(db_path)
    roots = get_roots()
    if not args.quiet:
        print(f"検索ルート: {len(roots)} 件")

    files = find_target_files(roots)
    print(f"対象ファイル: {len(files)} 件")

    total_added = 0
    total_skipped = 0
    total_updated = 0
    t1 = time.time()

    for file_path in files:
        proj_file = relpath_for(file_path, roots)
        file_mtime = int(file_path.stat().st_mtime)

        existing_mtime = get_indexed_mtime(conn, proj_file)
        if existing_mtime == file_mtime:
            total_skipped += 1
            continue

        if existing_mtime is not None:
            removed = delete_file_chunks(conn, proj_file)
            print(f"  更新: {proj_file} (旧 {removed} chunks 削除)")
            total_updated += 1
        else:
            print(f"  新規: {proj_file}")

        try:
            content = file_path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError) as e:
            print(f"    スキップ ({e})")
            continue

        project = proj_file.split("/")[0]
        chunks = split_into_chunks(content)
        if not chunks:
            continue

        # multilingual-e5 は "passage: " prefix 推奨（インデックス側）
        texts = [f"passage: {c[2]}" for c in chunks]
        embeddings = model.encode(texts, batch_size=32, show_progress_bar=False)

        indexed_at = int(time.time())
        for (line_start, line_end, content_text), emb in zip(chunks, embeddings):
            cur = conn.execute(
                "INSERT INTO chunks (project, file_path, line_start, line_end, content, file_mtime, indexed_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (project, proj_file, line_start, line_end, content_text, file_mtime, indexed_at),
            )
            chunk_id = cur.lastrowid
            conn.execute(
                "INSERT INTO vec_chunks (rowid, embedding) VALUES (?, ?)",
                (chunk_id, emb.astype("float32").tobytes()),
            )
        conn.commit()
        total_added += len(chunks)

    elapsed = time.time() - t1
    print()
    print(f"処理時間  : {elapsed:.1f}s")
    print(f"新規/更新 : {total_added} chunks")
    print(f"変更なし  : {total_skipped} ファイル")
    print(f"更新ファイル数: {total_updated}")
    if db_path.exists():
        size_mb = db_path.stat().st_size / 1024 / 1024
        print(f"DB サイズ : {size_mb:.1f} MB")

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
