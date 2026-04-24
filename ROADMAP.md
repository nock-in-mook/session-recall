# ROADMAP

## Phase 0: プロジェクト立ち上げ ✅
- [x] `session-recall/` フォルダ作成
- [x] 初期ドキュメント（README / HANDOFF / ROADMAP / DEVLOG / SESSION_HISTORY）
- [x] スキル・インストラクション・deploy スクリプトのスケルトン
- [x] git init + 初期コミット
- [x] GitHub リポジトリ作成 + push

## Phase 1 (Lv.0): CLAUDE.md 指示追加 ✅
過去セッション参照が必要なとき、Claude が自発的に grep するように指示を追加する。

- [x] `instructions/claude_md_patch.md` 確定版 v1（マーカー `<!-- session-recall:begin v1 -->` ... `:end v1 -->`）
- [x] `deploy.sh` 実装（冪等、Mac/Win 両対応、差分なしならバックアップも作らない）
- [x] `~/.claude/CLAUDE.md` に追記
- [x] `_claude-sync/CLAUDE.md` にも追記（Windows 側展開用）
- [x] 別プロジェクト（Memolette-Flutter）で grep 動作確認 → 「結合」「claude-mem」両方でヒット
- [x] 参照対象を `SESSION_HISTORY.md` / `HANDOFF.md` / `DEVLOG.md` に確定（`ROADMAP.md` は除外）

### Phase 1 の成功基準
- [x] 「前回 Memolette で何の作業してた？」と聞いた時に Claude が自動で grep して答える（指示追加済み、新セッションで実体検証要）
- [x] ユーザーが明示コマンドを打たなくても自然言語で動く（CLAUDE.md 指示で実現）

## Phase 2 (Lv.1): /recall スラッシュコマンド ✅
複数プロジェクト横断の想起を、明示的コマンドで呼べるようにする。Phase 1 の grep を skill 経由に切り替えた。

- [x] `scripts/search.sh` 本実装（ripgrep 優先・grep フォールバック、複数キーワード AND、前後 ±5 行、上位 10 件）
- [x] `commands/recall.md` 確定（既存の `_claude-sync/commands/` 形式に整合）
- [x] `deploy.sh` を Phase 2 拡張（`commands/recall.md` → `_claude-sync/commands/`、`scripts/search.sh` → `_claude-sync/session-recall/`）
- [x] `claude_md_patch.md` を v2 に更新（grep 直叩きから search.sh 経由 + /recall 案内に）
- [x] 動作検証: `claude-mem 撤去` AND 検索で 4 ファイルから関連箇所抽出、現セッションでも `/recall` スキルとして自動認識

### Phase 2 の成功基準
- [x] `/recall ToDo 結合` 等で過去の全プロジェクトから該当会話を引き出せる
- [x] 約 1 秒以内（user time）で返る（壁時計は Drive アクセスで 3 秒前後）
- [x] 日本語キーワードで正常動作

### Phase 2 で発見・修正したバグ
- **awk マーカー誤マッチ問題**: patch ファイル中の `<!-- session-recall:begin` の例示（バックティック内）も extract_block の awk が拾い、CLAUDE.md が肥大化（1876 行になった）
- 修正: awk パターンを行頭マッチ `^<!-- session-recall:` に変更
- 教訓: マーカーパターンは行頭 `^` 必須、説明文中での例示は安全

## Phase 3 (Lv.2): MCP サーバー化 ✅
ユーザーが `/recall` を打たなくても、Claude が会話文脈から自動で `session_recall_search` ツールを呼ぶ。

- [x] MCP サーバー実装（Python、`mcp` パッケージ 1.27.0、stdio transport）
- [x] ツール名: `session_recall_search`、引数: `keywords: string[]`
- [x] バックエンド: 当面は subprocess 経由で `search.sh` を呼ぶ（Phase 3.5 で SQLite FTS5 化検討）
- [x] `~/.claude/settings.local.json` に登録（jq merge で既存項目を破壊せず追記）
  - 注: `settings.json`（Drive 同期）ではなく `settings.local.json`（PC ローカル）に書く。Mac/Win で絶対パスが異なるため
