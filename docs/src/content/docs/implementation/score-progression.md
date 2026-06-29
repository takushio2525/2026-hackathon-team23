---
title: 楽譜進行アルゴリズム
description: beatNoから輪唱位置を毎拍再計算する
---

## サイクル位置

```text
cyclePos = (beatNo - 1) % 56
local = cyclePos - headRestBeats
```

- `local < 0`：その声部の入り前
- `0 <= local < 32`：`kScore[local]`を発音
- `local >= 32`：その声部はサイクル末尾まで休む

この計算を毎拍行うため、ローカルカウンタが1回ずれても次の`beatNo`で自己修復します。

## 発音長

`durationQ8`をBPMに応じてミリ秒へ変換します。

```text
durationMs = durationQ8 / 256 × 60000 / BPM
```

音量は楽譜velocityとCTRL velocityを`score × ctrl / 127`で合成します。

## 細分音符

`subNote`がある場合は`subOffsetQ8`から遅延時間を計算し、専用スロットへ予約します。
かえるのうたの8分音符を、BEAT自体を8分周期に増やさず表現できます。
