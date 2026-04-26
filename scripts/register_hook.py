#!/usr/bin/env python3
"""register_hook.py
deploy.sh から呼ばれる、settings.json の hooks.SessionStart に
session-recall sync_sessions hook を冪等に登録するユーティリティ。

jq が Windows に無いため、Python の標準 json モジュールで安全に編集する。

usage:
    python register_hook.py <settings.json path> <hook command>

exit code:
    0: 追加した
    2: 既登録 (no-op)
    1: エラー
"""
import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <settings.json> <hook command>", file=sys.stderr)
        return 1

    settings_path = Path(sys.argv[1])
    hook_cmd = sys.argv[2]

    if not settings_path.exists():
        print(f"  {settings_path} 不在のためスキップ")
        return 2

    try:
        data = json.loads(settings_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        print(f"  {settings_path} 読込/パース失敗: {e}", file=sys.stderr)
        return 1

    hooks = data.setdefault("hooks", {})
    session_starts = hooks.setdefault("SessionStart", [])

    # 既登録チェック
    for entry in session_starts:
        for h in entry.get("hooks", []):
            if h.get("command") == hook_cmd:
                return 2

    # matcher: "" のエントリに追加。無ければ新規エントリ。
    target = next((e for e in session_starts if e.get("matcher") == ""), None)
    if target is None:
        session_starts.append(
            {"matcher": "", "hooks": [{"type": "command", "command": hook_cmd}]}
        )
    else:
        target.setdefault("hooks", []).append(
            {"type": "command", "command": hook_cmd}
        )

    settings_path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
