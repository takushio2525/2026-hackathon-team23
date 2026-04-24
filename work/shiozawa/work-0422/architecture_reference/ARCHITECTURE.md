# Architecture Reference

> **本ファイルは、外部リポジトリ Embedded-Module-Architecture からの複製です。**
>
> - **採用元**: <https://github.com/takushio2525/Embedded-Module-Architecture>
> - **原本パス**: `ARCHITECTURE.md`
> - **取り込み日**: 2026-04-24
> - **編集禁止**: このファイルは上流の同期スナップショットです。修正が必要な場合は
>   上流リポジトリ側で行い、本フォルダへ再同期してください。
> - **本ハッカソンでの位置付け**: ADR-0005（[`docs/decisions/0005-firmware-embedded-module-architecture.md`](../../../../docs/decisions/0005-firmware-embedded-module-architecture.md)）で
>   採用決定済み。design_draft / report の設計記述はすべて本ファイルを正本とする。

---

組み込みシステム向けModuleインターフェース設計パターンのアーキテクチャリファレンス。
AI（Claude Code、GitHub Copilot等）および開発者向けの構造ガイド。

詳細な実装ルール・ワークフローは [CLAUDE.md](CLAUDE.md) を参照。

---

## 設計思想

**問題**: `loop()` にロジック・センサー読み込み・出力制御が混在すると、テストも移植も困難になる。

**解決策**: ハードウェアアクセスを「モジュール」に閉じ込め、データ共有を `SystemData` 構造体に一本化。ループは「入力 → ロジック → 出力」の3フェーズに固定し、データフローを単方向にする。

**移植性**: コア層（`IModule`, `ModuleTimer`）はプロジェクト非依存。`SystemData` の前方宣言のみを使用し、具体的な型定義を持たない。

---

## レイヤー構成

```
コア層（プロジェクト非依存）
  lib/ModuleCore/IModule.h        ← インターフェース定義
  lib/ModuleCore/ModuleTimer.h    ← millis()ベースノンブロッキングタイマー

プロジェクト層（プロジェクト固有）
  include/SystemData.h            ← 全モジュールのDataを集約
  include/ProjectConfig.h         ← 全モジュールのConfigインスタンス（ピンアサイン）
  src/main.cpp                    ← モジュール配列・3フェーズループ
  lib/{ModuleName}/               ← 個別モジュール実装
```

---

## IModule インターフェース

```cpp
struct SystemData;  // 前方宣言のみ（プロジェクト依存を避ける）

class IModule {
public:
    bool enabled = true;

    virtual bool init() = 0;                        // 初期化（純粋仮想）
    virtual void updateInput(SystemData& data) {}   // 入力フェーズ
    virtual void updateOutput(SystemData& data) {}  // 出力フェーズ
    virtual void deinit() {}                        // リソース解放
    virtual ~IModule() {}
};
```

- `init()` のみ純粋仮想（`= 0`）。すべてのモジュールが実装必須。
- `updateInput()` / `updateOutput()` / `deinit()` はデフォルト空実装。必要なものだけオーバーライド。

---

## モジュールの入出力分類

| 分類 | オーバーライド | 配列 | 例 |
|------|----------------|------|-----|
| 入力専用 | `updateInput()` のみ | `inputModules[]` | IMU, Button, Camera, Battery, Encoder |
| 出力専用 | `updateOutput()` のみ | `outputModules[]` | LED, Servo, Buzzer, TFT, Motor |
| 入出力 | 両方 | 両方の配列に含める | BLE, LCD+タッチ |
| 内部専用 | — | 配列に含めない | DriveMotor（ChassisModule内部で保持・制御） |

---

## 3フェーズ実行モデル

```cpp
void loop() {
    // 1. 入力フェーズ: センサー → SystemData
    for (int i = 0; i < INPUT_COUNT; i++) {
        if (inputModules[i]->enabled)
            inputModules[i]->updateInput(systemData);
    }

    // 2. ロジックフェーズ: SystemDataを読み書き（判断・変換）
    applyPattern(systemData);

    // 3. 出力フェーズ: SystemData → ハードウェア
    for (int i = 0; i < OUTPUT_COUNT; i++) {
        if (outputModules[i]->enabled)
            outputModules[i]->updateOutput(systemData);
    }
}
```

**制約**:
- 入力モジュールは `Data` を書き込む。出力モジュールは `Data` を読み込む。クロス参照禁止。
- `SystemData` への書き込みはフェーズ内のみ。割り込み・別タスクから直接触らない。
- Config変更（セッター等）はロジックフェーズ内のみ。
- 入出力両方のモジュールは `inputModules[]` と `outputModules[]` の**両方**に含める。

---

## モジュールの構造（.h/.cpp 分離）

### ヘッダー（宣言）

