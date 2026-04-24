---
name: recall
description: プロジェクト横断でSESSION_HISTORYとHANDOFFを検索し、過去の作業・決定・議論を想起する
---

# /recall スキル

## 使い方

`/recall <キーワード>` で、全プロジェクトの `SESSION_HISTORY.md` / `HANDOFF.md` を横断検索する。

例:
- `/recall ToDo 結合`
- `/recall ボタン 配置`
- `/recall Flutter デプロイ`

複数キーワードを空白区切りで指定すると AND 検索（各ファイル内で全キーワードを含む箇所）。

## 実装

（未実装 — Phase 2 で `search.sh` を作り、このスキルから呼び出す）
