#!/usr/bin/env bash
# session-recall の deploy スクリプト
#  - Phase 1: instructions/claude_md_patch.md のマーカー間ブロックを
#             ~/.claude/CLAUDE.md と _claude-sync/CLAUDE.md に注入
#  - Phase 2: commands/recall.md と scripts/search.sh を _claude-sync 経由で配置
# 全工程冪等（差分なしならバックアップも作らない）。

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="$HOME/.claude"
PATCH_FILE="$SELF_DIR/instructions/claude_md_patch.md"
RECALL_MD="$SELF_DIR/commands/recall.md"
SEARCH_SH="$SELF_DIR/scripts/search.sh"

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
echo ""

# patch ファイルからマーカー間ブロック（マーカー行を含む）を抽出
# マーカーは行頭一致のみ採用（説明文中のバックティック例示などを誤マッチしない）
extract_block() {
    awk '
        /^<!-- session-recall:begin/ { p=1 }
        p { print }
        /^<!-- session-recall:end/   { p=0 }
    ' "$PATCH_FILE"
}

# CLAUDE.md にマーカー間ブロックを注入（冪等）
#  - 既存マーカーあり → マーカー間を最新ブロックで置換（バージョン違いも検出）
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

    if grep -q "^<!-- session-recall:begin" "$target"; then
        # マーカーあり → マーカー間を新ブロックで置換（行頭マッチのみ）
        awk -v blockfile="$block_file" '
            BEGIN {
                while ((getline line < blockfile) > 0) {
                    block = block line "\n"
                }
                close(blockfile)
            }
            /^<!-- session-recall:begin/ {
                printf "%s", block
                skip = 1
                next
            }
            /^<!-- session-recall:end/ {
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

# ファイル単純コピー（冪等、差分なしならバックアップも作らない）
sync_file() {
    local src="$1"
    local dst="$2"

    if [ ! -f "$src" ]; then
        echo "  エラー: ソース $src が見つかりません" >&2
        return 1
    fi

    mkdir -p "$(dirname "$dst")"

    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        echo "  $dst → 変更なし"
        return 0
    fi

    if [ -f "$dst" ]; then
        local backup="${dst}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$dst" "$backup"
        echo "    バックアップ: $backup"
    fi
    cp "$src" "$dst"
    echo "  $dst → 更新"
}

# === Phase 1: CLAUDE.md 注入 ===
echo "─── Phase 1: CLAUDE.md 注入 ───"
echo "[1/4] $CLAUDE_HOME/CLAUDE.md"
inject_into "$CLAUDE_HOME/CLAUDE.md"
echo ""

if [ -n "$SYNC_DIR" ]; then
    echo "[2/4] $SYNC_DIR/CLAUDE.md"
    inject_into "$SYNC_DIR/CLAUDE.md"
else
    echo "[2/4] _claude-sync 未検出のためスキップ"
fi
echo ""

# === Phase 2: スキル & スクリプト配置 ===
echo "─── Phase 2: スキル & スクリプト配置 ───"
if [ -n "$SYNC_DIR" ]; then
    echo "[3/4] $SYNC_DIR/commands/recall.md"
    sync_file "$RECALL_MD" "$SYNC_DIR/commands/recall.md"
    echo ""

    echo "[4/4] $SYNC_DIR/session-recall/search.sh"
    sync_file "$SEARCH_SH" "$SYNC_DIR/session-recall/search.sh"
    chmod +x "$SYNC_DIR/session-recall/search.sh"
else
    echo "[3/4] _claude-sync 未検出のためスキップ（recall.md 配置不可）"
    echo "[4/4] _claude-sync 未検出のためスキップ（search.sh 配置不可）"
fi
echo ""

echo "deploy 完了。"
