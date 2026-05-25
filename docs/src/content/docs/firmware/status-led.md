---
title: StatusLedModule — 状態を LED で可視化する
description: solidOn / 点滅周期の 2 軸で状態を表現する出力モジュール。active LOW LED の扱い方
sidebar:
  label: 共通 — StatusLedModule
  order: 4
---

:::note[この章で分かること]
- `solidOn` と `blinkIntervalMs` の 2 つだけで状態を表現する設計
- XIAO ESP32-S3 の **active LOW LED** を `activeLow` フラグでどう扱うか
- 状態機械（Idle / Calibrating / Conducting / Fallback など）とどう対応するか
:::

## 実体

| ファイル | 行数 | 内容 |
|---|---|---|
| `firmware/test_v2/common/lib/StatusLedModule/StatusLedModule.h` | 33 | Config / Data / クラス宣言 |
| `firmware/test_v2/common/lib/StatusLedModule/StatusLedModule.cpp` | 35 | init() と updateOutput() 実装 |

出力フェーズのみに登場する純粋な **出力モジュール**。`updateInput()` は持たない。

## 役割と責務

| 観点 | 内容 |
|---|---|
| **書く側** | `applyPattern()`（状態機械の遷移時に `data.led.solidOn / blinkIntervalMs` を更新） |
| **読む側** | このモジュール（`updateOutput()` で物理 LED に反映） |
| **境界** | 状態 → LED 出力 の **変換層**。どの状態でどう点滅するかは applyPattern 側が決める |

## StatusLedConfig

```cpp
struct StatusLedConfig {
    uint8_t  pin;
    uint16_t blinkIntervalMs;   // 既定の点滅周期
    bool     activeLow;         // true: LOW で点灯
};
```

### 指揮者ノードの設定

```cpp
inline const StatusLedConfig STATUS_LED_CONFIG = {
    /*pin=*/             LED_BUILTIN,   // XIAO ESP32-S3 = GPIO21 (User LED)
    /*blinkIntervalMs=*/ 500,
    /*activeLow=*/       true,          // XIAO ESP32-S3 の User LED は LOW で点灯
};
```

### 楽器ノードの設定

```cpp
inline const StatusLedConfig STATUS_LED_CONFIG = {
    /*pin=*/             LED_BUILTIN,   // UNO R4 WiFi = D13
    /*blinkIntervalMs=*/ 500,
    /*activeLow=*/       false,         // UNO R4 WiFi の LED は HIGH で点灯
};
```

**同じ `LED_BUILTIN` でも `activeLow` の値が逆**。これがこのモジュールの一番大事な設計。

## StatusLedData

```cpp
struct StatusLedData {
    uint16_t blinkIntervalMs = 500;
    bool     solidOn = false;  // true なら点灯固定
};
```

たった 2 フィールド。**`solidOn` 優先 / 偽なら点滅周期で点滅** のセマンティクス。

| `solidOn` | `blinkIntervalMs` | 挙動 |
|---|---|---|
| true | (無視) | 点灯固定 |
| false | 1000 | 1 Hz 点滅 |
| false | 500 | 2 Hz 点滅 |
| false | 200 | 5 Hz 点滅 |

これだけで状態機械の全状態を表現できる。

## init() — ピン初期化と消灯

```cpp
bool StatusLedModule::init() {
    pinMode(cfg_.pin, OUTPUT);
    digitalWrite(cfg_.pin, cfg_.activeLow ? HIGH : LOW);   // 消灯
    ledOn_ = false;
    lastToggleMs_ = millis();
    return true;
}
```

ポイント：

- `pinMode(cfg_.pin, OUTPUT)` でデジタル出力モードに
- **`digitalWrite()` の初期値は「消灯レベル」を選ぶ**: active LOW なら HIGH、そうでなければ LOW
- 内部状態 `ledOn_ = false` と `lastToggleMs_ = millis()` も初期化

このモジュールは **ハードウェア初期化が単純で失敗しない** ので、`init()` は常に true を返す。

## updateOutput() — 点灯ロジック

```cpp
void StatusLedModule::updateOutput(SystemData& data) {
    const uint8_t onLevel  = cfg_.activeLow ? LOW  : HIGH;
    const uint8_t offLevel = cfg_.activeLow ? HIGH : LOW;
    uint32_t now = millis();

    if (data.led.solidOn) {
        if (!ledOn_) {
            digitalWrite(cfg_.pin, onLevel);
            ledOn_ = true;
        }
        return;
    }

    uint16_t period = data.led.blinkIntervalMs ? data.led.blinkIntervalMs
                                               : cfg_.blinkIntervalMs;
    if (now - lastToggleMs_ >= period) {
        lastToggleMs_ = now;
        ledOn_ = !ledOn_;
        digitalWrite(cfg_.pin, ledOn_ ? onLevel : offLevel);
    }
}
```

### `onLevel` / `offLevel` の計算

```cpp
const uint8_t onLevel  = cfg_.activeLow ? LOW  : HIGH;
const uint8_t offLevel = cfg_.activeLow ? HIGH : LOW;
```

`activeLow` の真偽で点灯レベルを選び替える。これにより、モジュール本体のロジックは
**`ledOn_` という抽象的な状態だけ** を扱える（具体的な電圧レベルを意識しなくていい）。

### solidOn 分岐

```cpp
if (data.led.solidOn) {
    if (!ledOn_) {
        digitalWrite(cfg_.pin, onLevel);
        ledOn_ = true;
    }
    return;
}
```

