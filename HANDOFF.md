# HANDOFF — session-recall

最終更新: 2026-04-25 セッション #9 終了時（Windows 1台目 deploy テスト完了、index_build.py パス修正）

---

## このファイルを読んだ次の Claude へ

初手：`README.md` → `ROADMAP.md` → この `HANDOFF.md` → `instructions/claude_md_patch.md` の順で読むと把握が早い。
以下にプロジェクトの全経緯・前提・方針を詰めたので、コードに入る前にざっと全部目を通すこと。

---

## 0. プロジェクトの一文説明

のっくりさんが手動メンテしている **`SESSION_HISTORY.md` / `HANDOFF.md` / `ROADMAP.md` / `DEVLOG.md`** を Claude が自発的に横断検索できるようにする自作ツール。claude-mem の自分版を、既存資産を活用した高 SN 比で実装する。

最終形は **Mac/Windows 両 PC で、全プロジェクトで自動的に動く**。

---

## 1. 経緯（なぜこれを作るのか）

### 1.1 前日までの文脈
- のっくりさんは Memolette-Flutter（Swift版メモアプリ「Memolette」の Flutter 移植）を開発中。セッション #27 まで進行。
- 今日（2026-04-24）のセッションで、TODO リストの結合マーク位置調整・チェックボックス位置調整・フィルタボタン中央固定などの UI 仕上げをコミット/push して完了。

### 1.2 claude-mem の記事をシェアしてもらった
- X で「claude-mem」という OSS が紹介されている記事を共有された
- Claude Code に永続メモリを与えるプラグイン、GitHub 6.5万スター、と煽り気味に宣伝
- のっくりさん「これどう思う？まぁやや煽り記事だけど、有益に見える」

### 1.3 数字確認
- 最初は俺（Claude）は眉唾判定したが、実際に `gh api` で叩いてみたら **本当に 6.6万スター**。作者 Alex Newman、v12.3.9 が 2026-04-22 にリリース済みなど、記事の数字は正確だった。謝罪。

### 1.4 claude-mem を試した
- `npm install -g claude-mem` → `claude-mem install` でインストール
- Claude Code プラグインとして登録、hook 経由で自動動作
- Mac の `~/.claude-mem/` に DB（SQLite FTS5）、port 37702 で worker 起動

### 1.5 試した結果、問題が続々
1. **hook エラー**: 毎回 `UserPromptSubmit hook error: Failed with non-blocking status code: No stderr output` が出る
2. 調べたら **claude-mem 側の既知バグ多数**（v12.3.9 は 4/22 リリースで、その直後から critical バグ issue が大量登録中）
   - #2090: hook スクリプトに `|| true` が抜けてる
   - #2108: observer-sessions churn
   - #2087: Gemini 429 でフォールバック未実装
3. **トークンオーバーヘッド重い**: Opus 4.7 で "やあ" 一往復に週 quota 3% 消費（通常 0.5〜1% 相当）。内訳はおおむね Opus 素体 1/3、のっくり global CLAUDE.md 読み込み 1/3、claude-mem 注入 1/3。
4. **要約ノイズ多い**: 「やあ」に対して "Initial greeting received" みたいな無意味サマリーが生成される
5. プロバイダを claude → gemini-2.5-flash-lite → gemini-2.5-flash に切り替えてある（設定ファイルで）。flash 無印にしてから 503 は緩和したが、ノイズ・コスト問題は構造的。

### 1.6 自作路線への転換
- のっくりさん既に **`SESSION_HISTORY.md` / `HANDOFF.md` / `ROADMAP.md` / `DEVLOG.md` を手動でしっかり維持** している
- `/end` スキルと `transcript_export.py` で自動書き出しまで運用中
- データ層はもう揃っている。「Claude に横断検索させる手段」だけ足せば claude-mem の価値の大半をカバーできると判断
- claude-mem と違って **のっくりさんの手動メンテ品質を活かす系**なので、情報密度圧倒的に高い

