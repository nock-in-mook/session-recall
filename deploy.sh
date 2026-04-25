#!/usr/bin/env bash
# session-recall の deploy スクリプト
#  - Phase 1: instructions/claude_md_patch.md のマーカー間ブロックを
#             ~/.claude/CLAUDE.md と _claude-sync/CLAUDE.md に注入
#  - Phase 2: commands/recall.md と scripts/search.sh を _claude-sync 経由で配置
#  - Phase 3: Python venv セットアップ + scripts/{server.py, run_server.sh} 配置
#             + claude mcp add で session-recall を user scope に登録
#  - Phase 4: 埋め込みライブラリ install + scripts/index_build.py 配置
#             + ~/.claude/session-recall-index.db が無ければ初回構築
#  - Phase 5: scripts/update_index.sh 配置 + _claude-sync/commands/end.md に
#             session-recall:end-hook ブロックを注入（/end 時に増分自動更新）
#  - Phase 7: scripts/{semantic.py, semantic.sh} を _claude-sync 経由で配置
#             （MCP regression 時の bash CLI フォールバック）
# 全工程冪等（差分なしならバックアップも作らない）。

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="$HOME/.claude"
PATCH_FILE="$SELF_DIR/instructions/claude_md_patch.md"
RECALL_MD="$SELF_DIR/commands/recall.md"
SEARCH_SH="$SELF_DIR/scripts/search.sh"
SERVER_PY="$SELF_DIR/scripts/server.py"
RUN_SERVER_SH="$SELF_DIR/scripts/run_server.sh"
INDEX_BUILD_PY="$SELF_DIR/scripts/index_build.py"
UPDATE_INDEX_SH="$SELF_DIR/scripts/update_index.sh"
SEMANTIC_PY="$SELF_DIR/scripts/semantic.py"
SEMANTIC_SH="$SELF_DIR/scripts/semantic.sh"
END_PATCH_FILE="$SELF_DIR/instructions/end_patch.md"
VENV_DIR="$CLAUDE_HOME/session-recall-venv"
INDEX_DB="$CLAUDE_HOME/session-recall-index.db"

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

# venv の python を返す（Mac は bin/、Win Git Bash は Scripts/）
venv_python() {
    for p in "$VENV_DIR/bin/python" "$VENV_DIR/Scripts/python" "$VENV_DIR/Scripts/python.exe"; do
        [ -x "$p" ] && echo "$p" && return 0
    done
    return 1
}

# Python venv セットアップ + mcp パッケージ install（PC ローカル、Drive 同期しない）
setup_venv() {
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

    local venv_py
    venv_py="$(venv_python)" || { echo "  エラー: venv の python が見つかりません" >&2; return 1; }

    if "$venv_py" -c "import mcp" >/dev/null 2>&1; then
        echo "  mcp パッケージ: 既にインストール済み"
    else
        echo "  mcp パッケージをインストール中..."
        "$venv_py" -m pip install --quiet --upgrade pip
        "$venv_py" -m pip install --quiet mcp
        echo "  mcp パッケージ: インストール完了"
    fi
}

# Phase 4 用: 埋め込みライブラリ install
setup_venv_phase4() {
    local venv_py
    venv_py="$(venv_python)" || { echo "  venv 未セットアップ"; return 1; }

    if "$venv_py" -c "import sentence_transformers, sqlite_vec" >/dev/null 2>&1; then
        echo "  sentence-transformers + sqlite-vec: 既にインストール済み"
    else
        echo "  sentence-transformers + sqlite-vec をインストール中（PyTorch 含む、数分かかる）..."
        "$venv_py" -m pip install --quiet sentence-transformers sqlite-vec
        echo "  完了"
    fi
}

