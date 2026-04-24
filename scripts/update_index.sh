#!/usr/bin/env bash
# session-recall インデックスの増分更新（/end フック用）
#
# 設計:
#   - venv または DB が無ければサイレントにスキップ（初回 deploy 前は何もしない）
#   - 標準出力/標準エラーは捨てる（/end の出力に混ざらない）
#   - バックグラウンド起動を /end 側で行うことを前提にした「同期」スクリプト
#     （nohup + & で呼ばれる側、ここでは普通に exec）
#   - 失敗しても exit 0（呼び出し側が && でつながない限り影響なし）

set +e
set +u

VENV_PY=""
for p in \
    "$HOME/.claude/session-recall-venv/bin/python" \
    "$HOME/.claude/session-recall-venv/Scripts/python" \
    "$HOME/.claude/session-recall-venv/Scripts/python.exe" ; do
    if [ -x "$p" ]; then
        VENV_PY="$p"
        break
    fi
done

if [ -z "$VENV_PY" ]; then
    exit 0
fi

INDEX_DB="$HOME/.claude/session-recall-index.db"
if [ ! -f "$INDEX_DB" ]; then
    exit 0
fi

SCRIPT=""
for p in \
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_claude-sync/session-recall/index_build.py" \
    "/g/マイドライブ/_claude-sync/session-recall/index_build.py" \
    "/G/マイドライブ/_claude-sync/session-recall/index_build.py" ; do
    if [ -f "$p" ]; then
        SCRIPT="$p"
        break
    fi
done

if [ -z "$SCRIPT" ]; then
    exit 0
fi

# sleep 秒数は第 1 引数で指定可能（デフォルト 30）。
# /end 用途では並列書き出し（HANDOFF/SESSION_HISTORY/SESSION_LOG）を待ってから mtime 比較するため 30 秒必要
# （待たないと書き出し前の mtime でインデックスが走り、最新セッション分を取りこぼす — #5 で実際に発生）。
# セッション開始時の追いつき用途では書き出しを待つ必要がないため 0 を渡す。
sleep "${1:-30}"

# 増分更新（mtime 変更ファイルのみ再埋め込み）
"$VENV_PY" "$SCRIPT" --db "$INDEX_DB" --quiet >/dev/null 2>&1
exit 0
