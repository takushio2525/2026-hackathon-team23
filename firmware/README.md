# firmware — マイコン用ファームウェア

このディレクトリは「**本番用** (`production/`)」と「**テスト用** (`test/`)」の
2 系統に分かれている。

| サブディレクトリ | 目的 | 中身 |
|---|---|---|
| [`production/`](production/) | 本番想定の素のテンプレート | クリーンな PlatformIO プロジェクト雛形 (node_01〜05) |
| [`test/`](test/) | 仕様書 (Arduino オーケストラ計画書) 準拠のテスト実装 | 指揮者 (node_01) + 楽器 1 (node_02) のみ |

`test/` は仕様書 `meetings/0429_3回/事前課題共有/arduino_塩澤.pdf` の
§2.3〜§2.4 に沿って書かれた実機検証用の最小実装。指揮者ノードのハードウェアは
`MPU6050` を `GY-521` モジュールで代替している (それ以外は仕様書通り)。

## ビルド

### test 版 (仕様準拠の検証用)

```bash
# 指揮者ノード (XIAO ESP32-S3 Sense + GY-521)
cd firmware/test/node_01
pio run                  # ビルド
pio run -t upload        # 書き込み
pio device monitor       # シリアルモニタ

# 楽器 1 (Arduino UNO R4 WiFi, 金管 1)
cd firmware/test/node_02
pio run
pio run -t upload
```

### production 版 (まだ素のテンプレ)

```bash
cd firmware/production/node_01
pio run
```

## コーディング方針

`test/` のコードは [Embedded-Module-Architecture (EMA)](https://github.com/takushio2525/Embedded-Module-Architecture)
に全面準拠する。

- 3 フェーズループ (入力 → ロジック → 出力) で `loop()` を構成
- 各機能は `IModule` (`init()` / `updateInput()` / `updateOutput()` / `deinit()`) を実装
- ノード内の共有状態は `SystemData` 構造体に集約
- ピン・定数・閾値は `ProjectConfig.h` に集約 (モジュール本体にハードコードしない)
- モジュール間の直接呼び出しは禁止。通信は `SystemData` のフィールド経由のみ

詳細は [`test/common/README.md`](test/common/README.md) と
[ADR-0005](../docs/decisions/0005-firmware-embedded-module-architecture.md) を参照。

## 共通層

`test/common/lib/` に全ノード共有のライブラリ群を置き、各ノードの
`platformio.ini` から `lib_extra_dirs = ../common/lib` で参照する。

| ライブラリ | 内容 |
|---|---|
| `ModuleCore/` | `IModule` 抽象基底 + `ModuleTimer` |
| `OrcProtocol/` | CTRL/BEAT/NOTE の 20 B パケット定義 (`magic=0x4F52`) |
| `OrcNetModule/` | WiFi UDP マルチキャスト送受信 |
| `StatusLedModule/` | 状態に応じた LED 点滅出力 |

## 役割分担 (test/)

| ノード | 役割 | ハードウェア | partId | startBeatNo |
|---|---|---|---|---|
| node_01 | 指揮者 (SoftAP + IMU) | XIAO ESP32-S3 Sense + GY-521 | — | — |
| node_02 | 楽器 1 (金管 1) | Arduino UNO R4 WiFi | 0x02 | 0 |
| node_03 | 楽器 2 (金管 2) | Arduino UNO R4 WiFi | 0x03 | 0 |
| node_04 | 楽器 3 (木管 1) | Arduino UNO R4 WiFi | 0x04 | 0 |
| node_05 | ドラム | (未実装) | 0x05 | 0 |

テスト実装では同期検証用に `startBeatNo` を全 0 で揃え、3 度・5 度の和音を積んで
C major 圏内のハモリで拍ズレを聞き取りやすくしている。本番の輪唱（4／8 拍ずらし）は
`ProjectConfig.h` の `startBeatNo` を差し替えるだけで切り替わる設計。
node_03〜05 は node_02 をコピーして `ProjectConfig.h` の `partId` /
`startBeatNo` と `score_data.cpp` の楽譜だけ差し替えれば動く
(仕様書 §2.4.3.6)。

## 仕様の核

| 項目 | 値 |
|---|---|
| WiFi SSID / pass | `OrchestraAP` / `orchestra2026` |
| マルチキャスト | `239.0.0.1:5001` |
| WiFi チャネル | 6 |
| 共通ヘッダ | 12 B (magic + version + type + seq + timestampMs) |
| ペイロード | 8 B (CTRL / BEAT / NOTE 共通サイズ) |
| パケット長 | 20 B 固定 |
| BPM 範囲 | 40–240 |
| マスタクロック | 指揮者ノードの `millis()`、楽器側は EMA で offset 推定 |
| MOP-1 同期誤差 | ≤ 20 ms (ADR-0006 に準拠) |
| MOP-2 通信遅延 | ≤ 10 ms |