### 1.7 claude-mem はどうしたか
- **セッション#27 終了直前に完全撤去済み**（session-recall 完成を待たずに撤去した）
- 実施した手順:
  - `npm uninstall -g claude-mem`（グローバル npm パッケージ削除、153 packages）
  - Worker プロセス kill
  - `~/.claude-mem/` 削除（DB・設定・ログ全部）
  - `~/.claude/plugins/marketplaces/thedotmack/` および `~/.claude/plugins/cache/thedotmack/` 削除
  - `~/.claude/settings.json` の `enabledPlugins.claude-mem@thedotmack` と `extraKnownMarketplaces.thedotmack` 削除
- バックアップ `~/.claude-backup-pre-claude-mem/` は小さいので保険として残置
- 副産物の `~/.bun/`（claude-mem が自動導入）は残置、不要なら `rm -rf ~/.bun` で削除可

---

## 2. 現状スナップショット

### 2.1 作ったもの（Phase 1〜6 完了）
```
_Apps2026/session-recall/
├── README.md                       プロジェクト概要 + ファイル構成 + デプロイ後の配置 + 利用形態
├── HANDOFF.md                      ← このファイル
├── ROADMAP.md                      Phase 0〜4 すべて ✅
├── DEVLOG.md                       開発ログ（フェーズごとの記録）
├── SESSION_HISTORY.md              セッション履歴
├── SESSION_LOG.md                  /end 時の自動書き出し先
├── .gitignore                      __pycache__/ など
├── commands/
│   └── recall.md                   /recall スキル定義（Claude が解釈する）
├── scripts/
│   ├── search.sh                   bash キーワード検索（ripgrep 優先、AND、±5 行、上位 10）
│   ├── server.py                   MCP サーバー (v4): search + semantic 両 tool 提供
│   ├── run_server.sh               MCP 起動 wrapper（venv の python を Mac/Win 両対応で探索）
│   ├── index_build.py              セマンティック検索 DB 構築（multilingual-e5-small、Markdown 見出し分割）
│   └── update_index.sh             /end フック用 wrapper（バックグラウンドで増分更新）
├── instructions/
│   ├── claude_md_patch.md          v4（search/semantic の使い分け、現プロ grep フォールバック）
│   └── end_patch.md                /end スキル (end.md) 注入用パッチ（Step 2.5: 自動増分更新）
└── deploy.sh                       13 工程の本番反映（Phase 1〜5 全自動化、/end フック注入まで）
```

### 2.2 git 状態
- `main` ブランチ、GitHub: https://github.com/nock-in-mook/session-recall
- 主要コミット:
  - `6527e8b` Phase 0（初期スケルトン）
  - `9421d5f` Phase 1 完了
  - `13a7b54` Phase 2 完了
  - `035537e` Phase 3 完了
  - `32ee178` Phase 4 完了（セマンティック検索）
  - `aafe018` Phase 5（/end フック注入）
  - `8e44449` Phase 5.1（フック競合バグ修正: sleep 30 + Step 2.9）
  - `a554928` セッション #6 終了: Phase 5.1 本番試験
  - `1bf2e10` Phase 6: プロジェクト絞り込み（両 MCP tool に project 引数追加、bash 3.2 空配列バグも修正）

### 2.3 デプロイ後の配置（Phase 1〜6 全部反映済み）
```
~/.claude/CLAUDE.md                                  ← v4 ブロック注入済み
~/.claude.json                                       ← mcpServers.session-recall 登録済み (claude mcp add --scope user)
~/.claude/session-recall-venv/                       ← Python venv (mcp + sentence-transformers + sqlite-vec)
~/.claude/session-recall-index.db                    ← セマンティック検索ベクトル DB (15 MB、4239 chunks)
_claude-sync/CLAUDE.md                               ← v4 ブロック注入済み（Win 同期用）
_claude-sync/commands/recall.md                      ← /recall スキル
_claude-sync/session-recall/search.sh                ← bash キーワード検索
_claude-sync/session-recall/server.py                ← MCP サーバー (v4: search + semantic)
_claude-sync/session-recall/run_server.sh            ← MCP 起動 wrapper
_claude-sync/session-recall/index_build.py           ← インデックス構築スクリプト
_claude-sync/session-recall/update_index.sh          ← /end フック用 wrapper
_claude-sync/commands/end.md                         ← session-recall:end-hook ブロック注入済み（Step 2.9、Phase 5.1 で 2.5 から移動）
```

