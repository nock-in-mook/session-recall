# ROADMAP

## Phase 0: プロジェクト立ち上げ ✅
- [x] `session-recall/` フォルダ作成
- [x] 初期ドキュメント（README / HANDOFF / ROADMAP / DEVLOG / SESSION_HISTORY）
- [x] スキル・インストラクション・deploy スクリプトのスケルトン
- [ ] git init + 初期コミット
- [ ] GitHub リポジトリ作成 + push

## Phase 1 (Lv.0): CLAUDE.md 指示追加
過去セッション参照が必要なとき、Claude が自発的に grep するように指示を追加する。

- [ ] `instructions/claude_md_patch.md` に指示文確定（ドラフト作成済み）
- [ ] `~/.claude/CLAUDE.md` に追記（deploy.sh 経由）
- [ ] `_claude-sync/CLAUDE.md` にも同期（Windows 側反映用）
- [ ] 別プロジェクトで「前回 Flutter で何してた？」等のクエリで動作確認
- [ ] 参照対象ファイル範囲の確定（SESSION_HISTORY のみか、HANDOFF/DEVLOG/ROADMAP も含むか）

### Phase 1 の成功基準
- 「前回 Memolette で何の作業してた？」と聞いた時に Claude が自動で SESSION_HISTORY.md を grep して答える
- ユーザーが「recall」とか明示的コマンドを打たなくても自然言語で動く

## Phase 2 (Lv.1): /recall スラッシュコマンド
複数プロジェクト横断の想起を、明示的コマンドで呼べるようにする。

- [ ] `skills/recall/search.sh` 実装
  - 引数: キーワード（複数AND検索対応）
  - 検索範囲: `_Apps2026/*/SESSION_HISTORY.md`, `_other-projects/*/SESSION_HISTORY.md` ほか
  - 結果: マッチ行前後 ±5 行を context 注入用に整形
- [ ] `skills/recall/skill.md` 定義
- [ ] deploy.sh で `~/.claude/skills/` に配置
- [ ] 動作検証（横串クエリ、日本語対応、ファイル数多い時のパフォーマンス）

### Phase 2 の成功基準
- `/recall ToDo 結合` 等で過去の全プロジェクトから該当会話を引き出せる
- 1 秒以内に返ってくる

## Phase 3 (Lv.2): MCP サーバー化（任意）
Lv.1 がパワー不足だった場合のみ進める。

- [ ] MCP サーバー実装（TypeScript or Python）
- [ ] ripgrep or FTS5 で高速化
- [ ] Claude が tool として自動呼び出し可能に
- [ ] `settings.json` に登録

### 進めるかどうかの判断基準
- Phase 2 で「キーワード完全一致では拾えない」ケースが頻発するか
- 検索速度が実用レベルか

## Phase 4 (Lv.3): セマンティック検索（遠い先）
曖昧な想起（「あのバグ直した時の話」）に対応したくなったら。

- [ ] 埋め込みモデル選定（sentence-transformers / multilingual-e5 等）
- [ ] SQLite + ベクトル拡張 or ChromaDB
- [ ] インクリメンタル更新機構
- [ ] PC ごとに DB 別管理（Google Drive 経由で SQLite 同期は壊れるため）

## アイデアメモ
- `/recall-proj <プロジェクト名> <キーワード>` で特定プロジェクトに限定検索
- `/timeline <期間>` で時系列ダイジェスト
- Roadmap の未完了タスク横断リスト（`/todo` で全プロジェクトの TODO をサマリー）
- Session 番号指定での詳細参照（`/session 26` → セッション#26 の要約と主要やり取り）

## 備忘（次回相談）
- 検索対象を SESSION_HISTORY.md のみにするか、DEVLOG/HANDOFF まで広げるか → 使ってみて判断
- deploy.sh を Mac/Win 両対応にするか、別々に書くか
- プロジェクト認識の正規表現（`_Apps2026/*`, `_other-projects/*`）を固定するか configurable にするか
