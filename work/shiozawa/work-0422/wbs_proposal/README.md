# wbs_proposal — ハッカソン1 WBS 再設計提案書

## このフォルダの目的

第2回議事録（`meetings/0422_2回/23_第2回議事録_24G1075.pdf`）の
**表1 WBS（作業分担表）** が、授業資料の正解形式
（時間的フェーズ＝設計→製造→テスト という工程軸）と異なる構造で書かれており、
そのままチーム提出計画書（`work/shiozawa/work-0422/提出用計画書/`）の
§3.1 に転記すると体裁が崩れる。

このフォルダでは、塩澤側で **WBS の再設計提案書** を独立した
LaTeX プロジェクトとしてまとめ、チーム内（特に先輩 24G 勢）への
レビュー材料として PDF を生成する。

提出用計画書本体（`提出用計画書/plan_template.tex`）は **編集しない**。
このフォルダの提案がチームで承認されたあと、別途分担で計画書本体に転記する。

## 不要になったら

このフォルダは **チーム内提案・議論用**。計画書本体に WBS が反映され、
役割を終えたら削除して構わない。ただし審議経緯を残したい場合は
`docs/decisions/` に ADR として要点だけ抜粋することを推奨する。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `main.tex` | 提案書本体（章セクション直書き） |
| `.latexmkrc` | latexmk 設定（lualatex 指定） |
| `hack-cover.sty` | 表紙スタイル（提出用計画書からコピー） |
| `hack-fonts.sty` | 日本語フォント設定（Hiragino、Mac 用） |
| `main.pdf` | コンパイル成果物（コミット対象） |

## ビルド方法

`% !TEX program = lualatex` 指定のため、Docker ではなく **ローカル lualatex** で
コンパイルする（Hiragino フォント依存）。

```bash
cd work/shiozawa/work-0422/wbs_proposal
latexmk -lualatex main.tex
```

`main.pdf` が生成される。中間ファイル（`.aux`, `.log` 等）は
リポジトリルートの `.gitignore` で除外済み。