注:
- `~/.claude/settings.local.json` の `mcpServers` キーは Claude Code 2.x では読まれないため使わない
- venv と index DB は PC ローカル（プラットフォーム依存・SQLite 破損リスク回避）。新 PC では `bash deploy.sh` で再構築

### 2.4 claude-mem の現状
- **完全撤去済み**（2026-04-24 セッション#27 終了直前に実施）
- 詳細手順は §1.7 と Memolette-Flutter/HANDOFF.md:62 参照
- バックアップは `~/.claude-backup-pre-claude-mem/` に残置

---

## 3. 全フェーズ計画（最終形まで作り込む前提）

のっくりさん要望: **最終フェーズまで作りこむ**、**Mac と Windows の全 PC 横断対応**。

### Phase 0: プロジェクト立ち上げ ✅ 完了
- スケルトン配置、git init、push

### Phase 1 (Lv.0): CLAUDE.md 指示追加
**目標**: Claude が過去の話題への質問に対して、自発的に `SESSION_HISTORY.md` を grep して答える。

**実装**:
1. `instructions/claude_md_patch.md` を磨く（現状ドラフト）
2. `deploy.sh` の最小版を書く（Mac/Win 両対応）
3. `~/.claude/CLAUDE.md` に追記。同時に `_claude-sync/CLAUDE.md`（あれば）も更新して Windows 側に同期
4. 検証: 別プロジェクト（例: Memolette）で `claude-code` 起動 → 「前回 TODO 結合の件どうだった？」と聞いて、grep 結果ベースで答えるか確認

**注意**:
- global CLAUDE.md は既に長い（たぶん 300 行以上）。**全文置換は絶対禁止**、特定マーカー（例: `<!-- session-recall: start -->` / `<!-- session-recall: end -->`）で管理する追記ブロック方式にする。
- 既存 CLAUDE.md のバックアップを `deploy.sh` が自動で取る
- `_claude-sync/` の扱いは Mac: `/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_claude-sync/`、Win: `G:/マイドライブ/_claude-sync/`

### Phase 2 (Lv.1): `/recall <キーワード>` スラッシュコマンド
**目標**: 明示的に横断検索するスラッシュコマンドを用意。

**実装**:
1. `skills/recall/search.sh` 本体（bash）:
   - 引数: キーワード（複数 AND）
   - 対象: `_Apps2026/*/SESSION_HISTORY.md`, `_Apps2026/*/HANDOFF.md`, `_other-projects/*/SESSION_HISTORY.md` ほか
   - 実装: `ripgrep` あれば優先、無ければ `grep -rn`。`--context 5` で前後取得。
   - 出力: `### プロジェクト名 (日付)\n本文抜粋`形式
   - 日本語対応: ripgrep / grep が UTF-8 で正常動作するようロケール指定（`LC_ALL=en_US.UTF-8`）
2. `skills/recall/skill.md` を Claude が解釈できる形式で確定
3. `deploy.sh` を拡張: `skills/recall/` を `~/.claude/skills/recall/` にコピー
4. 検証: `/recall ToDo 結合` 等で複数プロジェクトから該当箇所が抽出されること

**成功基準**:
- 1 秒以内にレスポンス
- 日本語キーワードで正しくマッチ
- 複数プロジェクト横断
- マッチ数が多い時はトップ 10 件程度に絞る

