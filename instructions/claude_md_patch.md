# CLAUDE.md 追加指示（確定版 v6）

このファイルの「マーカー間ブロック」を `deploy.sh` が `~/.claude/CLAUDE.md` と `_claude-sync/CLAUDE.md` に注入する。

- ブロックの開始/終了マーカーは**行頭一致**（`^<!-- session-recall:begin` / `^<!-- session-recall:end`）で検出される
- 再 deploy 時はマーカー間が最新ブロックで置換される（v1 → v2 → v3 → v4 → v5 のバージョンアップも自動）
- マーカー外の文章（このコメント部分や「メンテナンスメモ」）は注入対象外
- 説明文中で `<!-- session-recall:begin` のような例示を書く場合は、**行頭に置かない**（バックティック内、インデント内など）

---

<!-- session-recall:begin v6 -->
## 過去セッションの想起（session-recall）

過去の作業・決定・議論を思い出すための横断検索。データソースは各プロジェクト直下の `SESSION_HISTORY.md` / `HANDOFF.md` / `DEVLOG.md`（`ROADMAP.md` は未確定アイデアが多くノイズになるため対象外）。

### 自動で検索すべきタイミング

ユーザーの発言が以下のいずれかに該当したら、**回答する前に検索する**：

- 「前回」「以前」「過去に」「〜したっけ」「〜の件」「〜どうなった？」等、過去参照を匂わせる語
- 現プロジェクトの話題が、別プロジェクトでも遭遇した記憶があるテーマ（例: claude-mem、Tcl 競合、Drive 同期問題、Flutter ビルド失敗、特定エラーメッセージ等）
- ユーザーが思い出せず詰まっている気配（「あれなんだっけ」「どっかで見た」等）
- 別プロジェクト名（Memolette / Memolette-Flutter / HardReminder / Reminder_Flutter / Personal_Secretary / P3_reminder / P3 Craft / KANJI_HANTEI 等）が会話に出た

### 検索ツールの使い分け

**キーワードが明確** → MCP tool **`session_recall_search`**（高速、AND 検索）
- 引数: `keywords: string[]`、`project?: string`
- 例: `{keywords: ["claude-mem", "撤去"]}`、`{keywords: ["TODO", "結合"], project: "Memolette-Flutter"}`
- 結果は project/file:行番号 + 前後 ±5 行のブロック（更新日時降順、上位 10 件）

**曖昧な概念検索** → MCP tool **`session_recall_semantic`**（意味的近さ、ベクトル検索）
- 引数: `query: string`（1 文の自然言語推奨）、`project?: string`、`limit?: int`
- 例: `{query: "あのボタン配置で議論した時"}`、`{query: "パフォーマンスで悩んだ件", project: "Kanji_Stroke"}`
- 結果は file:行範囲 + 距離スコア + 該当段落（距離小さいほど近い）

**プロジェクト絞り込み（`project` 引数）の使いどころ**
- ユーザーの発言で特定プロジェクト名が明示されている（「Memolette の ToDo 結合どうなった？」「session-recall の競合バグ」等）→ 迷わず `project` 指定
- 現プロジェクト内を探したい場合も `project` を現プロジェクト名にすれば横断ノイズを避けられる
- プロジェクトが不明・複数プロジェクトに跨る話題なら `project` は省略（横断検索）
- プロジェクト名は `_Apps2026/` または `_other-projects/` **直下のフォルダ名**（`Memolette-Flutter`, `session-recall`, `Kanji_Stroke` など）

**両方使う**のもアリ。明確キーワードと曖昧クエリの両面から探す価値がある時は両方呼ぶ。

### フォールバック手段（MCP tool が使えないとき）

```bash
# bash 経由 search.sh（キーワード AND、Phase 2 由来）
SEARCH_SH=""
for p in \
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_claude-sync/session-recall/search.sh" \
    "/g/マイドライブ/_claude-sync/session-recall/search.sh" \
    "/G/マイドライブ/_claude-sync/session-recall/search.sh" ; do
    [ -x "$p" ] && SEARCH_SH="$p" && break
done
bash "$SEARCH_SH" "キーワード1" "キーワード2"
# プロジェクト絞り込み:
bash "$SEARCH_SH" --project Memolette-Flutter "キーワード1" "キーワード2"

# 現プロジェクトの 3 ファイルだけ grep（最速、横断は不要なケース）
LC_ALL=en_US.UTF-8 grep -n "キーワード" SESSION_HISTORY.md HANDOFF.md DEVLOG.md 2>/dev/null
```

