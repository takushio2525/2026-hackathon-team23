---
title: firmware の歩き方
description: main.cpp から ProjectConfig.h までを順に追いかけるツアー
sidebar:
  order: 2
---

:::note[この章で分かること]
- main.cpp を読み始めて何が見えるか
- どのファイルにどの情報があるか
- ハマったときの調べ方
:::

:::tip[読了目安]
**約 12 分**。前提: [Embedded-Module-Architecture](/architecture/ema/) を読んでいること。
:::

このツアーは `firmware/test_v2/node_01/`（指揮者ノード）を例に進める。
楽器ノード（node_02〜04）も同じ構造で、`SystemData` のフィールドが違うだけ。

## 1. エントリポイント: `src/main.cpp`

指揮者ノードの `setup()` と `loop()` がここにある。

```cpp
namespace {
    SystemData       gData;
    ImuModule        gImu(IMU_CONFIG);
    OrcNetModule     gNet(ORC_NET_CONFIG);
    OrcSenderModule  gSender(ORC_SENDER_CONFIG);
    StatusLedModule  gLed(STATUS_LED_CONFIG);

    IModule* gInputs[]  = { &gNet, &gImu };
    IModule* gOutputs[] = { &gSender, &gLed, &gNet };
}
```

ポイント：

- **全状態は `gData`（SystemData）に集約**
- 各モジュールは `ProjectConfig.h` の設定値を受け取って構築
- 入力フェーズと出力フェーズで使うモジュールを別配列で持つ
- `gNet` は入力にも出力にも入っている（受信と送信の両方を担当）

### `setup()` の流れ

```cpp
void setup() {
    DBG_BEGIN(115200);
    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    Wire.setClock(400000);

    initWithRetry(&gNet,    "OrcNetModule");
    initWithRetry(&gImu,    "ImuModule");
    initWithRetry(&gSender, "OrcSenderModule");
    initWithRetry(&gLed,    "StatusLedModule");
}
```

`initWithRetry()` は最大 3 回まで初期化を再試行する。
失敗したモジュールは `enabled = false` で **無効化されたまま** ループに入る
（他のモジュールが動き続ける設計）。

### `loop()` の流れ

```cpp
void loop() {
    for (auto* m : gInputs)  if (m->enabled) m->updateInput(gData);
    applyPattern(gData);
    for (auto* m : gOutputs) if (m->enabled) m->updateOutput(gData);

#if SERIAL_DEBUG
    trackPeak(gData);
    dumpEdges(gData);
    dumpPeriodic(gData);
#endif
}
```

3 フェーズが徹底されている。
デバッグ出力は `#if SERIAL_DEBUG` で完全に切り離せる。

## 2. ロジック本体: `src/applyPattern.cpp`

ここに **拍検出ロジック** が集約されている。
具体的な実装は読みながら把握するのが速いが、流れだけ：

```cpp
void applyPattern(SystemData& d) {
    updateCalibration(d);          // 起動 2 秒のキャリブレーション
    updateConductorState(d);       // 状態機械 (Idle/Calibrating/Conducting/Fallback)

    if (d.conductor.state != ConductorState::Conducting) return;

    detectBeat(d);                 // 動加速度ノルム → Armed → 経路長 → 拍発火
    updateTempo(d);                // 拍間隔から BPM を EMA
    prepareSenderOutputs(d);       // CTRL/BEAT 用のフィールドを SystemData にセット
}
```

実際のコード行数は約 200 行。`logic_params` の定数を引きながら閾値判定する。
詳しいアルゴリズムは [同期戦略](/architecture/sync/) 参照。

## 3. データ構造: `include/SystemData.h`

ノード内で共有する全状態：

```cpp
struct SystemData {
    ImuData             imu;          // IMU 生データ + LPF 後の値
    OrcNetData          orcNet;       // WiFi 接続状態・受信バッファ
    OrcSenderData       sender;       // CTRL/BEAT 送信統計
    StatusLedData       led;          // 現在の点滅周期
    BeatLogicData       beat;         // 拍検出結果
    TempoLogicData      tempo;        // bpm, nextBeatPredictedMs
    CalibrationData     calibration;  // 起動キャリブレーション結果
    ConductorStateData  conductor;    // 状態機械
};
```

各サブ構造体（`ImuData` 等）は対応するモジュール側のヘッダで定義されている：

- `ImuData` → `common/lib/ImuModule/ImuModule.h`（or node_01/lib/ 内）
- `OrcNetData` → `common/lib/OrcNetModule/OrcNetModule.h`
- ...

## 4. 設定値: `include/ProjectConfig.h`

ピン・閾値・WiFi 設定の集約。重要な抜粋：