- [x] `claude_md_patch.md` を v3 に更新（MCP tool 優先 / bash search.sh フォールバック / 現プロジェクト grep を先頭）
- [x] MCP プロトコル動作確認: initialize / tools/list / tools/call すべて正常

### 動作確認済み
- venv 自動セットアップ + mcp 自動インストール（`deploy.sh` 内で完結）
- `tools/call` で `session_recall_search(["claude-mem", "撤去"])` 実行 → `search.sh` の出力が JSON-RPC で返却

### 残課題（実体検証）
- Claude Code 再起動後にツールが認識・自動呼び出しされるか
- 自然言語クエリ（「前回 ○○ の話したよね」等）で Claude が自動的に MCP tool を呼ぶか
- Windows 機での venv セットアップ + MCP server 起動確認

### Phase 3 修正（resume 後の検証で判明）
- **Claude Code 2.x は `~/.claude/settings.local.json` の `mcpServers` キーを読まない**ことが判明
- 正規の登録経路は `claude mcp add` CLI（`~/.claude.json` に書かれる）
- `deploy.sh` の `register_mcp_server()` を `claude mcp add --scope user` 経由に変更
- 旧形式の `settings.local.json.mcpServers` キーは自動削除するクリーンアップも追加
- `claude mcp list` で `session-recall: ... ✓ Connected` 確認済み

## Phase 4 (Lv.3): セマンティック検索 ✅
キーワード一致しない曖昧クエリ（「あのボタン配置で議論した時」「パフォーマンスで悩んだ件」）に対応。

- [x] 埋め込みモデル: `intfloat/multilingual-e5-small`（384 次元、~470MB、CPU 動作、日本語対応）
- [x] ベクトル DB: SQLite + `sqlite-vec` 0.1.9（vec0 仮想テーブル）
- [x] `scripts/index_build.py`: 全プロジェクト 3 ファイル走査 → Markdown 見出し単位の段落分割 → 埋め込み → DB 保存
- [x] 増分更新: ファイル mtime 比較で変更ファイルだけ再埋め込み（`--force` で全再構築）
- [x] `server.py` に `session_recall_semantic` MCP tool 追加（既存 `session_recall_search` と並列提供）
- [x] `claude_md_patch.md` v4: 「キーワード明確 → search、曖昧 → semantic」使い分け指示

### 動作確認済み
- `index_build.py` で 4239 chunks、84 秒、DB 13.3 MB 生成
- in-process semantic_search で 3 クエリ全て関連性高い結果返却
- MCP tools/list で両 tool 認識（session_recall_search + session_recall_semantic）

### クロス PC 戦略（実装通り）
- 元データ（SESSION_HISTORY 等）は Google Drive 経由で全 PC 同期 = 共通土台 ✅
- ベクトル DB は PC ごとにローカル（`~/.claude/session-recall-index.db`）✅
- ツール本体（server.py / index_build.py / search.sh / run_server.sh）は Drive 同期 ✅
- 新 PC では `bash deploy.sh` 一発で index_build まで自動実行（モデル DL 含めて 1〜数分）

### 残課題（次セッション以降）
- 実 Claude Code から `mcp__session-recall__session_recall_semantic` 呼び出しの実体検証（resume 後）
- `/end` スキル拡張で増分インデックス更新の自動化
- Windows 機での venv + sentence-transformers + sqlite-vec 動作確認

## アイデアメモ
- `/recall-proj <プロジェクト名> <キーワード>` で特定プロジェクトに限定検索
- `/timeline <期間>` で時系列ダイジェスト
- 全プロジェクトの未完了 TODO を横断サマリーする `/todo`
- セッション番号指定での詳細参照（`/session 26` → セッション#26 の要約と主要やり取り）

## 解決済み備忘
- ~~検索対象を SESSION_HISTORY のみにするか、DEVLOG/HANDOFF まで広げるか~~ → SESSION_HISTORY + HANDOFF + DEVLOG に確定
- ~~deploy.sh を Mac/Win 両対応にするか、別々に書くか~~ → 1 本で両対応（uname 不要、`-d` 存在チェックで分岐）
