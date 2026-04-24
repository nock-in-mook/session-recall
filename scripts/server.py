#!/usr/bin/env python3
"""
session-recall MCP サーバー (Phase 3)

提供するツール:
  - session_recall_search: 全プロジェクトの SESSION_HISTORY/HANDOFF/DEVLOG を AND 検索

実体ロジックは scripts/search.sh に委譲（subprocess 経由）。
Phase 3.5 以降で SQLite FTS5 直接アクセスに置き換える可能性あり。
"""

import asyncio
import os
import subprocess
from pathlib import Path

import mcp.server.stdio
import mcp.types as types
from mcp.server import NotificationOptions, Server
from mcp.server.models import InitializationOptions

# search.sh の探索候補（Mac/Win 両対応）
SEARCH_SH_CANDIDATES = [
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_claude-sync/session-recall/search.sh",
    "/g/マイドライブ/_claude-sync/session-recall/search.sh",
    "/G/マイドライブ/_claude-sync/session-recall/search.sh",
]


def find_search_sh() -> str:
    for p in SEARCH_SH_CANDIDATES:
        if Path(p).is_file() and os.access(p, os.X_OK):
            return p
    raise FileNotFoundError(
        f"search.sh が見つかりません。候補: {SEARCH_SH_CANDIDATES}"
    )


server: Server = Server("session-recall")


@server.list_tools()
async def list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="session_recall_search",
            description=(
                "全プロジェクトの SESSION_HISTORY.md / HANDOFF.md / DEVLOG.md を "
                "AND 検索する。複数キーワード指定で精度が上がる。"
                "出力は project/file:行番号 ヘッダ + 前後 ±5 行のブロック。"
                "更新日時の新しいファイルから上位 10 件まで。"
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "keywords": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "検索キーワード（複数指定で AND 検索）。例: [\"ToDo\", \"結合\"]",
                        "minItems": 1,
                    }
                },
                "required": ["keywords"],
            },
        )
    ]


@server.call_tool()
async def call_tool(
    name: str, arguments: dict | None
) -> list[types.TextContent]:
    if name != "session_recall_search":
        raise ValueError(f"Unknown tool: {name}")

    if not arguments:
        return [types.TextContent(
            type="text",
            text="エラー: arguments が必要です（keywords を指定してください）",
        )]

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

    try:
        search_sh = find_search_sh()
    except FileNotFoundError as e:
        return [types.TextContent(type="text", text=str(e))]

    try:
        result = subprocess.run(
            ["bash", search_sh, *keywords],
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


async def main() -> None:
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="session-recall",
                server_version="3.0.0",
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )


if __name__ == "__main__":
    asyncio.run(main())
