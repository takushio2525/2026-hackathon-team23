---
title: ファームウェア モジュール詳説
description: productionの全モジュール、共有状態、3フェーズでの配置をコード基準で案内する
sidebar:
  label: 読み順ガイド
  order: 0
---

この章は[ファームウェア概要](/implementation/firmware-overview/)をさらに掘り下げ、
`firmware/production/`のクラス、構造体、処理順、異常系をモジュール単位で説明します。

## 対象構成

```text
firmware/production/
├── common/lib/
│   ├── ModuleCore/
│   ├── OrcProtocol/
│   ├── OrcNetModule/
│   ├── OrcReceiverModule/
│   ├── NoteSenderModule/
│   ├── StatusLedModule/
│   └── SerialDebug/
├── node_01/
│   └── lib/{ImuModule,OrcSenderModule}/
├── node_02/
│   └── lib/UiRelayModule/
├── node_03〜05/          金管の残り3声
└── node_06/              ドラム
```

## モジュール一覧

| モジュール | 使用ノード | フェーズ | 入出力 |
|---|---|---|---|
| `IModule` / `ModuleTimer` | 全ノード | 基盤 | 共通インターフェースと周期判定 |
| `ImuModule` | node_01 | 入力 | MPU6050 → `data.imu` |
| `OrcNetModule` | 全ノード | 入力＋出力 | UDP ↔ `data.orcNet` |
| `OrcSenderModule` | node_01 | 出力 | 拍・状態 → CTRL／BEAT |
| `OrcReceiverModule` | node_02〜06 | 入力 | CTRL／BEAT → 時計同期・保留拍 |
| `NoteSenderModule` | node_02〜06 | 出力 | `noteOut` → NOTE |
| `UiRelayModule` | node_02 | 出力 | `ctrl` → UI |
| `StatusLedModule` | 全ノード | 出力 | `data.led` → LED |
| `SerialDebug` | 全ノード | 補助 | コンパイル時切替ログ |
| `OrcProtocol` | 全ノード＋PC | 型定義 | 20 Bワイヤ形式 |

## 読み順

1. [IModuleとModuleTimer](/firmware/imodule/)
2. [OrcProtocol](/firmware/orc-protocol/)
3. [OrcNetModule](/firmware/orc-net/)
4. 指揮者：[ImuModule](/firmware/imu-module/) → [OrcSenderModule](/firmware/orc-sender/) → [main](/firmware/main-conductor/)
5. 楽器：[OrcReceiverModule](/firmware/orc-receiver/) → [NoteSenderModule](/firmware/note-sender/) → [UiRelayModule](/firmware/ui-relay/) → [main](/firmware/main-instrument/)
6. [StatusLedModule](/firmware/status-led/)と[SerialDebug](/firmware/serial-debug/)

## 3フェーズでの配置

```mermaid
flowchart LR
  subgraph Input[入力フェーズ]
    IMU[ImuModule]
    NETI[OrcNetModule]
    RECV[OrcReceiverModule]
  end
  subgraph Logic[ロジックフェーズ]
    APPLY[applyPattern(SystemData&)]
  end
  subgraph Output[出力フェーズ]
    SEND[OrcSenderModule]
    NOTE[NoteSenderModule]
    UI[UiRelayModule]
    LED[StatusLedModule]
    NETO[OrcNetModule]
  end
  Input --> APPLY --> Output
```

モジュール間の値は必ず`SystemData`を通します。たとえば`ImuModule`が送信モジュールを直接呼ぶことはありません。

## production固有の差分

- 指揮者状態に`Menu`と`Result`を追加
- CTRLの旧予約4 Bを`mode/navCursor/targetBpm/score`へ割り当て
- UIパケットと`UiRelayModule`を追加
- 楽器を`node_02〜06`へ拡張
- 楽譜をかえるのうた4声＋56拍ドラムへ変更
- BEATを4連送、2 ms間隔、45 ms先読みに調整
- 楽器ループを2 ms周期へ短縮

## 設計上の不変条件

- 設定値は`ProjectConfig.h`へ置く
- モジュールの公開データは`SystemData.h`へ置く
- ワイヤ形式変更はC++とProcessingを同時に更新する
- `SERIAL_DEBUG=1`とNOTEバイナリ送信は排他
- node_02〜05の金管楽譜と56拍サイクル定数を揃える

バージョンの経緯は[バージョン変遷](/history/versions/)を参照してください。
