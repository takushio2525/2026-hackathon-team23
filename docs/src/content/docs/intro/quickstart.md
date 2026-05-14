---
title: クイックスタート
description: clone から「指揮者を振って音が鳴る」までの最短ルート
sidebar:
  order: 2
---

:::note[この章で分かること]
- 何をインストールすればいいか
- どこをビルドして、どこを書き込めば動くか
- 「とりあえず音が出る」までの最短手順
:::

:::tip[読了目安]
**約 15 分**（実際に動かす場合は 30〜60 分）。
前提: ハードウェア一式（指揮者 1 台 + 楽器 3 台 + PC）を手元に持っていること。
:::

このページは「最短で動かす」ためのチートシートです。
詳しい解説は [開発ガイド](/guide/setup/) を参照してください。

## 0. 必要なもの

| カテゴリ | 物品 | 数量 |
|---|---|---|
| ハードウェア（指揮者） | XIAO ESP32-S3 Sense | 1 |
|  | GY-521（MPU6050 モジュール） | 1 |
|  | USB Type-C ケーブル | 1 |
| ハードウェア（楽器） | Arduino UNO R4 WiFi | 3 〜 4 |
|  | USB Type-C ケーブル | 3 〜 4 |
| PC | macOS / Windows / Linux | 1 |
|  | スピーカ（PC 内蔵で可） | 1 |
| ソフトウェア | [VS Code](https://code.visualstudio.com/) | — |
|  | [PlatformIO IDE](https://platformio.org/install/ide?install=vscode) 拡張 | — |
|  | [Processing 4](https://processing.org/download) | — |
|  | [Git](https://git-scm.com/downloads) | — |

詳細は [必要なものをそろえる](/guide/setup/) 参照。

## 1. リポジトリを clone する

```bash
git clone https://github.com/takushio2525/2026-hackathon-team23.git
cd 2026-hackathon-team23
```

詳しい手順（SSH 鍵の登録など）は [リポジトリを手元に持ってくる](/guide/clone/) 参照。

## 2. 指揮者ノードを書き込む

XIAO ESP32-S3 Sense に GY-521 を配線（D4 → SDA、D5 → SCL、3V3 / GND）してから:

```bash
pio run -d firmware/test_v2/node_01 -t upload
```

書き込み直後にボードが自動リセットされ、青 LED が点滅し始めれば成功。
2 秒間の起動キャリブレーション中は LED が早く点滅し、終わると遅くなる。

## 3. 楽器ノードを書き込む（3 台分）

Arduino UNO R4 WiFi を 3 台用意し、それぞれを書き込む:

```bash
pio run -d firmware/test_v2/node_02 -t upload   # 声部 1
pio run -d firmware/test_v2/node_03 -t upload   # 声部 2
pio run -d firmware/test_v2/node_04 -t upload   # 声部 3
```

書き込み後、各ノードは指揮者ノードが立てる WiFi SoftAP（SSID `OrchestraAP`、
パスワード `orchestra2026`）に自動接続する。

## 4. PC アプリを起動する

Processing 4 を開いて、次のスケッチを Run:

```
pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde
```

開いてからシリアルポートのドロップダウンで **どれか 1 つの楽器ノード** を選択する。

## 5. 指揮者を振る

指揮者ノードを手に持って、上下に振る。
拍に合わせて PC スピーカから音が鳴れば成功！

- 速く振る → テンポが上がる
- ゆっくり振る → テンポが下がる
- 大きく振る → 音量が上がる（強弱）

## うまく動かないとき

| 症状 | 確認 |
|---|---|
| 楽器の LED が点滅したまま音が出ない | WiFi 接続できているか（指揮者 LED の点滅周期と楽器 LED の点滅周期が一致しているか） |
| 音が遅れる / ずれる | PC の Processing がフォアグラウンドになっているか、シリアルバッファが詰まっていないか |
| シリアルポートが見えない | USB ケーブルがデータ通信対応か（充電専用 NG）、ドライバが入っているか |
| `pio run` がエラー | `~/.platformio/` を一度削除してリトライ |

詳しくは [よく出るトラブルと対処](/code/troubleshooting/) 参照。

## 次に読むべきページ

- 仕組みを理解する → [アーキテクチャ全体図](/architecture/overview/)
- コードを読む → [リポジトリ・マップ](/code/map/)
- 開発を始める → [開発ガイド](/guide/setup/)
