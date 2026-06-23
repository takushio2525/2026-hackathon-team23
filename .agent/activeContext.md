# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **week9 の4声輪唱・ドラム確認用 Processing スケッチを main へ統合済み**（commit `8afce57`）。
  `work/saito/week9/kaeru_score_debug/` は音色JSONを `data/` に同梱し、トランペット → ホルン → トロンボーン → チューバの順で輪唱する。再解析済みのキック、スネア、ハイハット、クラッシュは解析済み原音1打を再生し、サンプルのないJSONは従来の合成へフォールバックする。
- **test_v3 Processing 音色データを 2026-06-17 に差し替え済み**。
  `/Users/shota/Documents/3S/` の金管 4 種 JSON を
  `pc_app/test_v3/orchestra_resynth/data/` の番号付きファイル名へ上書き取り込み:
  - `trumpets.tweaked.instrument.json` → `0_trumpets.tweaked.instrument.json`
  - `horns.tweaked.instrument.json` → `1_horns.tweaked.instrument.json`
  - `trombones.tweaked.instrument.json` → `2_trombones.tweaked.instrument.json`
  - `tuba.tweaked.instrument.json` → `3_tuba.tweaked.instrument.json`
- 取り込み後、4 ファイルは元ファイルと byte 単位一致。`python3 -m json.tool` で JSON 構文 OK。
- ドラム系 `4_kick`〜`7_crash` と README は未変更。

## 次の一手

- week9 は Processing 4 で実音のバランス（ドラム4音の原音再生・チューバ終止）を必要に応じて確認する。
- 必要なら Processing 4 で `pc_app/test_v3/orchestra_resynth/orchestra_resynth.pde` を起動し、
  楽器定義パネルに `0_trumpets`〜`3_tuba` が表示されることと音色差を聴感確認する。
- ファーム変更はなし。PIO ビルド・実機 upload は不要。

## 現フェーズで Read すべき設計書

- Processing 音色データ作業: `pc_app/test_v3/orchestra_resynth/data/README.md`
- ゲームモード設計: `.agent/test_v3-game-design.md`
- プロトコル仕様: `.agent/api.md`

## ユーザーの好み

- 大規模作業は計画を作ってから着手。短い指示は行間を読み，前提のズレを感じたら着手前に指摘。
- 実機未テストの .ino/.cpp に Claude 起点で変更を入れたらコンパイル確認まで＝upload はユーザー。
