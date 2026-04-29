# CLAUDE.md

> **本ファイルは、外部リポジトリ Embedded-Module-Architecture からの複製です。**
>
> - **採用元**: <https://github.com/takushio2525/Embedded-Module-Architecture>
> - **原本パス**: `CLAUDE.md`
> - **取り込み日**: 2026-04-24
> - **編集禁止**: このファイルは上流の同期スナップショットです。修正が必要な場合は
>   上流リポジトリ側で行い、本フォルダへ再同期してください。
> - **本ハッカソンでの位置付け**: AI（Claude Code 等）が `firmware/` 配下のコードを
>   触るときに参照する**実装ルール詳細指示**。命名規則・ファイル分割・循環依存回避等を
>   厳守する根拠となる。

---

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

組み込みシステム向けModuleインターフェース設計パターンのリファレンス実装。PlatformIO + Arduino フレームワークを使用。

リポジトリには2つのプロジェクトが含まれる:
- `sample/` — 設計パターンの構造説明用サンプル（動作未確認）
- `verified/` — 実機で動作確認済みのプロジェクト

各プロジェクトは完全に自己完結しており、フォルダ単体でPlatformIOプロジェクトとして使用できる。

## アーキテクチャ更新フロー

アーキテクチャの変更は以下の順序で反映する:

1. **verified/ で実装・検証** — 実機で動作確認する
2. **CLAUDE.md を更新** — AI指示（アーキテクチャルール）を実装に合わせる
3. **sample/ に反映** — サンプルコードを新アーキテクチャに合わせる
4. **doc/ に反映** — LaTeX仕様書を更新する

**現在のステータス**: `updateInput()`/`updateOutput()` 分離アーキテクチャで全体統一済み（verified/ → sample/ → doc/ → CLAUDE.md）。

### sample/ と verified/ の技術差異

| 項目 | sample/ | verified/ | 理由 |
|---|---|---|---|
| I2C | Arduino Wire (`TwoWire*`) | ESP-IDF レガシー I2C API (`driver/i2c.h`) | esp_camera の SCCB が Wire と共存不可のため |
| LCD | TFT_eSPI | LovyanGFX | verified/ はタッチ統合が必要だったため |
| Arduino Core | v2.x (`ledcSetup`/`ledcAttachPin`) | v3.x (`ledcAttach`) | verified/ は最新プラットフォームで検証 |

doc/ と sample/ では Arduino Wire を標準として記載する。ESP-IDF I2C API は ESP32 + esp_camera 使用時の例外対応として扱う。

## ビルドコマンド

```bash
# サンプルプロジェクトのビルド
cd sample/
pio run -e esp32-s3-cam-n16r8

# ビルド＋書き込み
pio run -e esp32-s3-cam-n16r8 -t upload

# シリアルモニター（115200bps）
pio device monitor
```

## ドキュメント（LaTeX仕様書）

DevContainer内でVSCode + LaTeX Workshopを使いコンパイル。

- エントリーポイント: `doc/main.tex`
- セクションファイル: `doc/sections/`

## アーキテクチャ

### コア層（プロジェクト非依存）

各プロジェクトの `lib/ModuleCore/` 以下の2ファイルで構成。他プロジェクトにそのまま流用可能。

| ファイル | 役割 |
|---|---|
| `lib/ModuleCore/IModule.h` | `IModule` インターフェース |
| `lib/ModuleCore/ModuleTimer.h` | `millis()` ベースのノンブロッキングタイマー |

`IModule` は `SystemData` の前方宣言のみを使用し、プロジェクト固有の型に依存しない。メソッドは `init()`、`updateInput(SystemData& data)`、`updateOutput(SystemData& data)`、`deinit()` の4つ（`updateInput`/`updateOutput`/`deinit` はデフォルト空実装）。入力のみのモジュールは `updateInput` のみ、出力のみは `updateOutput` のみ、入出力両方を持つモジュール（BLE、LCD+タッチ等）は両方をオーバーライドする。

### プロジェクト層（プロジェクト固有）

| ファイル | 役割 |
|---|---|
| `include/SystemData.h` | 各モジュールの `Data` 構造体を集約した `SystemData` 構造体 |
| `include/ProjectConfig.h` | 共有バスピン定義 + 全モジュールのConfigインスタンス |
| `src/main.cpp` | モジュール配列の定義・ループ制御 |
| `lib/{ModuleName}/` | 個別ハードウェアモジュールの実装 |

各モジュールのヘッダーファイル内で `{Module}Config` と `{Module}Data` の型を定義し、`ProjectConfig.h` でConfigインスタンスの値を定義する。

### ピン定義ルール

- **モジュール固有のピン**（CSピン、信号ピン、カメラのDVPピン等）は `constexpr` 単体定数にせず、Configインスタンスのリテラルに**直書き**する
- 外部からモジュールのピンを参照する場合は `SERVO_CONFIG.pin` のようにConfig構造体経由でアクセスする（「どのモジュールのピンか」が常に明確になる）
- **共有バスピン**（SPI_MOSI/MISO/SCK、I2C_SDA/SCL等）は特定モジュールに属さない共有インフラのため、`constexpr` 単体定数として定義してよい（`main.cpp` の `bus.begin()` で直接使用するため）

### モジュールのファイル構成（.h/.cpp分離）

各モジュールは `.h`（宣言）と `.cpp`（実装）に分離する。`SystemData` の循環依存を回避するための必須ルール。

