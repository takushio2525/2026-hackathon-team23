---
title: モジュール拡張ガイド
description: 新しい IModule を足す手順 — SystemData 拡張・ProjectConfig 増設・3 フェーズの守り方・落とし穴
sidebar:
  order: 7
---

:::note[この章で分かること]
- 「新しいセンサ / アクチュエータを足したい」ときの最短コース
- SystemData にどう情報を追加するか
- ProjectConfig のどこに何を書くか
- 3 フェーズループに混ぜないコツと典型的なバグ
- 既存モジュールから新モジュールへの依存の扱い方
:::

:::tip[読了目安]
**約 12 分**。前提: [Embedded-Module-Architecture](/architecture/ema/) と
[拍検出アルゴリズム](/deep-dive/beat-detection/) を読み終えていること。
:::

実装本体（参考に読むコード）:
- 抽象基底: `firmware/test_v2/common/lib/ModuleCore/IModule.h`
- 入力モジュール例: `firmware/test_v2/node_01/lib/ImuModule/`
- 出力モジュール例: `firmware/test_v2/common/lib/StatusLedModule/`
- 通信モジュール（入出力両対応）: `firmware/test_v2/common/lib/OrcNetModule/`

## 拡張パターンの一覧

「新しい機能を足したい」と一口に言っても、置く場所と作法はパターンで決まる：

| やりたいこと | 種類 | 置く場所 |
|---|---|---|
| 全ノード共通の入出力（WiFi、LED） | 共通モジュール | `firmware/test_v2/common/lib/<Name>/` |
| 指揮者ノード固有のセンサ（IMU、スイッチ） | ノード固有モジュール | `firmware/test_v2/node_01/lib/<Name>/` |
| 楽器ノード固有の出力（NOTE 送信、追加 LED） | ノード固有モジュール | `firmware/test_v2/node_02/lib/<Name>/` |
| 既存モジュールに新フィールドを追加 | SystemData の拡張 | 該当の `<Module>.h` 内の `<Module>Data` 構造体 |
| ロジック追加（拍検出ルールの変更） | `applyPattern.cpp` の編集 | 該当ノードの `src/applyPattern.cpp` |
| ピンや閾値の変更 | `ProjectConfig.h` の編集 | 該当ノードの `include/ProjectConfig.h` |

ロジックや閾値の変更は最後の 2 行（`applyPattern` / `ProjectConfig`）だけで済む場合が多い。
新しいハードウェアを増やすときは新モジュールを作る必要がある。

## 新しい入力モジュールを作る（例: タクトスイッチ）

「指揮者ノードに `Start` ボタンを足したい」想定で進める。完全なファイル構成：

```
firmware/test_v2/node_01/lib/StartButtonModule/
├── StartButtonModule.h
└── StartButtonModule.cpp
```

### ステップ 1: モジュールヘッダを書く

```cpp
// firmware/test_v2/node_01/lib/StartButtonModule/StartButtonModule.h
#pragma once
#include <Arduino.h>
#include "IModule.h"

struct StartButtonConfig {
    uint8_t  pin;
    bool     activeLow;
    uint16_t debounceMs;
};

struct StartButtonData {
    bool     pressed = false;   // 現在の押下状態
    bool     edge    = false;   // 押下エッジ（1 ループだけ true）
    uint32_t lastEdgeMs = 0;    // 最終エッジ時刻
};

class StartButtonModule : public IModule {
public:
    explicit StartButtonModule(const StartButtonConfig& cfg) : cfg_(cfg) {}
    bool init() override;
    void updateInput(SystemData& data) override;

private:
    StartButtonConfig cfg_;
    bool     lastRaw_ = false;
    uint32_t lastChangeMs_ = 0;
};
```

ポイント：

- **Config 構造体** で外部から渡されるパラメータを集約。`activeLow` や `debounceMs` のような
  ハード依存の値を引数に取ることで、別ボードでの流用が効く
- **Data 構造体** が `SystemData` に組み込まれる単位。「ボタンが押されたか」「エッジか」を
  ロジック側が読む
- 入力モジュールなので **`updateInput()` だけ実装**。`updateOutput()` は `IModule` の
  デフォルト（空実装）に任せる
- 内部の `lastRaw_` / `lastChangeMs_` はデバウンス用の状態。**ここに業務状態を持たせない**

### ステップ 2: 実装を書く

