# common — 共通層ライブラリ

`firmware/test_v1/` 配下の全ノードが参照する共通モジュール置き場。
各ノードの `platformio.ini` から `lib_extra_dirs = ../common/lib` で参照する。

## 構成

| ライブラリ | 内容 |
|---|---|
| `lib/ModuleCore/` | `IModule` 抽象基底と `ModuleTimer` |
| `lib/OrcProtocol/` | CTRL / BEAT / NOTE の 20 B パケット定義 (`magic=0x4F52`) |
| `lib/OrcNetModule/` | WiFi UDP マルチキャスト送受信 (SoftAp / Sta 切替) |
| `lib/StatusLedModule/` | 状態に応じた LED 点滅出力 |
| `lib/SerialDebug/` | `SERIAL_DEBUG` フラグで切替えるシリアルデバッグマクロ (`DBG_PRINTF` 等) |

## 約束事

- 共通モジュールは各ノードの `include/SystemData.h` に依存する。
  各ノードは `OrcNetData` `StatusLedData` 等のフィールドを `SystemData` 内に
  持たなければならない。
- モジュール間の直接呼び出しは禁止 (EMA 規約)。
  通信は必ず `SystemData` の該当フィールド経由で行う。

詳細仕様は `meetings/0429_3回/事前課題共有/arduino_塩澤.pdf` 参照。