- **`.h`**: `<Arduino.h>` + `"IModule.h"` をインクルード。Config/Data構造体の定義、`struct SystemData;` の前方宣言、クラス宣言（プロトタイプのみ）
- **`.cpp`**: `"SystemData.h"` をインクルードし、メソッドを実装（`ProjectConfig.h` はインクルードしない）
- ヘッダーでは `SystemData.h` をインクルードしない（循環依存を防ぐため）
- `platformio.ini` の `build_flags` に `-I include` を追加する（`lib/` 内から `include/` を参照するため）

### 3フェーズ実行モデル

`loop()` は必ず以下の順序で実行する：

1. **入力フェーズ**: 全 `inputModules[]` の `updateInput(systemData)` を順次呼び出し、センサー値を `SystemData` へ書き込む
2. **ロジックフェーズ**: `applyPattern(systemData)` 等の関数で入力データを読み、出力データを書き換える
3. **出力フェーズ**: 全 `outputModules[]` の `updateOutput(systemData)` を順次呼び出し、ハードウェアを制御する

入出力両方を持つモジュール（BLE、LCD+タッチ等）は `inputModules[]` と `outputModules[]` の**両方に含める**。配列の並び順がフェーズ内の実行順序を決定する（例: BLE受信を先に、BLE送信は最後に、など順序を制御可能）。

`setup()` では全ユニークモジュールを1回だけ `init()` する（両配列に含まれるモジュールの重複initを避ける）。

### 命名規則

| 要素 | 規則 | 例 |
|---|---|---|
| Config構造体の型名 | `{Module}Config` | `LedConfig`, `TempSensorConfig` |
| Configインスタンス名 | `{MODULE}_CONFIG` (大文字) | `LED_CONFIG`, `TEMP_CONFIG` |
| Data構造体の型名 | `{Module}Data` | `LedData`, `TempData` |

### 通信バスパターン（SPI / I2C）

- **SPI**: `SPIClass` インスタンスを `main.cpp` のグローバルスコープで生成し、`setup()` 内で `bus.begin()` を呼ぶ。バスポインタはコンストラクタ引数でモジュールに渡す。`beginTransaction()` / `endTransaction()` で排他制御する
- **I2C**: Arduino Wire ライブラリ（`TwoWire*`）を標準とする。`TwoWire` インスタンスを `main.cpp` のグローバルスコープで生成し、`setup()` 内で `wire.begin(SDA, SCL)` を呼ぶ。バスポインタはコンストラクタ引数でモジュールに渡す。ただし ESP32 + esp_camera 使用時は Wire が SCCB のレガシー I2C ドライバと共存不可のため、ESP-IDF レガシー I2C API（`driver/i2c.h`）を使用する（verified/ がこのケース）
- バスポインタ/ポート番号はConfig構造体に含めず、コンストラクタの引数でモジュールに渡す
- モジュールの `init()` でバス初期化を呼ばない（CSピン設定等のみ）

### モジュール実装の要点

- コンストラクタは `const {Module}Config&` でConfigを受け取り、`_config` としてコピー保持する
- ピン番号はハードコードせず `_config` 経由でアクセスする
- `init()` は `bool` を返す（失敗時は `false`）
- `updateInput()`/`updateOutput()` でエラーが発生した場合は `SystemData` のサブ構造体にエラーフラグを設定する
- 周期実行にはメンバ変数として `ModuleTimer` を使い `delay()` を使用しない
- 各 `{Module}Data` 構造体はメンバにデフォルト値を明示する（例：`bool isValid = false;`、`float temperature = -999.0f;`）

### deinit()パターン

- `IModule` に `deinit()` メソッドがある（デフォルト空実装）
- リソース解放が必要なモジュールのみオーバーライドする
- スリープ突入前やモジュール停止時に呼び出す

### モジュールの入出力分類

各モジュールは以下の3種類に分類される。オーバーライドするメソッドで役割が明示される。

| 分類 | オーバーライド | 配列 | 例 |
|---|---|---|---|
| 入力専用 | `updateInput()` のみ | `inputModules[]` | IMU, カメラ, SD |
| 出力専用 | `updateOutput()` のみ | `outputModules[]` | サーボ, LED |
| 入出力 | 両方 | 両方の配列に含める | BLE, LCD+タッチ |

### スレッドセーフティ

- 3フェーズループの外（割り込み / 別タスク / BLEコールバック等）から `SystemData` に直接触らない
- 外部からのデータは**モジュール内部バッファ + `volatile` フラグ方式**で受け渡す
  - 別タスク/割り込み → モジュール内部バッファに書き込み + `volatile` フラグを `true` にする
  - `updateInput()` でフラグを確認し、バッファから `SystemData` にコピーする
- 割り込みでもマルチタスクでも同じルールを適用する

### init失敗後の復帰

- `init()` 失敗でモジュールを `enabled = false` にした後、ロジックフェーズで定期的に `init()` を再試行する
- 再init成功時に `enabled = true` に復帰させる

### ログ出力フォーマット

- フォーマット: `[モジュール名] メッセージ`（例：`[Camera] init failed: timeout`）
- デバッグログは `#ifdef DEBUG` 等で切り替え可能にする

### Config変更タイミング

- Config変更（セッター呼び出し）は**ロジックフェーズでのみ**行う
- BLE等の外部からのConfig変更要求は `SystemData` 経由でロジックフェーズに渡す

### メモリ管理

- 大容量バッファ（カメラフレーム等）はPSRAMの使用を推奨する
