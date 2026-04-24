#!/usr/bin/env bash
# /recall スキルの実処理（session-recall Phase 2）
# 使い方: search.sh <キーワード> [<キーワード2> ...]
#
# 複数キーワードは AND 検索（同じファイル内に全キーワードが存在）。
# 出力: 「### project/file:line」見出し + 前後 ±5 行の本文。
# 上位 10 ファイルまで表示、超過分は件数のみ末尾に表示。

set -uo pipefail
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# 引数なし → ヘルプ表示
if [ $# -eq 0 ]; then
    cat <<'EOF'
使い方: /recall <キーワード> [<キーワード2> ...]

複数キーワードは AND 検索（同じファイル内に全キーワードが存在）。

例:
    /recall ToDo 結合
    /recall claude-mem 撤去
    /recall Flutter ビルド エラー

検索対象:
    各プロジェクト直下の SESSION_HISTORY.md / HANDOFF.md / DEVLOG.md
    （_Apps2026/ と _other-projects/ 配下、Mac/Win 両対応）
EOF
    exit 0
fi

# 検索ルートを構築（Mac/Win 両対応、存在する方を採用）
ROOTS=()
for r in \
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_Apps2026" \
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_other-projects" \
    "/g/マイドライブ/_Apps2026" \
    "/g/マイドライブ/_other-projects" \
    "/G/マイドライブ/_Apps2026" \
    "/G/マイドライブ/_other-projects" ; do
    [ -d "$r" ] && ROOTS+=("$r")
done

if [ ${#ROOTS[@]} -eq 0 ]; then
    echo "検索ルートが見つかりません" >&2
    exit 1
fi

# ripgrep があれば優先
USE_RG=0
command -v rg >/dev/null 2>&1 && USE_RG=1

KEYWORDS=("$@")
FIRST_KW="${KEYWORDS[0]}"

# 1番目のキーワードで候補ファイル一覧を取得
CANDIDATES=()
for r in "${ROOTS[@]}"; do
    if [ "$USE_RG" -eq 1 ]; then
        while IFS= read -r f; do
            [ -n "$f" ] && CANDIDATES+=("$f")
        done < <(rg -l --no-messages \
            -g 'SESSION_HISTORY.md' -g 'HANDOFF.md' -g 'DEVLOG.md' \
            -- "$FIRST_KW" "$r" 2>/dev/null)
    else
        while IFS= read -r f; do
            [ -n "$f" ] && CANDIDATES+=("$f")
        done < <(grep -rl \
            --include='SESSION_HISTORY.md' --include='HANDOFF.md' --include='DEVLOG.md' \
            -- "$FIRST_KW" "$r" 2>/dev/null)
    fi
done

# AND 検索: 残りのキーワードでファイル単位フィルタ
if [ ${#KEYWORDS[@]} -gt 1 ] && [ ${#CANDIDATES[@]} -gt 0 ]; then
    for kw in "${KEYWORDS[@]:1}"; do
        FILTERED=()
        for f in "${CANDIDATES[@]}"; do
            grep -q -- "$kw" "$f" 2>/dev/null && FILTERED+=("$f")
        done
        CANDIDATES=("${FILTERED[@]}")
        [ ${#CANDIDATES[@]} -eq 0 ] && break
    done
fi

# 0件チェック
if [ ${#CANDIDATES[@]} -eq 0 ]; then
    echo "「${KEYWORDS[*]}」に該当する記述は見つかりませんでした"
    exit 0
fi

# 更新日時降順でソート（新しいセッションを優先表示）
SORTED=()
while IFS= read -r f; do
    [ -n "$f" ] && SORTED+=("$f")
done < <(ls -t "${CANDIDATES[@]}" 2>/dev/null)

# プロジェクト/ファイル相対パス抽出
project_name() {
    local f="$1"
    local r
    for r in "${ROOTS[@]}"; do
        if [[ "$f" == "$r/"* ]]; then
            echo "${f#$r/}"
            return
        fi
    done
    echo "$f"
}

TOTAL_FILES=${#SORTED[@]}
DISPLAY_FILES=0
MAX_DISPLAY=10

for f in "${SORTED[@]}"; do
    [ "$DISPLAY_FILES" -ge "$MAX_DISPLAY" ] && break

    # FIRST_KW を含む最初の行番号
    LINE_NUM=$(grep -n -- "$FIRST_KW" "$f" 2>/dev/null | head -1 | cut -d: -f1)
    [ -z "$LINE_NUM" ] && continue

    PROJ_FILE=$(project_name "$f")
    TOTAL_LINES=$(wc -l < "$f" | tr -d ' ')
    START=$((LINE_NUM - 5))
    END=$((LINE_NUM + 5))
    [ "$START" -lt 1 ] && START=1
    [ "$END" -gt "$TOTAL_LINES" ] && END=$TOTAL_LINES

    echo "### ${PROJ_FILE}:${LINE_NUM}"
    sed -n "${START},${END}p" "$f"
    echo ""

    DISPLAY_FILES=$((DISPLAY_FILES + 1))
done

if [ "$TOTAL_FILES" -gt "$DISPLAY_FILES" ]; then
    REMAINING=$((TOTAL_FILES - DISPLAY_FILES))
    echo "---"
    echo "（他に ${REMAINING} ファイルでマッチ、上位 ${DISPLAY_FILES} 件を表示）"
fi
