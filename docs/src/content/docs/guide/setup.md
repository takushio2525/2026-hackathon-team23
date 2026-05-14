---
title: 必要なものをそろえる
description: 開発に必要なハードウェア・ソフトウェアの一覧と入手方法
sidebar:
  order: 1
---

:::note[この章で分かること]
- 何を買えばいいか
- どのソフトをインストールすればいいか
- どのバージョンを選べばいいか
:::

:::tip[読了目安]
**約 10 分**（インストール作業を含めると 1 時間程度）。
前提知識は不要。
:::

## ハードウェア

### 指揮者ノード（1 セット）

| 物品 | 数量 | 入手先（例） | 備考 |
|---|---|---|---|
| **XIAO ESP32-S3 Sense** | 1 | スイッチサイエンス、秋月電子、Seeed 公式 | カメラ付きの「Sense」モデル（カメラは使わない） |
| **GY-521（MPU6050 ブレイクアウト）** | 1 | 秋月電子、Amazon | 1 個 200〜500 円程度 |
| **USB Type-C ケーブル** | 1 | — | データ通信対応のもの（**充電専用は NG**） |
| **ジャンパワイヤ（メス-メス）** | 4 本以上 | — | XIAO ↔ GY-521 配線用 |

#### XIAO ↔ GY-521 配線

| GY-521 | XIAO ESP32-S3 |
|---|---|
| VCC | 3V3 |
| GND | GND |
| SDA | D4（GPIO5） |
| SCL | D5（GPIO6） |
| AD0 | GND（I2C アドレス 0x68 固定） |

### 楽器ノード（3 〜 4 セット）

| 物品 | 数量 | 入手先 | 備考 |
|---|---|---|---|
| **Arduino UNO R4 WiFi** | 3〜4 | スイッチサイエンス、秋月電子 | 5000〜6000 円程度 |
| **USB Type-C ケーブル** | 3〜4 | — | データ通信対応 |

### PC

- **macOS / Windows / Linux** いずれでも可
- スピーカ（PC 内蔵で十分）
- USB ポートが楽器ノード台数 + 指揮者 = 4〜5 個必要（足りなければ USB ハブ）

## ソフトウェア

### 必須

#### VS Code

<https://code.visualstudio.com/>

理由: PlatformIO 拡張がここで動く。他のエディタでも PlatformIO CLI は使えるが、
本ドキュメントは VS Code 前提で書いている。

#### PlatformIO IDE 拡張

VS Code 起動後、左サイドバーの拡張機能（Ctrl/Cmd + Shift + X）で
「**PlatformIO IDE**」を検索してインストール。

インストール完了後、VS Code を再起動すると左サイドバーに **アリのアイコン**（PlatformIO）が
追加される。

#### Processing 4

<https://processing.org/download>

理由: PC アプリの実行環境。Processing 3 系では一部の API が違うので必ず 4 系。

#### Git

| OS | インストール方法 |
|---|---|
| macOS | `xcode-select --install` で Xcode Command Line Tools を入れる |
| Windows | <https://git-scm.com/download/win> から Git for Windows |
| Linux | `sudo apt install git` 等 |

Git の基本コマンドは [チームで Git を使う](/guide/git/) で解説する。

#### GitHub アカウント

<https://github.com/signup>

理由: リポジトリの push に必要。クローンは public 設定なら無くても可能。

### 任意（あると便利）

#### Docker Desktop

<https://www.docker.com/products/docker-desktop>

LaTeX 報告書のコンパイルに使う。報告書を触らない人は不要。

#### CLI ツール（`gh` コマンド）

GitHub の PR 操作などをコマンドラインから行いたい場合：

```bash
brew install gh    # macOS
gh auth login
```

## インストール確認

ターミナル（macOS は Terminal.app、Windows は PowerShell）で以下を実行：

```bash
git --version
# 出力例: git version 2.42.0

code --version    # VS Code の CLI が通っているか
# 出力例: 1.85.1

pio --version     # PlatformIO CLI
# 出力例: PlatformIO Core, version 6.1.13
```

`pio` コマンドが見つからない場合は、VS Code の PlatformIO 拡張を入れた後で
PATH 反映のため一度ターミナルを再起動する。

## 次に読むべきページ

- リポジトリを clone する → [リポジトリを手元に持ってくる](/guide/clone/)
- とにかく動かしたい → [クイックスタート](/intro/quickstart/)
