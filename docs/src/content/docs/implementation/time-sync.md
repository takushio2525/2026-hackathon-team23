---
title: 時刻同期アルゴリズム
description: 指揮者時計を各楽器のローカル時計へ写す
---

## オフセット

楽器が時刻`localReceiveMs`に、指揮者時刻`timestampMs`のパケットを受け取った場合、
観測値を次で作ります。

```text
offsetSample = timestampMs - localReceiveMs
masterNow ≈ localNow + offsetMs
```

通常はEMAで平滑化します。新しいCTRL／BEATは係数0.20、同じBEATの重複分は0.05です。

## 予約時刻変換

```text
targetLocalMs = playAtMasterMs - offsetMs
```

楽器の2 msループでこの時刻を過ぎたらNOTEを送ります。受信時点ですでに期限を過ぎていても、
音を捨てず即時発火します。

## リセット追従

指揮者の再起動でオフセット観測が1000 ms以上飛んだ場合、EMAでゆっくり追わず即時採用します。
これによりマスタ時計の巻き戻りから1パケットで復旧します。

## 重複排除

BEATは4連送されますが、同じ`beatNo`は1つの発音予約として扱います。
重複は時計推定の安定化にだけ利用します。
