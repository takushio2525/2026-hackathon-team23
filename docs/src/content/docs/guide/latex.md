---
title: LaTeX報告書をコンパイルする
description: report配下の提出資料をPDF化する
---

`docs/`は開発用サイト、`report/`は提出・印刷用資料です。役割を混ぜないでください。

## Docker

```bash
cd report
docker run --rm -v "$(pwd):/workspace" -w /workspace \
  ghcr.io/paperist/texlive-ja:debian latexmk main.tex
```

## LuaLaTeX

ファイル先頭にLuaLaTeX指定がある資料は、ローカル環境で次を使います。

```bash
latexmk -lualatex <file>.tex
```

## 確認

- エラー終了していない
- 未定義参照や引用がない
- 図表がページからはみ出していない
- PDFのコミット方針を対象ディレクトリの`.gitignore`で確認した
