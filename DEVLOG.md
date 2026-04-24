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

## 2026-04-24: Phase 3 完了

### 環境
- Mac: `/opt/homebrew/bin/python3.12` を使用（システムの 3.9 は古いため）
- venv は `~/.claude/session-recall-venv/` に PC ローカルで作成（Drive 同期しない）
- mcp パッケージ 1.27.0 を venv にインストール

### 実装
- `scripts/server.py`: MCP server 本体（stdio transport）。`session_recall_search` tool を提供、内部で subprocess 経由で `search.sh` を呼ぶ
- `scripts/run_server.sh`: 起動 wrapper。venv の python を Mac/Win 両対応で探して exec
- `deploy.sh` Phase 3 拡張:
  - `setup_venv()`: Python 3.10+ 自動探索（Mac は Homebrew、Win は `py -3.14`）→ venv 作成 → mcp 自動インストール
  - `register_mcp_server()`: `settings.local.json` に jq merge で `mcpServers.session-recall` を追記（既存 `permissions` / `hooks` を破壊しない）
  - 8 工程に整理（[1/8]〜[8/8]）

### `claude_md_patch.md` v3
- 検索手段の優先順位を明文化: MCP tool > bash search.sh > 現プロジェクト grep
- 「マーカーは行頭限定（`^` 必須）」を明示してメンテナンスメモに追記

### 動作確認
- `deploy.sh` 1 回目: Phase 1 v2→v3 マーカー間置換、Phase 3 venv 既存・mcp 既存・新規ファイル配置・settings.local.json 更新
- `deploy.sh` 2 回目: 全 8 工程「変更なし」（冪等性 OK）
- `settings.local.json` 確認: 既存 `permissions` / `hooks` が保持され、`mcpServers.session-recall` が追加されている
- MCP プロトコル smoke test:
  - initialize → `protocolVersion: 2024-11-05` / `serverInfo: session-recall@3.0.0` 返却 OK
  - tools/list → `session_recall_search` ツール定義返却 OK
  - tools/call → `keywords: ["claude-mem", "撤去"]` で search.sh 結果を JSON-RPC で返却 OK

### 設計判断
- ツール名は `session_recall_search` 単数形（MCP 慣習）
- search.sh のロジックを Python に再実装せず subprocess 呼び出しに（一実装で済む、テスト容易、Phase 2 と整合）
- 将来パフォーマンス課題なら Phase 3.5 で SQLite FTS5 直接アクセスに置き換え（プロセス起動オーバーヘッド削減）
- venv は PC ローカル（Drive 同期するとプラットフォーム互換性が壊れる）
- `settings.json`（Drive 同期）ではなく `settings.local.json` に登録（絶対パスが Mac/Win で異なるため）
- `_claude-sync/session-recall/` は配布物（search.sh / server.py / run_server.sh）の集約場所。venv は別

### 残課題（次セッション以降）
- Claude Code を再起動して、セッション内で `session_recall_search` ツールが認識されるか確認
- ユーザーが「前回 ○○ の話したよね」と聞いた時に Claude が自動で MCP tool を呼ぶか観察
- Windows 機での venv セットアップ + MCP server 起動確認（py -3.14 経路の動作確認）
- Phase 4 着手: セマンティック検索（埋め込みモデル + sqlite-vec）

## 2026-04-24: Phase 3 修正（resume 後の検証で発覚）

### 問題
- セッション #2 終了後、`/exit` → `claude --resume` で復帰したところ、`session_recall_search` MCP tool が認識されていなかった（ToolSearch でヒットせず、pgrep でも MCP server プロセスなし）
- `claude mcp list` で確認すると `session-recall` が一覧にない（claude.ai の Drive/Gmail/Calendar しか出ない）

### 原因
- **Claude Code 2.x は `~/.claude/settings.local.json` の `mcpServers` キーを読まない**
- 正規の MCP サーバー登録は `claude mcp add` CLI 経由（`~/.claude.json` に保存される）
- 当初の deploy.sh は jq で `settings.local.json.mcpServers` を merge していたが、効果なかった

### 修正
- `claude mcp add --scope user session-recall "<run_server.sh>"` で登録 → `claude mcp list` で `✓ Connected` 確認
- `deploy.sh` の `register_mcp_server()` を以下に変更:
  - 旧形式の `settings.local.json.mcpServers` キーがあれば自動削除（クリーンアップ）
  - `claude mcp list` で既存登録チェック
  - 未登録なら `claude mcp add --scope user` 実行
