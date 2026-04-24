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

---
## #7 (2026-04-24): Phase 5.1 本番検証 + Phase 6「プロジェクト絞り込み」完成

### Phase 5.1 本番検証（完全達成 ✅）
セッション #6 終了時の /end が修正版フックの初回本番試験。結果:

| 項目 | 値 |
|---|---|
| コミット時刻（#6 終了） | 23:27:02 |
| DB 更新時刻（indexed_at） | 23:27:47（45 秒後 ≒ sleep 30 + 処理時間） |
| 総 chunks | 4264 → 4277（+13） |
| ファイル別 file_mtime | SESSION_HISTORY.md / HANDOFF.md / DEVLOG.md すべて実ファイルと完全一致 ✅ |

Phase 5.1 の sleep 30 + Step 2.9 配置が本番で機能。取りこぼしゼロ。

### Phase 6: プロジェクト絞り込み（完成）

#### スコープ決定
当初案 A-E を検討し、デメリット検証で A のみを採択:
- A: プロジェクト絞り込み（採用）
- B: セッション番号指定（頻度低い）
- C: ハイブリッド検索（tool 数増 → 判断コスト増）
- D: 時系列フィルタ（書式依存で脆い）
- E: 横断 TODO（ROADMAP 除外方針と矛盾）

#### 実装
- `scripts/search.sh`: `--project <名前>` オプション追加（先頭・途中どちらでも受付け）
- `scripts/server.py` v6.0.0: 両 tool に project optional 引数追加
  - keyword: subprocess に `--project` 引き渡し
  - semantic: SQL WHERE に `c.project = ?` 追加、sqlite-vec の post-filter を考慮して k を limit × 20（最大 500）に拡張
- `commands/recall.md`: `/recall [--project <名前>] <キーワード>` に拡張
- `instructions/claude_md_patch.md` v5: project 引数の使い分け指示を追加

#### 同時修正した既存バグ
bash 3.2（macOS default）で `set -u` 下の空配列 `"${A[@]}"` が unbound variable 扱いになる問題。Phase 6 の keyword_search テストで顕在化したため `${A[@]+"${A[@]}"}` 形式に修正。

#### 動作確認
- search.sh: ヘルプ、--project 絞り込み、無効 project の全パターン OK
- server.py in-process: semantic で project=Memolette-Flutter / session-recall の絞り込み動作 ✅
- deploy.sh 1 回目: CLAUDE.md v4→v5 置換、recall.md / search.sh / server.py 更新
- deploy.sh 2 回目: 全 13 工程「変更なし」（冪等性 OK）

### コミット
- `1bf2e10` Phase 6: プロジェクト絞り込み（両 MCP tool に project 引数追加）

### 次セッションで観察する点
- Claude Code 再起動後、新 MCP server v6.0.0 が有効化される
- 「Memolette の○○」のような発言で自動的に project 引数付き検索が走るか
- Phase 5.1 フック継続動作（2 回目の本番稼働）

---
## #8 (2026-04-25) resume 試験 + Mac B deploy + Phase 5.2 実装

### Mac A 側での Phase 6 完成版挙動の実地検証
- 「Memolette のトレー実装で苦労した話したいな」に対し `session_recall_search(["Memolette","トレー"])` と `session_recall_semantic` を並列発火 → Memolette-Flutter/SESSION_HISTORY #002 (ルーレットUI再現) / #003 (トレースライド実装) をヒットさせて要約提示 ✅
- 特定プロジェクト名が会話に出たら自動で `project` 引数を付ける挙動も確認 ✅

### Mac A → Mac B への `claude --resume` 試験
- 一度は Claude が「resume は PC ローカルなので無理」と誤答 → ユーザー指摘 → `~/.claude/` の実機確認で `commands / memory / projects / settings.json` が全て `_claude-sync/` への symlink であることを発見
- つまり Claude Code のセッション履歴 jsonl も PC 間共有されている = **別 PC で `claude --resume` で同セッションを続けられる**
- 実際に Mac A で `/exit` → Mac B（KYO-YaguchinoMacBook-Air）で `claude --resume` → 同セッションに復帰成功 ✅

### Mac B 初回 deploy
- Mac B は完全未 deploy（`venv` / `index.db` / `~/.claude.json.mcpServers` すべてなし）を確認
- `bash deploy.sh` 1 発実行 → 全 13 工程 exit 0、**トータル約 90 秒で完走**
  - venv 作成（`/opt/homebrew/bin/python3.12`）+ mcp/sentence-transformers/sqlite-vec/PyTorch インストール
  - index DB 初回構築（64 ファイル、4297 chunks、処理時間 72.9 秒、DB 13.4 MB）
  - MCP server を `claude mcp add --scope user` で登録
- Claude Code 再起動後、resume で戻ったセッションでシステムリマインダーに MCP deferred tools 再出現
- Mac B で「トレーの取っ手部分の実装は苦労したよね」に対して自動検索発火 → Memolette-Flutter/SESSION_HISTORY #005 の `TrapezoidTabClipper/Painter`（Swift `addArc(tangent1:tangent2:radius:)` を tan/sin/atan2 で再現）の記憶を要約提示 ✅ = PC 間完全等価

### Phase 5.2 実装（セッション開始時の DB 自動追いつき）
**動機**: PC 間 DB 更新タイミングのズレ。`/end` は各 PC ローカル DB を更新するだけなので、別 PC で書かれた最新 SESSION_HISTORY は自機で次の /end まで反映されない = 1 セッション分の検索盲点が残る。

**実装**:
- `scripts/update_index.sh`: `sleep 30` を引数化（`sleep "${1:-30}"`）。デフォルトは /end 用 30 秒、start 用途は `0` を渡す
- `instructions/claude_md_patch.md` v6: 「セッション開始時の DB 自動追いつき（必ず実行）」セクション追加。Step 0 と並列で `nohup bash update_index.sh 0 &` を実行する bash ブロックを明示
- deploy.sh 実行で両 CLAUDE.md に v6 注入、update_index.sh の引数化を Drive 同期（deploy.sh 自体は変更不要、既存工程でカバー）

**動作確認**: `time bash update_index.sh 0` = 8.5 秒（純粋な venv 起動 + mtime 比較コスト、sleep 30 なら 38 秒超になる）

**設計判断**:
- 引数化方式（別スクリプト化せず）で既存 end-hook の後方互換を維持
- /end 側は引数なし呼び出しなのでデフォルト 30 秒が効く
- Phase 番号は 5.2（終了時と対称な開始時フック、Phase 5 系列）

### コミット
- `88896b0` Phase 5.2: セッション開始時のインデックス自動追いつき
- `d6503a4` scripts/update_index.sh の実行ビット復元（Edit tool 副作用）

### 次セッションで観察する点
- Step 0 と並列で Claude が `nohup bash update_index.sh 0 &` を自動発火するか
- 発火すれば `~/.claude/session-recall-index.db` の indexed_at がセッション開始直後（±10 秒以内）に更新される
- 今この #8 の SESSION_HISTORY 追記が、次セッション冒頭で search / semantic ヒット対象になっていれば Phase 5.2 完全動作の証拠
- Windows 機 deploy は継続して残課題
