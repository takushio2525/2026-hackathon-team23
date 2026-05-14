---
title: Embedded-Module-Architecture
description: ファーム全体で採用している組み込み設計パターンの解説
sidebar:
  order: 2
---

:::note[この章で分かること]
- なぜ「3 フェーズループ」を採用しているか
- `IModule`・`SystemData`・`ProjectConfig` がどう連携するか
- 新しい機能を足したいときにどこを触ればいいか
:::

:::tip[読了目安]
**約 8 分**。前提: C++ の基本的な構文（`struct` / クラス / `namespace`）。
:::

リファレンス実装: <https://github.com/takushio2525/Embedded-Module-Architecture>
本プロジェクトで EMA を採用した決定経緯: [ADR-0005](/decisions/0005-firmware-embedded-module-architecture/)

## なぜパターンを統一するのか

`setup()` と `loop()` に処理を全部書く Arduino スタイルは、1 人が 1 ファイルを書く分には
最速だが、**チーム開発では即破綻する**:

- ループ内で入力・制御・出力のコードが混ざってテストできない
- ノード間で同じ機能（UDP 受信・LED 表示）を別実装してしまう
- グローバル変数が増えて担当者以外が読めなくなる

EMA はこれを **共通の設計パターンを最初から固定** することで防ぐ。
複数人が同じノードを触っても境界が崩れない。

## 3 フェーズループ

すべてのノードは `loop()` を **入力 → ロジック → 出力** の順で構成する。

```cpp
void loop() {
    // ① 入力フェーズ
    for (auto* m : gInputs)  if (m->enabled) m->updateInput(gData);

    // ② ロジックフェーズ
    applyPattern(gData);

    // ③ 出力フェーズ
    for (auto* m : gOutputs) if (m->enabled) m->updateOutput(gData);
}
```

- **入力モジュール** は `updateInput(SystemData&)` のみ実装する（外界から `gData` に書く）
- **出力モジュール** は `updateOutput(SystemData&)` のみ実装する（`gData` から外界に出す）
- **`applyPattern(SystemData&)`** がロジック。`gData` のフィールドだけを見て状態を更新する

**モジュール同士の直接呼び出しは禁止**。モジュール A の出力を B が使いたいときは、
必ず `SystemData` のフィールド経由で渡す。

## `IModule` 抽象基底

各機能は `IModule` を継承する。実体は `firmware/test_v2/common/lib/ModuleCore/IModule.h` に
ある。

```cpp
class IModule {
public:
    bool enabled = false;

    virtual bool init() = 0;                          // 起動時 1 回
    virtual void updateInput(SystemData&)  {}         // 入力フェーズ
    virtual void updateOutput(SystemData&) {}         // 出力フェーズ
    virtual void deinit() {}                          // 終了時（任意）
};
```

`init()` で初期化に成功したら `enabled = true` となり、以降フェーズで呼ばれる。
失敗時は `enabled = false` のまま無視される（他のモジュールに影響しない）。

## `SystemData` — モジュール間共有データ

ノード内の **全モジュールが共有する状態** を 1 つの `struct` に集約する。
モジュール本体には状態を持たせず、すべて `SystemData` に書く。

```cpp
// firmware/test_v2/node_01/include/SystemData.h
struct SystemData {
    ImuData             imu;
    OrcNetData          orcNet;
    OrcSenderData       sender;
    StatusLedData       led;
    BeatLogicData       beat;
    TempoLogicData      tempo;
    CalibrationData     calibration;
    ConductorStateData  conductor;
};
```

各サブ構造体（`ImuData`、`OrcNetData` 等）は、それぞれのモジュール側のヘッダで定義する。

### なぜグローバル `struct` 1 個に集約するのか

- どこに何があるか **1 ファイルで一覧できる**
- ロジックは `SystemData&` を受け取るだけで全部見える（依存注入が要らない）
- テストでは `SystemData` をモックすれば全モジュールを独立に検証できる

## `ProjectConfig` — ノード固有設定

