# 6. 共通インターフェース方針

本章は EMA（Embedded-Module-Architecture）の主要インターフェースを「方針レベル」で示す。
各 API の具体的シグネチャと実装例は第 10 章で詳述する。

> **正本**: [`../../architecture_reference/ARCHITECTURE.md`](../../architecture_reference/ARCHITECTURE.md) /
> [`../../architecture_reference/CLAUDE.md`](../../architecture_reference/CLAUDE.md) /
> `pdf/03_設計仕様書.pdf`。本章はこれらをハッカソン文脈に合わせて引用・要約したもの。

## 6.1 3 フェーズループ（EMA 標準）

すべてのノードで `loop()` は **入力フェーズ → ロジックフェーズ → 出力フェーズ** の順で
実行する。EMA の流儀では、入力／出力フェーズは **モジュール配列の for ループ** として
書き、ロジックフェーズは **`applyPattern(systemData)` 関数** として書く。

```cpp
// firmware/node_XX/src/main.cpp（抜粋）
void loop() {
    // 1. 入力フェーズ: センサー / UDP 受信 → SystemData
    for (int i = 0; i < INPUT_COUNT; i++) {
        if (inputModules[i]->enabled)
            inputModules[i]->updateInput(systemData);
    }

    // 2. ロジックフェーズ: SystemData を読み書き（判断・変換）
    applyPattern(systemData);

    // 3. 出力フェーズ: SystemData → ハードウェア / UDP 送信
    for (int i = 0; i < OUTPUT_COUNT; i++) {
        if (outputModules[i]->enabled)
            outputModules[i]->updateOutput(systemData);
    }
}
```

**EMA の制約（厳守）**:

- 入力モジュールは `SystemData` を **書き込む**。出力モジュールは **読み込む**。クロス参照禁止
- `SystemData` への書き込みはフェーズ内のみ。割り込み・別タスクから直接触らない
- Config 変更（セッター呼び出し）は **ロジックフェーズ内のみ**
- 入出力両方を持つモジュール（例: `OrcNetModule`）は `inputModules[]` と `outputModules[]` の **両方** に含め、配列の並び順で「先に受信」「最後に送信」を制御する

## 6.2 `IModule` インターフェース（EMA の核）

EMA で定義された、すべてのハードウェアモジュールが実装する抽象基底クラス。

```cpp
struct SystemData;  // 前方宣言のみ（プロジェクト依存を避ける）

class IModule {
public:
    bool enabled = true;

    virtual bool init() = 0;                        // 初期化（純粋仮想）
    virtual void updateInput(SystemData& data) {}   // 入力フェーズ（デフォルト空）
    virtual void updateOutput(SystemData& data) {}  // 出力フェーズ（デフォルト空）
    virtual void deinit() {}                        // リソース解放（デフォルト空）
    virtual ~IModule() {}
};
```

| 観点 | EMA のルール | 本プロジェクトでの解釈 |
|---|---|---|
| 初期化 | `init()` で H/W 初期化、`bool` を返す（失敗時 false） | `setup()` で各モジュールの `init()` を呼び、失敗時はリトライ → それでも失敗なら `enabled = false`（第 11.x で詳述） |
| 入力フェーズ | `updateInput(SystemData&)` を入力モジュール / 入出力モジュールがオーバーライド | IMU・UDP 受信側で実装 |
| 出力フェーズ | `updateOutput(SystemData&)` を出力モジュール / 入出力モジュールがオーバーライド | UDP 送信・LED 表示で実装 |
| リソース解放 | `deinit()` は必要なモジュールだけオーバーライド | 本プロジェクトでは BLE/カメラ等を使わないため基本的に未使用（`OrcNetModule` で WiFi 切断時の再接続用に検討余地あり） |

## 6.3 モジュールの入出力分類

EMA に従い、各モジュールは以下の 4 分類のいずれかに属する。

| 分類 | オーバーライド | 配列 | 本プロジェクトでの例 |
|---|---|---|---|
| 入力専用 | `updateInput()` のみ | `inputModules[]` | `ImuModule`（node_01）、`OrcReceiverModule`（node_02〜05） |
| 出力専用 | `updateOutput()` のみ | `outputModules[]` | `OrcSenderModule`、`StatusLedModule` |
| 入出力 | 両方 | 両配列に含める | `OrcNetModule`（WiFi 接続維持 + 受信ポーリング + 送信） |
| 内部専用 | — | 配列に含めない | 該当なし |

## 6.4 `SystemData` 集約方針

EMA では、モジュール間の状態共有を `SystemData` 構造体に **`{Module}Data` フィールドを
並べる方式**で一元管理する。

```cpp
// firmware/node_01/include/SystemData.h（イメージ）
#pragma once
#include "ImuModule.h"
#include "OrcReceiverModule.h"
#include "BeatLogicData.h"   // applyPattern() の中間状態を持つ場合は別ヘッダで定義

struct SystemData {
    ImuData          imu;
    OrcReceiverData  receiver;
    BeatLogicData    beat;     // 拍検出 / テンポ推定の結果（applyPattern が書く）
    // ...
};
```

**ルール**:

- モジュールが他モジュールを直接呼ぶことは禁止。すべて `SystemData` 経由
- 「書き込み責務」と「読み取り責務」を役割ごとに明確に分ける（例: `ImuModule` が `data.imu` に書き、`applyPattern()` が `data.imu` を読んで `data.beat` に書き、`OrcSenderModule` が `data.beat` を読んで送信）
- 各 `{Module}Data` のメンバには **デフォルト値を必ず明示** する（`bool isValid = false;` 等）
- `applyPattern()` の中間結果は専用の `{Logic}Data` 構造体（例: `BeatLogicData`）として `SystemData` に集約してよい

## 6.5 `ProjectConfig` 集約方針

EMA では、各モジュールの設定は **`{Module}Config {MODULE}_CONFIG = {…};` インスタンス
として `include/ProjectConfig.h` に集約**する。

```cpp
// firmware/node_01/include/ProjectConfig.h（イメージ）
#pragma once
#include "SystemData.h"

// 共有バスピン（特定モジュールに属さない）
constexpr int I2C_SDA_PIN = 18;
constexpr int I2C_SCL_PIN = 19;

// モジュール固有のピン・閾値はConfigインスタンスのリテラルに直書き
const ImuConfig          IMU_CONFIG          = { .address = 0x6A, .sampleIntervalMs = 5 };
const OrcNetConfig       ORC_NET_CONFIG      = { .ssid = "OrchestraAP", .pass = "...", .listenPort = 5001 };
const OrcSenderConfig    ORC_SENDER_CONFIG   = { .ctrlIntervalMs = 50 };
const StatusLedConfig    STATUS_LED_CONFIG   = { .pin = LED_BUILTIN, .blinkIntervalMs = 500 };
```

- モジュール固有のピンは `constexpr` 単体定数にせず、Config インスタンスのリテラルに **直書き**
- 共有バスピン（SPI_MOSI/MISO/SCK、I2C_SDA/SCL 等）のみ `constexpr` 単体定数として定義してよい（`main.cpp` の `bus.begin()` で直接使用するため）
- モジュール `.cpp` から `ProjectConfig.h` を include しない（Config はコンストラクタ引数で渡す）

## 6.6 `ModuleTimer`

`millis()` ベースのノンブロッキング周期判定ユーティリティ。EMA コア層
（`firmware/common/lib/ModuleCore/ModuleTimer.h`）で提供される。

| 用途 | 例 |
|---|---|
| サンプリング周期 | IMU を 200 Hz で読む |
| 送信周期 | CTRL を 20 Hz で送る |
| ハートビート | StatusLed を 0.5 Hz で点滅 |
| 不応期 | 拍検出後 250 ms は再検出を抑制 |

`delay()` は禁止（特に `setup()` 中の起動シーケンス以外では使わない）。詳細 API は §10.2。

## 6.7 通信プロトコル概要（UDP、CTRL / BEAT / NOTE）

指揮者 → 楽器 → PC の 3 系統で、3 種類のメッセージを流す。詳細なパケット構造は
第 10.3 章で定義する。本節では各メッセージの位置付けのみ示す。

| メッセージ | 送信元 → 宛先 | 送信契機 | 性質 | 役割 |
|---|---|---|---|---|
| **CTRL** | node_01 → node_02〜05（ブロードキャスト） | 定期（例: 20 Hz） | 冪等・状態送信 | BPM・velocity・演奏状態を通知 |
| **BEAT** | node_01 → node_02〜05（ブロードキャスト） | 拍検出時（不定期） | イベント・即時性重視 | 楽譜ポインタを前進させるトリガ |
| **NOTE** | node_02〜05 → PC(ユニキャスト) | 音符発火時 | イベント | Processing に発音を依頼 |

**設計原則**:

- CTRL は冪等性を持ち、取りこぼしても次回送信で整合する（パケロス耐性を通信方針側で確保）
- BEAT は即時性が必要なので、送信失敗時のリカバリは **楽譜側で内挿**する（直前の BPM から
  次拍の予測時刻を計算し、その時刻を過ぎても BEAT が来なければ自走する）
- NOTE は楽器 → PC で 1 経路。楽譜に従って必ず送出する
- すべてに共通ヘッダ（プロトコルバージョン・メッセージ種別・シーケンス番号）を付ける

## 6.8 命名規則・ログ書式（EMA 準拠）

| 要素 | 規則 | 例 |
|---|---|---|
| Config 型 | `{Module}Config` | `ImuConfig`, `OrcNetConfig` |
| Config インスタンス | `{MODULE}_CONFIG` | `IMU_CONFIG`, `ORC_NET_CONFIG` |
| Data 型 | `{Module}Data` | `ImuData`, `OrcReceiverData` |
| ログ | `[ModuleName] msg` | `[Imu] init failed`, `[OrcNet] reconnecting` |
| デバッグログ切替え | `#ifdef DEBUG` 等で切り替え可能に | — |

これらは EMA の正本（[`../../architecture_reference/CLAUDE.md`](../../architecture_reference/CLAUDE.md)
「命名規則」「ログ出力フォーマット」）に従う。
