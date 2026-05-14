---
title: LaTeX 報告書をコンパイルする
description: Docker でのコンパイル、LuaLaTeX のローカル運用、PDF のコミットルール
sidebar:
  order: 6
---

:::note[この章で分かること]
- Docker で報告書を PDF 化する手順
- LuaLaTeX が必要なファイルの判別
- PDF を Git にコミットするルール
:::

:::tip[読了目安]
**約 10 分**。前提: Docker Desktop をインストール済み。
:::

## 報告書の場所

| ディレクトリ | 内容 |
|---|---|
| `report/` | 公式の報告書テンプレ |
| `work/shiozawa/work-*/` | 塩澤の作業ファイル（事前課題・設計書原案など） |
| `work/<member>/...` | 各メンバーの個人作業 |
| `work/shiozawa/ai_declaration/` | 生成 AI 利用申告書テンプレ |

このリポジトリ内のすべての `.tex` プロジェクトに、同じ運用ルールが適用される。

## Docker でコンパイル（基本）

ターミナルで、`.tex` がある（= `main.tex` と同階層の）ディレクトリに入って：

```bash
docker run --rm -v "$(pwd):/workspace" -w /workspace \
  ghcr.io/paperist/texlive-ja:debian latexmk main.tex
```

- 完了すると `main.pdf` が生成される
- 中間ファイル（`*.aux`、`*.log` 等）は `.gitignore` で除外済み

### Docker Desktop が止まっているとき

事前に Docker Desktop を起動しておく必要がある。ワンライナーで自動起動：

```bash
docker info > /dev/null 2>&1 || (open -a Docker && until docker info > /dev/null 2>&1; do sleep 2; done)
docker run --rm -v "$(pwd):/workspace" -w /workspace \
  ghcr.io/paperist/texlive-ja:debian latexmk main.tex
```

## LuaLaTeX が必要なファイル

ファイル先頭に次のマジックコメントがあるものは LuaLaTeX が必要：

```tex
% !TEX program = lualatex
```

これらは Docker（`pdflatex` / `platex` ベース）ではコンパイルできない。
**ローカル LuaLaTeX** を使う：

```bash
latexmk -lualatex main.tex
```

### なぜローカル

LuaLaTeX 指定の `.tex` は **Hiragino フォント** を呼び出している。
Docker イメージにはこのフォントが入っていない（macOS システムフォント）ため、
ローカルでコンパイルするほうが手間が少ない。

### ローカルに LaTeX がない場合

macOS:
```bash
brew install --cask mactex   # 約 5 GB
```

または小さく済ませたい場合は BasicTeX：
```bash
brew install --cask basictex
sudo tlmgr update --self
sudo tlmgr install latexmk luatexja
```

## コンパイル成功の確認

```bash
ls *.pdf
# main.pdf が生成されていれば OK
```

開いて中身を確認：

```bash
open main.pdf       # macOS
xdg-open main.pdf   # Linux
start main.pdf      # Windows
```

## コミットルール（重要）

`.tex` を変更したら、**必ず PDF も一緒にコミット** する：

```bash
git add main.tex sections/*.tex main.pdf
git commit -m "[ドキュメント] 報告書の §3 を修正"
git push origin main
```

理由: Docker 環境を持たないメンバーが PDF を確認できないと、提出物のレビューが止まる。

### コミットしてはいけないもの

中間ファイル（`.gitignore` で除外済みだが念のため）：

- `*.aux` / `*.log` / `*.fls` / `*.fdb_latexmk`
- `*.synctex.gz` / `*.dvi` / `*.out` / `*.toc`

git status で見えてしまっている場合は `.gitignore` の追加を検討。

### `report/` 配下の PDF

`report/**/*.pdf` は `.gitignore` で**除外**されている。
公式テンプレ側は中間生成物として扱う運用。

一方で `work/` 配下の作業 TeX が生成する PDF は**コミット対象**。
ここが要点：

| 場所 | PDF のコミット |
|---|---|
| `report/` 配下 | しない（中間生成物扱い） |
| `work/` 配下 | **する**（提出物 / レビュー対象） |

## エラー時の対処

### `! LaTeX Error: File 'xxx.sty' not found.`

TeX Live のパッケージが足りない。Docker 版なら次でほぼ網羅：

```bash
docker run --rm -v "$(pwd):/workspace" -w /workspace \
  ghcr.io/paperist/texlive-ja:debian tlmgr install <パッケージ名>
```

### 日本語フォントが文字化け

- `pLaTeX` 系なら `\documentclass[uplatex,dvipdfmx]{...}` の指定
- `LuaLaTeX` 系なら `\usepackage{luatexja}` の有無
- `XeLaTeX` は本プロジェクトでは使わない

### 図が表示されない

`\includegraphics{path}` のパスは `main.tex` からの相対パス。
画像が `figs/` 配下なら `\includegraphics{figs/system.png}`。

## 報告書テンプレを新規追加するには

1. `work/<your-name>/<work-name>/` を作る
2. `main.tex`、`sections/*.tex` をテンプレからコピー
3. 1 回コンパイルして `main.pdf` を作る
4. `.tex` と `.pdf` を同一コミットで push

## 次に読むべきページ

- 変更を保存する → [チームで Git を使う](/guide/git/)
- 全体のディレクトリ → [リポジトリ・マップ](/code/map/)
