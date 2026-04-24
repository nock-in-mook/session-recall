# CLAUDE.md 追加指示（確定版 v1）

このファイルの「マーカー間ブロック」を `deploy.sh` が `~/.claude/CLAUDE.md` と `_claude-sync/CLAUDE.md` に注入する。

- ブロックの開始/終了マーカーは固定文字列。再 deploy 時はマーカー間を置換する。
- マーカー外の文章（このコメント部分や「メンテナンスメモ」）は注入対象外。

---

<!-- session-recall:begin v1 -->
## 過去セッションの想起（session-recall）

過去の作業・決定・議論を思い出すための横断検索ルール。データソースは各プロジェクト直下の `SESSION_HISTORY.md` / `HANDOFF.md` / `DEVLOG.md`（`ROADMAP.md` は対象外＝未確定アイデアが多くノイズになるため）。

### 自動で検索すべきタイミング

ユーザーの発言が以下のいずれかに該当したら、**回答する前に grep で根拠を取る**。

- 「前回」「以前」「過去に」「〜したっけ」「〜の件」「〜どうなった？」等、過去参照を匂わせる語
- 現プロジェクトの話題が、別プロジェクトでも遭遇した記憶のあるテーマ（例: claude-mem、Tcl 競合、Drive 同期問題、Flutter ビルド失敗、特定エラーメッセージ等）
- ユーザーが思い出せず詰まっている気配（「あれなんだっけ」「どっかで見た」等）
- 別プロジェクト名（Memolette / Memolette-Flutter / HardReminder / Reminder_Flutter / Personal_Secretary / P3_reminder / P3 Craft / KANJI_HANTEI 等）が会話に出た

### 検索手順（二段階）

1. **現プロジェクトを先に検索**（cwd 直下の `SESSION_HISTORY.md` / `HANDOFF.md` / `DEVLOG.md`）
2. 現プロジェクトでヒットしない、または別プロジェクト言及あり、または横断したい意図が明らかな場合 → **全プロジェクト横断検索**
3. マッチ箇所の前後 ±5 行を読んで文脈を把握
4. 「○○プロジェクトの○月○日（あるいはセッション#○○）の記述に該当あり」と**出典を明示**してから内容を答える

### 検索コマンド

`ripgrep`（`rg`）が入っていれば優先、なければ `grep -rn`。日本語ロケール明示。

```bash
# 検索対象パス（存在する方を採用、Mac と Windows 両対応）
ROOTS=()
for r in \
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_Apps2026" \
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_other-projects" \
    "G:/マイドライブ/_Apps2026" \
    "G:/マイドライブ/_other-projects" ; do
    [ -d "$r" ] && ROOTS+=("$r")
done

# 現プロジェクト（cwd）
LC_ALL=en_US.UTF-8 grep -n "キーワード" SESSION_HISTORY.md HANDOFF.md DEVLOG.md 2>/dev/null

# 横断（ripgrep が使える場合）
for r in "${ROOTS[@]}"; do
    rg -n --no-heading \
        -g 'SESSION_HISTORY.md' -g 'HANDOFF.md' -g 'DEVLOG.md' \
        "キーワード" "$r" 2>/dev/null
done | head -30

# 横断（ripgrep が無い場合）
for r in "${ROOTS[@]}"; do
    LC_ALL=en_US.UTF-8 grep -rn \
        --include='SESSION_HISTORY.md' --include='HANDOFF.md' --include='DEVLOG.md' \
        "キーワード" "$r" 2>/dev/null
done | head -30
```

### 結果の扱い方

- マッチ多数なら関連性の高い 3〜5 件に絞る
- grep 結果を貼って終わりにしない。ヒット箇所を読んで「○○プロジェクトでは△△と決着」のように**要約してから**提示する
- 出典は `プロジェクト名/ファイル名:行番号` 形式
- 該当が見つからなかったときは「検索したが該当なし」と明示する（黙って推測で答えない）

### アンチパターン

- 検索せず「以前は X だった気がします」と推測で答える
- 横断検索を最初からやって関連プロジェクト以外のノイズを混ぜる
- 全マッチを列挙する
- 検索結果を貼るだけで要約しない
- 過去参照を匂わせる発言を見逃して通常応答する

<!-- session-recall:end v1 -->

---

## メンテナンスメモ（注入対象外）

- このブロックは `session-recall/deploy.sh` で `~/.claude/CLAUDE.md` と `_claude-sync/CLAUDE.md` の両方に展開される
- バージョン更新時は `v1` を `v2` に上げ、`deploy.sh` も両バージョンを認識して置換できるようにする
- マーカー文字列を変更する場合は `deploy.sh` 側も追従させる
- Phase 2 完了時にこの指示を `/recall` スラッシュコマンドへの誘導に書き換える予定（grep を Claude が直接打つ → スキル経由に切り替え）
- Phase 3 完了時に MCP tool 呼び出しに置き換える
