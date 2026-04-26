#!/usr/bin/env bash
# sync_sessions.sh
#   Phase 8: PC 横断 resume 自動化
#   SessionStart hook (matcher: "startup|resume") から呼ばれ、
#   ~/.claude/projects/ 配下の他 PC 由来 jsonl を自 cwd フォルダに copy する。
#
#   - 自フォルダ basename からプロジェクト末尾を抽出
#   - 末尾が一致する全フォルダ（"(1)" 等の Drive 同期重複も含む）を兄弟扱い
#   - 兄弟フォルダの jsonl のうち、自フォルダに無いものだけ copy
#   - 既存ファイルは skip（冪等、ファイル名 = UUID なのでユニーク）
#   - エラー時もサイレント exit 0（セッション開始をブロックしない）

set -u

# stdin から hook input JSON を読む
input="$(cat 2>/dev/null || true)"

# transcript_path を抽出（jq 不要、grep + sed で対応）
transcript_path=$(printf '%s' "$input" | grep -o '"transcript_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')

if [ -z "$transcript_path" ]; then
    exit 0
fi

# 自フォルダパスを得る
self_dir=$(dirname "$transcript_path")
self_name=$(basename "$self_dir")

# projects ルート
projects_root=$(dirname "$self_dir")
[ -d "$projects_root" ] || exit 0

# プロジェクト末尾を抽出
#   Apps2026 系: 最後の "Apps2026-XXX" の "XXX" を末尾とする
#   _other-projects 系も同様パターンで動くよう、最後のセグメント区切りを推定
#   フォルダ名は "/" "_" "@" "." を全て "-" に置換した encoded cwd なので、
#   実 cwd の最後の path segment (basename) は連続しないハイフンの後ろに来る
#   一番安定なのは、$PWD or hook input の cwd を使うこと
cwd=$(printf '%s' "$input" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')
if [ -z "$cwd" ]; then
    cwd="$PWD"
fi
project_tail=$(basename "$cwd" 2>/dev/null || true)
[ -n "$project_tail" ] || exit 0

# 兄弟フォルダ走査
#   末尾が "${project_tail}" または "${project_tail} (N)" のフォルダを兄弟とする
copied=0
skipped=0
for sibling in "$projects_root"/*; do
    [ -d "$sibling" ] || continue
    sibling_name=$(basename "$sibling")
    [ "$sibling_name" = "$self_name" ] && continue

    # 末尾マッチ判定
    case "$sibling_name" in
        *"$project_tail")          ;;  # 完全末尾一致
        *"$project_tail "*"("*")") ;;  # "(N)" 付き Drive 同期重複
        *) continue ;;
    esac

    # 兄弟フォルダの jsonl を自フォルダに copy（無いものだけ）
    for src in "$sibling"/*.jsonl; do
        [ -f "$src" ] || continue
        fname=$(basename "$src")
        dst="$self_dir/$fname"
        if [ -e "$dst" ]; then
            skipped=$((skipped + 1))
            continue
        fi
        if cp -p "$src" "$dst" 2>/dev/null; then
            copied=$((copied + 1))
        fi
    done
done

# ログ（任意、デバッグ用）
log_file="$HOME/.claude/session-recall-sync.log"
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] sync_sessions: project_tail=$project_tail self=$self_name copied=$copied skipped=$skipped"
} >> "$log_file" 2>/dev/null || true

exit 0
