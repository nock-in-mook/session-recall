#!/usr/bin/env bash
# pre_claude_sync.sh
#   Phase 10: claude wrapper 経由で claude 起動前に呼ばれる
#
#   sync_sessions.sh と異なり、stdin (hook input JSON) を必要としない。
#   $PWD から cwd を取得し、~/.claude/projects/ 配下の他 PC 由来 jsonl を
#   自 cwd フォルダに copy (mtime 比較で新しい方優先)。
#
#   - Drive 同期事故で正規・(1)・退避フォルダに分裂した jsonl の最新版を集約
#   - 自フォルダに無いファイル → copy
#   - 自フォルダにあるが mtime が古い → 新版で上書き
#   - エラー時もサイレント exit 0 (起動ブロックしない)

set -u

cwd="$PWD"

# Claude Code の encoded folder 名は cwd の英数字以外を全て - に置換したもの
# (Unicode 文字 1 個 = - 1 個。bash sed のバイト単位処理ではダメなので Python で計算)
encoded=""
for py_cmd in "py -3.14" "py -3" "python3" "python"; do
    encoded=$($py_cmd -c "import re, sys; print(re.sub(r'[^a-zA-Z0-9\-]', '-', sys.argv[1]))" "$cwd" 2>/dev/null) && break
done
[ -n "$encoded" ] || exit 0

projects_root="$HOME/.claude/projects"
self_dir="$projects_root/$encoded"
[ -d "$self_dir" ] || exit 0  # 自フォルダがなければ何もしない (claude --resume picker は空のまま)

project_tail=$(basename "$cwd" 2>/dev/null || true)
[ -n "$project_tail" ] || exit 0

# 兄弟フォルダ走査: 末尾が project_tail / project_tail (N) / project_tail (N)-退避-* のどれか
copied_new=0
overwritten=0
skipped=0
for sibling in "$projects_root"/*; do
    [ -d "$sibling" ] || continue
    sibling_name=$(basename "$sibling")
    [ "$sibling_name" = "$encoded" ] && continue

    case "$sibling_name" in
        *"$project_tail")              ;;  # 完全末尾一致 (Win cwd vs Mac cwd など)
        *"$project_tail "*"("*")")     ;;  # "(N)" 付き Drive 同期重複
        *"$project_tail "*"-退避-"*)   ;;  # 退避リネームされたフォルダ
        *) continue ;;
    esac

    for src in "$sibling"/*.jsonl; do
        [ -f "$src" ] || continue
        fname=$(basename "$src")
        dst="$self_dir/$fname"
        if [ -e "$dst" ]; then
            if [ "$src" -nt "$dst" ]; then
                cp -p "$src" "$dst" 2>/dev/null && overwritten=$((overwritten + 1))
            else
                skipped=$((skipped + 1))
            fi
        else
            cp -p "$src" "$dst" 2>/dev/null && copied_new=$((copied_new + 1))
        fi
    done
done

# ログ
log_file="$HOME/.claude/session-recall-pre-launch.log"
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] pre_claude_sync: encoded=$encoded new=$copied_new overwritten=$overwritten skipped=$skipped"
} >> "$log_file" 2>/dev/null || true

exit 0
