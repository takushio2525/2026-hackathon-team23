# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- `saitou-work` の `work/saito/week10/kaeru_score_week10_adjusted/` を `main` の同じ場所へ反映
- フルート・オルガン音色を含む Processing スケッチのコミット・プッシュ

## 直近の観点

- `saitou-work` から該当フォルダだけを `main` に `git restore --source=saitou-work` で取り込み。
- 反映対象:
  - `work/saito/week10/kaeru_score_week10_adjusted/kaeru_score_week10_adjusted.pde`
  - `work/saito/week10/kaeru_score_week10_adjusted/README.md`
  - `work/saito/week10/kaeru_score_week10_adjusted/data/flute.tweaked.instrument.json`
  - `work/saito/week10/kaeru_score_week10_adjusted/data/organ.tweaked.instrument.json`
- JSON 検証: `jq empty` 成功。
- Processing 検証: `processing-java --build` 成功。

## 次の一手

- 実機・発表環境では Processing 4 で `work/saito/week10/kaeru_score_week10_adjusted/kaeru_score_week10_adjusted.pde` を開いて聴感確認する。

## 現フェーズで Read すべき設計書

- 音色・Processing 作業確認: `work/saito/week10/kaeru_score_week10_adjusted/README.md`