- 修正後の deploy.sh は冪等（再実行で「登録済み」表示）

### 教訓
- Claude Code の MCP 周りは v2.x で API が変わった可能性。**設定ファイル直書き** ではなく、**公式 CLI 経由** で操作するのが安全
- `claude mcp list` で `✓ Connected` まで確認するのがゴール（ヘルスチェック付き）
- 検証は実 resume してみないと分からない（私自身の context だけでは MCP の有効化状態を判定できなかった）

### 残課題（resume 後の再検証）
- もう一度 `/exit` → `claude --resume` で復帰し、ツール一覧に `session-recall` の MCP tool が出るか確認
- 自然言語クエリで Claude が自動呼び出しするか観察

## 2026-04-24: Phase 4 完了（セマンティック検索）

### 技術選定
- **埋め込みモデル**: `intfloat/multilingual-e5-small`
  - 384 次元、~470MB、CPU で動作、100+ 言語対応（日本語含む）
  - インデックス側は `passage:` prefix、検索側は `query:` prefix（multilingual-e5 推奨）
- **ベクトル DB**: SQLite + `sqlite-vec` 0.1.9
  - `vec0` 仮想テーブル、`MATCH` 演算子 + `k=N` で近傍検索
  - sqlite-vss は更新止まってるので sqlite-vec が後継として安心
- **段落分割**: Markdown の `^#{1,4} ` 見出しで区切る + 40 行で強制分割
- **増分判定**: ファイル mtime と DB の `chunks.file_mtime` を比較

### 実装
- `scripts/index_build.py`: 全プロジェクト走査 → 段落分割 → 埋め込み → SQLite 保存
- `scripts/server.py` v4.0: `session_recall_semantic` tool 追加（既存 `session_recall_search` と並列）
- `deploy.sh` を 11 工程に拡張:
  - `setup_venv_phase4()`: `sentence-transformers` + `sqlite-vec` install
  - `build_index_if_missing()`: DB 未存在なら `index_build.py` 自動実行
- `claude_md_patch.md` v4: 「キーワード明確 → search、曖昧 → semantic」使い分け指示

### 動作確認
- `index_build.py` 初回構築:
  - 全 _Apps2026/ + _other-projects/ の全 3 ファイル走査
  - 4239 chunks 生成、84.7 秒、DB 13.3 MB
  - モデル DL（HuggingFace）はオフラインキャッシュに保存される（次回以降速い）
- in-process semantic_search テスト 3 クエリ全成功:
  1. 「TODO リストの結合機能を実装した話」→ Memolette-Flutter HANDOFF/SESSION_HISTORY の結合実装 + Swift 版 Memolette の関連機能
  2. 「claude-mem を撤去した経緯」→ Memolette-Flutter HANDOFF/SESSION_HISTORY と session-recall DEVLOG の撤去手順
  3. 「Drive 同期の問題で困った」→ Kanji_Stroke / Data_Share の Dropbox 隠しフォルダ問題議論
- MCP smoke test:
  - tools/list で両 tool 認識（session_recall_search + session_recall_semantic）
  - tools/call (semantic) 経路は subprocess parse で問題ありだが in-process は OK
  - 実 Claude Code 経由の検証は resume 後に持ち越し

### 設計判断
- ロジックを Python に移植せず subprocess (search.sh) と Python (semantic) でツール別に実装
- 増分更新は手動で `python index_build.py` を回す方式（自動化は `/end` フック検討中）
- DB は PC ローカル（Drive 同期は SQLite 破損リスクで NG）
- ツール本体（server.py、index_build.py、search.sh、run_server.sh）は Drive 同期して全 PC で同じものを使う

### 残課題（次セッション以降）
- resume 後に `mcp__session-recall__session_recall_semantic` が実 Claude Code から呼び出されるか
- `/end` スキル拡張で `python index_build.py` の自動実行を組み込む
- Windows 機での全工程動作確認（py -3.14 経路、PyTorch インストール、sqlite-vec ロード）
- Phase 5 アイデア: プロジェクト絞り込み、時系列フィルタ、ハイブリッド検索（keyword + semantic re-rank）

## 2026-04-24: Phase 5 完了（/end フックで増分インデックス自動更新）

