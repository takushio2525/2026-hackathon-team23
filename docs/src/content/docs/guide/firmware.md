---
title: Arduino を書き換える
description: PlatformIO で各ノードをビルド・書き込みする手順
sidebar:
  order: 3
---

:::note[この章で分かること]
- PlatformIO の使い方（ビルド・書き込み・シリアル）
- 5 台それぞれにどう書き込むか
- 書き込み時のよくあるエラー
:::

:::tip[読了目安]
**約 15 分**（実機を触りながら）。
前提: PlatformIO 拡張をインストール済み（[必要なものをそろえる](/guide/setup/)）。
:::

## PlatformIO の基本コマンド

すべてリポジトリのルート（`2026-hackathon-team23/`）で実行する。

| 用途 | コマンド |
|---|---|
| ビルド（書き込みなし） | `pio run -d <project_path>` |
| ビルド + 書き込み | `pio run -d <project_path> -t upload` |
| シリアルモニタを開く | `pio device monitor -d <project_path>` |
| クリーンビルド | `pio run -d <project_path> -t clean` |
| シリアルポートを一覧 | `pio device list` |

`<project_path>` には `firmware/test_v2/node_01` のような **`platformio.ini` がある
フォルダのパス** を指定する。

## 指揮者ノード（XIAO ESP32-S3）

### 配線（再掲）

| GY-521 | XIAO ESP32-S3 |
|---|---|
| VCC | 3V3 |
| GND | GND |
| SDA | D4（GPIO5） |
| SCL | D5（GPIO6） |
| AD0 | GND |

### 書き込み

```bash
pio run -d firmware/test_v2/node_01 -t upload
```

初回はライブラリ群のダウンロードで 5〜10 分かかることがある。
2 回目以降は 30 秒程度。

書き込み完了直後にボードが自動リセットされ、青 LED が点滅し始める：

- **2 Hz 点滅（早め）**: キャリブレーション中（起動から 2 秒）
- **1 Hz 点滅（遅め）**: Idle（指揮待ち）
- **拍ごとに 1 回点灯**: Conducting

### XIAO の書き込みモード

`platformio.ini` で `upload_protocol = esp-builtin` を指定しているため、
**BOOT / RESET ボタンを押す必要はない**。USB Type-C を挿すだけで書き込める。

### シリアル監視

```bash
pio device monitor -d firmware/test_v2/node_01
```

`SERIAL_DEBUG=1` がデフォルトなので、200 ms ごとにステータスが流れる：

```
[N1 t=12345 st=Conducting wifi=1 imu=1 acc=(0.10,0.85,-0.05) ...]
```

終了は `Ctrl+C`（macOS / Linux）または `Ctrl+T → Ctrl+X`（Windows）。

## 楽器ノード（Arduino UNO R4 WiFi × 3）

### 書き込み

3 台それぞれ別ポートに繋いで個別に書き込む：

```bash
pio run -d firmware/test_v2/node_02 -t upload   # 声部 1（headRest=0, instrument=0）
pio run -d firmware/test_v2/node_03 -t upload   # 声部 2（headRest=8, instrument=1）
pio run -d firmware/test_v2/node_04 -t upload   # 声部 3（headRest=16, instrument=2）
```

**1 台ずつ繋いで書き込む** のが基本。複数同時に繋ぐと PlatformIO がどのポートか
迷うことがある。

### `--upload-port` で明示する

複数台同時に繋ぐ場合は、シリアルポートを明示：

```bash
# macOS / Linux
pio run -d firmware/test_v2/node_02 -t upload --upload-port /dev/cu.usbmodem14101

# Windows
pio run -d firmware/test_v2/node_02 -t upload --upload-port COM3
```

ポート名は `pio device list` で確認。

### 楽器ノードの LED

楽器ノードはデフォルト `SERIAL_DEBUG=0`（バイナリ NOTE を流すため）。
状態は LED で確認：

- **5 Hz 点滅**: WiFi 未接続 or Fallback
- **1 Hz 点滅**: WiFi 接続済み、CTRL 受信中
- **拍ごとに点灯**: 演奏中

## test_v1 / production の書き込み

```bash
# test_v1（最初の検証版・C major 和音）
pio run -d firmware/test_v1/node_01 -t upload
pio run -d firmware/test_v1/node_02 -t upload
# ...

# production（素テンプレ）
pio run -d firmware/production/node_01 -t upload
```

`test_v1` と `test_v2` は別バイナリ。指揮者ノードを切り替えるときは書き直す必要がある。

## 開発中のループ

実装中は次のリズム：

```
1. ファイル編集（VS Code）
2. pio run -d ... -t upload     # ビルド + 書き込み
3. pio device monitor -d ...    # ログを見る
4. （問題があれば 1 に戻る）
```

VS Code 内蔵ターミナルで複数タブを開くと便利：

- タブ 1: 指揮者の書き込み
- タブ 2: 指揮者のシリアル監視
- タブ 3: 楽器の書き込み
- タブ 4: PC アプリ起動コマンド

## よくあるエラー

### `fatal error: Network.h: No such file or directory`

`platformio.ini` の `platform = espressif32@6.10.0` を確認。
これは Arduino-ESP32 v2.0.17 系に固定するためのバージョン指定。
最新の `espressif32` だと Arduino v3.x が要求する `Network.h` で詰まる。

### `Could not open port /dev/cu.usbmodem...`

別のターミナル or Processing がシリアルポートを開いている可能性。
`Ctrl+C` で監視を閉じる、Processing を停止してから書き込み直す。

### XIAO の書き込みでハング

USB Serial/JTAG コントローラに問題があるとき：

1. ボード上の BOOT ボタンを押しながら RESET ボタンを押す
2. BOOT ボタンを離す
3. `pio run -d ... -t upload` を実行
4. 完了後にもう一度 RESET ボタンを押す

これで普通は復帰する。

### `WiFi Connection Failed`

楽器が指揮者 SoftAP に接続できないとき：

- 指揮者ノードが起動しているか
- 楽器ノードの `ProjectConfig.h` の SSID / pass が一致しているか
- 周囲に同じ SSID の WiFi がないか（チャネル干渉）

詳しくは [よく出るトラブルと対処](/code/troubleshooting/) 参照。

## 次に読むべきページ

- PC アプリを起動する → [PC アプリを動かす](/guide/processing/)
- ログを読む → [シリアルモニタでデバッグする](/guide/debug/)
- コードの中身 → [firmware の歩き方](/code/firmware/)