```cpp
// firmware/test_v2/node_01/lib/StartButtonModule/StartButtonModule.cpp
#include "StartButtonModule.h"
#include "SystemData.h"

bool StartButtonModule::init() {
    pinMode(cfg_.pin, cfg_.activeLow ? INPUT_PULLUP : INPUT);
    return true;
}

void StartButtonModule::updateInput(SystemData& data) {
    const uint32_t now = millis();
    const bool raw = digitalRead(cfg_.pin) == (cfg_.activeLow ? LOW : HIGH);

    // 立ち上がり / 立ち下がりエッジ検出 + デバウンス
    if (raw != lastRaw_) {
        lastChangeMs_ = now;
        lastRaw_ = raw;
    }
    bool debouncedPressed = data.startButton.pressed;
    if (now - lastChangeMs_ >= cfg_.debounceMs) {
        debouncedPressed = raw;
    }

    data.startButton.edge = (!data.startButton.pressed && debouncedPressed);
    data.startButton.pressed = debouncedPressed;
    if (data.startButton.edge) data.startButton.lastEdgeMs = now;
}
```

ポイント：

- 「**SystemData に書き込む**」のがこのフェーズの仕事。直接 LED を点灯したり、
  通信を送ったりしてはいけない（出力フェーズの仕事）
- デバウンスはモジュールの内部状態でやって OK（業務状態ではない）
- `edge` は 1 ループだけ true になる。次のループで `applyPattern()` が読み取り後、
  `false` に戻されることを期待する設計（または `updateInput()` の最初で false にする）

### ステップ 3: SystemData に組み込む

`firmware/test_v2/node_01/include/SystemData.h` を編集：

```cpp
#include "StartButtonModule.h"   // StartButtonData

struct SystemData {
    ImuData             imu;
    OrcNetData          orcNet;
    OrcSenderData       sender;
    StatusLedData       led;
    BeatLogicData       beat;
    TempoLogicData      tempo;
    CalibrationData     calibration;
    ConductorStateData  conductor;
    StartButtonData     startButton;   // ← 追加
};
```

これにより `applyPattern()` から `data.startButton.edge` を読めるようになる。

### ステップ 4: ProjectConfig に Config を増設

`firmware/test_v2/node_01/include/ProjectConfig.h`：

```cpp
#include "StartButtonModule.h"   // StartButtonConfig

// ... 既存の設定 ...

inline const StartButtonConfig START_BUTTON_CONFIG = {
    /*pin=*/         3,           // XIAO ESP32-S3 の D3 = GPIO4
    /*activeLow=*/   true,        // INPUT_PULLUP 想定
    /*debounceMs=*/  20,
};
```

### ステップ 5: main.cpp で生成・登録

`firmware/test_v2/node_01/src/main.cpp`：

```cpp
namespace {
    SystemData          gData;
    ImuModule           gImu(IMU_CONFIG);
    OrcNetModule        gNet(ORC_NET_CONFIG);
    OrcSenderModule     gSender(ORC_SENDER_CONFIG);
    StatusLedModule     gLed(STATUS_LED_CONFIG);
    StartButtonModule   gBtn(START_BUTTON_CONFIG);   // ← 追加

    IModule* gInputs[]  = { &gNet, &gImu, &gBtn };   // ← 入力フェーズで呼ぶ
    IModule* gOutputs[] = { &gSender, &gLed, &gNet };
}

void setup() {
    // ...
    initWithRetry(&gNet,    "OrcNetModule");
    initWithRetry(&gImu,    "ImuModule");
    initWithRetry(&gSender, "OrcSenderModule");
    initWithRetry(&gLed,    "StatusLedModule");
    initWithRetry(&gBtn,    "StartButtonModule");   // ← 追加
}
```

`gInputs` に登録するのが大事。`gOutputs` には登録しない（出力フェーズで仕事がないので）。

### ステップ 6: ロジックで使う

`firmware/test_v2/node_01/src/applyPattern.cpp`：

```cpp
void applyPattern(SystemData& data) {
    // ... 既存の処理

    // 新規追加: スタートボタンで強制的に Conducting に遷移
    if (data.startButton.edge &&
        data.conductor.state == ConductorState::Idle) {
        data.conductor.state = ConductorState::Calibrating;
        // ...
    }
}
```

`data.startButton.edge` を読むだけ。直接 GPIO を叩かない（EMA の禁則事項）。

### ステップ 7: ビルドして書き込み

```bash
pio run -d firmware/test_v2/node_01
pio run -d firmware/test_v2/node_01 -t upload
pio device monitor -d firmware/test_v2/node_01
```

ボタンを押して動作確認。シリアルに `[N1 state=Calibrating]` が出れば OK。

## 新しい出力モジュールを作る（例: ブザー）

入力モジュールとほぼ同じ手順だが、**`updateOutput()` だけ実装** する。
ブザーの例：

