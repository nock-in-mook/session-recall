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
- Windows 機での venv + sentence-transformers + sqlite-vec 動作確認

## Phase 5: /end フックで増分インデックス自動更新 ✅
セッション終了時に最新追記分を自動で DB 反映する。

- [x] `scripts/update_index.sh`: venv の python で `index_build.py` を呼ぶ薄い wrapper（DB / venv 未存在ならサイレントスキップ）
- [x] `instructions/end_patch.md`: `_claude-sync/commands/end.md` に注入する Step 2.5 ブロック（マーカー `<!-- session-recall:end-hook:begin/end -->`）
- [x] `deploy.sh` を 13 工程に拡張: `extract_end_hook_block()` + `inject_end_hook()` 関数追加
- [x] 注入された end.md は `nohup bash update_index.sh >/dev/null 2>&1 &` でバックグラウンド起動 → /end の終了をブロックしない

### 動作確認
- `update_index.sh` 単体実行で increment update 成功（exit 0、15 秒）
- `inject_end_hook` で end.md 末尾追記、冪等性 OK

## Phase 5.1: /end フック競合条件修正 ✅
セッション #5 の実体検証で Step 2 の並列書き出しと Step 2.5 フックが並走し、書き出し完了前に mtime 比較が走るバグを修正。

- [x] `scripts/update_index.sh` に `sleep 30` 追加（書き出し完了を待つ）
- [x] `instructions/end_patch.md` のセクション名を Step 2.5 → Step 2.9 + 説明文に「Step 2 の並列処理完了後に実行」と明記
- [x] 競合シナリオ再現テストで sleep 30 後の新 mtime を正しく検出することを確認
- [x] セッション #6 終了時の本番試験: コミット 23:27:02 → DB indexed_at 23:27:47、file_mtime も実ファイルと完全一致（Phase 6 セッション開始時に検証完了）

## Phase 5.2: セッション開始時のインデックス自動追いつき ✅
/end フック（Phase 5/5.1）はセッション終了時に自機 DB を更新する。しかし PC 間で作業を跨ぐと「別 PC で書かれた SESSION_HISTORY が自機 DB に次の自機 /end まで反映されない 1 セッション分の盲点」が残る（セッション #8 の Mac A ↔ B 試験で確認）。開始時にも追いつかせることで盲点を消す。

- [x] `scripts/update_index.sh` の `sleep 30` を引数化（`sleep "${1:-30}"`、start 用途は `0` を渡す）
- [x] `instructions/claude_md_patch.md` v6: 「セッション開始時の DB 自動追いつき（必ず実行）」セクション追加。Step 0 と並列でバックグラウンド実行を明示
- [x] deploy.sh 実行で両 CLAUDE.md に v6 注入 + update_index.sh の引数化を Drive 同期

### 動作確認
- `time bash update_index.sh 0` = 8.5 秒（sleep 0 が効いてる、sleep 30 なら 38 秒超になるはず）
- deploy.sh 冪等性: 2 回目実行で update_index.sh 以外の 12 工程は「変更なし」

### 設計判断
- 引数化方式（別スクリプト化せず）で既存 end-hook の後方互換を維持
- deploy.sh は変更不要（Phase 1 の CLAUDE.md 注入と Phase 5 の update_index.sh 配置で完結）

### 残課題
- 次セッション開始時（別 Mac や Windows で）に start-hook が実際に発火するか実体観察

## Phase 6: プロジェクト絞り込み ✅
両 MCP tool に optional な `project` 引数を追加し、特定プロジェクトのみを対象にした検索を可能に。DB 再構築不要。

- [x] `scripts/search.sh` に `--project <名前>` オプション追加（先頭・途中どちらでも受付け）
- [x] `scripts/server.py` v6.0.0: 両 tool の inputSchema / description に `project` optional を追加
  - keyword: search.sh に `--project` を引き渡すだけ
  - semantic: SQL WHERE に `c.project = ?` を追加、k を limit × 20（最大 500）に広げて post-filter でも十分な候補を確保
- [x] `commands/recall.md` 更新: `/recall [--project <名前>] <キーワード> ...` に拡張
- [x] `instructions/claude_md_patch.md` v5: project 引数の使い分け指示を追加
- [x] bash 3.2（macOS default）で空配列展開が unbound variable になる既存バグも同時修正（`${ARGS[@]+"${ARGS[@]}"}` 形式）

### 動作確認
- search.sh 単体: ヘルプ / `--project session-recall 競合` / 無効プロジェクト名エラーすべて OK
- server.py in-process: semantic で `project=Memolette-Flutter` / `project=session-recall` の絞り込みが効く
- deploy.sh 1 回目: CLAUDE.md v4→v5 置換、recall.md / search.sh / server.py 更新
- deploy.sh 2 回目: 全 13 工程「変更なし」（冪等性 OK）

## Phase 7: bash CLI フォールバック (semantic.sh / search.sh) ✅
Claude Code v2.1.116〜 の MCP regression（custom stdio MCP のツール露出が壊れる既知バグ #51736）対策。MCP 不在でもセマンティック検索が動く bash 単体ルートを新設。

