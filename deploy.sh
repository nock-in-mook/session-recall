#!/usr/bin/env bash
# session-recall の deploy スクリプト
#  - Phase 1: instructions/claude_md_patch.md のマーカー間ブロックを
#             ~/.claude/CLAUDE.md と _claude-sync/CLAUDE.md に注入
#  - Phase 2: commands/recall.md と scripts/search.sh を _claude-sync 経由で配置
#  - Phase 3: Python venv セットアップ + scripts/server.py & run_server.sh 配置
#             + ~/.claude/settings.local.json に MCP サーバー登録
# 全工程冪等（差分なしならバックアップも作らない）。

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="$HOME/.claude"
PATCH_FILE="$SELF_DIR/instructions/claude_md_patch.md"
RECALL_MD="$SELF_DIR/commands/recall.md"
SEARCH_SH="$SELF_DIR/scripts/search.sh"
SERVER_PY="$SELF_DIR/scripts/server.py"
RUN_SERVER_SH="$SELF_DIR/scripts/run_server.sh"
VENV_DIR="$CLAUDE_HOME/session-recall-venv"

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
        # マーカー無し → 末尾追記
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

# ファイル単純コピー（冪等）
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

# Python venv セットアップ（PC ローカル、Drive 同期しない）
# venv に mcp パッケージをインストール
setup_venv() {
    # Python 3.10+ を探す（Mac: Homebrew python3.12、Win: py -3.14）
    local py_cmd=""
    if command -v py >/dev/null 2>&1 && py -3.14 --version >/dev/null 2>&1; then
        py_cmd="py -3.14"
    elif command -v py >/dev/null 2>&1 && py -3.12 --version >/dev/null 2>&1; then
        py_cmd="py -3.12"
    else
        for cmd in \
            "/opt/homebrew/bin/python3.12" \
            "/opt/homebrew/bin/python3.13" \
            "/opt/homebrew/bin/python3.11" \
            "python3.12" "python3.13" "python3.11" "python3.10" ; do
            if command -v "$cmd" >/dev/null 2>&1; then
                py_cmd="$cmd"
                break
            fi
        done
    fi

    if [ -z "$py_cmd" ]; then
        echo "  Python 3.10+ が見つかりません。venv セットアップをスキップ" >&2
        return 1
    fi

    if [ ! -d "$VENV_DIR" ]; then
        echo "  venv 作成: $VENV_DIR (using $py_cmd)"
        $py_cmd -m venv "$VENV_DIR"
    else
        echo "  venv 既存: $VENV_DIR"
    fi

    # venv 内の python を特定
    local venv_py=""
    for p in "$VENV_DIR/bin/python" "$VENV_DIR/Scripts/python" "$VENV_DIR/Scripts/python.exe"; do
        [ -x "$p" ] && venv_py="$p" && break
    done

    if [ -z "$venv_py" ]; then
        echo "  エラー: venv の python が見つかりません" >&2
        return 1
    fi

    # mcp パッケージ確認・インストール
    if "$venv_py" -c "import mcp" >/dev/null 2>&1; then
        echo "  mcp パッケージ: 既にインストール済み"
    else
        echo "  mcp パッケージをインストール中..."
        "$venv_py" -m pip install --quiet --upgrade pip
        "$venv_py" -m pip install --quiet mcp
        echo "  mcp パッケージ: インストール完了"
    fi
}

# MCP サーバー登録（Claude Code 2.x 以降は `claude mcp add` 経由が正規）
# 注: 当初 settings.local.json の mcpServers キーに書き込んでいたが、
#     Claude Code 2.x はそれを読まないため、claude mcp add --scope user に統一。
register_mcp_server() {
    local run_server="$SYNC_DIR/session-recall/run_server.sh"

    # 旧形式（settings.local.json.mcpServers）のクリーンアップ
    if command -v jq >/dev/null 2>&1; then
        local settings="$CLAUDE_HOME/settings.local.json"
        if [ -f "$settings" ] && jq -e '.mcpServers' "$settings" >/dev/null 2>&1; then
            local tmp
            tmp="$(mktemp)"
            jq 'del(.mcpServers)' "$settings" > "$tmp"
            mv "$tmp" "$settings"
            echo "  旧形式の mcpServers キーを $settings から削除"
        fi
    fi

    if ! command -v claude >/dev/null 2>&1; then
        echo "  claude CLI が見つかりません（MCP 登録スキップ）" >&2
        return 1
    fi

    # 既に登録済みかチェック
    if claude mcp list 2>/dev/null | grep -qE "^session-recall:"; then
        echo "  session-recall MCP server: 登録済み"
        return 0
    fi

    # claude mcp add で user scope に登録（~/.claude.json に書かれる）
    echo "  claude mcp add --scope user session-recall <run_server.sh>"
    claude mcp add --scope user session-recall "$run_server" 2>&1 | sed 's/^/    /'
}

# === Phase 1: CLAUDE.md 注入 ===
echo "─── Phase 1: CLAUDE.md 注入 ───"
echo "[1/8] $CLAUDE_HOME/CLAUDE.md"
inject_into "$CLAUDE_HOME/CLAUDE.md"
echo ""

if [ -n "$SYNC_DIR" ]; then
    echo "[2/8] $SYNC_DIR/CLAUDE.md"
    inject_into "$SYNC_DIR/CLAUDE.md"
else
    echo "[2/8] _claude-sync 未検出のためスキップ"
fi
echo ""

# === Phase 2: スキル & スクリプト配置 ===
echo "─── Phase 2: スキル & 検索スクリプト配置 ───"
if [ -n "$SYNC_DIR" ]; then
    echo "[3/8] $SYNC_DIR/commands/recall.md"
    sync_file "$RECALL_MD" "$SYNC_DIR/commands/recall.md"
    echo ""

    echo "[4/8] $SYNC_DIR/session-recall/search.sh"
    sync_file "$SEARCH_SH" "$SYNC_DIR/session-recall/search.sh"
    chmod +x "$SYNC_DIR/session-recall/search.sh"
else
    echo "[3/8] _claude-sync 未検出のためスキップ"
    echo "[4/8] _claude-sync 未検出のためスキップ"
fi
echo ""

# === Phase 3: MCP サーバー配置 + venv + 登録 ===
echo "─── Phase 3: MCP サーバー ───"
echo "[5/8] venv セットアップ ($VENV_DIR)"
setup_venv
echo ""

if [ -n "$SYNC_DIR" ]; then
    echo "[6/8] $SYNC_DIR/session-recall/server.py"
    sync_file "$SERVER_PY" "$SYNC_DIR/session-recall/server.py"
    echo ""

    echo "[7/8] $SYNC_DIR/session-recall/run_server.sh"
    sync_file "$RUN_SERVER_SH" "$SYNC_DIR/session-recall/run_server.sh"
    chmod +x "$SYNC_DIR/session-recall/run_server.sh"
    echo ""

    echo "[8/8] MCP server 登録 (claude mcp add --scope user)"
    register_mcp_server
else
    echo "[6/8] _claude-sync 未検出のためスキップ"
    echo "[7/8] _claude-sync 未検出のためスキップ"
    echo "[8/8] _claude-sync 未検出のためスキップ"
fi

echo ""
echo "deploy 完了。"
echo ""
echo "ヒント: MCP サーバーを Claude Code で有効化するには Claude Code の再起動が必要です。"
