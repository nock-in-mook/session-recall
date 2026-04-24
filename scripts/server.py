#!/usr/bin/env python3
"""
session-recall MCP サーバー (Phase 6)

提供するツール:
  - session_recall_search   : キーワード AND 検索（search.sh ベース、Phase 2 由来）
  - session_recall_semantic : 意味的検索（multilingual-e5-small + sqlite-vec、Phase 4 で追加）

両 tool は Phase 6 で `project` optional 引数をサポート（プロジェクト絞り込み）。
セマンティック検索 DB は ~/.claude/session-recall-index.db に PC ローカル。
deploy.sh の Phase 4 工程または手動で `index_build.py` を回して構築する。
"""

import asyncio
import os
import sqlite3
import subprocess
from pathlib import Path
from typing import Optional

import mcp.server.stdio
import mcp.types as types
import sqlite_vec
from mcp.server import NotificationOptions, Server
from mcp.server.models import InitializationOptions

# search.sh の探索候補（Mac/Win 両対応）
SEARCH_SH_CANDIDATES = [
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_claude-sync/session-recall/search.sh",
    "/g/マイドライブ/_claude-sync/session-recall/search.sh",
    "/G/マイドライブ/_claude-sync/session-recall/search.sh",
]

# セマンティック検索インデックス DB（PC ローカル）
INDEX_DB_CANDIDATES = [
    str(Path.home() / ".claude" / "session-recall-index.db"),
]

EMBED_MODEL_NAME = "intfloat/multilingual-e5-small"

# 埋め込みモデルは初回呼び出し時に遅延ロード（起動オーバーヘッド回避）
_model = None


def get_model():
    global _model
    if _model is None:
        # ロード時のみ重い import を実行
        from sentence_transformers import SentenceTransformer
        _model = SentenceTransformer(EMBED_MODEL_NAME)
    return _model


def find_search_sh() -> str:
    for p in SEARCH_SH_CANDIDATES:
        if Path(p).is_file() and os.access(p, os.X_OK):
            return p
    raise FileNotFoundError(
        f"search.sh が見つかりません。候補: {SEARCH_SH_CANDIDATES}"
    )


def find_index_db() -> Optional[str]:
    for p in INDEX_DB_CANDIDATES:
        if Path(p).is_file():
            return p
    return None


server: Server = Server("session-recall")


@server.list_tools()
async def list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="session_recall_search",
            description=(
                "全プロジェクトの SESSION_HISTORY.md / HANDOFF.md / DEVLOG.md を AND 検索する。"
                "キーワードが明確なときに使う（例: ['ToDo', '結合']、['claude-mem', '撤去']）。"
                "会話で特定のプロジェクト名（Memolette-Flutter / session-recall / Kanji_Stroke 等）が"
                "出ていて、その中だけ調べたい場合は project 引数で絞り込むと精度・速度ともに向上する。"
                "出力は project/file:行番号 ヘッダ + 前後 ±5 行のブロック、更新日時の新しい順、上位 10 件。"
                "曖昧な概念検索（『あのボタン配置の議論』等）は session_recall_semantic を使う。"
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "keywords": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "検索キーワード（複数指定で AND 検索）。例: [\"ToDo\", \"結合\"]",
                        "minItems": 1,
                    },
                    "project": {
                        "type": "string",
                        "description": (
                            "絞り込むプロジェクト名（_Apps2026/ or _other-projects/ 直下のフォルダ名）。"
                            "省略時は全プロジェクト横断。例: 'Memolette-Flutter', 'session-recall'"
                        ),
                    },
                },
                "required": ["keywords"],
            },
        ),
        types.Tool(
            name="session_recall_semantic",
            description=(
                "全プロジェクトの SESSION_HISTORY.md / HANDOFF.md / DEVLOG.md を"
                "意味的に近い順で検索する。キーワード一致しない曖昧クエリ向け。"
                "例: 『あのボタン配置で議論した時』『パフォーマンスで悩んだ件』『○○を諦めた経緯』"
                "会話で特定のプロジェクト名が出ていてその中だけ調べたい場合は project 引数で絞り込む。"
                "出力は file:行範囲 + 距離スコア + 該当段落。スコア小さいほど近い。"
                "キーワードが明確なら session_recall_search のほうが速くて正確。"
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "意味的に検索したい問い。1 文の自然言語推奨。",
                    },
                    "limit": {
                        "type": "integer",
                        "description": "返す上位件数（デフォルト 5、上限 30）",
                        "minimum": 1,
                        "maximum": 30,
                        "default": 5,
                    },
                    "project": {
                        "type": "string",
                        "description": (
                            "絞り込むプロジェクト名（_Apps2026/ or _other-projects/ 直下のフォルダ名）。"
                            "省略時は全プロジェクト横断。例: 'Memolette-Flutter', 'session-recall'"
                        ),
                    },
                },
                "required": ["query"],
            },
        ),
    ]


