# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **本番プログラム構築** (`feature/production-program` ブランチ)。レビュー＆リファクタ完了。
  - 前の子の4コミット（ベロシティ・ドラム音色・node_06 新設・マスターリセット修正）は全て正しく反映
  - Processing ドラム対応を追加実装（noteNumber → 音色インデックス変換）
  - node_03〜06 のコメントパス修正

## 次の一手

- PR 作成 → main マージの判断はユーザー
- 実機 upload はユーザー作業
- crash の drum_sample 原音再生は未対応（倍音合成で鳴る。実機で音を聞いて判断）

## 現フェーズで Read すべき設計書

- プロトコル仕様: `.agent/api.md`
- さいとうくんの参照実装: `work/saito/week9/kaeru_score_debug/kaeru_score_debug.pde`（saitou-work ブランチ）
