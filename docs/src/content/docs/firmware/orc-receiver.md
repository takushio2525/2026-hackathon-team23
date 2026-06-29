---
title: OrcReceiverModule — 時計同期と重複排除
description: productionのCTRL／BEATをSystemDataへ整形し、時計オフセットと保留発音を管理する入力モジュール
sidebar:
  label: 楽器 — OrcReceiverModule
  order: 8
---

## 実体

| ファイル | 行数 |
|---|---:|
| `firmware/production/common/lib/OrcReceiverModule/OrcReceiverModule.h` | 52 |
| `firmware/production/common/lib/OrcReceiverModule/OrcReceiverModule.cpp` | 118 |

OrcNetModuleが受信した生パケットを、楽器ロジックが使いやすい`CtrlData`、`SyncLogicData`、
`PendingBeat`へ変換する入力モジュールです。

## Config

```cpp
struct OrcReceiverConfig {
  uint8_t partId;
  uint16_t headRestBeats;
  float clockSyncEmaAlpha;
  float clockSyncEmaAlphaDup;
  uint8_t clockSyncMinSamples;
  int32_t clockSyncSnapThresholdMs;
  uint16_t loopIntervalMs;
};
```

production共通値は新規EMA 0.20、重複EMA 0.05、最小5サンプル、スナップ1000 ms、ループ2 msです。
`partId`と`headRestBeats`だけがノードごとに異なります。

## 共有データ

### `CtrlData`

BPM、velocity、指揮者state、mode、navCursor、targetBpm、score、受信時刻を保持します。
node_02のUiRelayModuleもここを読みます。

### `SyncLogicData`

`offsetMs = master - local`、サンプル数、収束フラグ、直近観測を持ちます。

### `PendingBeat`

`valid`、`beatNo`、`playAtMasterMs`を持つ1スロットの予約です。
同じ拍の4連送で4スロットを消費しません。

## 1ループの流れ

```text
OrcNetModuleがhasNewCtrl/hasNewBeatを立てる
  → CTRLの全フィールドをdata.ctrlへコピー
  → timestampMsと受信時刻からoffsetサンプル
  → EMAまたはスナップでdata.syncを更新
  → BEATのbeatNoを重複判定
  → 新規ならpendingへ保存
  → 生パケットのnewフラグをclear
```

## 時計オフセット

受信時刻`localReceive`に、送信時刻`masterSent`を持つパケットを受けたとき：

```text
sample = masterSent - localReceive
offset = offset + alpha × (sample - offset)
```

ネットワーク遅延があるためサンプルは真のオフセットより遅延ぶん小さくなりますが、全楽器が同じ経路を使うことで
楽器間差を抑えられます。重複パケットは同じ送信時刻で到着だけが遅れるため、係数0.05で影響を弱めます。

## スナップ追従

`abs(sample - offset) >= 1000 ms`なら指揮者再起動とみなし、EMAせずsampleを即採用します。
時計巻き戻りを数十パケットかけて追うと演奏が止まるためです。

## 重複排除

同じ`beatNo`は時計更新には使いますが、pendingは置き換えません。新しい拍だけを予約します。
番号比較は16 bitラップを考慮した符号付き差分で行います。

## なぜ1スロットか

先読み45 msに対して人間の最短拍間隔は250 ms（240 BPM）であり、通常は次の拍が前の予約を追い越しません。
1スロットにすることでキュー長、古い拍の破棄、再送重複の管理を単純化しています。

## Playing遷移との関係

`clockSyncMinSamples=5`は診断上の収束目安です。楽器は最初のBEATまたはConducting CTRLでPlayingへ入り、
収束待ちで最初の音が鳴らない状態を避けます。未収束でも現在のoffsetで予約し、後続パケットで補正します。

## 異常と復帰

- CTRLだけ届く：時計と画面情報は更新、発音は次のBEAT待ち
- BEATだけ届く：予約発音可能、BPMは最後のCTRLを使う
- BEATが10秒途絶える：applyPatternがWaitStartへ戻す
- 指揮者再起動：スナップ追従し、次のBEAT番号から楽譜位置を再計算

## 変更時の注意

- EMA係数をBPM用0.30と混同しない
- 受信コールバック内で発音しない
- 同じBEATを複数発音へ変換しない
- `offsetMs`の符号は常にmaster-local

関連：[時刻同期メカニズム](/deep-dive/time-sync/) / [楽器main](/firmware/main-instrument/)