### Phase 3 (Lv.2): MCP サーバー化（Claude が自動で呼ぶ）
**目標**: ユーザーが `/recall` を明示しなくても、Claude が会話文脈から「これは過去検索した方がいい」と判断して自動で呼ぶ。

**実装**:
1. MCP サーバー（Python か TypeScript）:
   - ツール名: `session_recall_search`
   - 引数: `keywords: string[]`, `projects: string[]` (optional)
   - 内部実装: ripgrep 経由（Phase 2 の `search.sh` を流用 or FTS5 DB で高速化）
2. `~/.claude/settings.json` の `mcpServers` に登録
3. Claude が自発的に呼ぶよう、CLAUDE.md の指示文を Phase 1 の単純 grep 指示から MCP 呼び出しに切り替え
4. 検証: 明示的に `/recall` を打たずに「前回 ToDo の結合どうしたっけ」で自動呼び出しされるか

**判断**: Phase 2 の time-to-result が 1 秒以内で十分速ければ Phase 3 は不要になる可能性あり。やるかどうかは Phase 2 完了時に再判断。

### Phase 4 (Lv.3): セマンティック検索（最終形）
**目標**: キーワード一致しない曖昧クエリ（「あのボタン配置で議論した時」「パフォーマンスで悩んだ件」）に対応。

**実装**:
1. **埋め込みモデル選定**
   - 日本語対応が必要 → `multilingual-e5-small` か `cl-nagoya/sup-simcse-ja-base` あたり
   - CPU で動くサイズ（onnxruntime で回す）を優先
2. **ベクトル DB**
   - SQLite + `sqlite-vec` 拡張（軽量、PC ローカル）
   - または ChromaDB（claude-mem と同じだが重い）
3. **インデックス構築**
   - 初回: 全プロジェクトの `SESSION_HISTORY.md` / `HANDOFF.md` を段落単位で分割 → 埋め込み → DB に保存
   - 増分: `/end` スキル発火時に最新追記分だけ埋め込み更新（新規 skill として実装）
4. **検索ツール**
   - MCP ツール `session_recall_semantic` を Phase 3 の grep 版と並列提供
   - Claude がキーワード明確なら grep、曖昧なら semantic を使い分ける

**クロス PC 戦略（重要）**:
- **元データ（SESSION_HISTORY.md 等）は Google Drive 経由で全 PC 同期されている**。これが土台。
- **ベクトル DB はローカル専用**（SQLite + cloud sync = 腐敗の既知問題）
- 各 PC で独立にインデックス構築。`index_build.sh` を投入後、初回だけ重いが以後は差分のみ。
- `~/.claude-recall/index.db` みたいな場所に格納、`.gitignore` しない運用（session-recall リポ外）
- **同期対象**: ツール本体（スクリプト、MCP サーバ）のみ。インデックス DB は PC ごと。

---

## 4. 技術前提メモ

### 4.1 パス・環境
- **Mac**: `/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_Apps2026/`
- **Windows**: `G:/マイドライブ/_Apps2026/`
- **Mac シェル**: zsh、Git Bash 相当は `/bin/bash`
- **Windows シェル**: Git Bash（`bash` コマンドで動く）
- 両環境で `_claude-sync/setup.bat`（Windows） or `_claude-sync/setup.sh`（Mac、要確認）でセットアップが走る

### 4.2 Claude Code の設定ファイル構造
- `~/.claude/CLAUDE.md` — グローバル指示（全プロジェクトで読まれる）
- `~/.claude/settings.json` — プラグイン、MCP サーバ、hook 設定
- `~/.claude/skills/` — ユーザー定義スキル
- `~/.claude/plugins/` — プラグイン本体

### 4.3 既存の `_claude-sync/` との関係
- `_claude-sync/shared-env` に環境変数（`GEMINI_API_KEY` など）
- `_claude-sync/setup.bat` が初回セットアップを実行
- session-recall でもここに `recall_skill/` 配置して、setup が `~/.claude/skills/` に symlink か copy する方式が素直

