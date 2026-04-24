#!/usr/bin/env bash
# /recall スキルの実処理（session-recall Phase 2 / Phase 6 で --project 追加）
# 使い方: search.sh [--project <名前>] <キーワード> [<キーワード2> ...]
#
# 複数キーワードは AND 検索（同じファイル内に全キーワードが存在）。
# --project 指定時は該当プロジェクトフォルダ直下のみを対象にする。
# 出力: 「### project/file:line」見出し + 前後 ±5 行の本文。
# 上位 10 ファイルまで表示、超過分は件数のみ末尾に表示。

set -uo pipefail
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# 引数パース（--project <name> / --project=<name> を先頭・途中どちらでも受け付ける）
PROJECT=""
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --project)
            PROJECT="${2:-}"
            shift 2 || shift
            ;;
        --project=*)
            PROJECT="${1#--project=}"
            shift
            ;;
        --)
            shift
            ARGS+=("$@")
            break
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done
# bash 3.2 (macOS default) は set -u 下で空配列 "${A[@]}" を unbound variable 扱いする
# ため、条件付き展開 ${A[@]+"${A[@]}"} でガードする
set -- ${ARGS[@]+"${ARGS[@]}"}

# 引数なし → ヘルプ表示
if [ $# -eq 0 ]; then
    cat <<'EOF'
使い方: /recall [--project <名前>] <キーワード> [<キーワード2> ...]

複数キーワードは AND 検索（同じファイル内に全キーワードが存在）。
--project 指定時は該当プロジェクト（_Apps2026/ or _other-projects/ 直下のフォルダ名）のみが対象。

例:
    /recall ToDo 結合
    /recall claude-mem 撤去
    /recall Flutter ビルド エラー
    /recall --project Memolette-Flutter ToDo 結合
    /recall --project session-recall 競合

検索対象:
    各プロジェクト直下の SESSION_HISTORY.md / HANDOFF.md / DEVLOG.md
    （_Apps2026/ と _other-projects/ 配下、Mac/Win 両対応）
EOF
    exit 0
fi

# 検索ルートを構築（Mac/Win 両対応、存在する方を採用）
# --project 指定時は ROOT/PROJECT で存在するものだけに絞る
ROOTS=()
ROOT_CANDIDATES=(
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_Apps2026"
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_other-projects"
    "/g/マイドライブ/_Apps2026"
    "/g/マイドライブ/_other-projects"
    "/G/マイドライブ/_Apps2026"
    "/G/マイドライブ/_other-projects"
)
for r in "${ROOT_CANDIDATES[@]}"; do
    if [ -n "$PROJECT" ]; then
        [ -d "$r/$PROJECT" ] && ROOTS+=("$r/$PROJECT")
    else
        [ -d "$r" ] && ROOTS+=("$r")
    fi
done

if [ ${#ROOTS[@]} -eq 0 ]; then
    if [ -n "$PROJECT" ]; then
        echo "プロジェクト『${PROJECT}』が _Apps2026/ または _other-projects/ 直下に見つかりません" >&2
    else
        echo "検索ルートが見つかりません" >&2
    fi
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
# FILTERED が空のとき bash 3.2 + set -u で unbound エラーになるため条件展開
if [ ${#KEYWORDS[@]} -gt 1 ] && [ ${#CANDIDATES[@]} -gt 0 ]; then
    for kw in "${KEYWORDS[@]:1}"; do
        FILTERED=()
        for f in "${CANDIDATES[@]}"; do
            grep -q -- "$kw" "$f" 2>/dev/null && FILTERED+=("$f")
        done
        CANDIDATES=(${FILTERED[@]+"${FILTERED[@]}"})
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
# ROOTS は --project 指定時にサブディレクトリまで絞るため、表示用の相対パスは
# ROOT_CANDIDATES（親ディレクトリ）から計算する。
project_name() {
    local f="$1"
    local r
    for r in "${ROOT_CANDIDATES[@]}"; do
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
