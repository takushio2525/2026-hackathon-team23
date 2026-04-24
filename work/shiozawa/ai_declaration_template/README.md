# 生成AI利用申告書 テンプレート

ハッカソンの提出課題ごとに、生成AIの利用内容を記述した PDF を提出する。
このディレクトリは **LaTeX テンプレートの原本** で、課題ごとに別ディレクトリへコピーして埋める運用にする。

## このディレクトリの位置づけ

- ここは **触らないテンプレート（原本）**
- 各回の作業ディレクトリ（例: `work/shiozawa/work-0422/`）の下に、
  申告書用フォルダを作ってコピーして使う

```
work/shiozawa/
├── ai_declaration_template/   ← このディレクトリ（原本テンプレート、触らない）
│   ├── README.md              ← このファイル
│   ├── main.tex
│   ├── .latexmkrc
│   └── plistings.sty
├── work-0415/                 ← 4/15 回の作業（HCK01_xx, sketch_xx）
└── work-0422/                 ← 4/22 回の作業
    ├── HCK02_01/              ← Arduino スケッチ（提出物）
    ├── HCK02_01.zip           ← 提出用ZIP
    ├── work1/, work2/, work3/, work2_processing/   ← 例題・試作
    └── ai_declaration/          ← その回の生成AI利用申告書（埋めた実体）
        └── HCK02_01/
            ├── main.tex
            ├── .latexmkrc
            ├── plistings.sty
            └── main.pdf       ← Docker でコンパイルして生成
```

## 新しい課題の申告書を作る手順

ここではテンプレートを `work-0422/ai_declaration/HCK02_02/` に複製する例を示す。
日付やコース番号に合わせてパスを読み替える。

1. テンプレートを複製
   ```bash
   # work/shiozawa/ をカレントとした場合
   mkdir -p work-0422/ai_declaration
   cp -r ai_declaration_template work-0422/ai_declaration/HCK02_02
   ```
2. `work-0422/ai_declaration/HCK02_02/main.tex` を編集し、6項目と基本情報を埋める
3. コンパイル
   ```bash
   # Docker Desktop が未起動なら起動してから
   docker info > /dev/null 2>&1 || (open -a Docker && until docker info > /dev/null 2>&1; do sleep 2; done)

   docker run --rm \
     -v "$(pwd)/work-0422/ai_declaration/HCK02_02:/workspace" \
     -w /workspace \
     ghcr.io/paperist/texlive-ja:debian latexmk main.tex
   ```
4. 生成された `main.pdf` を提出用ファイル名にリネームして提出
   ```bash
   cp work-0422/ai_declaration/HCK02_02/main.pdf HCK02_02.pdf
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