### 4.4 のっくりさんの既存運用パターン
- **グローバル CLAUDE.md**:
  - 日本語で会話
  - npx 禁止、`npm install -g` → 直接コマンドが原則
  - APIキーは `.env` か `_claude-sync/shared-env`、チャットに貼らせない
  - セッション開始時の自動処理（Chat フォルダはスキップ）
  - セッション終了時の自動処理（`/end` で HANDOFF / SESSION_LOG / SESSION_HISTORY 更新 + commit/push）
- **プロジェクトごとの規約**:
  - 最初に git リポ作る、default ブランチは `main`
  - 各プロジェクトに `HANDOFF.md`, `ROADMAP.md`, `DEVLOG.md`, `SESSION_LOG.md`, `SESSION_HISTORY.md` がある前提
  - この規約が session-recall の検索対象データを保証している

### 4.5 触ってはいけないもの
- **`_Apps2026/` 直下に勝手に新フォルダ作らない**（global CLAUDE.md のルール）。session-recall は今日のこのタイミングでユーザー確認済みなので OK
- 既存 `~/.claude/CLAUDE.md` 全文置換は厳禁、追記ブロック方式で
- `~/.claude-mem/` はまだ残す（session-recall 完成後に撤去）

---

## 5. 作業の進め方（推奨フロー）

### 5.1 セッション開始時
1. `cd .../_Apps2026/session-recall`
2. `git pull` で最新取得
3. このファイル `HANDOFF.md` を読む
4. `ROADMAP.md` で次フェーズ確認
5. `DEVLOG.md` 末尾で直前の開発状況確認

### 5.2 作業中
- 実装は `session-recall/` 内で完結、テストもここで書く
- 実際の適用は `deploy.sh` 実行時のみ
- **検証は Memolette や別プロジェクトを開いて**行う（session-recall 内だと自己言及的に検索されちゃうので切り分け必要）

### 5.3 セッション終了時
- 例のごとく `/end` で HANDOFF / SESSION_HISTORY / SESSION_LOG 更新 + push
- ただし、この `HANDOFF.md` は長文なので、**「現状」部分だけ書き換える**運用にする（経緯・全体計画は残す）

---

## 6. 落とし穴（先回り共有）

1. **グローバル CLAUDE.md の追記マーカー方式を守る** — `deploy.sh` 実装時、既存 CLAUDE.md を雑に上書きするとのっくりさんの長大な指示が消える。マーカー間のみ置換すること。
2. **Windows パスを忘れない** — `deploy.sh` は `uname` で判定して両方のパスに適用
3. **SQLite + Google Drive はダメ** — Phase 4 で再確認、ベクトル DB はローカルのみ
4. **hook 登録は慎重に** — 将来 hook 化する場合、claude-mem で見た「hook 失敗で UI にエラー表示」の轍を踏まないよう `|| true` 付与・冪等性確保
5. **japanese grep** — macOS の BSD grep は日本語回り不安定なことがある。ripgrep (`rg`) が素直。Windows Git Bash にも ripgrep 入ってるか確認すること
6. **symlink vs copy** — `_claude-sync/` を symlink 元にすると Windows 側で symlink が Drive に辿れない罠がある。Windows は copy 運用が安全

---

## 7. 今すぐの次アクション（Windows MCP ツール認識問題の解決）

### 問題: MCP Connected だがツールが deferred tools に出ない

**状況（セッション #10, #10.5 で確認）:**
- `claude mcp list` → **session-recall: ✓ Connected** ✅
- 手動 smoke test（initialize + tools/list）→ 正常応答、2 ツール返却 ✅
- venv・index.db・server.py・run_server.sh → 全て正常 ✅
- **だが `<available-deferred-tools>` に `mcp__session-recall__*` が出ない** ❌

