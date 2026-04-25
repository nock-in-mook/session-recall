#!/usr/bin/env bash
# session-recall セマンティック検索 CLI ラッパー (Phase 7、Mac/Win 両対応)
#
# Claude Code 2.1.116〜 の custom stdio MCP regression で MCP 経由が
# 使えない場合のフォールバック。run_server.sh と同じく venv の python
# を自動探索して semantic.py を起動する。
#
# 使い方:
#     bash semantic.sh "クエリ文" [--project NAME] [--limit N]
#
# 例:
#     bash semantic.sh "claude-mem を撤去した経緯"
#     bash semantic.sh "ToDo 結合の議論" --project Memolette-Flutter --limit 3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEMANTIC_PY="$SCRIPT_DIR/semantic.py"

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
    echo "session-recall の venv が見つかりません: $VENV_DIR" >&2
    echo "deploy.sh を実行して venv をセットアップしてください" >&2
    exit 1
fi

if [ ! -f "$SEMANTIC_PY" ]; then
    echo "semantic.py が見つかりません: $SEMANTIC_PY" >&2
    exit 1
fi

# 引数なしならヘルプ表示
if [ $# -eq 0 ]; then
    cat <<'EOF'
使い方: bash semantic.sh "クエリ文" [--project NAME] [--limit N]

例:
    bash semantic.sh "claude-mem を撤去した経緯"
    bash semantic.sh "ToDo 結合の議論" --project Memolette-Flutter --limit 3

検索対象:
    全プロジェクトの SESSION_HISTORY.md / HANDOFF.md / DEVLOG.md を
    multilingual-e5-small で意味検索（インデックス DB は ~/.claude/session-recall-index.db）
EOF
    exit 0
fi

exec "$VENV_PY" "$SEMANTIC_PY" "$@"
