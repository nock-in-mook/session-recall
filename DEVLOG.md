# DEVLOG

## 2026-04-24: プロジェクト発足

### 経緯
- claude-mem (OSS) を試用 → 1往復で週 quota 3% 消費、ノイズ多い、v12.3.9 に critical バグ多数で実用は時期尚早と判断
- 既存の `SESSION_HISTORY.md` / `HANDOFF.md` / `ROADMAP.md` 運用が実は「手動メンテされたクリーンなメモリ」として強い資産だと再認識
- Claude に grep/検索させる仕組みだけ追加すれば、claude-mem の価値の多くを高 SN 比で代替できるという仮説

### 決定
- 独立プロジェクト `session-recall/` を立ち上げ
- 段階実装: Lv.0（CLAUDE.md 指示追加）→ Lv.1（`/recall` スラッシュコマンド）→ Lv.2 以降は必要に応じて
- デプロイは `~/.claude/` と `_claude-sync/` に配置して全プロジェクト自動適用、Mac/Win 同期

### 設計上の判断
- **既存ドキュメント資産をそのまま使う** — DB 化しない、SQLite/ChromaDB 不要
- **claude-mem 型の自動要約はやらない** — 要約は `/end` スキルが既にやってるので重複回避
- **対象範囲は段階的に広げる** — まず SESSION_HISTORY.md のみ、必要に応じて HANDOFF/DEVLOG へ拡張