```cpp
// FooModule.h
#pragma once
#include <Arduino.h>
#include "IModule.h"
#include "ModuleTimer.h"

struct FooConfig {
    uint8_t pin;
    uint32_t intervalMs;
};

struct FooData {
    float value = 0.0f;   // デフォルト値必須
    bool isValid = false; // デフォルト値必須
};

class FooModule : public IModule {
public:
    explicit FooModule(const FooConfig& config);
    bool init() override;
    void updateInput(SystemData& data) override;  // 入力モジュールの場合
    // void updateOutput(SystemData& data) override; // 出力モジュールの場合
private:
    FooConfig   _config;
    ModuleTimer _timer;
};
```

**ルール**:
- `.h` で `SystemData.h` をインクルード**しない**（循環依存防止）
- バスポインタ（`TwoWire*`, `SPIClass*`）はコンストラクタ引数で受け取りメンバ保持

### 実装（.cpp）

```cpp
// FooModule.cpp
#include "FooModule.h"
#include "SystemData.h"  // ここでインクルード
// ProjectConfig.h はインクルードしない

bool FooModule::init() {
    pinMode(_config.pin, INPUT);
    _timer.setTime();
    return true;
}

void FooModule::updateInput(SystemData& data) {
    if (_timer.getNowTime() < _config.intervalMs) return;
    _timer.setTime();
    data.foo.value = readHardware();
    data.foo.isValid = true;
}
```

---

## SystemData の集約

```cpp
// include/SystemData.h
#pragma once
#include "LedModule.h"
#include "Mpu6500Module.h"
#include "CameraModule.h"

struct SystemData {
    LedData     led;
    Mpu6500Data mpu;
    CameraData  camera;
};
```

モジュールを追加するたびに `SystemData.h` に `{Module}Data` フィールドを追加する。

---

## ProjectConfig.h の役割

全モジュールの Config インスタンスをここで定義する。モジュール `.cpp` からはインクルードしない。

```cpp
// include/ProjectConfig.h
#pragma once
#include "SystemData.h"

// 共有バスピン（特定モジュールに属さない）
constexpr int SPI_MOSI_PIN = 38;
constexpr int SPI_MISO_PIN = 40;
constexpr int SPI_SCK_PIN  = 39;
constexpr int I2C_SDA_PIN  = 41;
constexpr int I2C_SCL_PIN  = 42;

// モジュール固有のピンはConfig内に直書き
const LedConfig LED_CONFIG = { .ledPin = 2 };
const Mpu6500Config MPU6500_CONFIG = { .address = 0x68, .sampleIntervalMs = 20 };
```

---

## 通信バスパターン（SPI / I2C）

```cpp
// main.cpp
static TwoWire mpuWire = TwoWire(0);

void setup() {
    mpuWire.begin(I2C_SDA_PIN, I2C_SCL_PIN);  // bus.begin() は全 init() より前
    initModules(...);
}

// モジュール側
Mpu6500Module::Mpu6500Module(const Mpu6500Config& cfg, TwoWire* wire)
    : _config(cfg), _wire(wire) {}
// init() 内で bus.begin() は呼ばない
```

- バスポインタはConfig構造体に含めず、コンストラクタ引数で渡す
- SPI使用時は `beginTransaction()` / `endTransaction()` で排他制御

---

## スレッドセーフティ

割り込み・別FreeRTOSタスク・BLEコールバックからの `SystemData` 直接アクセスは禁止。

```cpp
// 割り込み/別タスク側
volatile bool _hasNewData = false;
SensorRaw _buffer;

void ISR_or_Task() {
    _buffer = readRaw();
    _hasNewData = true;
}

// updateInput() 内
void FooModule::updateInput(SystemData& data) {
    if (_hasNewData) {
        _hasNewData = false;
        data.foo.value = convert(_buffer);
    }
}
```

---

## init失敗とリカバリ

```cpp
// setup() での初期化（MAX_RETRY回リトライ）
for (int r = 0; r < MAX_RETRY; r++) {
    if (module.init()) break;
    delay(100);
}
if (!success) module.enabled = false;

// ロジックフェーズでの定期再試行
if (!module.enabled && retryTimer.getNowTime() > 5000) {
    retryTimer.setTime();
    if (module.init()) module.enabled = true;
}
```

---

## 命名規則

| 要素 | 規則 | 例 |
|------|------|-----|
| Config型 | `{Module}Config` | `LedConfig`, `Mpu6500Config` |
| Configインスタンス | `{MODULE}_CONFIG` | `LED_CONFIG`, `MPU6500_CONFIG` |
| Data型 | `{Module}Data` | `LedData`, `Mpu6500Data` |
| ログ | `[ModuleName] msg` | `[Camera] init failed` |

---

## platformio.ini の必須設定

```ini
build_flags =
    -I include   ; lib/ 内から include/ を参照するために必須
```

---

## 新規モジュール追加チェックリスト

1. `lib/{Name}Module/{Name}Module.h` — Config/Data構造体 + クラス宣言
2. `lib/{Name}Module/{Name}Module.cpp` — `init()` / `updateInput()` or `updateOutput()` 実装
3. `include/SystemData.h` — `{Name}Data` フィールドを追加
4. `include/ProjectConfig.h` — `{NAME}_CONFIG` インスタンスを追加
5. `src/main.cpp` — インスタンス生成 → `inputModules[]` or `outputModules[]` に追加
