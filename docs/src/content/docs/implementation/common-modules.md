---
title: 共通モジュール
description: production/common/libにある共有部品
---

## 一覧

| モジュール | 役割 |
|---|---|
| `ModuleCore` | `IModule`と`ModuleTimer` |
| `OrcProtocol` | CTRL／BEAT／NOTE／UIの20B構造 |
| `OrcNetModule` | SoftAP／Station、UDPマルチキャスト |
| `OrcReceiverModule` | CTRL／BEAT受信、重複排除、時計補正 |
| `NoteSenderModule` | NOTEをUSB Serialへ送信 |
| `StatusLedModule` | 状態に応じた点灯・点滅 |
| `SerialDebug` | コンパイル時切り替えのログ |

指揮者固有の`ImuModule`と`OrcSenderModule`、node_02固有の`UiRelayModule`は各ノードの`lib/`にあります。

## `IModule`

モジュールは初期化、入力更新、出力更新、終了処理の共通インターフェースを持ちます。
入力専用モジュールは出力更新を、出力専用モジュールは入力更新を実質的に何もしない実装にします。

## `ModuleTimer`

`delay()`でループ全体を止めず、経過時間で処理周期を決めます。例外はBEATの4連送間に入れる2 ms間隔です。

## 変更時の境界

- 全ノード共通の通信変更：`common/lib`
- 指揮者だけの送信変更：`node_01/lib`
- 特定楽器だけの出力変更：該当ノードの`lib`
- 判断条件：`applyPattern.cpp`、数値は`ProjectConfig.h`
