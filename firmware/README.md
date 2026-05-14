# firmware — マイコン用ファームウェア

このディレクトリは「**本番用** (`production/`)」と「**テスト用** (`test_v1/` / `test_v2/`)」に
分かれている。

| サブディレクトリ | 目的 | 中身 |
|---|---|---|
| [`production/`](production/) | 本番想定の素のテンプレート | クリーンな PlatformIO プロジェクト雛形 (node_01〜05) |
| [`test_v1/`](test_v1/) | 仕様書（Arduino オーケストラ計画書）準拠の最初の検証実装 | 指揮者 + 楽器 3。各拍で C major 圏内の和音を鳴らして拍ズレを聞き取る用（旧 `firmware/test`） |
| [`test_v2/`](test_v2/) | きらきら星の輪唱 + 楽器番号付き NOTE | 指揮者 + 楽器 3。楽譜「きらきら星」全曲を内蔵し、3 声部を 8 拍ずつずらして輪唱。NOTE に `instrumentId`（楽器番号）を載せ、PC 側で sound_lab の音色定義を選んで合成する |

どちらも仕様書 `meetings/0429_3回/事前課題共有/arduino_塩澤.pdf` の §2.3〜§2.4 に沿った
実機検証用実装。指揮者ノードのハードウェアは `MPU6050` を `GY-521` モジュールで代替している。
**新しく動かすなら `test_v2/` を使う**（`test_v1/` は最初の同期検証版として残してある）。

`test_v2` での主な変更点（詳細は [`test_v2/README.md`](test_v2/README.md)）:

- 楽譜「きらきら星」全曲を内蔵（`node_02/03/04/src/score_data.cpp`、3 台とも同一）
- 3 声部の輪唱（カノン）：`headRestBeats`（ProjectConfig.h）で頭の休符ぶんずらして入る
  （node_02→0 / node_03→8 / node_04→16 拍）
- NOTE パケットに `instrumentId`（楽器番号）を追加（旧 `reserved[0]`）。各ノードが固定で送る
  （node_02→0 / node_03→1 / node_04→2）。PC 側 `pc_app/test_v2/orchestra_resynth` がこの番号で
  `data/*.json` を選んで加算合成する
- 楽器ノードは指揮者の **拍番号** から自分の楽譜位置を計算 → PC 側 Processing を曲の途中で起動しても
  「いまの拍」から鳴り始める
- 初期テンポ 100 BPM（最初の 1 音）→ 2 拍目で簡易テンポ確定 → 以降 EMA で随時補正
- node_02/03/04 の `platformio.ini` は既定で `SERIAL_DEBUG=0`（バイナリ NOTE を Serial に流す）

## ビルド

```bash
# === test_v2 (きらきら星 輪唱・推奨) ===
pio run -d firmware/test_v2/node_01 -t upload   # 指揮者 (XIAO ESP32-S3 Sense + GY-521)
pio run -d firmware/test_v2/node_02 -t upload   # 輪唱 声部 1
pio run -d firmware/test_v2/node_03 -t upload   # 輪唱 声部 2
pio run -d firmware/test_v2/node_04 -t upload   # 輪唱 声部 3

# === test_v1 (最初の同期検証版) ===
pio run -d firmware/test_v1/node_01 -t upload
pio run -d firmware/test_v1/node_02 -t upload   # ...node_03 / node_04 も同様

# === production (まだ素のテンプレ) ===
pio run -d firmware/production/node_01
```

`pio device monitor -d firmware/test_v2/node_01` でシリアルモニタ。

## コーディング方針

`test_v1/` `test_v2/` のコードは [Embedded-Module-Architecture (EMA)](https://github.com/takushio2525/Embedded-Module-Architecture)
に全面準拠する。

- 3 フェーズループ（入力 → ロジック → 出力）で `loop()` を構成
- 各機能は `IModule`（`init()` / `updateInput()` / `updateOutput()` / `deinit()`）を実装
- ノード内の共有状態は `SystemData` 構造体に集約
- ピン・定数・閾値は `ProjectConfig.h` に集約（モジュール本体にハードコードしない）
- モジュール間の直接呼び出しは禁止。通信は `SystemData` のフィールド経由のみ

詳細は [`test_v2/common/README.md`](test_v2/common/README.md) と、
`docs/` サイトの「アーキテクチャ > Embedded-Module-Architecture」または
[ADR-0005 のソース](../docs/src/content/docs/decisions/0005-firmware-embedded-module-architecture.md) を参照。

## 共通層

各バージョンの `common/lib/` に全ノード共有のライブラリ群を置き、各ノードの
`platformio.ini` から `lib_extra_dirs = ../common/lib` で参照する。

| ライブラリ | 内容 |
|---|---|
| `ModuleCore/` | `IModule` 抽象基底 + `ModuleTimer` |
| `OrcProtocol/` | CTRL/BEAT/NOTE の 20 B パケット定義（`magic=0x4F52`）。test_v2 では NOTE に `instrumentId` 追加 |
| `OrcNetModule/` | WiFi UDP マルチキャスト送受信 |
| `StatusLedModule/` | 状態に応じた LED 点滅出力 |
| `SerialDebug/` | `SERIAL_DEBUG` フラグで切替えるシリアルデバッグマクロ |

## 役割分担

| ノード | test_v1 | test_v2 | ハードウェア | partId |
|---|---|---|---|---|
| node_01 | 指揮者（SoftAP + IMU）| 同左（初期テンポ 100 BPM）| XIAO ESP32-S3 Sense + GY-521 | — |
| node_02 | 楽器 1（金管 1 / C4 ベース）| 輪唱 声部 1（headRest=0, instr=0）| Arduino UNO R4 WiFi | 0x02 |
| node_03 | 楽器 2（金管 2 / E4 ベース）| 輪唱 声部 2（headRest=8, instr=1）| Arduino UNO R4 WiFi | 0x03 |
| node_04 | 楽器 3（木管 1 / G4 ベース）| 輪唱 声部 3（headRest=16, instr=2）| Arduino UNO R4 WiFi | 0x04 |
| node_05 | ドラム（未実装）| — | (未実装) | 0x05 |

どちらも node_03〜 は node_02 をコピーして `ProjectConfig.h` だけ差し替えれば動く設計
（仕様書 §2.4.3.6）。test_v2 は楽譜 `score_data.cpp` も 3 台同一（= 輪唱）。

## 仕様の核

| 項目 | 値 |
|---|---|
| WiFi SSID / pass | `OrchestraAP` / `orchestra2026` |
| マルチキャスト | `239.0.0.1:5001` |
| WiFi チャネル | 6 |
| 共通ヘッダ | 12 B（magic + version + type + seq + timestampMs）|
| ペイロード | 8 B（CTRL / BEAT / NOTE 共通サイズ）|
| パケット長 | 20 B 固定 |
| BPM 範囲 | 40–240（初期値 test_v1=120 / test_v2=100）|
| マスタクロック | 指揮者ノードの `millis()`、楽器側は EMA で offset 推定 |
| MOP-1 同期誤差 | ≤ 20 ms（ADR-0006 に準拠）|
| MOP-2 通信遅延 | ≤ 10 ms |
