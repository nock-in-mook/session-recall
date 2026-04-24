# SESSION HISTORY

---
## #1 (2026-04-24)
- プロジェクト発足、スケルトン配置、git init
- claude-mem 試用 → 自作路線に舵切り決定
- Phase 1 (Lv.0) 着手予定

---
## #2 (2026-04-24): Phase 1〜3 を一気に完了

### 完了したフェーズ
- **Phase 1 (Lv.0)**: `claude_md_patch.md` v1 → `deploy.sh` で `~/.claude/CLAUDE.md` と `_claude-sync/CLAUDE.md` にマーカー間ブロック注入（冪等、Mac/Win 両対応）
- **Phase 2 (Lv.1)**: `scripts/search.sh` + `commands/recall.md` で `/recall` スキル化。ripgrep 優先・複数キーワード AND・前後 ±5 行・上位 10 件
- **Phase 3 (Lv.2)**: `scripts/server.py`（mcp 1.27.0、stdio）で MCP サーバー化、`settings.local.json` に jq merge で自動登録。initialize / tools/list / tools/call すべて smoke test OK

### 構造変更
- 旧 `skills/recall/{skill.md, search.sh}` → 新 `commands/recall.md` + `scripts/{search.sh, server.py, run_server.sh}`（既存 `_claude-sync/commands/` 形式に整合）

### 主なバグと修正
- **awk マーカー検出を行頭マッチ `^<!-- session-recall:` に限定**：patch ファイル冒頭の説明文中に含まれるバックティック内例示を誤マッチして CLAUDE.md が 1876 行に肥大化していた。バックアップから復旧、awk パターン修正で再発防止

### 検証ステータス
- ✅ `search.sh` 単体（「結合」「claude-mem 撤去」等で関連箇所抽出）
- ✅ Skill ツール経由 `/recall`（現セッション内で自動認識・実行）
- ✅ MCP プロトコル smoke test（stdio で initialize → tools/list → tools/call の handshake と実検索）
- 🟡 Claude Code 再起動後の MCP tool 自動呼び出し（次セッション = この resume 後に検証予定）
- 🟡 Windows 機での venv セットアップと MCP server 起動（別 PC で確認予定）

### 次にやること（resume 後）
- Claude Code 再起動 = `claude --resume` でこのセッションを継続
- ツールリストに `mcp__session-recall__session_recall_search` が出てくるか確認
- 「前回 Memolette で何してた？」のような自然言語クエリで Claude が自動で MCP tool を呼ぶか観察
- 問題なければ Phase 4 (セマンティック検索) 着手

### コミット
- `9421d5f` Phase 1 完了
- `13a7b54` Phase 2 完了
- `035537e` Phase 3 完了

---
## #3 (2026-04-24): resume 後の MCP 認識バグ判明・修正

### 経緯
- セッション #2 終了後、`/exit` → `claude --resume` で復帰したところ、`session_recall_search` MCP tool が認識されていなかった
- ToolSearch でヒットせず、`pgrep` でも MCP server プロセスが立っていなかった
- `claude mcp list` で確認すると `session-recall` が一覧にない（claude.ai 系の OAuth 必要なやつしか出ない）

### 原因
- **Claude Code 2.x は `~/.claude/settings.local.json` の `mcpServers` キーを読まない**
- 正規の登録経路は `claude mcp add` CLI 経由（`~/.claude.json` に保存される）

### 修正
- `claude mcp add --scope user session-recall <run_server.sh>` で登録 → `claude mcp list` で `✓ Connected` 確認
- `deploy.sh` の `register_mcp_server()` を `claude mcp add` 経由に変更
- 旧形式の `settings.local.json.mcpServers` キーは自動クリーンアップするロジックも追加
- DEVLOG / ROADMAP / HANDOFF に経緯と教訓を追記
- コミット `d48f5bd` push 済み

### 次（再 resume 後）
- ツール一覧に `mcp__session-recall__session_recall_search` が現れるか確認
- 「前回 ○○ の話したよね」型の自然言語クエリで Claude が自動で MCP tool を呼ぶか
- うまく行けば Phase 4（セマンティック検索）着手

---
## #4 (2026-04-24): Phase 4 完了（セマンティック検索）

### 経緯
- セッション #3 後の resume で MCP tool 認識成功 → `session_recall_search` の動作確認 OK
- そのまま Phase 4 に着手して一気に完成

### 完了したこと
- **埋め込みモデル**: `intfloat/multilingual-e5-small`（384 次元、~470MB、日本語対応、CPU 動作）
- **ベクトル DB**: SQLite + `sqlite-vec` 0.1.9（vec0 仮想テーブル）
- **`scripts/index_build.py`**: 全プロジェクト走査 → Markdown 見出し単位の段落分割（最大 40 行）→ 埋め込み → DB 保存。mtime ベース増分更新
- **`scripts/server.py` v4**: `session_recall_semantic` tool 追加（既存 `session_recall_search` と並列）
- **`deploy.sh` 11 工程化**: Phase 4 用に `setup_venv_phase4()` (sentence-transformers + sqlite-vec install) と `build_index_if_missing()` (DB 未存在なら自動構築) を追加
- **`claude_md_patch.md` v4**: 「キーワード明確 → search、曖昧 → semantic」使い分け指示