**試したこと（全て効果なし）:**
1. `.mcp.json`（プロジェクトレベル）に登録 → 承認タイミング問題で効かず
2. `claude mcp remove` → `claude mcp add --scope user` で再登録 → Connected になるが同じ
3. Claude Code 再起動 2 回 → 変わらず
4. permissions は `"allow": ["*"]` で問題なし
5. settings.json に deny ルールなし

**まだ試していないこと:**
1. **Claude Code のバージョン更新**（現在 2.1.91）→ MCP ツール読み込みのバグが修正されている可能性
2. **`--scope project` で追加**（`--scope user` でなく）→ プロジェクトスコープの方が読み込み優先度が高い可能性
3. **`.mcp.json` を git tracked にして承認ダイアログを出させる**（untracked だと承認されない？）
4. **Mac で同じ問題が起きるか確認**→ Mac では動いているなら Windows 固有の問題

### 緊急: `.claude.json` が空になった（セッション #10.5 で発生）
- `sed -i` で autoUpdates を書き換えようとして、日本語パス含む JSON が壊れた（0バイト化）
- Claude Code 再起動すれば `.claude.json` は再生成される（統計データは失われるが実害なし）
- **再起動後にやること:**
  1. `claude mcp add session-recall --scope user -- bash "C:/Users/msp/.claude/session-recall-mcp.sh"` で MCP 再登録
  2. settings.json 側の autoUpdates を有効化（`.claude.json` ではなく settings.json の方で設定すべき）
  3. MCP ツールが deferred tools に出るか確認

### Step 1（次セッション）: 上記の復旧 + MCP テスト
- Claude Code は 2.1.91 → **2.1.119** にアップデート済み
- `.claude.json` 再生成 → MCP 再登録 → ツール認識テスト
- それでもダメなら `claude mcp add session-recall --scope project` を試す
- それでもダメなら Mac で確認して Windows 固有問題か切り分け

### セッション #11 でやったこと（2026-04-25, 14:15 頃）
**症状:** 再起動して resume したが、deferred tools に `mcp__session-recall__*` が依然として出ない。
**判明:** `claude mcp list` を叩いたら **session-recall の登録自体が消えていた**（Google 系 MCP 3 つしか出ない）。session #10.5 で `.claude.json` が壊れた → 再起動で再生成されたが、session-recall の登録は復活していなかった。
**実行したコマンド:**
```bash
claude mcp add session-recall --scope user -- bash "C:/Users/msp/.claude/session-recall-mcp.sh"
```
**結果:** `claude mcp list` → **session-recall: ✓ Connected** ✅ に復活。
**ただし:** このセッションの deferred tools には反映されない（セッション開始時に MCP ツール一覧が固定されるため）。次回 /exit → 再起動が必要。

### セッション #12 でやったこと（2026-04-25）
**症状(前半):** resume 後も deferred tools に `mcp__session-recall__*` が出ない（user スコープで Connected なのに）。
**前半の対応:** project スコープに切り替え。
```bash
claude mcp remove session-recall              # user スコープ削除
mv .mcp.json.bak .mcp.json                    # project スコープ用ファイル復活
```
→ 再起動後も deferred tools に出ず（`claude mcp list` は Connected）。

**症状(後半) 真因判明:** `.claude.json` の `projects."G:/マイドライブ/_Apps2026/session-recall".enabledMcpjsonServers` が `[]`（空配列）になっていた。これにより Claude Code は `.mcp.json` の session-recall を「未承認」扱いしてツールをロードしていなかった。`claude mcp list` の Connected 表示は MCP プロトコルの health check が通っているだけで、セッションへのツール露出とは別判定。
**後半の対応:** Python で `.claude.json` を安全に書き換え（前回 sed で 0 バイト化した教訓）。
```python
proj['enabledMcpjsonServers'] = ['session-recall']
```
→ JSON 整合性 OK、ファイルサイズ 28KB 維持。

