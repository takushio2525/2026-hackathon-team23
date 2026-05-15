# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **2026-05-15**: docs/ 充実化フェーズ第 4 弾。ユーザー要望「音声解析と Processing 側の
  処理について、設計方針や詳細を増やしてほしい。test_v2 と sound_lab を題材に、塩澤の実装は
  一例として、他メンバーが自分で実装するときの参考にできるように」に応える形で
  **「PC アプリ・音声処理（塩澤の実装例）」章を新規追加**。

## 直近の観点

1. 新セクション **「PC アプリ・音声処理（塩澤の実装例）」**（`docs/src/content/docs/pc-audio/`）
   を独立で追加。既存「ファームウェア モジュール詳説」と並ぶ位置で、塩澤の Processing 実装と
   sound_lab analyzer を「**一例**」として明示的に扱うトーンで統一。
2. 全 11 ページを `pc-audio/` 配下にフラット配置:
   - `index.md` — 章全体の読み順ガイド・登場人物・「正解と一例の区別」
   - 設計層 2 本: `design.md` / `signal-flow.md`
   - Processing 層 4 本: `resynth-main.md` / `resynth-voice.md` / `instr-model.md` /
     `serial-handling.md`
   - 解析層 3 本: `analyzer-overview.md` / `analyzer-harmonics.md` / `analyzer-modulation.md`
   - 移行支援 1 本: `extending.md`
3. 各ページの統一構造:
   - 実体ファイルパスと行数 → 役割 → データ構造 → 中の数学/コード → 落とし穴 →
     **「どこを書き換えるか（別実装するときの観点）」** 表
   - 「塩澤の実装は一例」のニュアンスを各ページに分散
4. `astro.config.mjs` にサイドバー追加（PC 章はファーム章の直下に挿入）
5. `code/pc-app.md` 末尾の「さらに深掘りしたい」に新章への導線追加
6. `npm run build` で **66 ページ生成成功**（55 → 66、新規 11 ページ）。リンク切れなし、
   slug エラーなし。WARN は元からある sitemap `site` 未設定のみ

## 次の一手

- **コミット**: `[ドキュメント] PC アプリ・音声処理章を新規追加（塩澤の実装例として）` で 1 コミット
- **次に深掘りしたい候補**:
  - `pc-audio/editor-studio.md` — `sound_lab/analyzer/static/` のブラウザ編集スタジオ（fx パラメータ）の解説
  - `pc-audio/sound-lab-processing.md` — `sound_lab/processing/instrument_player/` の単体プレーヤ解説
  - `firmware/score-data.md` — `kScore[]` フォーマットと `score_data.cpp` の書き方
- **既存ドキュメントの整合**: `code/pc-app.md` 自体も将来「概要だけ残し詳細は新章に委譲」
  形にできるが、今は導線追加のみで温存

## ユーザーの今回の好み

- 「**塩澤は一例として、こんな感じに作らせました**」のトーンを明示要求。確定実装ではなく
  メンバーが自分で書き直すときの参考にしたい
- 「**他の人が自分の実装をするときに、参考とできるように**」を最優先
- 「**test_v2 や sound_lab の実装を見つつ、その方針を核としたら**」と、現実コードからの帰納
  を要望（理想形ではなく実コードの解剖）
- 質問返しせず即着手の運用が継続好まれている（autonomous モード明示）

## 既知の論点

- `pc-audio/` 章は塩澤実装の解剖がメイン。チームの他メンバーが「自分の方針」で書いた実装が
  増えたら、章名から「（塩澤の実装例）」を外して `pc-audio/<member>-impl.md` を並べる
  形にもできる
- `instr-model.md` と `sound_lab/library_format.md` は内容が大きく重なる。SSOT を
  `library_format.md` に置き、docs 側は導線にする選択肢もあるが、現状はサイト読者の
  利便性を優先して両方持つ
- `extending.md` に「サンプル再生で書き直す案」「FM 合成案」を書いたが、誰かが実際に
  着手したらそれぞれ専用ページに昇格させる
