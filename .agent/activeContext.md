# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- `sound_lab/analyzer` の単一楽器JSON書き出しを全UI設定保存へ修正済み
- 通常書き出しで欠落していた `fx.master_volume` を追加
- 全60個のUI値を `fx.studio_state` に保存し、Processing側もFX後段のマスター音量を反映

## 次の一手

- ユーザーが解析ページから新しいJSONを書き出し、`instrument_player/data/`へ配置して聴感確認する
- 既存 `0708_2...json` は修正前出力なので、必要なら解析ページで再書き出しする

## 現フェーズで Read すべき設計書

- 書き出し実装: `work/umezawa/hck/sound_lab/analyzer/static/engine.js`
- UI連携: `work/umezawa/hck/sound_lab/analyzer/static/app.js`
- 再生実装: `work/umezawa/hck/sound_lab/processing/instrument_player/instrument_player.pde`