# 初回 index 構築（DB が無ければ実行、あればスキップ）
build_index_if_missing() {
    if [ -f "$INDEX_DB" ]; then
        local size_mb
        size_mb=$(du -m "$INDEX_DB" 2>/dev/null | awk '{print $1}')
        echo "  index DB 既存: $INDEX_DB (${size_mb} MB)"
        echo "  増分更新は別途 'python index_build.py' を手動実行（または /end フック）"
        return 0
    fi

    local venv_py
    venv_py="$(venv_python)" || { echo "  venv 未セットアップ"; return 1; }

    echo "  index DB 初回構築中（モデル DL ~470MB + 全プロジェクト埋め込み、数分かかる）..."
    "$venv_py" "$INDEX_BUILD_PY" --db "$INDEX_DB"
}

# end_patch.md からマーカー間ブロックを抽出（行頭一致）
extract_end_hook_block() {
    awk '
        /^<!-- session-recall:end-hook:begin/ { p=1 }
        p { print }
        /^<!-- session-recall:end-hook:end/   { p=0 }
    ' "$END_PATCH_FILE"
}

# end.md にマーカー間ブロックを注入（冪等、CLAUDE.md と同じ要領）
inject_end_hook() {
    local target="$1"

    if [ ! -f "$target" ]; then
        echo "  $target が存在しないためスキップ（先に他の deploy 系を整えてください）" >&2
        return 0
    fi

    local block_file
    block_file="$(mktemp)"
    extract_end_hook_block > "$block_file"

    if [ ! -s "$block_file" ]; then
        echo "  エラー: $END_PATCH_FILE からマーカー間が抽出できませんでした" >&2
        rm -f "$block_file"
        return 1
    fi

    local tmp
    tmp="$(mktemp)"
    local mode

    if grep -q "^<!-- session-recall:end-hook:begin" "$target"; then
        awk -v blockfile="$block_file" '
            BEGIN {
                while ((getline line < blockfile) > 0) {
                    block = block line "\n"
                }
                close(blockfile)
            }
            /^<!-- session-recall:end-hook:begin/ {
                printf "%s", block
                skip = 1
                next
            }
            /^<!-- session-recall:end-hook:end/ {
                skip = 0
                next
            }
            !skip { print }
        ' "$target" > "$tmp"
        mode="マーカー間置換"
    else
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

    if claude mcp list 2>/dev/null | grep -qE "^session-recall:"; then
        echo "  session-recall MCP server: 登録済み"
        return 0
    fi

    echo "  claude mcp add --scope user session-recall <run_server.sh>"
    claude mcp add --scope user session-recall "$run_server" 2>&1 | sed 's/^/    /'
}

# === Phase 1: CLAUDE.md 注入 ===
echo "─── Phase 1: CLAUDE.md 注入 ───"
echo "[1/15] $CLAUDE_HOME/CLAUDE.md"
inject_into "$CLAUDE_HOME/CLAUDE.md"
echo ""

if [ -n "$SYNC_DIR" ]; then
    echo "[2/15] $SYNC_DIR/CLAUDE.md"
    inject_into "$SYNC_DIR/CLAUDE.md"
else
    echo "[2/15] _claude-sync 未検出のためスキップ"
fi
echo ""

# === Phase 2: スキル & 検索スクリプト配置 ===
echo "─── Phase 2: スキル & 検索スクリプト配置 ───"
if [ -n "$SYNC_DIR" ]; then
    echo "[3/15] $SYNC_DIR/commands/recall.md"
    sync_file "$RECALL_MD" "$SYNC_DIR/commands/recall.md"
    echo ""

    echo "[4/15] $SYNC_DIR/session-recall/search.sh"
    sync_file "$SEARCH_SH" "$SYNC_DIR/session-recall/search.sh"
    chmod +x "$SYNC_DIR/session-recall/search.sh"
else
    echo "[3/15] _claude-sync 未検出のためスキップ"
    echo "[4/15] _claude-sync 未検出のためスキップ"
fi
echo ""

# === Phase 3: MCP サーバー (キーワード検索) ===
echo "─── Phase 3: MCP サーバー (キーワード検索) ───"
echo "[5/15] venv セットアップ + mcp パッケージ ($VENV_DIR)"
setup_venv
echo ""