async def keyword_search(arguments: dict) -> list[types.TextContent]:
    keywords = arguments.get("keywords", [])
    if not isinstance(keywords, list) or not keywords:
        return [types.TextContent(
            type="text",
            text="エラー: keywords は 1 つ以上の文字列の配列を指定してください",
        )]
    keywords = [str(k) for k in keywords if str(k).strip()]
    if not keywords:
        return [types.TextContent(
            type="text",
            text="エラー: 空でないキーワードを最低 1 つ指定してください",
        )]

    project = str(arguments.get("project", "")).strip() or None

    try:
        search_sh = find_search_sh()
    except FileNotFoundError as e:
        return [types.TextContent(type="text", text=str(e))]

    cmd = ["bash", search_sh]
    if project:
        cmd.extend(["--project", project])
    cmd.extend(keywords)

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ, "LC_ALL": "en_US.UTF-8", "LANG": "en_US.UTF-8"},
        )
    except subprocess.TimeoutExpired:
        return [types.TextContent(
            type="text",
            text="検索がタイムアウトしました（30 秒）",
        )]

    output = result.stdout if result.stdout else "（出力なし）"
    if result.returncode != 0 and result.stderr:
        output += f"\n\n--- stderr ---\n{result.stderr}"

    return [types.TextContent(type="text", text=output)]


async def semantic_search(arguments: dict) -> list[types.TextContent]:
    query = str(arguments.get("query", "")).strip()
    if not query:
        return [types.TextContent(
            type="text",
            text="エラー: query が空です",
        )]

    limit_raw = arguments.get("limit", 5)
    try:
        limit = max(1, min(30, int(limit_raw)))
    except (TypeError, ValueError):
        limit = 5

    project = str(arguments.get("project", "")).strip() or None

    db_path = find_index_db()
    if not db_path:
        return [types.TextContent(
            type="text",
            text=(
                "セマンティック検索 DB が未構築です。\n"
                "以下のいずれかでインデックスを構築してください:\n"
                "  bash <session-recall>/deploy.sh                # フル deploy（Phase 1〜4）\n"
                "  python <session-recall>/scripts/index_build.py # 単体実行"
            ),
        )]

    try:
        model = get_model()
        # multilingual-e5 は "query: " prefix を使うのが推奨
        query_vec = model.encode([f"query: {query}"])[0]
        query_bytes = query_vec.astype("float32").tobytes()
    except Exception as e:
        return [types.TextContent(
            type="text",
            text=f"埋め込み生成に失敗: {e}",
        )]

    conn = sqlite3.connect(db_path)
    try:
        conn.enable_load_extension(True)
        sqlite_vec.load(conn)
        conn.enable_load_extension(False)

        if project:
            # sqlite-vec の k = ? は「近傍 k 件取得」の指示。追加 WHERE は post-filter
            # として効くため、project 絞り込み後に limit 件確保できるよう k を広く取る。
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
        return [types.TextContent(
            type="text",
            text=f"検索クエリ失敗: {e}\nDB が壊れている可能性: --force で再構築してください",
        )]
    finally:
        conn.close()

    if not rows:
        hint = f"（project='{project}' 絞り込み）" if project else ""
        return [types.TextContent(
            type="text",
            text=f"「{query}」に意味的に近い記述は見つかりませんでした{hint}",
        )]

    out = []
    for file_path, line_start, line_end, content, distance in rows:
        out.append(f"### {file_path}:{line_start}-{line_end} (距離 {distance:.3f})")
        out.append(content)
        out.append("")

    return [types.TextContent(type="text", text="\n".join(out))]


@server.call_tool()
async def call_tool(
    name: str, arguments: dict | None
) -> list[types.TextContent]:
    if not arguments:
        arguments = {}

    if name == "session_recall_search":
        return await keyword_search(arguments)
    elif name == "session_recall_semantic":
        return await semantic_search(arguments)
    else:
        raise ValueError(f"Unknown tool: {name}")


async def main() -> None:
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="session-recall",
                server_version="6.0.0",
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )


if __name__ == "__main__":
    asyncio.run(main())
