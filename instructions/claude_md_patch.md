# CLAUDE.md 追加指示（確定版 v2）

このファイルの「マーカー間ブロック」を `deploy.sh` が `~/.claude/CLAUDE.md` と `_claude-sync/CLAUDE.md` に注入する。

- ブロックの開始/終了マーカーは前方一致（`<!-- session-recall:begin` で始まる行）で検出される
- 再 deploy 時はマーカー間が最新ブロックで置換される（v1 → v2 のバージョンアップも自動）
- マーカー外の文章（このコメント部分や「メンテナンスメモ」）は注入対象外

---

<!-- session-recall:begin v2 -->
## 過去セッションの想起（session-recall）

過去の作業・決定・議論を思い出すための横断検索。データソースは各プロジェクト直下の `SESSION_HISTORY.md` / `HANDOFF.md` / `DEVLOG.md`（`ROADMAP.md` は未確定アイデアが多くノイズになるため対象外）。

### 自動で検索すべきタイミング

ユーザーの発言が以下のいずれかに該当したら、**回答する前に検索する**：

- 「前回」「以前」「過去に」「〜したっけ」「〜の件」「〜どうなった？」等、過去参照を匂わせる語
- 現プロジェクトの話題が、別プロジェクトでも遭遇した記憶があるテーマ（例: claude-mem、Tcl 競合、Drive 同期問題、Flutter ビルド失敗、特定エラーメッセージ等）
- ユーザーが思い出せず詰まっている気配（「あれなんだっけ」「どっかで見た」等）
- 別プロジェクト名（Memolette / Memolette-Flutter / HardReminder / Reminder_Flutter / Personal_Secretary / P3_reminder / P3 Craft / KANJI_HANTEI 等）が会話に出た

### 検索手順（二段階）

1. **現プロジェクトを先に grep**（cwd 直下の `SESSION_HISTORY.md` / `HANDOFF.md` / `DEVLOG.md`）
   ```bash
   LC_ALL=en_US.UTF-8 grep -n "キーワード" SESSION_HISTORY.md HANDOFF.md DEVLOG.md 2>/dev/null
   ```
2. 現プロジェクトでヒットしない、または別プロジェクト言及あり、または横断したい意図 → **search.sh で全プロジェクト検索**
   ```bash
   SEARCH_SH=""
   for p in \
       "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_claude-sync/session-recall/search.sh" \
       "/g/マイドライブ/_claude-sync/session-recall/search.sh" \
       "/G/マイドライブ/_claude-sync/session-recall/search.sh" ; do
       [ -x "$p" ] && SEARCH_SH="$p" && break
   done
   bash "$SEARCH_SH" "キーワード1" "キーワード2"
   ```
   - 引数は AND 検索（同じファイルに全キーワードが存在）
   - 複数キーワード指定で精度が上がる
   - 出力フォーマット: `### project/file:行番号` ヘッダ + 前後 ±5 行の本文ブロック
   - 上位 10 ファイルまで表示、超過分は末尾に件数のみ

### 結果の扱い方

- grep / search.sh の生出力を貼って終わりにしない。読んで「○○プロジェクトでは△△と決着」のように**要約してから**提示する
- 出典は `プロジェクト名/ファイル名:行番号` 形式で必ず明示
- マッチ多数なら関連性の高い 3〜5 件に絞る
- 該当が見つからなかったときは「検索したが該当なし」と明示する（黙って推測で答えない）

### ユーザーが `/recall <キーワード>` を明示的に呼んだ場合

スキル定義（`_claude-sync/commands/recall.md`）に従って同じ search.sh を実行する。出力の扱い（要約、出典明示）も同じ。

### アンチパターン

- 検索せず「以前は X だった気がします」と推測で答える
- 横断検索を最初からやって関連プロジェクト以外のノイズを混ぜる（必ず現プロジェクト先）
- 全マッチを列挙する
- 検索結果を貼るだけで要約しない
- 過去参照を匂わせる発言を見逃して通常応答する

<!-- session-recall:end v2 -->

---

## メンテナンスメモ（注入対象外）

- このブロックは `session-recall/deploy.sh` で `~/.claude/CLAUDE.md` と `_claude-sync/CLAUDE.md` の両方に展開される
- バージョン更新時は `v2` を `v3` に上げ、本文を更新するだけで OK（deploy.sh は前方一致でマーカー検出するためバージョン番号は何でも置換可）
- マーカー文字列（`<!-- session-recall:begin` / `<!-- session-recall:end`）を変更する場合は `deploy.sh` の awk ロジックも追従させる
- Phase 3 完了時に MCP tool 呼び出しに置き換える予定（Claude が tool 経由で自動呼び出し）
- Phase 4 完了時にセマンティック検索（`session_recall_semantic` tool）も並列提供する予定