if [ -n "$SYNC_DIR" ]; then
    echo "[6/15] $SYNC_DIR/session-recall/server.py"
    sync_file "$SERVER_PY" "$SYNC_DIR/session-recall/server.py"
    echo ""

    echo "[7/15] $SYNC_DIR/session-recall/run_server.sh"
    sync_file "$RUN_SERVER_SH" "$SYNC_DIR/session-recall/run_server.sh"
    chmod +x "$SYNC_DIR/session-recall/run_server.sh"
    echo ""

    echo "[8/15] MCP server 登録 (claude mcp add --scope user)"
    register_mcp_server
else
    echo "[6/15] _claude-sync 未検出のためスキップ"
    echo "[7/15] _claude-sync 未検出のためスキップ"
    echo "[8/15] _claude-sync 未検出のためスキップ"
fi
echo ""

# === Phase 4: セマンティック検索 ===
echo "─── Phase 4: セマンティック検索（埋め込み + ベクトル DB）───"
echo "[9/15] sentence-transformers + sqlite-vec を venv に追加"
setup_venv_phase4
echo ""

if [ -n "$SYNC_DIR" ]; then
    echo "[10/15] $SYNC_DIR/session-recall/index_build.py"
    sync_file "$INDEX_BUILD_PY" "$SYNC_DIR/session-recall/index_build.py"
    chmod +x "$SYNC_DIR/session-recall/index_build.py"
else
    echo "[10/15] _claude-sync 未検出のためスキップ"
fi
echo ""

echo "[11/15] index DB 構築 (PC ローカル: $INDEX_DB)"
build_index_if_missing
echo ""

# === Phase 5: /end フック（増分インデックス自動更新）===
echo "─── Phase 5: /end フック（増分インデックス自動更新）───"
if [ -n "$SYNC_DIR" ]; then
    echo "[12/15] $SYNC_DIR/session-recall/update_index.sh"
    sync_file "$UPDATE_INDEX_SH" "$SYNC_DIR/session-recall/update_index.sh"
    chmod +x "$SYNC_DIR/session-recall/update_index.sh"
    echo ""

    echo "[13/15] $SYNC_DIR/commands/end.md (session-recall:end-hook ブロック注入)"
    inject_end_hook "$SYNC_DIR/commands/end.md"
else
    echo "[12/15] _claude-sync 未検出のためスキップ"
    echo "[13/15] _claude-sync 未検出のためスキップ"
fi
echo ""

# === Phase 7: bash CLI フォールバック (semantic.py + semantic.sh) ===
echo "─── Phase 7: bash CLI フォールバック（MCP regression 時の保険）───"
if [ -n "$SYNC_DIR" ]; then
    echo "[14/15] $SYNC_DIR/session-recall/semantic.py"
    sync_file "$SEMANTIC_PY" "$SYNC_DIR/session-recall/semantic.py"
    chmod +x "$SYNC_DIR/session-recall/semantic.py"
    echo ""

    echo "[15/15] $SYNC_DIR/session-recall/semantic.sh"
    sync_file "$SEMANTIC_SH" "$SYNC_DIR/session-recall/semantic.sh"
    chmod +x "$SYNC_DIR/session-recall/semantic.sh"
else
    echo "[14/15] _claude-sync 未検出のためスキップ"
    echo "[15/15] _claude-sync 未検出のためスキップ"
fi
echo ""

echo "deploy 完了。"
echo ""
echo "ヒント:"
echo "  - MCP サーバーを Claude Code で有効化するには Claude Code の再起動が必要"
echo "  - 増分インデックス更新は手動で:  ~/.claude/session-recall-venv/bin/python $INDEX_BUILD_PY"
echo "  - 全再構築は: ~/.claude/session-recall-venv/bin/python $INDEX_BUILD_PY --force"
