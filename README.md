# session-recall

のっくり専用のセッション想起ツール。claude-mem 的な「永続メモリ」を、**既存の手書き資産（`SESSION_HISTORY.md` / `HANDOFF.md` / `ROADMAP.md` / `DEVLOG.md`）を活用する形**で実現する自作キット。

## 背景

claude-mem (OSS) を試したところ：
- 動作は重く、1往復あたり週 quota 3% 程度消費
- 要約ノイズが多く、情報密度が低い（「Initial greeting received」みたいな無意味要約）
- 上流に既知 critical バグが多数（v12.3.9 時点）

一方、のっくり環境では既に：
- 全プロジェクトで `SESSION_HISTORY.md` / `HANDOFF.md` / `ROADMAP.md` を手動維持（高品質・高S/N）
- `/end` スキルで自動書き出し
- グローバル `CLAUDE.md` + `~/.claude/projects/.../memory/` で auto-memory 運用

データ層は既に揃っているので、**Claude に「横断検索させる」仕組み**だけ用意すれば、claude-mem 的挙動を高い SN 比で実現できる。

## 設計方針

- **既存資産を汚さない** — 新しいデータベースを作らない、SESSION_HISTORY/HANDOFF をそのまま活用
- **全プロジェクト自動適用** — `~/.claude/` と `_claude-sync/` にデプロイして、全プロジェクトで機能
- **段階的実装** — Lv.0 から順に、ノイズ少なくパワー増やす

## アーキテクチャ（予定）

| Lv | 機能 | 実装先 |
|---|---|---|
| Lv.0 | グローバル CLAUDE.md に「過去セッション検索は grep で」指示追加 | `~/.claude/CLAUDE.md` |
| Lv.1 | `/recall <キーワード>` スラッシュコマンド | `~/.claude/skills/recall/` |
| Lv.2 | MCP サーバーで ripgrep/FTS5 経由の高速検索 | `~/.claude/settings.json` |
| Lv.3 | セマンティック検索（埋め込みベース） | 同上、DB は PC ごと |

## 配置ルール

- `session-recall/` は開発リポジトリ。**ここは自動デプロイされない**
- `deploy.sh` を実行すると `~/.claude/` と `_claude-sync/` にコピー
- `_claude-sync/` 経由で Mac ↔ Windows 同期される

## ファイル構成

```
session-recall/
├── README.md                       このファイル
├── HANDOFF.md                      現状と次のアクション
├── ROADMAP.md                      フェーズ計画
├── DEVLOG.md                       開発ログ
├── SESSION_HISTORY.md              セッション履歴
├── SESSION_LOG.md                  /end 時の書き出し先
├── commands/
│   └── recall.md                   /recall スキル定義（Claude が解釈する）
├── scripts/
│   └── search.sh                   実処理（複数キーワード AND、ripgrep 優先）
├── instructions/
│   └── claude_md_patch.md          global CLAUDE.md に追加する指示文
└── deploy.sh                       本番反映スクリプト（Mac/Win 両対応、冪等）
```

## デプロイ後の配置

`./deploy.sh` を実行すると以下に展開される：

```
~/.claude/CLAUDE.md                                       ← マーカー間ブロック注入
_claude-sync/CLAUDE.md                                    ← マーカー間ブロック注入（Win 同期用）
_claude-sync/commands/recall.md                           ← /recall スキル
_claude-sync/session-recall/search.sh                     ← 実処理スクリプト
```

冪等性あり: 差分なしならバックアップも作らない。再 deploy で v1 → v2 などのバージョン置換も自動。
