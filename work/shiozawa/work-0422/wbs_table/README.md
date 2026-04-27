# wbs_table — WBS 表のみ出力版

## このフォルダの目的

第2回議事録（`meetings/0422_2回/23_第2回議事録_24G1075.pdf`）の
**表1 WBS（作業分担表）** と同じ体裁
（時間的フェーズ／番号／要素成果物／活動タスク／担当者 の5列・`multirow` 構造）の
表だけを 1 PDF にまとめた、**ミニマルな再設計版 WBS** を出力する LaTeX プロジェクト。

`wbs_proposal/`（章立て付きの提案書本体）と内容は同じだが、
こちらは**表だけ**を見たい人向け。チーム共有や印刷時に「議事録の表と並べて
見比べる」用途を想定している。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `main.tex` | WBS 表本体（章立てなし、表のみ） |
| `.latexmkrc` | latexmk 設定（lualatex 指定） |
| `main.pdf` | コンパイル成果物（コミット対象） |

スタイルファイル（`hack-cover.sty` `hack-fonts.sty`）は使わず、
最小プリアンブル（`ltjsarticle` + `luatexja-fontspec` + `multirow`）で構成している。
日本語フォントは Hiragino Kaku Gothic ProN（Mac 標準）。

## ビルド方法

`% !TEX program = lualatex` 指定のため、Docker ではなく **ローカル lualatex** で
コンパイルする（Hiragino フォント依存）。

```bash
cd work/shiozawa/work-0422/wbs_table
latexmk -lualatex main.tex
```

## 不要になったら

`wbs_proposal/` と同じく**チーム内議論用**。計画書本体に WBS が反映され、
役割を終えたら削除して構わない。
