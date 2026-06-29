---
title: ナビゲーションと採点
description: 重力基準の方向判定とゲーム得点の計算
---

## メニューナビ

加速度LPFからさらに遅いLPFで重力ベクトルを推定し、振り加速度を重力軸成分と水平面成分へ分けます。
250 msの判定窓で両成分を積算し、縦優勢なら決定、横優勢ならカーソル移動とします。

主な値は、開始1.00 g、解放0.30 g、不応期400 ms、縦優勢比0.55です。

## ガイド強度

```text
beat < 16       : guide = 1
16 <= beat < 32 : guide = 1 - (beat - 16) / 16
beat >= 32      : guide = 0
```

## 得点

目標100 BPMの拍間隔は600 msです。各実拍間隔との差`err`へ`weight = 1 - guide`を掛け、
ガイドが弱い後半を重く評価します。

```text
averageError = Σ(weight × err) / Σ(weight)
score = 100 × (1 - averageError / (targetInterval × 0.5))
```

得点は0〜100へ制限します。56拍で確定し、CTRLとUIを通してPCの結果画面へ表示します。
