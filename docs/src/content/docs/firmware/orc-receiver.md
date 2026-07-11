---
title: OrcReceiverModule — 時計同期と重複排除
description: productionのCTRL／BEATをSystemDataへ整形し、発音予約に必要な時計差を管理する入力モジュール
sidebar:
  label: 楽器 — OrcReceiverModule
  order: 8
---

## 役割

`OrcReceiverModule`は、Wi-Fiで受け取ったCTRLとBEATを、楽器側のロジックが使える形へ整えます。主な仕事は3つです。

1. 指揮者時計と楽器時計の差を推定する
2. 同じBEATを4回受けても、音を1回だけ予約する
3. 指揮者の再起動を検出し、新しい時計へすぐ追従する

## Config

```cpp
struct OrcReceiverConfig {
  uint8_t  partId;
  uint16_t headRestBeats;
  uint16_t clockSyncWindowMs;
  uint8_t  clockSyncMinSamples;
  uint16_t clockSyncSnapThresholdMs;
  uint16_t loopIntervalMs;
};
```

productionの共通値は、時計同期窓2000 ms、診断用の最小5サンプル、スナップ1000 ms、楽器ループ2 msです。`partId`と`headRestBeats`だけが声部ごとに異なります。

## 時計同期

パケットを受けた時刻から、次の観測を作ります。

```text
offsetSample = master timestamp - local receive time
masterNow    ≒ localNow + offsetMs
```

SoftAPのマルチキャストは遅れて届くことがあるため、平均値ではなく、**2秒の窓で最大の`offsetSample`**を使います。これは配送遅延がもっとも小さい観測に近い値です。

- より大きいサンプルはすぐ採用する
- 窓の終了時には、その窓の最大値へ引き直す
- 差が1000 ms以上跳んだら指揮者再起動とみなし、窓を待たず即時採用する

## 発音予約と重複排除

`PendingBeat`は`valid`、`beatNo`、`playAtMasterMs`を持つ1スロットの予約です。指揮者は同じBEATを4連送しますが、最初に届いた1個だけを予約します。

後続の重複は時計同期の観測に使っても、同じ`beatNo`を再予約しません。これにより、遅れて届いた重複で同じ音が二度鳴ることを防ぎます。

## なぜ1スロットでよいか

現在の発音予約は220 msで、人間の最短拍間隔は240 BPMでも250 msです。通常は次の拍が前の予約を追い越しません。1スロットにすることで、古い拍の破棄や再送時の複雑なキュー管理を避けています。

## 異常と復帰

- CTRLだけ届く：時計と画面情報は更新し、次のBEATを待つ
- BEATだけ届く：最後に受けたCTRLのBPMで発音予約できる
- BEATが10秒途絶える：楽器は`WaitStart`へ戻る
- 指揮者再起動：予約を破棄し、次のBEAT番号から楽譜位置を再計算する

関連：[時刻同期メカニズム](/deep-dive/time-sync/) / [楽器main](/firmware/main-instrument/)