`solidOn = true` のときは：
- 既に点灯中 (`ledOn_ == true`) なら何もしない（無駄な `digitalWrite` を避ける）
- 消灯中 (`ledOn_ == false`) なら点灯して状態を更新

`return` で早期脱出するので、以降の点滅処理は走らない。

### 点滅処理

```cpp
uint16_t period = data.led.blinkIntervalMs ? data.led.blinkIntervalMs
                                           : cfg_.blinkIntervalMs;
if (now - lastToggleMs_ >= period) {
    lastToggleMs_ = now;
    ledOn_ = !ledOn_;
    digitalWrite(cfg_.pin, ledOn_ ? onLevel : offLevel);
}
```

毎周期 `now - lastToggleMs_ >= period` をチェック。閾値超えたらトグル。

**`period` の決め方が二段構え**:
- `data.led.blinkIntervalMs` が非ゼロならそれを使う（実行時動的変更）
- ゼロなら `cfg_.blinkIntervalMs` にフォールバック（Config の既定）

この設計により、Config の既定だけ覚えておけば、`SystemData` を初期化し忘れても LED が
動かないという事故を避けられる。

## 状態と LED 周期の対応

### 指揮者ノード（`applyPattern.cpp` から抜粋）

```cpp
void updateLed(SystemData& data) {
    switch (data.conductor.state) {
        case ConductorState::Idle:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_IDLE_MS;          // 1000 (1 Hz)
            break;
        case ConductorState::Calibrating:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_CALIBRATING_MS;   // 500 (2 Hz)
            break;
        case ConductorState::Conducting:
            data.led.solidOn = true;                          // 点灯固定
            break;
        case ConductorState::Fallback:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_FALLBACK_MS;      // 200 (5 Hz)
            break;
    }
}
```

LED の見え方で「今何を待っているか」「異常状態に入ったか」が一目で分かる。

| 見た目 | 状態 | 意味 |
|---|---|---|
| 1 Hz ゆっくり点滅 | Idle | 起動直後、WiFi 接続待ち |
| 2 Hz 中速点滅 | Calibrating | 静止キャリブ中（2 秒間） |
| 点灯固定 | Conducting | 拍検出稼働中 |
| 5 Hz 高速点滅 | Fallback | IMU タイムアウト or WiFi 切断 |

### 楽器ノード

```cpp
void updatePerformerLed(SystemData& data) {
    switch (data.performer.state) {
        case PerformerState::Idle:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_IDLE_MS;          // 1000
            break;
        case PerformerState::WaitStart:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_WAIT_START_MS;    // 500
            break;
        case PerformerState::Playing:
            data.led.solidOn = true;                          // 点灯固定
            break;
    }
}
```

楽器側は 3 状態。WiFi 接続待ち → BEAT 受信待ち → 演奏中 を点滅速度で表す。

## active LOW LED の罠

XIAO ESP32-S3 Sense の User LED (GPIO21) は **active LOW**:

```
GPIO21 → 抵抗 → LED → +3.3V
```

つまり：
- `digitalWrite(GPIO21, LOW)`: GPIO がグラウンドに引かれ、LED に電流が流れる → **点灯**
- `digitalWrite(GPIO21, HIGH)`: GPIO が +3.3V になり、LED の両端が同電位 → **消灯**

これは多くのボードと逆の挙動。普通の Arduino（UNO 系）は active HIGH（HIGH で点灯）。

**間違えると確実に挙動が逆になる**：
- 「点灯したいのに消灯」「消灯したいのに点灯」が常に発生
- `solidOn = true` のとき LED が消えていれば、`activeLow` の値を確認すべき

このモジュールでは `activeLow` フラグ 1 つで両方の極性を吸収するので、`applyPattern()` 側は
極性を一切意識しない。

## 落とし穴

- **`activeLow` の値を間違えると即動作が逆転する**。新しいボードを足すときは
  データシートの LED 結線を必ず確認する。
- **`pinMode(LED_BUILTIN, OUTPUT)` を `init()` で呼ぶ**。`main.cpp` 側で
  `pinMode` を呼んでいないので、`init()` を必ず通すこと（`enabled = false` なら LED は
  まったく光らない）。
- **`digitalWrite` を毎周期呼ばない**: solidOn 状態で既に点灯済みのときは `digitalWrite` を
  スキップする。常時 1 ms 周期で `digitalWrite` を呼ぶと、I/O バスに微妙な負荷がかかる
  （実害はほぼないが、書かなくていい I/O は書かない方が良い）。
- **`millis()` のラップアラウンド**: `now - lastToggleMs_ >= period` は 49.7 日跨ぎでも
  `uint32_t` の自然な減算で正しく動く（[IModule の解説参照](/firmware/imodule/#millis-のラップアラウンド対策)）。

## なぜ「点灯」「点滅周期」だけで状態を表すのか

別案として：
- LED の色（赤・緑・青）で状態を表す → 多色 LED が必要、配線が増える
- LED の数（1 個・2 個）で状態を表す → 部品が増える
- シリアル出力でログを見る → 物理的な確認手段としては遠回り

シンプルさを優先して、**単色 LED 1 個** で point の状態を表す方針にした。点滅周波数を変えれば
状態数は十分カバーできる（Idle / Active / Error の 3 状態で点滅速度が異なれば判別できる）。

## 関連ページ

- どの状態でどう点滅するかの設計 → [拍検出アルゴリズム](/deep-dive/beat-detection/)（指揮者側）
- 状態機械の全体 → [main フロー（指揮者）](/firmware/main-conductor/) / [main フロー（楽器）](/firmware/main-instrument/)
- IModule の仕組み → [IModule と ModuleTimer](/firmware/imodule/)
