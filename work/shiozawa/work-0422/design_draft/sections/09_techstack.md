# 9. 技術スタック

| レイヤ | 採用技術 | バージョン / 備考 |
|---|---|---|
| MCU | Arduino UNO R4 WiFi | Renesas RA4M1 + ESP32-S3（WiFi 子機） |
| 開発ボード搭載センサ | 内蔵 IMU（LSM6DSOX 相当） | 6 軸: 加速度 3 軸 + 角速度 3 軸 |
| フレームワーク | Arduino Framework | PlatformIO 経由で参照 |
| 言語 | C++（C++11） | `arduino-core` がサポートする範囲 |
| ビルドツール | PlatformIO | `platform = renesas-ra`, `board = uno_r4_wifi` |
| 外部ライブラリ | `Arduino_LSM6DSOX` | IMU 読み取り |
| 外部ライブラリ | `WiFiS3` | UNO R4 WiFi 標準の WiFi / UDP |
| 自作ライブラリ | `common/lib/` 配下（IModule / ModuleTimer / OrcProtocol / OrcNet） | 本設計書第 10 章で定義 |
| ネットワーク | UDP over IEEE 802.11（WiFi） | ローカル AP 経由、ブロードキャスト + ユニキャスト |
| 構成管理 | Git（GitHub） | リポジトリ `2026-hackathon-team23` |
| CI | GitHub Actions（`pio-build.yml`） | `firmware/` 変更時に全ノードをビルド |
| 参考リファレンス | Embedded-Module-Architecture | 塩澤作成、ADR-0005 で採用決定 |

**依存ライブラリの追加はしない方針**（Arduino 標準 + 自作共通層のみ）。
理由: ライブラリ追加の意思決定は CLAUDE.md ルールで「理由説明が必要」となっており、
本プロジェクトで標準以外を引く強い必要性が現時点で無いため。
