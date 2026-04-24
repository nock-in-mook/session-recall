#!/usr/bin/env bash
# session-recall MCP サーバー起動 wrapper（Mac/Win 両対応）
# venv は ~/.claude/session-recall-venv/ に PC ローカルで作る（Drive 同期しない）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_PY="$SCRIPT_DIR/server.py"

# venv の python を探す（Mac: bin/、Win Git Bash: Scripts/）
VENV_DIR="$HOME/.claude/session-recall-venv"
VENV_PY=""
for candidate in "$VENV_DIR/bin/python" "$VENV_DIR/Scripts/python" "$VENV_DIR/Scripts/python.exe"; do
    if [ -x "$candidate" ]; then
        VENV_PY="$candidate"
        break
    fi
done

if [ -z "$VENV_PY" ]; then
    echo "session-recall MCP サーバーの venv が見つかりません: $VENV_DIR" >&2
    echo "deploy.sh を実行して venv をセットアップしてください" >&2
    exit 1
fi

if [ ! -f "$SERVER_PY" ]; then
    echo "server.py が見つかりません: $SERVER_PY" >&2
    exit 1
fi

# stdio で MCP プロトコル通信
exec "$VENV_PY" "$SERVER_PY" "$@"