### 設計
- `_claude-sync/commands/end.md` に Step 2.5 を末尾追記する形（既存 Step 1〜3 を破壊しない）
- マーカーは `<!-- session-recall:end-hook:begin v1 -->` ... `:end v1 -->`（CLAUDE.md とは別系統、行頭一致）
- `update_index.sh` は `nohup ... &` でバックグラウンド起動 → /end の終了を遅らせない
- DB 未存在・venv 未セットアップなら `update_index.sh` 内でサイレント exit 0（初回 deploy 前は何もしない）

### 実装
- `scripts/update_index.sh`: venv の python を Mac/Win 両対応で探索、`index_build.py --quiet` を呼ぶ薄い wrapper
- `instructions/end_patch.md`: end.md 注入用の Step 2.5 ブロック（バックグラウンド起動コマンド + Mac/Win 両対応 path 探索）
- `deploy.sh` を 13 工程に拡張:
  - 定数: `UPDATE_INDEX_SH`, `END_PATCH_FILE`
  - 関数: `extract_end_hook_block()`, `inject_end_hook()`（既存 `extract_block` / `inject_into` の end-hook 版）
  - メイン処理: Phase 5 セクション追加（[12/13] update_index.sh 配置、[13/13] end.md 注入）

### 動作確認
- `update_index.sh` 単体実行 → exit 0、15 秒（モデルロード + 変更ファイルの再埋め込み）
- `deploy.sh` 1 回目: end.md に末尾追記、バックアップ作成
- `deploy.sh` 2 回目: 全 13 工程「変更なし」（冪等性 OK、update_index.sh / end.md 共に再注入なし）
- 注入後の end.md 末尾に Step 2.5 ブロックが正しく挿入されてることを確認

### 設計判断
- end.md は別チームの「グローバル設定」だが、マーカー方式で既存内容を破壊せず追記できる
- 増分更新は変更ファイルがあるときだけ動くので、毎 /end で 0〜数十秒のオーバーヘッド
- バックグラウンド起動なので /end 体感は変わらない
- update_index.sh は CLAUDE.md ルールに従って失敗無視（exit 0）

### 残課題
- 別 PC（Windows 含む）での全 13 工程動作確認
- /end が実際に呼ばれた際に update_index.sh が起動するか実体検証（次回 /end で確認可能）

## 2026-04-24: Phase 5.1 バグ修正（/end フックの競合条件）

### 症状
セッション #5 の実体検証で、フックは走ったのに最新セッションの HANDOFF.md / SESSION_HISTORY.md がインデックスに未反映。

| 指標 | 値 |
|---|---|
| DB indexed_at | 22:18:35 |
| SESSION_HISTORY.md 実ファイル mtime | 22:18:43（8 秒後） |
| HANDOFF.md 実ファイル mtime | 22:18:45（10 秒後） |

### 原因
`/end` Step 2.5 フックが Step 2（HANDOFF / SESSION_HISTORY / SESSION_LOG の並列書き出し）と並走し、書き出し完了前に mtime 比較が走って取りこぼし。毎回 1 セッション遅れで反映されるバグだった。

### 修正（C 案: A + B の二重防衛）
1. **A: `scripts/update_index.sh` に `sleep 30` 追加** — 書き出しを待ってから mtime 比較
2. **B: `instructions/end_patch.md` のセクション名を Step 2.5 → Step 2.9** + 説明文に「Step 2 の並列処理完了後に実行」と明記 — Claude の解釈順序上も後ろに配置
3. `_claude-sync/` 側の `update_index.sh` と `commands/end.md` にも反映

### 検証
1. セッション #5 分の取りこぼしは `update_index.sh` 手動実行で補完（SESSION_HISTORY.md chunks 21→27、file_mtime も現ファイルと一致）
2. 修正版を競合シナリオで再現テスト: バックグラウンド起動 → 1 秒後に DEVLOG.md touch → sleep 30 後に update_index.sh が touch 後の新 mtime を正しく検出してインデックス反映 ✅

## 2026-04-24: Phase 5.1 本番検証（セッション #7 開始時）

セッション #6 終了時の /end が修正版フックの初回本番試験。

### 結果: 完全達成 ✅

| 指標 | 値 |
|---|---|
| コミット時刻（#6 終了） | 23:27:02 |
| DB 更新時刻（indexed_at） | 23:27:47（コミットの 45 秒後 ≒ sleep 30 + 処理時間） |
| 総 chunks | 4264 → 4277（+13） |

ファイル別 DB file_mtime と実ファイル mtime の完全一致:

| ファイル | DB 記録 | 実ファイル | 判定 |
|---|---|---|---|
| SESSION_HISTORY.md | 23:25:10 | 23:25:10 | ✅ |
| HANDOFF.md | 23:26:49 | 23:26:49 | ✅ |
| DEVLOG.md | 22:54:10 | 22:54:10 | ✅ |

