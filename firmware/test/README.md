# firmware/test — Arduino オーケストラ仕様書準拠のテスト実装

仕様書 `meetings/0429_3回/事前課題共有/arduino_塩澤.pdf` を実装可能な水準まで
落とし込んだ動作検証用ファームウェア。指揮者 (node_01) と楽器 1 (node_02) の
2 ノードのみ含む。

## クイックスタート

```bash
# 1. 指揮者ノードを書き込む
cd firmware/test/node_01
pio run -t upload

# 2. 楽器 1 ノードを書き込む
cd ../node_02
pio run -t upload

# 3. 楽器 1 を Mac に USB 接続し、Processing で
#    pc_app/test/orchestra_player/orchestra_player.pde を Run
```

詳細は各ノードの README を参照。

| ディレクトリ | 内容 |
|---|---|
| [`common/`](common/) | 全ノード共通ライブラリ (`OrcProtocol` / `OrcNetModule` / `StatusLedModule` / `ModuleCore`) |
| [`node_01/`](node_01/) | 指揮者ノード (XIAO ESP32-S3 Sense + GY-521) |
| [`node_02/`](node_02/) | 楽器 1 ノード (Arduino UNO R4 WiFi, 金管 1) |

## 起動順

1. 楽器ノード (node_02) を電源 ON → `Idle` (LED 1 Hz 点滅)
2. 指揮者ノード (node_01) を電源 ON → SoftAP 起動 → `Calibrating` (2 Hz 点滅, 2 秒) → `Conducting` (点灯)
3. 楽器ノードが SoftAP 接続 → `WaitStart` (2 Hz) → CTRL を 5 個受信して時計同期収束 → 入り拍到来で `Playing` (点灯)

## マスタクロック方式

仕様 §2.3.3.6 に従い、指揮者の `millis()` をマスタ時刻として全ノードで共有する。
BEAT は「マスタ時刻 `playAtMasterMs` に発音せよ」という未来時刻指定で送り、
楽器側は CTRL/BEAT 受信時に offset を EMA で学習し、`masterNow = millis() + offset`
が `playAtMasterMs` に到達した瞬間に発音する。これにより WiFi 到達ばらつきが
時計同期誤差に押し付けられ、楽器間の相対同期はほぼゼロに収束する。