**次回 /exit → 再起動が必要。**

### セッション #12 後半 真の真因: Claude Code v2.1.116〜 の regression
**症状:** `enabledMcpjsonServers: ["session-recall"]` + `hasTrustDialogAccepted: true` を設定して再起動しても、deferred tools に `mcp__session-recall__*` が出ない。手動 smoke test では server side は完璧（initialize / tools/list で 2 ツール正常返却）。
**判明:** Claude Code v2.1.116 以降の regression（GitHub Issue #51736）。custom stdio MCP server のツールが deferred tools 登録メカニズムから消失する既知バグ。built-in HTTP connector（Google 系 Gmail/Drive/Calendar）は動く症状と完全一致。
**関連 issue:** #29443（Windows Server 2022 で同症状）, #51736（v2.1.116 以降の regression）

### 試した回避策とその結果（記録）
1. **`ENABLE_TOOL_SEARCH=false` を settings.json `env` に追加**: deferred mechanism は確かに無効化された（ToolSearch も "no matching" を返す）。**しかし MCP ツールは upfront にも出ない** → regression は deferred メカニズムだけでなくツール露出パス全体に及ぶことが判明。回避策不成立。
2. **Claude Code アップデート**: 既に最新（v2.1.119）。npm に新しいバージョン無し。

### 採用した着地点: bash CLI フォールバック (Phase 7)
MCP regression 修正待ちの間も検索能力をロスしないよう、`semantic.sh` を新設。`search.sh`（キーワード）に並ぶ第二の bash ルート。

**追加したファイル（`_claude-sync/session-recall/`、Drive 同期で全 PC 配布）:**
- `semantic.py` — セマンティック検索の CLI 単体実装（multilingual-e5-small + sqlite-vec、server.py ロジックを移植）
- `semantic.sh` — Mac/Win 両対応 bash ラッパー（venv の python を自動探索）

**動作確認:** `bash semantic.sh "claude-mem を撤去した経緯" --limit 3` → Memolette-Flutter / session-recall 等から関連段落を距離 0.4 前後で正常返却（17 秒）。

**速度トレードオフ:**
- MCP 経由（理想）: server.py が常駐してモデルがメモリ上にあるため 100〜300ms
- bash CLI 経由（保険）: 呼ぶたびに python 起動 + embedding モデル毎回ロード → 初回 5〜17 秒
- 機能ロスは無し、速度のみ劣化。曖昧クエリは滅多に呼ばないので実用上ストレスは低い

**CLAUDE.md フォールバック節更新:** `_claude-sync/CLAUDE.md` の「フォールバック手段（MCP tool が使えないとき）」に semantic.sh の手順と「MCP があれば MCP 優先、なければ bash」の自動判断ルールを追記。Claude が起動時にツール一覧を見て自動分岐する。

### Step 2（次セッション開始時に最初にやること）
1. **deferred tools に `mcp__session-recall__*` が出ているか確認**
2. **出ていれば**: regression 修正済み → MCP 経由でフル稼働、Windows 1 台目 完了 → 2 台目に進む
3. **出ていなければ**: 引き続き regression 中。**bash semantic.sh / search.sh フォールバックで実用フル稼働中なので慌てる必要なし**。Claude Code リリースノートを定期確認、修正バージョンが出たら ENABLE_TOOL_SEARCH=false 設定を外して再テスト

### 今後の段取り（のっくりさんが宣言した順序、2026-04-25 確定）
1. **残 Windows 2 台目に session-recall を deploy**（`bash deploy.sh` 一発で venv + index 構築まで完走するはず。1 台目 #9 でパスバグ修正済みなので素直に通る想定）
2. **残 Windows 3 台目に session-recall を deploy**（同上）
3. **両 Win で MCP regression 状況確認 + bash フォールバック動作確認**（`bash semantic.sh "テストクエリ"` が動けば OK）
4. **Mac に戻って最終テスト**:
   - Mac でも MCP regression を踏んでないか確認（v2.1.116〜2.1.119 を Mac で起動した経験が直近にあったか不明、未確認）
   - 全 PC（Mac + Win × 3）で同じクエリを叩いて検索結果の等価性を確認（HANDOFF #8 の「PC 間等価性実証」を Win 含めて再演）
   - 等価 OK なら Phase 7 完全完了、session-recall プロジェクトとしては実用フェーズに移行

