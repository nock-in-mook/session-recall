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

# 増分更新（mtime 変更ファイルのみ再埋め込み）
"$VENV_PY" "$SCRIPT" --db "$INDEX_DB" --quiet >/dev/null 2>&1
exit 0
