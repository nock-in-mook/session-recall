# HANDOFF

最終更新: 2026-04-24

## 現状

プロジェクト立ち上げ直後。スケルトン配置完了、実装は未着手。

- フォルダ: `_Apps2026/session-recall/`
- claude-mem を試した結果、自前の `SESSION_HISTORY.md` / `HANDOFF.md` 活用型の想起ツールを作る方針に決定
- claude-mem は後で撤去予定（プラグイン無効化 + `~/.claude-mem/` 削除）

## 次のアクション（Phase 1 = Lv.0）

1. `instructions/claude_md_patch.md` に「過去セッション参照時に grep する」指示文を確定
2. 別プロジェクト（例: Memolette）で動作検証
3. 問題なければ `deploy.sh` で `~/.claude/CLAUDE.md` に追記

## 検討事項

- 検索対象ファイルの範囲（まずは `SESSION_HISTORY.md` のみにするか、`HANDOFF.md` / `DEVLOG.md` / `ROADMAP.md` まで含めるか）
- プロジェクトルート特定ロジック（現在の cwd から親辿って `SESSION_HISTORY.md` 探す or 全プロジェクト決め打ち）
- 検索結果のフォーマット（マッチ行＋前後数行 or 該当セクション全体）

## claude-mem の扱い

- 現在 `~/.claude/settings.json` で `claude-mem@thedotmack: true` に有効化済み
- session-recall 開発完了後にアンインストール
- バックアップ済み: `~/.claude-backup-pre-claude-mem/`

## 環境

- 開発機: Mac (MacBook Air)
- 本番適用: Mac + Windows（`_claude-sync/` 経由で同期）