Phase 5.1 の sleep 30 + Step 2.9 配置の二重対策で、書き出し完了を確実に待ってから差分を取る挙動を本番で検証できた。

## 2026-04-24: Phase 6 完了（プロジェクト絞り込み）

### 動機
両 MCP tool は全プロジェクト横断が前提の設計で、特定プロジェクト内の話題を探したいときに他プロジェクトのノイズが混じっていた。DB の `chunks.project` カラムは既存（Phase 4 から）なので、引数追加と SQL WHERE で素直に実装できる。

### 検討と判断（Phase 6 スコープ）
当初案は以下 5 つ:
A. プロジェクト絞り込み（今回採用）
B. セッション番号指定参照
C. ハイブリッド検索（keyword AND → semantic re-rank）
D. 時系列フィルタ / タイムライン
E. 横断未完了 TODO

検討結果、A 以外はいずれもデメリットあり:
- B: 番号を覚えているケース限定で頻度低い
- C: MCP tool が 3 つに増えて Claude のツール選択判断コストが増す
- D: SESSION_HISTORY ヘッダ書式依存で脆い、出力過多リスク
- E: ROADMAP を検索対象から除外した経緯（未確定アイデアがノイズ）と矛盾

→ **A だけを Phase 6 スコープに確定**。

### 実装
1. **`scripts/search.sh`**: `--project <名前>` / `--project=<名前>` を先頭・途中どちらでも受付け。ROOT_CANDIDATES を走査して `ROOT/PROJECT` が存在するもののみ ROOTS に採用。0 件時は「プロジェクトが見つからない」エラー
2. **`scripts/server.py` v6.0.0**:
   - keyword_search: `project` を subprocess 引数に `--project` として引き渡す
   - semantic_search: SQL に `WHERE c.project = ?` を追加。sqlite-vec の `k = ?` は近傍 k 件取得の指示で追加 WHERE は post-filter になるため、`k = max(limit * 20, 100)`（最大 500）に広げて project 絞り込み後に十分な候補が残るようにした
   - inputSchema / description に `project` optional 追加
3. **`commands/recall.md`**: 使用例に `/recall --project Memolette-Flutter ToDo 結合` 追加。引数はそのまま search.sh に渡すだけ
4. **`instructions/claude_md_patch.md` v5**: 両 tool の引数説明更新 + 「プロジェクト絞り込み（`project` 引数）の使いどころ」セクション追加。アンチパターンに「特定プロジェクト名を言っているのに project を省いて横断ノイズを混ぜる」を追加

### 同時修正した既存バグ
bash 3.2（macOS default）は `set -u` 下で空配列 `"${A[@]}"` を unbound variable 扱いする。`search.sh` の `CANDIDATES=("${FILTERED[@]}")` と `set -- "${ARGS[@]}"` がこれに該当し、Phase 6 の keyword_search で AND フィルタが 0 件になった時に顕在化したため、`${A[@]+"${A[@]}"}` 形式に修正。

### 動作確認
- `search.sh --project session-recall 競合`: session-recall の chunk のみ返却 ✅
- `search.sh --project NoSuchProject test`: 「プロジェクトが見つからない」エラー ✅
- `server.py` semantic in-process:
  - project 指定なしで「Flutter のビルドエラー」→ Memolette-Flutter / P3_reminder がトップ
  - `project=Memolette-Flutter`: Memolette-Flutter のみ
  - `project=session-recall`（Flutter 無関係プロジェクト）: session-recall の chunk に絞り込まれた（距離は遠くなったが ORDER BY は有効）
- `deploy.sh` 1 回目: CLAUDE.md v4→v5 置換、recall.md / search.sh / server.py が更新
- `deploy.sh` 2 回目: 全 13 工程「変更なし」（冪等性 OK）

### 設計判断
- プロジェクト名は `_Apps2026/` or `_other-projects/` 直下のフォルダ名（`chunks.project` と完全一致）。外部入力なのでバリデーション不要、0 件ならその旨を返す
- ハイブリッド検索（C 案）は見送り。将来 search / semantic の精度が足りないと判明したら検討
- DB スキーマは無変更、既存インデックスをそのまま流用（再構築不要）

### 残課題
- Windows 機での動作確認（既存の残課題に含める）
- Claude Code 再起動後に新しい project 引数が Claude の自動判断で使われるか観察