- [x] `scripts/semantic.py`: server.py の semantic_search を CLI 単体実装に移植
- [x] `scripts/semantic.sh`: venv の python を Mac/Win 両対応で探索する bash ラッパー
- [x] `deploy.sh` を 15 工程に拡張（[14/15], [15/15] で _claude-sync 経由配布）
- [x] CLAUDE.md フォールバック節更新（MCP があれば優先、なければ bash 自動分岐）
- [x] Win 1/2/3 台目で deploy + 動作確認、Mac は MCP 経由でフル稼働

### 既知バグ (#14 で発見、#15 で修正)
- **semantic.sh の Windows cp932 エンコードエラー**: 検索結果に絵文字 (例: 📅) が含まれると `UnicodeEncodeError: 'cp932' codec can't encode character`
- 修正 (#15): `scripts/semantic.py` 冒頭に `sys.stdout.reconfigure(encoding='utf-8')` + `sys.stderr.reconfigure(encoding='utf-8')` 追加（Python 3.7+ の hasattr ガード付き、Linux/Mac は no-op）
- Win 実機で「Claude Code のセッションを別 PC で resume できる仕組み」クエリ実行 → 距離 0.392 の関連段落が絵文字含めて正常出力されることを確認

## Phase 8: PC 横断 resume 自動化 — ❌ 撤去 (#19, 2026-04-27)

#15〜#18 で Mac/Win 双方の SessionStart hook 自動発火・picker 反映までは実証できたが、**Drive 同期事故が構造的に避けられない**ことが判明したため #19 で完全撤去。

### 撤去理由
- `~/.claude/projects/` 配下の jsonl は Drive 同期対象 → 複数 PC が同時更新すると `(1)` 付きフォルダに分裂し、picker は正規フォルダしか見ないため壊れた途中状態を表示する事故が #17 で発生
- #18 では Mac 側ローカルの古い mtime が「勝った」競合解決で Win 側の最新版 jsonl が巻き戻され、データ消失リスクが現実化
- jsonl 共有は本筋（HANDOFF / SESSION_HISTORY 運用）から見ると付加機能。リスクが利益を上回ると判断

### 確定運用方針（#18 末判断）
- 各 PC で **新規 `claude` 起動** (resume せず)
- cwd は通常のプロジェクトフォルダ
- CLAUDE.md Step 0 で git pull → HANDOFF / SESSION_HISTORY を読んで前回文脈把握
- 続きを実行 → /end で締め (HANDOFF/SESSION_HISTORY 自動更新)
- jsonl 共有は **しない**

### 撤去内容 (#19)
- リポと `_claude-sync/session-recall/` から `sync_sessions.sh` / `register_hook.py` 削除
- `_claude-sync/settings.json` の `hooks.SessionStart` から sync_sessions エントリ削除
- `deploy.sh` から Phase 8 工程 [16/17][17/17] と関連変数・関数削除

### 教訓
- Drive 同期 + git/jsonl 共有は本質的に詰む (Phase 9 の `.git/` symlink 不可と同根)
- PC 横断は手動メンテのテキストファイル (HANDOFF / SESSION_HISTORY) を介する方が頑健
- バックアップ jsonl は `~/aeed7cdd-backup/` 等に Drive 圏外保持 (撤去後も削除しない)

## Phase 9: .git Drive 同期問題の根本対策 — 技術的詰み、運用ルールで代替 (#15 で結論)

### 背景
- `_Apps2026/session-recall/` は Drive 上 → `.git/` ディレクトリも同期対象
- セッション #14 で Mac 側 Claude が古い `.git/` 状態で resume → Drive 同期で Win 側 `.git/` が `6ead100` (#12 終了時) に上書きされる事故発生
- ローカルから push 済みコミット (`18d1f51` `89c8ead` 等) が消えて見える状態に
- 復旧は `git fetch && git reset --hard origin/main` で可能（GitHub に残ってるので）

### 当初の設計（symlink/junction 案）
`_Apps2026/session-recall/.git` を PC ローカル (`~/repos/session-recall/.git`) への symlink/junction に置き換えれば Drive 同期から外せる。setup.bat / setup_mac.sh で自動化、既存 Drive 配下リポ（Memolette-Flutter 等）も順次展開。

### #15 で技術的に詰んだことが判明
| 試した方式 | 結果 |
|---|---|
| Win junction (`mklink /J`) | ❌ Drive 仮想 FS は NTFS でないため拒否 |
| Win symlink (`mklink /D`) | ❌ Drive クライアントが「このデバイスではシンボリックリンクがサポートされていません」 |
| Mac symlink | ⚠️ 「起動時のみ同期」「regular file 扱い」「PC ごとパス違い」で死亡 |
| Drive Desktop 「Sync only these folders」 | ❌ サブフォルダ単位 (`.git/`) の除外不可 |
| 第三者ツール Insync ($30) | △ glob exclude 可、ただし要購入 + Mac でも入れ替え必要 |
| gitfile (`.git` を `gitdir: ...` テキスト) | ❌ PC ごとに内容違う必要 → Drive 同期で毎回衝突 |

→ **Drive 同期と git の同居は本質的に詰む**。Drive 配下にリンクを作る方式は OS / Drive クライアントの両方で拒否される。

### 採用した代替: 運用ルールで巻き戻り検知
`_claude-sync/CLAUDE.md` の Step 0 を改修済み（#15 で実装）:

1. `git fetch origin` で最新リモート取得
2. `git status -sb` で behind / ahead を判定
3. behind なら `git pull --ff-only` を試す。失敗（fast-forward 不可）→ **Drive 同期巻き戻り**と判定 → ユーザーに「未 push WIP ありますか？」確認の上 `git reset --hard origin/main`
4. ahead のみなら自動 `git push`
5. ahead && behind なら手動判断を仰ぐ

これで「push 済みコミットは GitHub から復元」「未 push WIP はユーザーが意識して commit 切る」運用が成立。事故起きても自動検知 + 復旧で実害ゼロ。

## Phase 10: claude wrapper による起動時最新反映 + ゴミ jsonl 自動掃除 (#17 追加)

### 背景
Phase 8 の SessionStart hook は **picker 表示後** に発動する設計のため、`claude --resume` 1 回目では他 PC からの新規 jsonl が picker に出ない。「2 回起動 (即 /exit → 再 resume)」運用で回避できるが、即 /exit のたびに空ゴミセッション jsonl (例: b6e607f3 = 2.7KB / no user) が picker 候補に蓄積する。

#17 末で「Mac の修復が反映されない問題」が露見し、wrapper 方式での「起動時最新即反映」需要が明確化。

### 設計
| 役割 | 場所 | 内容 |
|---|---|---|
| 起動前 jsonl 同期 | `_claude-sync/session-recall/scripts/pre_claude_sync.sh` | `sync_sessions.sh` を stdin なし版に再実装。`pwd` から cwd 算出 → encoded folder 名で自フォルダ特定 → 兄弟フォルダ jsonl を copy |
| ゴミ掃除 | `_claude-sync/session-recall/scripts/cleanup_empty_sessions.sh` | 自フォルダの jsonl で「ユーザー発言 0 件 + mtime 5 分以上古い」ものを `~/.claude/projects-trash/` に移動 (削除でなくゴミ箱方式) |
| claude function 定義 | `_claude-sync/session-recall/scripts/claude_wrapper.sh` | bash/zsh 両対応の `claude()` 関数。`pre_claude_sync.sh` + `cleanup_empty_sessions.sh` を実行してから本物 claude を起動 |
| .bashrc/.zshrc 注入 | `setup.bat` Step 4e / `setup_mac.sh` Step 4.6 | `source $WRAPPER` 1 行を追加 (冪等) |

### 期待効果
- ✅ `claude --resume` 1 回で他 PC 由来の最新 jsonl が picker に並ぶ (起動時 sync 完了後に picker 表示)
- ✅ 即 /exit ゴミセッションが picker から自動消滅
- ✅ Mac の修復伝播も hook 待たず即時反映
- ⚠️ claude 起動が 1〜10 秒遅くなる (jsonl 数 + Drive 状態による)
- ⚠️ alias / function 上書きなので Claude Code アップデートで PATH 解決の影響受ける可能性

### 実装メモ
- `encode_cwd` 関数: cwd 文字列の `/`, `_`, `@`, `.` を `-` に置換 → `~/.claude/projects/<encoded>` を取る
  - Mac の `/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_Apps2026/session-recall` → `-Users-nock-re-Library-CloudStorage-GoogleDrive-yagukyou-gmail-com---------Apps2026-session-recall`
  - Win の `G:\マイドライブ\_Apps2026\session-recall` → `G----------Apps2026-session-recall` (バックスラッシュとコロンも `-` 化、日本語も `-` 化される観察)
- 兄弟フォルダ走査ロジックは `sync_sessions.sh` から流用
- ゴミ掃除の判定: `jq` が Win に無いので Python 標準 json で「last user text count == 0」を抽出

## アイデアメモ
- `/timeline <期間>` で時系列ダイジェスト
- 全プロジェクトの未完了 TODO を横断サマリーする `/todo`（ROADMAP 運用と重複しないかは要検討）
- セッション番号指定での詳細参照（`/session 26` → セッション#26 の要約と主要やり取り）
- ハイブリッド検索（keyword AND の結果を semantic で re-rank、必要性は要検討）

## 解決済み備忘
- ~~検索対象を SESSION_HISTORY のみにするか、DEVLOG/HANDOFF まで広げるか~~ → SESSION_HISTORY + HANDOFF + DEVLOG に確定
- ~~deploy.sh を Mac/Win 両対応にするか、別々に書くか~~ → 1 本で両対応（uname 不要、`-d` 存在チェックで分岐）
