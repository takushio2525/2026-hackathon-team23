# CLAUDE.md — プロジェクト固有の開発ルール

## プロジェクト概要

ハッカソン・チーム開発用のテンプレートリポジトリ。
大学2年生（Git・共同開発未経験）が対象読者。様々なプロジェクトで流用できる汎用テンプレート。

## ドキュメントの言語

すべて日本語で記述する。コード内のコメントも日本語。

## ディレクトリ構成のルール

- 各ディレクトリには README.md を置き、「何のフォルダか」「不要なら削除OK」を明記する
- サンプルコードは最小限だが動作する状態を維持する
- `.gitkeep` は空ディレクトリの維持用。ファイルが追加されたら削除してよい

## ドキュメント整合性

以下のドキュメント間で記述が矛盾しないよう注意する：

- `README.md`（ルート）: テンプレートの全体像
- `CONTRIBUTING.md`: Git の使い方・開発ルール
- 各ディレクトリの `README.md`: そのフォルダ固有の説明
- `report/README.md`: LaTeX 報告書の使い方

機能の追加・削除（CI ワークフロー等）を行った場合、関連するすべての README を更新すること。

## ビルド

### ファームウェア（PlatformIO）

```bash
cd firmware/node_01 && pio run
```

### LaTeX 報告書

```bash
cd report
docker run --rm -v "$(pwd):/workspace" -w /workspace \
  ghcr.io/paperist/texlive-ja:debian latexmk main.tex
```

## CI

- `.github/workflows/pio-build.yml`: firmware/ 変更時に全ノードをビルド
- LaTeX の自動コンパイル CI は未設定（手元で Docker コンパイルする運用）
