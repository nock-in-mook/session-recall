#!/usr/bin/env bash
# claude_wrapper.sh
#   Phase 10: bash/zsh 両対応の `claude()` 関数を定義する。
#   .bashrc / .zshrc から source されて読み込まれる。
#
#   役割: claude 本体起動前に pre_claude_sync.sh + cleanup_empty_sessions.sh を実行し、
#         他 PC 由来の最新 jsonl を picker に並べる + ゴミ jsonl を掃除する。
#
#   起動が 1〜10 秒遅くなるトレードオフあり。
#   Drive 同期で本体スクリプトが取れなければ何もせず素通し (claude は普通に起動)。

claude() {
    local _wrapper_base=""
    for _wrapper_p in \
        "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_claude-sync/session-recall" \
        "/g/マイドライブ/_claude-sync/session-recall" \
        "/G/マイドライブ/_claude-sync/session-recall" ; do
        if [ -d "$_wrapper_p" ]; then
            _wrapper_base="$_wrapper_p"
            break
        fi
    done

    if [ -n "$_wrapper_base" ]; then
        [ -x "$_wrapper_base/pre_claude_sync.sh" ] && bash "$_wrapper_base/pre_claude_sync.sh" </dev/null
        [ -x "$_wrapper_base/cleanup_empty_sessions.sh" ] && bash "$_wrapper_base/cleanup_empty_sessions.sh" </dev/null
    fi

    command claude "$@"
}