```cpp
// firmware/test_v2/node_01/lib/BuzzerModule/BuzzerModule.h
struct BuzzerConfig {
    uint8_t  pin;
    uint16_t frequency;   // Hz
};

struct BuzzerData {
    bool active = false;          // ロジックがここに書く → 出力モジュールが読む
    uint16_t durationMs = 0;      // 鳴らす長さ
    uint32_t startedAtMs = 0;     // 内部状態（モジュールが管理）
};

class BuzzerModule : public IModule {
public:
    explicit BuzzerModule(const BuzzerConfig& cfg) : cfg_(cfg) {}
    bool init() override;
    void updateOutput(SystemData& data) override;
private:
    BuzzerConfig cfg_;
};
```

```cpp
// .cpp
void BuzzerModule::updateOutput(SystemData& data) {
    const uint32_t now = millis();
    if (data.buzzer.active && data.buzzer.startedAtMs == 0) {
        tone(cfg_.pin, cfg_.frequency);
        data.buzzer.startedAtMs = now;
    }
    if (data.buzzer.active &&
        (now - data.buzzer.startedAtMs) >= data.buzzer.durationMs) {
        noTone(cfg_.pin);
        data.buzzer.active = false;
        data.buzzer.startedAtMs = 0;
    }
}
```

ロジック側：

```cpp
if (data.beat.event) {
    data.buzzer.active = true;
    data.buzzer.durationMs = 100;
}
```

「拍に合わせてブザーを鳴らす」が完成。

## 入出力両方やるモジュール（例: 通信モジュール）

`OrcNetModule` がこのパターン。`updateInput()` と `updateOutput()` の両方を実装：

```cpp
class OrcNetModule : public IModule {
public:
    bool init() override;
    void updateInput(SystemData& data) override;   // 受信
    void updateOutput(SystemData& data) override;  // 送信
};
```

`main.cpp` で **両方の配列に登録** する：

```cpp
IModule* gInputs[]  = { &gNet, &gImu };
IModule* gOutputs[] = { &gSender, &gLed, &gNet };   // ← gNet を出力にも入れる
```

これにより、入力フェーズで受信、出力フェーズで送信が回る。

## モジュール間の依存

EMA の原則: **モジュール同士は SystemData 経由でしか通信しない**。

### NG パターン

```cpp
// 入力モジュール A が出力モジュール B を直接呼ぶ
void ImuModule::updateInput(SystemData& data) {
    // ...
    gLed.flash(100);   // ← 禁止
}
```

これをやると、テストで A を独立に動かせなくなり、依存グラフが複雑化する。

### OK パターン

```cpp
// 入力モジュール A は SystemData にだけ書く
void ImuModule::updateInput(SystemData& data) {
    // ...
    data.imu.ready = true;
}

// ロジックが SystemData を見て、別の SystemData フィールドに書く
void applyPattern(SystemData& data) {
    if (data.imu.ready) {
        data.led.flash100ms = true;
    }
}

// 出力モジュール B は SystemData を見て動く
void LedModule::updateOutput(SystemData& data) {
    if (data.led.flash100ms) {
        // ...
        data.led.flash100ms = false;
    }
}
```

すべての通信が `SystemData` 経由なので、各モジュールは独立にテスト可能。

## 3 フェーズに混ぜない

| フェーズ | やる | やらない |
|---|---|---|
| 入力 | センサ読み取り、受信、デバウンス | LED 点灯、シリアル書き込み、判断 |
| ロジック | SystemData → SystemData の状態更新 | センサ読み取り、出力、I/O |
| 出力 | LED 点灯、シリアル書き込み、送信 | 判断、別モジュールの状態を変更 |

### よくあるバグ

#### バグ 1: 入力フェーズで判断する

```cpp
// NG
void ImuModule::updateInput(SystemData& data) {
    // ...
    if (data.imu.dynNorm > 1.2f) {     // ← 判断を入れている
        data.beat.event = true;        // ← 業務状態を書いている
    }
}
```

`updateInput()` は「外界からデータを取り込む」だけ。判断は `applyPattern()` の仕事。

#### バグ 2: ロジックで I/O を直接叩く

```cpp
// NG
void applyPattern(SystemData& data) {
    if (data.beat.event) {
        digitalWrite(LED_PIN, HIGH);   // ← 直接 GPIO 操作
    }
}
```

`applyPattern()` は `SystemData` だけ触る。LED は `LedModule::updateOutput()` に任せる。

#### バグ 3: 出力フェーズで判断する

```cpp
// NG
void LedModule::updateOutput(SystemData& data) {
    if (data.imu.dynNorm > 1.2f) {   // ← 判断
        digitalWrite(...);
    }
}
```

判断は `applyPattern()` で済ませて、`data.led.xxxx` を経由する。
これにより、LED 点灯ルールを変えたいときに `applyPattern()` だけ触れば済む。

## `init()` の戻り値

`init()` で `false` を返すと、その IModule は `enabled = false` になり、以降の
ループでは呼ばれない。これにより：

- センサ接続失敗で全体が止まることはない（他のモジュールが動き続ける）
- LED やシリアルだけで「自分は無効です」を表示できる

