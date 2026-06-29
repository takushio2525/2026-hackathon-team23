---
title: 開発環境を準備する
description: production版の開発に必要なソフトウェアとライブラリ
---

## 必要なソフトウェア

| 用途 | ソフトウェア |
|---|---|
| ファームウェア | VS Code + PlatformIO |
| PCアプリ | Processing 4 + Minim |
| ドキュメント | Node.js 20以上 + npm |
| 検証 | Python 3.8以上 + pyserial |
| 報告書 | Docker、またはLuaLaTeX |

## 確認コマンド

```bash
pio --version
node --version
npm --version
python3 --version
```

ProcessingのMinimは「スケッチ → ライブラリをインポート → ライブラリを追加」から導入します。

## ドキュメントサイト

```bash
cd docs
npm install
npm run dev
```

ブラウザで`http://localhost:4321`を開きます。macOSでは`docs/start-docs.command`も利用できます。

## 次の手順

- 初めて取得する：[リポジトリの使い方](/guide/repository/)
- 実機へ書き込む：[ファームウェアを書き込む](/guide/firmware/)
- PCアプリを起動する：[Processingを動かす](/guide/processing/)