### Mac での起動時に必ず確認すること（重要）
HANDOFF #8 で確認した「Mac MCP 動作」は 4/24 時点。その後 Claude Code が 2.1.116〜2.1.119 に上がってる。次に Mac セッション開始したら **Mac でも regression を踏んでないか必ず確認**:
- `mcp__session-recall__*` が deferred tools に出ているか
- 出ていれば Mac は無事、出ていなければ Mac も bash フォールバック運用に切り替え（semantic.sh は既に Drive 同期で配布済み、即動く）

### 教訓（次以降の PC 展開時に活かす）
- Claude Code 2.x で project レベル `.mcp.json` を使う場合、**`.claude.json` の該当プロジェクトエントリで `enabledMcpjsonServers: ["<server名>"]` を明示的に設定する必要がある**。
- `claude mcp list` の Connected ≠ セッションでツールが使える、という落とし穴あり。
- `.claude.json` を直接編集する際は **必ず Python json モジュール経由** で（sed/awk は日本語パスを含む JSON で破損リスク）。
- Claude Code v2.1.116〜 の custom MCP regression は `ENABLE_TOOL_SEARCH=false` でも回避できなかった。bash CLI フォールバック (`search.sh` + `semantic.sh`) を持っておくのが最強の保険。

### Step 2: 残り Windows 2台での deploy テスト
- MCP 問題が解決してから

### Step 3: 残課題
1. **Phase 7 アイデア（必要に応じて）**: 時系列フィルタ、ハイブリッド検索、セッション番号指定参照

### 補足
- `bash _claude-sync/session-recall/search.sh [--project <名前>] "キーワード"` 直叩きは常に動く（MCP 不要のフォールバック）
- **PC 間等価性実証**（#8）: Mac A ↔ Mac B で同じ検索結果確認済み
- **Windows 1台目**（#9）: deploy 完走 + パスバグ修正 + index 構築成功（4310 chunks, 13.5 MB）

## 8. Phase 1〜3 で得た教訓（Phase 4 で活かす）

1. **マーカーは行頭限定**: `^<!-- session-recall:` で grep / awk しないと、説明文中の例示も拾って肥大化バグになる
2. **冪等性は cmp で検証**: 「変更なし」の判定を `cmp -s` でやれば、同じ内容なら出力しない・バックアップも作らない、が成立
3. **Drive 同期されるもの・されないものを明確に分ける**:
   - 同期: ロジック本体（search.sh、server.py、run_server.sh、recall.md）
   - 非同期: Python venv（プラットフォーム依存）、`settings.local.json`（絶対パスが PC ごと）
4. **subprocess 呼び出しは安全策として有効**: server.py が Python ロジックを再実装する代わりに `bash search.sh` を叩く方式で、二重メンテを避けつつテストの一意性を保てる
5. **MCP プロトコルの smoke test は手動で十分**: `{ echo INIT; sleep; echo NOTIF; sleep; echo CALL; sleep; } | run_server.sh` で initialize / tools/list / tools/call をシェル一行で検証可能

---

## 8. 参照リンク

- session-recall GitHub: https://github.com/nock-in-mook/session-recall
- claude-mem GitHub（反面教師）: https://github.com/thedotmack/claude-mem
- Memolette-Flutter（今日の本業）: https://github.com/nock-in-mook/Memolette-Flutter
- 今日の本業最新コミット: `cecb85a 結合マーク位置とチェックボックス配置の調整 + フィルタボタンを中央固定`
