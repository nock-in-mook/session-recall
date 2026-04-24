#!/usr/bin/env bash
# session-recall の deploy スクリプト
# instructions/claude_md_patch.md のマーカー間ブロックを
# ~/.claude/CLAUDE.md と _claude-sync/CLAUDE.md に注入する（冪等）。

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="$HOME/.claude"
PATCH_FILE="$SELF_DIR/instructions/claude_md_patch.md"

# _claude-sync の場所（Mac/Win 両対応）
SYNC_DIR=""
for p in \
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_claude-sync" \
    "/g/マイドライブ/_claude-sync" \
    "/G/マイドライブ/_claude-sync" \
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
echo "patch  : $PATCH_FILE"
echo ""

if [ ! -f "$PATCH_FILE" ]; then
    echo "エラー: patch ファイルが見つかりません: $PATCH_FILE" >&2
    exit 1
fi

# patch ファイルからマーカー間ブロック（マーカー行を含む）を抽出
extract_block() {
    awk '
        /<!-- session-recall:begin/ { p=1 }
        p { print }
        /<!-- session-recall:end/   { p=0 }
    ' "$PATCH_FILE"
}

# 抽出ブロックを CLAUDE.md に注入（冪等）
#  - 既存マーカーあり → マーカー間を最新ブロックで置換
#  - マーカー無し     → 末尾に追記
#  - 内容差分が無ければ何もせず終了（バックアップも作らない）
inject_into() {
    local target="$1"

    if [ ! -f "$target" ]; then
        mkdir -p "$(dirname "$target")"
        touch "$target"
        echo "  新規作成: $target"
    fi

    local block_file
    block_file="$(mktemp)"
    extract_block > "$block_file"

    if [ ! -s "$block_file" ]; then
        echo "  エラー: $PATCH_FILE からマーカー間が抽出できませんでした" >&2
        rm -f "$block_file"
        return 1
    fi

    local tmp
    tmp="$(mktemp)"
    local mode

    if grep -q "<!-- session-recall:begin" "$target"; then
        # マーカーあり → マーカー間を新ブロックで置換
        awk -v blockfile="$block_file" '
            BEGIN {
                while ((getline line < blockfile) > 0) {
                    block = block line "\n"
                }
                close(blockfile)
            }
            /<!-- session-recall:begin/ {
                printf "%s", block
                skip = 1
                next
            }
            /<!-- session-recall:end/ {
                skip = 0
                next
            }
            !skip { print }
        ' "$target" > "$tmp"
        mode="マーカー間置換"
    else
        # マーカー無し → 末尾追記（前に空行 2 つ入れて区切る）
        cat "$target" > "$tmp"
        printf '\n\n' >> "$tmp"
        cat "$block_file" >> "$tmp"
        mode="末尾追記"
    fi

    if cmp -s "$target" "$tmp"; then
        echo "  $target → 変更なし"
        rm -f "$tmp" "$block_file"
        return 0
    fi

    local backup="${target}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$target" "$backup"
    mv "$tmp" "$target"
    echo "  $target → $mode で更新"
    echo "    バックアップ: $backup"
    rm -f "$block_file"
}

echo "[1/2] $CLAUDE_HOME/CLAUDE.md"
inject_into "$CLAUDE_HOME/CLAUDE.md"
echo ""

if [ -n "$SYNC_DIR" ]; then
    echo "[2/2] $SYNC_DIR/CLAUDE.md"
    inject_into "$SYNC_DIR/CLAUDE.md"
else
    echo "[2/2] _claude-sync が未検出のためスキップ"
fi

echo ""
echo "deploy 完了。"
