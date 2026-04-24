#!/usr/bin/env bash
# session-recall の deploy スクリプト。
# `~/.claude/` と `_claude-sync/` に本番反映する。
#
# 未実装。Phase 1 以降で段階的に中身を書いていく。

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="$HOME/.claude"

# Mac/Win のパス差異
for p in \
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_claude-sync" \
    "/g/マイドライブ/_claude-sync" \
    "$HOME/Dropbox/_claude-sync" ; do
    if [ -d "$p" ]; then
        SYNC_DIR="$p"
        break
    fi
done

echo "=== session-recall deploy ==="
echo "source : $SELF_DIR"
echo "claude : $CLAUDE_HOME"
echo "sync   : ${SYNC_DIR:-(未検出)}"
echo ""
echo "[TODO] Phase 1 で以下を実装:"
echo "  - CLAUDE.md への追記処理"
echo "  - 既存 CLAUDE.md のバックアップ"
echo "  - skills/ のコピー"
echo "  - _claude-sync/ への同期"
echo ""
echo "未実装のため終了。"
exit 1