ピン配置・閾値・WiFi 設定など、ノードごとに異なる **定数値** は `ProjectConfig.h` に
集約する。モジュール本体（`src/*.cpp`）にハードコードしない。

```cpp
// firmware/test_v2/node_01/include/ProjectConfig.h（抜粋）
constexpr uint8_t I2C_SDA_PIN = 5;
constexpr uint8_t I2C_SCL_PIN = 6;

inline const ImuConfig IMU_CONFIG = {
    /*address=*/          0x68,
    /*sampleIntervalMs=*/ 5,
    /*accelRangeG=*/      4,
    /*gyroRangeDps=*/     2000,
};

namespace logic_params {
    constexpr float BEAT_DYN_THRESHOLD_G = 1.20f;
    constexpr uint32_t BEAT_REFRACTORY_MS = 350;
    // ...
}
```

これにより、楽器ノードを増やしたいときは **`ProjectConfig.h` の数行だけ差し替え** て
他は全部コピーで動く。

## 共通層（`firmware/test_v2/common/lib/`）

5 台共通で使うライブラリは `common/lib/` 配下に置き、各ノードの `platformio.ini` から
`lib_extra_dirs = ../common/lib` で参照する。

| ライブラリ | 中身 |
|---|---|
| `ModuleCore/` | `IModule` 抽象基底 + `ModuleTimer`（周期実行・非ブロッキング） |
| `OrcProtocol/` | CTRL / BEAT / NOTE の 20 B パケット定義（`magic=0x4F52`） |
| `OrcNetModule/` | WiFi UDP マルチキャストの送受信 |
| `StatusLedModule/` | 状態に応じた LED 点滅出力 |
| `SerialDebug/` | `SERIAL_DEBUG` マクロで切替えるシリアルデバッグマクロ |

test_v1 にも同じ構成の `firmware/test_v1/common/lib/` がある（バージョンごとに独立）。

## ノード固有モジュール

共通層以外のモジュールは、ノードの `src/` 配下に置く。例:

| ノード | 固有モジュール例 |
|---|---|
| node_01（指揮者） | `ImuModule`、`OrcSenderModule` |
| node_02〜04（楽器） | `ScoreModule`、`NoteEmitterModule`、`OrcReceiverModule` |

これらは `firmware/test_v2/<node>/lib/<ModuleName>/` 配下にライブラリとして置くことが多い。

## 新しい機能を足すには

| やりたいこと | 触る場所 |
|---|---|
| 新しい入力デバイス | `IModule` 継承クラスを作り、`updateInput()` を実装。`SystemData` に出力フィールドを追加 |
| 新しい出力（LED / アクチュエータ） | `IModule` 継承クラスで `updateOutput()` を実装 |
| 拍検出ロジックを調整 | `node_01/include/ProjectConfig.h` の `logic_params` 名前空間の定数だけ |
| 通信パケット形式を変える | `common/lib/OrcProtocol/` を編集 + `.agent/api.md` を同期更新 |
| ノード固有のピンを変える | 該当ノードの `ProjectConfig.h` だけ |

詳細チェックリストは EMA リファレンスの `ARCHITECTURE.md` 参照。

## 守るべきルール（コードレビュー時の観点）

1. **モジュール同士の直接呼び出し禁止**: `gImu.read()` を `gLed` から呼ばない。`SystemData` 経由
2. **ハードコード禁止**: 数値リテラルは `ProjectConfig.h` か `logic_params` に
3. **状態はモジュールに持たせない**: メンバ変数は設定値のみ。状態は `SystemData`
4. **3 フェーズに混ぜない**: ロジックを `updateInput()` に書かない、出力を `applyPattern()` に書かない
5. **新規モジュールは `init()` を必ず実装**: 失敗時は `false` を返す

## 次に読むべきページ

- 通信プロトコル → [通信プロトコル（UDP）](/architecture/protocol/)
- 拍検出ロジック → [同期戦略（±20ms）](/architecture/sync/)
- 実コードの歩き方 → [firmware の歩き方](/code/firmware/)
