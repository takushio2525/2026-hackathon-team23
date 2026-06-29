---
title: 通信プロトコル
description: UDPとUSB Serialで使う20バイト固定パケット
---

## 共通仕様

- リトルエンディアン
- 20 B固定：12 Bヘッダー + 8 Bペイロード
- magic：`0x4F52`（メモリ上は`52 4F`、ASCII `RO`の並び）
- version：`0x01`

| type | 名前 | 経路 | 用途 |
|---:|---|---|---|
| 1 | CTRL | 指揮者 → 楽器、UDP | テンポ・状態・ゲーム情報 |
| 2 | BEAT | 指揮者 → 楽器、UDP | 拍番号・発音予約時刻 |
| 3 | NOTE | 楽器 → PC、USB | 音高・強さ・長さ・音色 |
| 4 | UI | node_02 → PC、USB | メニュー・状態・得点の中継 |

## 共通ヘッダー（12 B）

| フィールド | 型 | 内容 |
|---|---|---|
| `magic` | `uint16_t` | `0x4F52` |
| `version` | `uint8_t` | `0x01` |
| `type` | `uint8_t` | 1〜4 |
| `seq` | `uint32_t` | 送信系列の連番 |
| `timestampMs` | `uint32_t` | 指揮者基準の送信時刻 |

## ペイロード

### CTRL

`bpmQ8`, `velocity`, `state`, `mode`, `navCursor`, `targetBpm`, `score`。
50 ms周期（20 Hz）で送ります。

### BEAT

`beatNo`, 予約2 B, `playAtMasterMs`。同じ内容を4回、2 ms間隔で送信します。

### NOTE

`partId`, `noteNumber`, `velocity`, `gate`, `durationMs`, `instrumentId`, 予約1 B。

### UI

`state`, `mode`, `navCursor`, `targetBpm`, `score`, `partId`, `bpmQ8`。
node_02が変化時に最大30 Hz、無変化時も1秒ごとに中継します。

実装の唯一の定義は`firmware/production/common/lib/OrcProtocol/OrcProtocol.h`です。
