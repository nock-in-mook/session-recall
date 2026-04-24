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

### 同日夜: claude-mem を完全撤去
- session-recall 完成を待たず、セッション#27 終了直前に撤去
- 理由: プラグイン残置のままだと次セッション以降もフック発火・トークンオーバーヘッド・既知バグの影響を受けるため、不要な中間状態は避ける
- 撤去手順は HANDOFF.md §1.7 に詳細記録

## 2026-04-24: Phase 1 完了

### 実装
- `instructions/claude_md_patch.md` を確定版 v1 に。マーカー `<!-- session-recall:begin v1 -->` ... `<!-- session-recall:end v1 -->` で囲む形式
- `deploy.sh` を Phase 1 相当まで実装
  - 冪等（差分なしならバックアップも作らない）
  - Mac/Win 両対応（パス存在チェックで分岐、`uname` 不要）
  - 既存 CLAUDE.md にマーカーがあればマーカー間置換、無ければ末尾追記
  - awk でブロック抽出 → 一時ファイル経由で挿入 → cmp で差分判定

### 動作確認
- Mac で `./deploy.sh` 実行 → `~/.claude/CLAUDE.md` と `_claude-sync/CLAUDE.md` 両方に末尾追記、バックアップ作成
- 2 回目実行 → 両方とも「変更なし」、バックアップは作られず（冪等性 OK）
- Memolette-Flutter の SESSION_HISTORY / HANDOFF を「結合」で grep → ToDo 結合機能関連の記述が複数ヒット
- 横断 grep「claude-mem」→ Memolette-Flutter / session-recall 両プロジェクトからヒット
- `ripgrep` インストール済み（Phase 2 で本格活用）

### 設計上の確定事項
- 検索対象: `SESSION_HISTORY.md` / `HANDOFF.md` / `DEVLOG.md`（ROADMAP は未確定アイデアが多くノイズ源になるため除外）
- 自動検索の積極性: 中庸（過去参照キーワード + 詰まり気配 + 別プロジェクト名）
- 検索フロー: 現プロジェクト先 → 必要なら全プロジェクト横断（二段階）
- マーカーバージョニング: `<!-- session-recall:begin v1 -->` の `v1` で将来の patch 更新に対応

### 残課題（次セッション以降）
- 新セッションを起こして実体検証（CLAUDE.md 注入が読み込まれるか）
- Windows 機での `deploy.sh` 動作確認
- Phase 2 着手: `/recall` スラッシュコマンド本実装