```cpp
// I2C ピン
constexpr uint8_t I2C_SDA_PIN = 5;
constexpr uint8_t I2C_SCL_PIN = 6;

// IMU 設定
inline const ImuConfig IMU_CONFIG = {
    /*address=*/          0x68,
    /*sampleIntervalMs=*/ 5,
    /*accelRangeG=*/      4,
    /*gyroRangeDps=*/     2000,
};

// 送信周期
inline const OrcSenderConfig ORC_SENDER_CONFIG = {
    /*ctrlIntervalMs=*/  50,   // 20 Hz
    /*beatRedundancy=*/  2,    // BEAT 2 連送
    /*beatLookaheadMs=*/ 50,   // playAtMasterMs = masterNow + 50 ms
};

// 拍検出ロジック係数
namespace logic_params {
    constexpr float    BEAT_DYN_THRESHOLD_G = 1.20f;
    constexpr uint32_t BEAT_REFRACTORY_MS   = 350;
    constexpr float    BEAT_FIRE_PATH_M     = 0.20f;
    // ...
}
```

**変更時はこのファイルだけ触る**。モジュール本体に手を入れない。

## 5. 共通モジュール: `firmware/test_v2/common/lib/`

### `ModuleCore/`

- `IModule.h`: 抽象基底
- `ModuleTimer.h`: 周期実行ヘルパー

### `OrcProtocol/`

- `OrcProtocol.h`: パケット構造体（`CtrlPacket`、`BeatPacket`、`NotePacket`）
- `OrcProtocol.cpp`: シリアライズ／デシリアライズ

詳細は [通信プロトコル](/architecture/protocol/) を参照。

### `OrcNetModule/`

- WiFi SoftAP / Station の切替、UDP マルチキャスト送受信
- 受信バッファを `OrcNetData::rxQueue` に積む
- 切断時は `reconnectIntervalMs` で自動再接続

### `StatusLedModule/`

- 状態に応じて LED 点滅周期を切替
- XIAO ESP32-S3 の active LOW LED に対応（`activeLow = true`）

### `SerialDebug/`

- `SERIAL_DEBUG` マクロで切替えるラッパー
- `DBG_PRINTF` / `DBG_PRINTLN` を使う（直 `Serial.print` 禁止）

## 6. ビルド設定: `platformio.ini`

```ini
[env:seeed_xiao_esp32s3]
platform = espressif32@6.10.0
board = seeed_xiao_esp32s3
framework = arduino
build_flags =
    -I include
    -I ../common/lib/ModuleCore
    -I ../common/lib/OrcProtocol
    -I ../common/lib/OrcNetModule
    -I ../common/lib/StatusLedModule
    -I ../common/lib/SerialDebug
    -DARDUINO_USB_MODE=1
    -DARDUINO_USB_CDC_ON_BOOT=1
    -DSERIAL_DEBUG=1
lib_extra_dirs = ../common/lib
lib_ldf_mode = deep+
monitor_speed = 115200
upload_protocol = esp-builtin
upload_speed = 921600
```

ポイント：

- `platform = espressif32@6.10.0`: Arduino-ESP32 v2.0.17 系で固定（v3.x は `Network.h` で詰まる）
- `-I` で各ライブラリのヘッダパスを明示
- `lib_extra_dirs = ../common/lib`: 共通ライブラリの探索場所
- `lib_ldf_mode = deep+`: ライブラリ間の依存を深く解決
- `upload_protocol = esp-builtin`: 内蔵 USB Serial/JTAG で書き込み（BOOT ボタン不要）

楽器ノード（node_02〜04）の `platformio.ini` は `board = uno_r4_wifi` で、
`-DSERIAL_DEBUG=0` がデフォルト。

## 7. 楽器ノード固有: `score_data`

楽器ノードには楽譜データが追加で乗る：

- `include/score_data.h`: `ScoreEvent` 構造体定義、外部参照宣言
- `src/score_data.cpp`: 配列リテラルで全曲分の音符を直書き

3 ノード（node_02/03/04）で **完全に同一内容**（輪唱なので）。
ロジック側（`applyPattern.cpp`）は `beatNo - headRestBeats` から楽譜位置を計算する。

## 読み始めの推奨順

1. `node_01/include/ProjectConfig.h` → 何が定数化されているか把握
2. `node_01/include/SystemData.h` → ノードが扱うデータの全体像
3. `node_01/src/main.cpp` → 起動とループの骨格
4. `node_01/src/applyPattern.cpp` → 拍検出の中身
5. `common/lib/OrcProtocol/` → パケット形式
6. `common/lib/OrcNetModule/` → 通信モジュール

楽器ノードを読むときは `node_02/` を選んで同じ順番。

## 次に読むべきページ

- PC 側 → [pc_app の歩き方](/code/pc-app/)
- バージョン差分 → [test_v1 / test_v2 / production の差分](/code/versions/)
- 困ったら → [よく出るトラブルと対処](/code/troubleshooting/)

### さらに深掘りしたい

- `applyPattern.cpp` を行単位で読み解く → [拍検出アルゴリズム](/deep-dive/beat-detection/)
- 受信側の `OrcReceiverModule` と発火タイミング → [時刻同期メカニズム](/deep-dive/time-sync/)
- 楽器ノードの楽譜進行ロジック → [楽譜進行ロジック](/deep-dive/score-progression/)
- 新しいモジュールを足す → [モジュール拡張ガイド](/deep-dive/module-extension/)
