# 9. 技術スタック

| レイヤ | 採用技術 | バージョン / 備考 |
|---|---|---|
| MCU | Arduino UNO R4 WiFi | Renesas RA4M1 + ESP32-S3（WiFi 子機） |
| 開発ボード搭載センサ | 内蔵 IMU（LSM6DSOX 相当） | 6 軸: 加速度 3 軸 + 角速度 3 軸 |
| フレームワーク | Arduino Framework | PlatformIO 経由で参照 |
| 言語 | C++（C++11） | `arduino-core` がサポートする範囲 |
| ビルドツール | PlatformIO | `platform = renesas-ra`, `board = uno_r4_wifi`、`build_flags = -I include` 必須 |
| 外部ライブラリ | `Arduino_LSM6DSOX` | IMU 読み取り |
| 外部ライブラリ | `WiFiS3` | UNO R4 WiFi 標準の WiFi / UDP（ボードコア同梱） |
| **設計パターン** | **Embedded-Module-Architecture（EMA）** | 塩澤本人作成のリファレンス。本書全章の前提（ADR-0005）。<br>採用元: <https://github.com/takushio2525/Embedded-Module-Architecture><br>正本: [`../../architecture_reference/`](../../architecture_reference/) |
| 共通層実装 | EMA コア層（`ModuleCore` = `IModule.h` + `ModuleTimer.h`） | EMA リファレンスの `lib/ModuleCore/` をそのまま採用。`firmware/common/lib/ModuleCore/` に配置 |
| 自作ライブラリ | `OrcProtocol`（CTRL/BEAT/NOTE のシリアライズ）、`OrcNetModule`（WiFi+UDP の `IModule` 実装） | 本設計書第 10 章で定義。EMA の通信バスパターン（`main.cpp` でバス初期化）に従う |
| ネットワーク | UDP over IEEE 802.11（WiFi） | ローカル AP 経由、ブロードキャスト + ユニキャスト |
| 構成管理 | Git（GitHub） | リポジトリ `2026-hackathon-team23` |
| CI | GitHub Actions（`pio-build.yml`） | `firmware/` 変更時に全ノードをビルド |

**依存ライブラリの追加はしない方針**（Arduino 標準 + EMA コア層 + 自作通信層のみ）。
理由: ライブラリ追加の意思決定は CLAUDE.md ルールで「理由説明が必要」となっており、
本プロジェクトで標準以外を引く強い必要性が現時点で無いため。

## 9.1 EMA との対応

| EMA リファレンスの要素 | 本プロジェクトでの所在 |
|---|---|
| `lib/ModuleCore/IModule.h` | `firmware/common/lib/ModuleCore/IModule.h`（EMA からそのまま流用） |
| `lib/ModuleCore/ModuleTimer.h` | `firmware/common/lib/ModuleCore/ModuleTimer.h`（EMA からそのまま流用） |
| `include/SystemData.h` | `firmware/node_XX/include/SystemData.h`（ノード別） |
| `include/ProjectConfig.h` | `firmware/node_XX/include/ProjectConfig.h`（ノード別） |
| `src/main.cpp` の 3 フェーズループ | `firmware/node_XX/src/main.cpp`（§11.9 / §12.6） |
| sample/ の `LedModule` / `Mpu6500Module` 等 | `ImuModule`（IMU）、`StatusLedModule`（LED）として相当する構造で実装 |

EMA の sample / verified コードは本プロジェクトには取り込まないが、新規モジュール
作成時のテンプレートとして [`../../architecture_reference/pdf/02_実装ガイド.pdf`](../../architecture_reference/pdf/02_実装ガイド.pdf)
を都度参照する。
