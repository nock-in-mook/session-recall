#!/usr/bin/env python3
"""
session-recall セマンティック検索 CLI 単体実装 (Phase 7)

server.py の MCP 経由セマンティック検索が Claude Code 2.1.116〜 の
custom stdio MCP regression で動かない場合のフォールバック。
ロジックは server.py の semantic_search() と等価で、CLI から直接呼び出す。

使い方:
    python semantic.py "クエリ文" [--project NAME] [--limit N]

例:
    python semantic.py "claude-mem を撤去した経緯"
    python semantic.py "ToDo 結合の議論" --project Memolette-Flutter --limit 3
"""

import argparse
import sqlite3
import sys
from pathlib import Path

import sqlite_vec
from sentence_transformers import SentenceTransformer

INDEX_DB_CANDIDATES = [
    str(Path.home() / ".claude" / "session-recall-index.db"),
]

EMBED_MODEL_NAME = "intfloat/multilingual-e5-small"


def find_index_db() -> str | None:
    for p in INDEX_DB_CANDIDATES:
        if Path(p).is_file():
            return p
    return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="session-recall セマンティック検索 (CLI フォールバック)",
    )
    parser.add_argument("query", help="意味的に検索したい問い（1 文の自然言語推奨）")
    parser.add_argument(
        "--project",
        default=None,
        help="絞り込むプロジェクト名（_Apps2026/ or _other-projects/ 直下のフォルダ名）",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=5,
        help="返す上位件数（デフォルト 5、上限 30）",
    )
    args = parser.parse_args()

    query = args.query.strip()
    if not query:
        print("エラー: query が空です", file=sys.stderr)
        return 1

    limit = max(1, min(30, args.limit))
    project = args.project.strip() if args.project else None
    if project == "":
        project = None

    db_path = find_index_db()
    if not db_path:
        print(
            "セマンティック検索 DB が未構築です。\n"
            "以下のいずれかでインデックスを構築してください:\n"
            "  bash <session-recall>/deploy.sh                # フル deploy（Phase 1〜4）\n"
            "  python <session-recall>/scripts/index_build.py # 単体実行",
            file=sys.stderr,
        )
        return 1

    try:
        model = SentenceTransformer(EMBED_MODEL_NAME)
        # multilingual-e5 は "query: " prefix 推奨
        query_vec = model.encode([f"query: {query}"])[0]
        query_bytes = query_vec.astype("float32").tobytes()
    except Exception as e:
        print(f"埋め込み生成に失敗: {e}", file=sys.stderr)
        return 1

    conn = sqlite3.connect(db_path)
    try:
        conn.enable_load_extension(True)
        sqlite_vec.load(conn)
        conn.enable_load_extension(False)

        if project:
            # post-filter のため k を広めに取って絞り込み後 limit 件確保
            k = min(500, max(limit * 20, 100))
            rows = conn.execute(
                """
                SELECT
                    c.file_path, c.line_start, c.line_end, c.content,
                    v.distance
                FROM vec_chunks v
                JOIN chunks c ON c.id = v.rowid
                WHERE v.embedding MATCH ?
                  AND k = ?
                  AND c.project = ?
                ORDER BY v.distance
                LIMIT ?
                """,
                (query_bytes, k, project, limit),
            ).fetchall()
        else:
            rows = conn.execute(
                """
                SELECT
                    c.file_path, c.line_start, c.line_end, c.content,
                    v.distance
                FROM vec_chunks v
                JOIN chunks c ON c.id = v.rowid
                WHERE v.embedding MATCH ?
                  AND k = ?
                ORDER BY v.distance
                """,
                (query_bytes, limit),
            ).fetchall()
    except sqlite3.OperationalError as e:
        print(
            f"検索クエリ失敗: {e}\nDB が壊れている可能性: --force で再構築してください",
            file=sys.stderr,
        )
        return 1
    finally:
        conn.close()

    if not rows:
        hint = f"（project='{project}' 絞り込み）" if project else ""
        print(f"「{query}」に意味的に近い記述は見つかりませんでした{hint}")
        return 0

    out = []
    for file_path, line_start, line_end, content, distance in rows:
        out.append(f"### {file_path}:{line_start}-{line_end} (距離 {distance:.3f})")
        out.append(content)
        out.append("")

    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
