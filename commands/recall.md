プロジェクト横断で過去の `SESSION_HISTORY.md` / `HANDOFF.md` / `DEVLOG.md` を検索する。

引数（複数キーワード、空白区切り）を AND 検索し、マッチしたファイルから関連箇所（前後 ±5 行）を抽出して提示する。
`--project <名前>` オプションを付けると特定プロジェクト（`_Apps2026/` or `_other-projects/` 直下のフォルダ名）のみに絞り込める。

## 実行手順

ユーザーが入力した引数を、以下のスクリプトに**そのまま**渡して実行する。`--project` を含む全オプションは search.sh 側がパースするので、特別な前処理は不要：

```bash
SEARCH_SH=""
for p in \
    "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_claude-sync/session-recall/search.sh" \
    "/g/マイドライブ/_claude-sync/session-recall/search.sh" \
    "/G/マイドライブ/_claude-sync/session-recall/search.sh" ; do
    [ -x "$p" ] && SEARCH_SH="$p" && break
done
[ -z "$SEARCH_SH" ] && { echo "search.sh が見つかりません（deploy 未実行？）"; exit 1; }
bash "$SEARCH_SH" <ユーザーが指定した引数...>
```

`<ユーザーが指定した引数...>` の部分にユーザーの引数をそのまま渡す。スペースを含む語は個別に引用する。

使用例:
- `/recall ToDo 結合` — 全プロジェクトから AND 検索
- `/recall --project Memolette-Flutter ToDo 結合` — Memolette-Flutter のみから AND 検索
- `/recall --project session-recall フック 競合` — session-recall のみから AND 検索

## 結果の整形

スクリプトの生出力をそのまま貼り付けるのは NG。文脈を読んで以下のように整形する：

1. **マッチが 0 件**: 「『○○』に該当する記述は見つかりませんでした」と短く伝える
2. **マッチが少数（1〜3 件）**: 各ヒットの本文を読んで、`{プロジェクト名/ファイル名}:{行番号} → {要約 1〜2 行}` 形式で並べる
3. **マッチが多数**: 関連性が高いトップ 3〜5 件を要約 + 出典付きで提示し、残りは「他に N 件あり」と件数のみ示す

要約は「○月の Memolette-Flutter で△△を実装中、◯◯について議論」のように文脈を補ってまとめる。

## 引数なしの場合

`/recall` だけで呼ばれた場合、search.sh が使い方を表示するのでそれをそのまま伝える。

## 補足

- 検索対象は各プロジェクト直下の 3 ファイル（SESSION_HISTORY / HANDOFF / DEVLOG）
- ROADMAP は未確定アイデアが多くノイズになるため対象外
- 結果は更新日時降順（新しいセッションを優先表示）
- このスキルは bash 直接実行版。Phase 3 で MCP サーバー化される予定