### 動作確認
- 初回 index 構築: 4239 chunks、84.7 秒、DB 13.3 MB
- in-process semantic_search 3 クエリ全成功:
  1. 「TODO リストの結合機能を実装した話」→ Memolette-Flutter 結合実装 + Swift 版前身機能
  2. 「claude-mem を撤去した経緯」→ 撤去手順 3 件
  3. 「Drive 同期の問題で困った」→ Kanji_Stroke / Data_Share の同期トラブル議論
- MCP smoke test: tools/list で両 tool 認識（search + semantic）

### クロス PC 戦略
- Drive 同期: 元データ + ツール本体（server.py、index_build.py、search.sh、run_server.sh、recall.md）
- PC ローカル: venv（プラットフォーム依存）、index DB（SQLite 破損リスク回避）
- 新 PC セットアップは `bash deploy.sh` 一発で全自動

### 次（再 resume 後）
- ツール一覧に `mcp__session-recall__session_recall_semantic` が追加で現れるか確認
- 曖昧クエリ（「あのバグで悩んだ件」「○○のアプローチを諦めた経緯」等）で Claude が自動で semantic を選ぶか
- 残課題: `/end` フックで増分 index 更新の自動化、Windows 機での全工程動作確認

### コミット
- `32ee178` Phase 4 完了

---
## #5 (2026-04-24): Phase 4 実体検証完了 + Phase 5（/end フック）完成

### resume 後の実 Claude Code から MCP tool 検証
- `mcp__session-recall__session_recall_semantic` が deferred tool として認識
- 3 つの曖昧クエリで質の高い結果:
  - 「セッション横断で過去の作業を思い出すツールを自作した動機」 → session-recall プロジェクト立ち上げ経緯 + Kanji_Stroke の SESSION_LOG 自動蓄積アイデア
  - 「リモートデスクトップで作業する時に詰まった問題と解決」 → Chat の Mac リモート Enter 2 回問題 + Karabiner-Elements + everyWEAR でスマホ用 Vercel デプロイ
  - 「iOS アプリのリリース申請で必要なものを揃えるのに苦労した件」 → P3 Craft の D-U-N-S 申請詰まり + Apple サポート問い合わせ → 正規ルート判明
- キーワード一致しないクエリでも概念で関連箇所を拾えることが実証された

### Phase 5 完了
- `scripts/update_index.sh`: venv の python で `index_build.py --quiet` を呼ぶ薄い wrapper
- `instructions/end_patch.md`: `_claude-sync/commands/end.md` に注入する Step 2.5 ブロック
- `deploy.sh` を 13 工程に拡張: `extract_end_hook_block()` + `inject_end_hook()` 関数追加、Phase 5 セクション追加
- 注入された end.md は `nohup bash update_index.sh & ` でバックグラウンド起動 → /end の終了をブロックしない

### 動作確認
- update_index.sh 単体 OK（exit 0、15 秒）
- deploy.sh 1 回目: Phase 5 [12/13][13/13] が末尾追記、バックアップ作成
- deploy.sh 2 回目: 全 13 工程「変更なし」（冪等性 OK）
- end.md 末尾に Step 2.5 ブロック正しく挿入

### コミット
- `aafe018` Phase 5: /end フックで増分インデックス自動更新

### 完了状態
- Phase 1〜5 全フェーズ達成
- 残課題: Windows 機での全 13 工程動作確認のみ
- Phase 6 アイデア（ハイブリッド検索、プロジェクト絞り込み、時系列フィルタ）は ROADMAP のアイデアメモに残置


---
## #6 (2026-04-24): Phase 5.1 フック競合バグ修正

### 経緯
前回 #5 終了後の実体検証で、Phase 5 フック（/end Step 2.5）が Step 2 の並列書き出しと並走し、書き出し完了前に mtime 比較が走って最新セッション分を取りこぼしていたバグを発見。

### 発見の糸口
- DB indexed_at: 22:18:35
- HANDOFF.md 実 mtime: 22:18:45（10 秒後） ← DB 記録は 22:05:43 のまま
- SESSION_HISTORY.md 実 mtime: 22:18:43（8 秒後） ← DB 記録は 21:55:48 のまま

### 修正（C 案 = A + B の二重防衛）
1. **A**: `scripts/update_index.sh` に `sleep 30` 追加（書き出し完了を待つ）
2. **B**: `instructions/end_patch.md` を Step 2.5 → Step 2.9 + 並列完了後に走る意味を明示
3. `_claude-sync/` 側の `update_index.sh` と `commands/end.md` にも反映

### 検証
- セッション #5 分の取りこぼしは手動 `update_index.sh` で補完（SESSION_HISTORY.md chunks 21→27、file_mtime が実ファイルと一致）
- 修正版を競合シナリオで再現テスト: バックグラウンド起動 → 1 秒後 DEVLOG.md touch → sleep 30 後に update_index.sh が新 mtime を正しく検出して反映 ✅

### コミット
- `8e44449` Phase 5.1: /end フックの競合条件を修正（sleep 30 + Step 2.9）

### 本番動作検証
- 今 /end（セッション #6 終了時）が **修正版フックの初回本番試験**。Step 2.9 のバックグラウンド起動 → sleep 30 → 増分更新 が意図通り動けば、次回セッション開始時に最新状態でインデックスされているはず。

### 残課題
- 次セッション開始時に DB 状態を確認して本番動作完了を検証
- Windows 機での全工程検証（Mac 単独試験は完了）
