# 生成AI利用申告書

ハッカソン1 の提出課題ごとに、生成AIの利用内容を記述した PDF を提出する。
ここでは **LaTeX 軽量テンプレート** を提供し、課題ごとにコピーして埋める運用にする。

## ディレクトリ構成

```
ai_declaration/
├── README.md         ← このファイル
├── template/         ← 原本テンプレート（触らず、コピー元として保持）
│   ├── main.tex
│   ├── .latexmkrc
│   └── plistings.sty
├── HCK02_01/         ← 提出課題1 用（埋めた実体）
│   └── …
└── HCK02_02/         ← 提出課題2 用（必要になったら template からコピー）
    └── …
```

## 新しい課題の申告書を作る手順

1. テンプレートを複製
   ```bash
   cp -r template HCK02_02   # 提出課題2 の場合
   ```
2. `HCK02_02/main.tex` を編集し、6項目と基本情報を埋める
3. コンパイル
   ```bash
   # Docker Desktop が未起動なら起動してから
   docker info > /dev/null 2>&1 || (open -a Docker && until docker info > /dev/null 2>&1; do sleep 2; done)

   docker run --rm -v "$(pwd)/HCK02_02:/workspace" -w /workspace \
     ghcr.io/paperist/texlive-ja:debian latexmk main.tex
   ```
4. 生成された `HCK02_02/main.pdf` を提出用ファイル名にリネーム
   ```bash
   cp HCK02_02/main.pdf HCK02_02.pdf
   ```

## 記入のポイント

- **項目4（正しいと確認した方法）は実機テスト後に書く**。動作確認していないのに
  「動作を確認した」と書くのは虚偽申告になる
- プロンプトは **AI へ送った文を原文のまま** 貼る（要約しない）
- 「参考にしただけ」と書いた場合、どの部分を参考にしたか具体的に示す
- 自分の言葉で説明できない箇所は提出物に含めない

## ファイル命名規約（講義資料より）

| 課題 | Arduino | Processing | 申告書 |
|---|---|---|---|
| 提出課題1 | `HCK02_01.ino` | — | `HCK02_01.pdf` |
| 提出課題2 | `HCK02_02.ino` | `HCK02_02.pde` | `HCK02_02.pdf` |
| 発展課題 | `HCK02_03.ino` | `HCK02_03.pde` | `HCK02_03.pdf` |
