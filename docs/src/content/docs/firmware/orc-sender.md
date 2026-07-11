---
title: OrcSenderModule — CTRLとBEATを組み立てる
description: productionで周期CTRLとイベントBEATを20 Bへ梱包し、4連送予約する出力モジュール
sidebar:
  label: 指揮者 — OrcSenderModule
  order: 7
---

## 実体

| ファイル | 行数 |
|---|---:|
| `firmware/production/node_01/lib/OrcSenderModule/OrcSenderModule.h` | 36 |
| `firmware/production/node_01/lib/OrcSenderModule/OrcSenderModule.cpp` | 62 |

入力モジュールではなく、`SystemData`に確定した拍・BPM・状態をワイヤ形式へ変換する出力モジュールです。

## Config

```cpp
struct OrcSenderConfig {
  uint32_t ctrlIntervalMs;
  uint8_t beatRedundancy;
  uint16_t beatLookaheadMs;
};
```

production値は50 ms、4回、220 msです。

- CTRLは20 Hz。状態変化とBPM表示を十分滑らかにしつつ帯域を抑える
- BEATは4連送。1発ごとの損失が独立確率`p`なら全損失は`p^4`
- 220 ms先読み。SoftAPのマルチキャストが最大約205 ms遅れて届く実測に対し、予約時刻までに受信できる余裕を取る

## Data

```cpp
struct OrcSenderData {
  uint32_t ctrlSeq;
  uint32_t beatSeq;
  bool forceCtrlSend;
};
```

BEATとCTRLで連番を分けるため、周期パケットの多さが拍連番へ影響しません。
`forceCtrlSend`はMenu→Conductingなどの画面切替を次の50 ms周期まで待たせないために使います。

## 初期化

`init()`はCTRL用タイマの基準時刻を設定します。ネットワーク自体の初期化はOrcNetModuleの責務です。

## 出力更新

### BEAT

```text
data.beat.event
  → BeatPacket{}をゼロ初期化
  → header（magic/version/type/seq/timestamp）
  → beatNoとplayAtMasterMs
  → data.orcNet.pendingBeatへコピー
  → pendingBeatRedundancy = 4
  → eventをclear
```

`playAtMasterMs = masterNow + 220`はモジュール内で設定されます。ロジック側は拍発火だけを決めます。

### CTRL

CTRLタイマが50 ms経過した場合、または`forceCtrlSend`が立った場合に送ります。

```cpp
pkt.payload.bpmQ8    = round(data.tempo.bpm * 8);
pkt.payload.velocity = data.tempo.velocity;
pkt.payload.state    = (uint8_t)data.conductor.state;
pkt.payload.mode      = data.game.mode;
pkt.payload.navCursor = data.game.navCursor;
pkt.payload.targetBpm = data.game.targetBpm;
pkt.payload.score     = data.game.score;
```

組み立てたパケットは`data.orcNet.pendingCtrl`へ置きます。実際のUDP送信は同じ出力フェーズ後段のOrcNetModuleです。

## イベントと周期を分ける理由

- BEAT：1回の発火を落としたくない。イベント駆動＋冗長送信
- CTRL：最新値だけ届けばよい。周期駆動で自然に上書き
- UI：UDPのCTRLをnode_02がPCへ中継。送信側は画面IDを持たない

## 4連送の時間配置

OrcNetModuleは同じBEATを4回送り、各回の間に2 ms待ちます。連続送信を1つの無線バーストへ固めず、
radio側のまとめ落ちを減らす狙いです。重複排除は受信側の`beatNo`で行います。

## 異常時

Wi-Fiリンクが落ちている間もロジックは状態を更新できますが、OrcNetModuleは送信できません。`forceCtrlSend`はMenu→Conductingなどの状態変化で最新CTRLを即時通知し、次の50 ms周期までPC画面を待たせないために使います。

## 変更時の注意

- 先読み値は受信・4連送・楽器2 msループの合計より大きくする
- 冗長数を変える場合は`beatGapMs`とセットで実機測定する
- CTRLにフィールドを追加する場合は8 B制約とProcessingのUiEventも更新する
- `event`をclearし忘れると毎ループ同じ拍を新規イベントとして送る

関連：[同期方式](/system/synchronization/) / [時刻同期](/deep-dive/time-sync/)
