---
title: 楽器ノード
description: node_02〜06の受信、楽譜進行、NOTE送信
---

## 共通処理

1. Stationとして`OrchestraAP`へ接続
2. CTRL／BEATを受信
3. 指揮者時計とのオフセットを更新
4. `playAtMasterMs`をローカル時刻へ変換して待つ
5. `beatNo`から楽譜位置を求める
6. NOTEを115200 bpsでPCへ送る

## ノード差分

| node | `partId` | `headRestBeats` | `instrumentId` | 固有機能 |
|---|---:|---:|---:|---|
| 02 | `0x02` | 0 | 0 | UI中継 |
| 03 | `0x03` | 8 | 1 | — |
| 04 | `0x04` | 16 | 2 | — |
| 05 | `0x05` | 24 | 3 | — |
| 06 | `0x06` | 0 | 4 | 56拍ドラム譜 |

## 状態

楽器はIdle、WaitStart、Playingの3状態です。Wi-Fi接続でWaitStartへ進み、最初のBEATまたは
Conducting状態のCTRLでPlayingへ合流します。BEATが10秒以上途絶えるとWaitStartへ戻ります。

## 細分音符

拍頭のNOTEとは別に`noteOutSub`を持ち、8分音符などを予約できます。
メインNOTEと同じループで重なっても上書きしない構造です。
