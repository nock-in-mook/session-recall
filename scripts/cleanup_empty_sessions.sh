#!/usr/bin/env bash
# cleanup_empty_sessions.sh
#   Phase 10: 自フォルダ内の jsonl で「ユーザー発言 0 件 + mtime 5 分以上古い」ものを
#   ~/.claude/projects-trash/ に移動 (削除でなくゴミ箱方式、復元可能)
#
#   発生源: 「2 回起動 (即 /exit + 再 resume)」運用や picker キャンセルで生成される空 jsonl
#   対策: claude wrapper 経由で起動前に掃除し、picker 候補を綺麗に保つ

set -u

cwd="$PWD"

# encode_cwd
encoded=""
for py_cmd in "py -3.14" "py -3" "python3" "python"; do
    encoded=$($py_cmd -c "import re, sys; print(re.sub(r'[^a-zA-Z0-9\-]', '-', sys.argv[1]))" "$cwd" 2>/dev/null) && break
done
[ -n "$encoded" ] || exit 0

self_dir="$HOME/.claude/projects/$encoded"
[ -d "$self_dir" ] || exit 0

trash_dir="$HOME/.claude/projects-trash"
mkdir -p "$trash_dir"

# 5 分前の epoch
threshold=$(($(date +%s) - 300))

moved=0
for jsonl in "$self_dir"/*.jsonl; do
    [ -f "$jsonl" ] || continue

    # mtime check (Win/Mac 両対応)
    mtime=$(stat -c %Y "$jsonl" 2>/dev/null || stat -f %m "$jsonl" 2>/dev/null) || continue
    [ "$mtime" -gt "$threshold" ] && continue  # 5 分以内は skip (進行中の可能性)

    # ユーザー発言 0 件 check (Python で判定、Win cp932 対策で UTF-8 強制)
    is_empty=""
    for py_cmd in "py -3.14" "py -3" "python3" "python"; do
        is_empty=$(JSONL_PATH="$jsonl" $py_cmd -c "
import json, os, sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
path = os.environ['JSONL_PATH']
count = 0
try:
    with open(path, encoding='utf-8') as fp:
        for line in fp:
            try:
                obj = json.loads(line)
            except:
                continue
            if obj.get('type') == 'user' and not obj.get('isMeta', False):
                msg = obj.get('message', {})
                content = msg.get('content', '')
                if isinstance(content, list):
                    for c in content:
                        if c.get('type') == 'text':
                            text = c.get('text', '').strip()
                            if text and not text.startswith('<'):
                                count += 1
                elif isinstance(content, str):
                    text = content.strip()
                    if text and not text.startswith('<'):
                        count += 1
    print('1' if count == 0 else '0')
except:
    print('0')
" 2>/dev/null) && break
    done

    if [ "$is_empty" = "1" ]; then
        ts=$(date +%Y%m%d-%H%M%S)
        mv "$jsonl" "$trash_dir/$(basename "$jsonl").${ts}" 2>/dev/null && moved=$((moved + 1))
    fi
done

# ログ
log_file="$HOME/.claude/session-recall-cleanup.log"
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] cleanup: encoded=$encoded moved=$moved"
} >> "$log_file" 2>/dev/null || true

exit 0
