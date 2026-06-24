# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **本番プログラム分離** (`feature/production-program` ブランチ)
  - test_v3 を main の状態に復元済み
  - test_v3 ベースの `firmware/production/` と `pc_app/production/` を新設
  - 本番用変更（楽譜ベロシティ・ドラム音色・node_06・リセット修正・Processing ドラム対応）は production のみに反映
  - コメント内パスを test_v3 → production に一括置換
  - 全 7 ノード pio run SUCCESS

## 次の一手

- PR 作成 → main マージの判断はユーザー
- 実機 upload はユーザー作業
- crash の drum_sample 原音再生は未対応（倍音合成で鳴る。実機で音を聞いて判断）

## 現フェーズで Read すべき設計書

- プロトコル仕様: `.agent/api.md`