`initWithRetry()` で最大 3 回まで再試行する：

```cpp
void initWithRetry(IModule* m, const char* name) {
    for (int i = 0; i < 3; ++i) {
        if (m->init()) {
            m->enabled = true;
            return;
        }
        delay(100);
    }
    m->enabled = false;
}
```

I2C デバイスなど、起動直後に応答しないものはこれで救う。

## 楽器ノードでの拡張

楽器ノードは指揮者ノードと `SystemData` が違うので注意：

```cpp
// node_02 の SystemData
struct SystemData {
    OrcNetData          orcNet;
    StatusLedData       led;
    ReceiverLogicData   receiver;
    NoteOutData         noteOut;
    NoteSenderData      noteSender;
    SyncLogicData       sync;
    CtrlData            ctrl;
    PerformerStateData  performer;
    ScoreProgressData   score;
};
```

楽器ノードに何か足すときは、こちらの `SystemData.h` を編集する。

たとえば「演奏中だけ青 LED を光らせたい」なら：

1. `BlueLedModule` を作る（出力モジュール）
2. `SystemData` に `BlueLedData blueLed;` を追加
3. `applyPattern.cpp` で `data.blueLed.on = (data.performer.state == PerformerState::Playing);`
4. `BlueLedModule::updateOutput()` で `data.blueLed.on` を見て GPIO 操作

## 共通モジュールにするか、ノード固有にするか

判断基準：

| 共通モジュール | ノード固有モジュール |
|---|---|
| 複数ノードで使う（WiFi、LED、シリアル） | そのノードだけで使う（IMU、楽器音譜進行） |
| ハード抽象が必要（ESP32 / UNO R4 で `#if`） | ハードが固定 |
| 全ノードの `platformio.ini` に `lib_extra_dirs` で参照 | 該当ノードの `lib/` 内 |

迷ったら **共通から始めて、不要なら個別に移す** ほうが楽。

## platformio.ini への影響

新しい共通モジュールを足したら、各ノードの `platformio.ini` の `build_flags` に
`-I` で include パスを足す：

```ini
build_flags =
    -I include
    -I ../common/lib/ModuleCore
    -I ../common/lib/OrcProtocol
    -I ../common/lib/OrcNetModule
    -I ../common/lib/StatusLedModule
    -I ../common/lib/SerialDebug
    -I ../common/lib/MyNewModule   # ← 追加
```

`lib_extra_dirs = ../common/lib` で全ライブラリのソースが探索されるので、
`-I` だけ追加すれば OK（リンクは自動）。

ノード固有モジュールの場合、`lib/` 直下に置けば PlatformIO が自動的に拾うので、
追加作業は不要。

## CI でビルド確認

`.github/workflows/pio-build.yml` が `firmware/` 配下の変更で全ノードを自動ビルドする。
push する前にローカルで `pio run` が通ることを確認しておくと安心。

ローカルで通っていれば CI でも通る（はず）。落ちたら：

- include パス漏れ
- `SystemData` への追加忘れ
- ESP32 / UNO R4 で異なる `#include` の不整合

を疑う。

## 拡張サンプル一覧

参考になる既存実装：

| やったこと | 参考にできる例 |
|---|---|
| GPIO 入力 + デバウンス | `StartButtonModule`（このページの例） |
| GPIO 出力 + タイマー | `StatusLedModule` |
| I2C デバイス読み取り | `ImuModule` |
| UDP マルチキャスト | `OrcNetModule` |
| シリアル書き込み | `NoteSenderModule` |
| 受信パケットを SystemData に分配 | `OrcReceiverModule` |

「やりたいことに一番近い既存モジュールをコピー」が一番速い。

## トラブルシューティング

| 症状 | 原因 |
|---|---|
| ビルドが落ちる: `undefined reference to ...` | `platformio.ini` の `-I` 漏れ、または `lib_extra_dirs` 配置忘れ |
| ビルドが落ちる: `incomplete type` | `SystemData` をインクルードする前にモジュールヘッダで `struct SystemData;` の前方宣言が必要 |
| モジュールが動かない | `gInputs` / `gOutputs` 配列への登録忘れ、`init()` 失敗で `enabled = false` のまま |
| ロジックがおかしい | 入力フェーズに判断を書いていないか、ロジックで GPIO 直叩きしていないか |
| 1 サイクル遅れる | エッジが `applyPattern()` で読まれずに `updateInput()` で `false` に戻されていないか |

## 次に読むべきページ

- 全体設計の原則 → [Embedded-Module-Architecture](/architecture/ema/)
- 既存モジュールの中身 → [firmware の歩き方](/code/firmware/)
- どの情報をどこに書くか → [リポジトリ・マップ](/code/map/)
