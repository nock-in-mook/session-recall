# CLAUDE.md 追加指示（ドラフト）

Phase 1 (Lv.0) で global `CLAUDE.md` に追記する指示文。正式確定前のドラフト。

---

## 過去セッションの想起

ユーザーが以下のような発言をした場合、まず対象プロジェクトの `SESSION_HISTORY.md` / `HANDOFF.md` を grep で検索してから回答する：

- 「前回何してた？」「前に〇〇の話したよね？」「以前やった〇〇の件」
- 「〇〇のバグどう直したっけ？」「〇〇の決定どうなった？」
- 「似た問題に取り組んだことあった気がする」

### 検索ルール

1. **まず現在のプロジェクトルート**（cwd 近辺）の `SESSION_HISTORY.md`, `HANDOFF.md`, `DEVLOG.md`, `ROADMAP.md` を対象に grep
2. 現プロジェクトで見つからない or ユーザーが「他のプロジェクトかも」と言ったら、`_Apps2026/*/SESSION_HISTORY.md` と `_other-projects/*/SESSION_HISTORY.md` を横断検索
3. マッチ箇所の前後 5 行程度を読んで文脈を把握してから回答
4. 検索したら「〇〇プロジェクトの〇月〇日に該当する記述を見つけました」と明示してから内容を示す

### 検索の実装

```bash
# 現プロジェクトで
grep -n "キーワード" SESSION_HISTORY.md HANDOFF.md 2>/dev/null

# 横断検索
grep -rn "キーワード" \
  "G:/マイドライブ/_Apps2026"/*/SESSION_HISTORY.md \
  "/Users/nock_re/Library/CloudStorage/GoogleDrive-yagukyou@gmail.com/マイドライブ/_Apps2026"/*/SESSION_HISTORY.md \
  2>/dev/null | head -20
```

どちらのパスも使えるように、環境変数や存在チェックで両対応すること。

### アンチパターン

- 過去参照なしに「それは以前〇〇だったかもしれません」と推測で答える（→ 検索して確証を持つ）
- grep 結果を提示しただけで終わる（→ 文脈読み取って要約する）
- 全マッチを列挙する（→ 関連性の高いトップ 3〜5 件に絞る）

---

## 確定前の検討事項

- 「過去セッションの想起」という項目名でよいか
- 対象ファイル: SESSION_HISTORY.md だけで十分か、HANDOFF.md や DEVLOG.md も入れるか
- パスの書き方: 環境変数化するか、両パス並記するか
- 「ユーザーが明示的に聞かない場合でも、関連しそうな話題では自発的に参照する」まで踏み込むかは要議論
