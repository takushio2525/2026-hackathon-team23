# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- `main` に残っていた `1093f04 [改善] 本番版のドラム拍子と全楽器音量を調整` 由来の説明を整理
- 実行コード本体は触らず、README とドラム譜ヘッダコメントのみ修正
- 対象: `firmware/production/README.md`、`firmware/production/node_06/include/score_data.h`、`pc_app/production/README.md`

## 次の一手

- `main` にコミット・push する
- `saitou-work` での個人作業は引き続き `work/saito/` 配下中心に行い、通常作業では `firmware/`・`pc_app/` のプログラムを触らない

## 現フェーズで Read すべき設計書

- コミット規約: `.agent/conventions.md`
- 必要に応じて production 構成: `firmware/production/README.md`、`pc_app/production/README.md`
