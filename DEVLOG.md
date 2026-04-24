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

## 2026-04-24: Phase 2 完了

### 構造変更
- 旧 `skills/recall/{skill.md, search.sh}` → 新 `commands/recall.md` + `scripts/search.sh` に再編
- 既存の `_claude-sync/commands/<name>.md` 形式（end.md / setup_claude_sync.md など）と整合させた
- skill.md の独自フォルダ形式は廃止

### 実装
- `scripts/search.sh`: 複数キーワード AND 検索、ripgrep 優先・grep フォールバック、Mac/Win 両対応パス、前後 ±5 行抽出、更新日時降順、上位 10 件
- `commands/recall.md`: Claude 解釈用のスキル定義。search.sh のパスを Mac/Win 両並記して動的解決、結果は要約 + 出典明示
- `deploy.sh` を Phase 2 拡張: `inject_into` に加えて `sync_file` 関数を追加、4 工程に整理

### `claude_md_patch.md` v2
- v1 の grep 直叩き指示を、search.sh 経由 + `/recall` 案内の二段階構成に更新
- マーカーは `<!-- session-recall:begin v2 -->` ... `<!-- session-recall:end v2 -->`
- deploy.sh は前方一致でマーカー検出するため、v1 → v2 への自動置換が成立

### バグと修正（重要）
- **awk マーカー誤マッチ**: `extract_block` の awk パターン `/<!-- session-recall:begin/` が、patch ファイル冒頭の説明文に含まれるバックティック内の例示文字列も拾ってしまい、巨大ブロックを抽出 → CLAUDE.md が 1876 行に肥大化
- **修正**: awk パターンを行頭マッチ `/^<!-- session-recall:begin/` に限定。inject_into の grep / awk 両方とも修正
- **復旧**: `.bak.20260424_194939`（完全クリーン状態）から両 CLAUDE.md を復元、壊れたバックアップ 6 個を削除
- **教訓**: マーカー検出は行頭限定 `^` 必須。Markdown のバックティック内例示は行頭ではないので安全

### 動作確認
- 1 回目 deploy: 末尾追記 で更新（バックアップ作成）
- 2 回目 deploy: 全 4 工程「変更なし」（冪等性 OK、バックアップ作成なし）
- `search.sh "claude-mem" "撤去"` → 4 ファイルから関連箇所抽出（user 0.14s、壁時計 3 秒）
- 現セッションのシステムリマインダーに `recall: プロジェクト横断で過去の SESSION_HISTORY.md / HANDOFF.md / DEVLOG.md を検索する。` が追加され、`Skill` ツール経由で `/recall` 実行可能に

### 残課題（次セッション以降）
- 新セッション（CLAUDE.md 再ロード後）で「前回 Memolette で何してた？」など自然言語クエリが自動で search.sh を呼ぶか検証
- Windows 機での `deploy.sh` / `search.sh` 動作確認
- Phase 3 着手: MCP サーバー化（ripgrep ベース or SQLite FTS5）