### 検索手順（二段階）

1. **現プロジェクトを先に grep**（cwd 直下の `SESSION_HISTORY.md` / `HANDOFF.md` / `DEVLOG.md`）
2. 現プロジェクトでヒットしない、または別プロジェクト言及あり、または横断したい意図 → **MCP tool で全プロジェクト検索**（特定プロジェクト名が会話にあれば `project` 引数で絞る）

### 結果の扱い方

- ツール出力をそのまま貼って終わりにしない。読んで「○○プロジェクトでは△△と決着」のように**要約してから**提示する
- 出典は `プロジェクト名/ファイル名:行番号` 形式で必ず明示
- マッチ多数なら関連性の高い 3〜5 件に絞る
- 該当が見つからなかったときは「検索したが該当なし」と明示する（黙って推測で答えない）

### ユーザーが `/recall <キーワード>` を明示的に呼んだ場合

スキル定義（`_claude-sync/commands/recall.md`）に従って同じ search.sh を実行する。`--project <名前>` オプション付きでユーザーが指定してきた場合もそのまま渡せば動く。出力の扱い（要約、出典明示）も同じ。

### アンチパターン

- 検索せず「以前は X だった気がします」と推測で答える
- 横断検索を最初からやって関連プロジェクト以外のノイズを混ぜる（必ず現プロジェクト先）
- 全マッチを列挙する
- 検索結果を貼るだけで要約しない
- 過去参照を匂わせる発言を見逃して通常応答する
- 明確なキーワードがあるのに `session_recall_semantic` を使う（遅いし精度低い、`session_recall_search` の方が良い）
- 曖昧クエリで `session_recall_search` を使う（キーワード一致しなくて 0 件になりがち）
- ユーザーが特定プロジェクト名を言っているのに `project` 引数を省いて全横断して他プロジェクトのノイズを混ぜる

### セッション開始時の DB 自動追いつき（必ず実行）

session-recall の DB は PC ローカル保存。他 PC で `/end` 時に書かれた最新 `SESSION_HISTORY.md` / `HANDOFF.md` / `DEVLOG.md` 追記分は、Drive 同期で来てもこの PC の DB にはまだ入っていない。放置すると「別 PC で話した内容が検索に出てこない」盲点が 1 セッション分残る。

**セッション開始時、グローバル CLAUDE.md の Step 0（文脈引き継ぎ + git pull）と並列で**、以下を**必ずバックグラウンド実行**する：

- `update_index.sh 0` をバックグラウンド起動（第 1 引数の `0` は sleep 秒数 = 待ちなし／/end 用途の 30 秒とは別）
- ユーザー応答を遅らせない（非ブロッキング、nohup 経由）
- 失敗しても無視（venv/DB 未構築・初回 deploy 前などは内部でサイレントスキップ）
- 増分更新なので変更ファイルがなければ即終了（mtime 比較）

```bash
for p in \
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_claude-sync/session-recall/update_index.sh" \
    "/g/マイドライブ/_claude-sync/session-recall/update_index.sh" \
    "/G/マイドライブ/_claude-sync/session-recall/update_index.sh" ; do
    if [ -x "$p" ]; then
        nohup bash "$p" 0 >/dev/null 2>&1 &
        break
    fi
done
```

これで「Step 0 書き出し直後の開始時追いつき」と「Step 2.9 書き出し直後の終了時追いつき」の両端で DB を最新化する。PC 間の検索盲点は残らない。

<!-- session-recall:end v6 -->

---

## メンテナンスメモ（注入対象外）

- このブロックは `session-recall/deploy.sh` で `~/.claude/CLAUDE.md` と `_claude-sync/CLAUDE.md` の両方に展開される
- バージョン更新時は `v5` を `v6` に上げ、本文を更新するだけで OK（deploy.sh は前方一致でマーカー検出するためバージョン番号は何でも置換可）
- マーカー文字列（`<!-- session-recall:begin` / `<!-- session-recall:end`）を変更する場合は `deploy.sh` の awk ロジックも追従させる
- マーカーは行頭限定（`^` 必須）。説明文中での例示は行頭に置かないこと
- Phase 6 以降で必要そうな改良: ハイブリッド検索（keyword AND → semantic re-rank）、時系列フィルタ
