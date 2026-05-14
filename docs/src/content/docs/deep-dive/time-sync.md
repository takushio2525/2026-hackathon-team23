---
title: 時刻同期メカニズム
description: 5 台のマイコンの millis() を揃える仕掛け — EMA オフセット推定・playAtMasterMs 先読み・誤差解析
sidebar:
  order: 2
---

:::note[この章で分かること]
- なぜ「マスタ時計を選ぶ」だけでは揃わないか
- 楽器側がオフセットを EMA で推定する数式と収束特性
- `playAtMasterMs` 先読みで何が吸収できるか、何ができないか
- 誤差予算（±20 ms）の内訳と、各誤差要因の大きさ
:::

:::tip[読了目安]
**約 12 分**。前提: [拍検出アルゴリズム](/deep-dive/beat-detection/) を読み終えていること。EMA の意味、絶対時間と相対時間の区別。
:::

実装本体:
- 楽器側 EMA 推定: `firmware/test_v2/node_02/lib/OrcReceiverModule/OrcReceiverModule.cpp`
- 楽器側発音判定: `firmware/test_v2/node_02/src/applyPattern.cpp`
- 指揮者側 BEAT 送信: `firmware/test_v2/node_01/lib/OrcSenderModule/OrcSenderModule.cpp`

## 問題設定

各マイコンは独立した水晶発振器で `millis()` を進めている。同じ時刻に電源を入れても：

- 水晶ごとの個体差で進み方が違う（典型的に ±20 ppm = 1 時間で 0.07 秒ずれる）
- 起動順がバラバラ。電源を入れた瞬間の `millis()` は 0 だが、その「瞬間」は揃わない

つまり「指揮者の `millis()` が 1000」のとき、楽器 A は 800、楽器 B は 1200 ということが
普通に起こる。この **時計のオフセット** を吸収しないと、いくら BPM を共有しても
発音タイミングは揃わない。

## 解決の戦略

3 つの仕掛けで重ねて吸収する。

| 段 | 仕掛け | 何を解決するか |
|---|---|---|
| 第 1 | EMA オフセット推定 | 楽器側で「指揮者時計 − 自時計」の差を継続推定する |
| 第 2 | `playAtMasterMs` 先読み | 「いつ鳴らすか」を指揮者時計で指示し、ネットワーク遅延を吸収する |
| 第 3 | 5 ms 周期ループでの待機 | 発音時刻に達するまで `delay()` せず、毎ループで再評価する |

## 第 1 段: EMA オフセット推定

### 何を推定するか

時刻 $t_m$ を指揮者時計、$t_l$ を楽器の自時計と書く。両者の関係は

$$
t_m = t_l + \text{offset}
$$

で、この `offset` を楽器側で求めたい。指揮者が CTRL や BEAT を送る瞬間、
パケットの `timestampMs` フィールドにそのときの $t_m$ を載せる。楽器は
受信した瞬間に `millis()` を呼んで $t_l$ を測る：

$$
\text{offset}_\text{sample} = \text{timestampMs} - \text{millis}_\text{受信時}
$$

しかし `offset_sample` は **ネットワーク遅延 + パケット処理時間** ぶんバイアスがある。
1 サンプルでは精度が出ないので、EMA で平滑化する。

### EMA の更新式

```cpp
const int32_t sample = (int32_t)(timestampMs - millis());
if (sync.sampleCount == 0) {
    sync.offsetMs = sample;
} else {
    const float prev = (float)sync.offsetMs;
    const float next = (1.0f - alpha) * prev + alpha * (float)sample;
    sync.offsetMs = (int32_t)next;
}
```

$\alpha = 0.10$（`clockSyncEmaAlpha`、`ProjectConfig.h` で設定）。

### なぜ $\alpha = 0.10$

EMA の時定数は $\tau \approx 1 / \alpha$ サンプルぶん。20 Hz の CTRL で更新されるので：

- $\alpha = 0.10$ → 時定数 ≒ 10 サンプル = **0.5 秒**
- 起動から 1 秒程度でほぼ収束、5 サンプル受信した時点で `converged = true`（`clockSyncMinSamples`）

$\alpha$ を大きくすると速く収束するが、ネットワーク遅延ジッタが直接 offset に乗ってしまう。
小さくすると安定するが、起動時の収束が遅い。0.10 は両者の中庸。

### 収束特性

EMA は指数的に真値に近づく：

$$
\text{offset}_n - \text{offset}_\text{true} \approx (1-\alpha)^n \cdot (\text{offset}_0 - \text{offset}_\text{true})
$$

$\alpha = 0.10$、20 Hz なら：

| 時間 | 残差 |
|---|---|
| 0.5 秒（10 サンプル） | 初期誤差の ≒ 35% |
| 1 秒（20 サンプル） | ≒ 12% |
| 2 秒（40 サンプル） | ≒ 1.5% |
| 5 秒（100 サンプル） | ほぼ完全収束 |

初期誤差が 100 ms 程度（典型的なネット遅延 1 ms × 起動順のバラつき）なら、
2 秒で 1.5 ms 以下になる。

### CTRL と BEAT の両方でサンプリングする理由

CTRL は 20 Hz で常時流れるが、起動直後やバースト的に拍が出る瞬間は CTRL だけだと
更新が間に合わない。BEAT 受信時にも同じく `updateClockOffset()` を呼んでサンプル数を
稼ぐ実装になっている：

```cpp
if (data.orcNet.hasNewBeat) {
    updateClockOffset(data, lastBeat.header.timestampMs, alpha, minSamples);
    // ... 重複排除と pending キューイング
}
```

## 第 2 段: `playAtMasterMs` 先読み

### 何のためにあるか

拍の瞬間に BEAT を投げると、ネットワーク遅延（実測 1〜3 ms）の分だけ
楽器の受信が遅れる。受信した瞬間に発音すると、結局その分だけずれる。

これを防ぐため、指揮者は「**未来時刻**」を BEAT に載せる：

```cpp
pkt.payload.playAtMasterMs = masterNow + cfg_.beatLookaheadMs;   // 50 ms 先
```

楽器側は「指揮者時計で `playAtMasterMs` の瞬間に鳴らせ」という命令として受け取る。

### 自時計への変換

楽器側は受信後、第 1 段の EMA で得た `offset` を使って自時計に変換する：

$$
t_{l,\text{target}} = \text{playAtMasterMs} - \text{offset}
$$

```cpp
const int32_t targetLocalMs = (int32_t)pending.playAtMasterMs - sync.offsetMs;
const int32_t waitMs        = targetLocalMs - (int32_t)millis();
```

### なぜ 50 ms

`beatLookaheadMs` のチューニング：

| 値 | 効果 |
|---|---|
| 0 ms | 即発火。ネット遅延（1〜3 ms）で楽器間がずれる |
| 10 ms | バラつき吸収にはギリギリ |
| **50 ms** | 余裕を持ってネット遅延を吸収、体感遅延としても気にならない |
| 200 ms | 振りと音の遅延が体感できてしまう |

50 ms は **遅延吸収余裕** と **体感遅延の許容範囲** のスイートスポット。

> 音楽認知では概ね 30 ms 程度から「ズレ」として知覚されはじめるが、絶対的な遅延
> （振り → 音）としては 100 ms 程度までは「同期している」と感じる。50 ms はその中で
> 余裕を持って収まる値。

### 5 ms 周期ループでの待機

楽器のメインループは EMA の 3 フェーズで 5 ms 周期。「`playAtMasterMs` まで待つ」を
`delay()` で実装すると、ループが止まって他の入力（CTRL 受信、楽譜更新）が遅れる。

そこで **毎ループで再評価** する設計にする：

```cpp
if (data.receiver.pending.valid) {
    const int32_t targetLocalMs =
        (int32_t)pending.playAtMasterMs - sync.offsetMs;
    const int32_t waitMs = targetLocalMs - (int32_t)millis();
    if (waitMs <= 0) {
        fired = true;
        firedBeatNo = pending.beatNo;
        pending.valid = false;
    }
    // waitMs > 0: 次ループで再評価する (pending は valid のまま)
}
```

- `waitMs > 0`: まだ早い → 何もせず次ループへ
- `waitMs <= 0`: 時刻に達した（または受信が遅れて期限切れ）→ 即発火、`pending` を消費

**期限切れでも捨てない** のがポイント。捨てると鳴らなくなる事故が起きるので、
「遅延吸収」より「とにかく鳴らす」を優先する。

### 解像度は ±5 ms

毎ループで評価するので、`waitMs` の検出粒度は **5 ms**（loopIntervalMs）。
これがそのまま「楽器が鳴る瞬間」のタイミング精度になる。

実機の振りに対して 5 ms の揺れは聴覚上気にならない。複数楽器間でも各楽器が
同じ `playAtMasterMs` を見て同じ精度で発火するので、**揃ったまま揺れる** ことに
なる（楽器間相対は変わらない）。

## 第 3 段: 発音側のオフセット計算 — 統合の流れ

全部組み合わせると、こうなる：

```
指揮者: 拍を検出 (時刻 t_beat_master)
   │
   │ BEAT パケット組み立て
   │ payload.playAtMasterMs = t_beat_master + 50ms
   │
   ▼
UDP マルチキャスト (2 連送)
   │
   │ ネット遅延 1〜3 ms
   ▼
楽器: BEAT 受信
   │
   │ OrcReceiverModule:
   │   1. updateClockOffset で EMA 更新
   │   2. 重複排除して pending キューに積む
   │
   ▼
楽器: applyPattern() 毎ループ (5 ms 周期)
   │
   │ targetLocalMs = pending.playAtMasterMs - sync.offsetMs
   │ waitMs = targetLocalMs - millis()
   │   waitMs > 0 → 次ループ
   │   waitMs <= 0 → 発火
   ▼
楽器: 該当 ScoreEvent を発火
   │
   │ NoteSenderModule が NotePacket を組み立て USB Serial で PC へ
   ▼
PC: orchestra_resynth が発音
```

## 誤差予算（なぜ ±20 ms に収まるか）

楽器間の同期誤差（複数楽器を同じ部屋で鳴らしたときに聞こえる「ズレ」）を要素分解する：

| 要素 | 大きさ | 説明 |
|---|---|---|
| 指揮者 → 楽器のネット遅延の **差** | ≤ 1 ms | 同じ SoftAP/同じマルチキャストグループなので、楽器間の差は無視できる |
| 楽器 A / B の EMA 残差の **差** | ≤ 2 ms | 各楽器が独立にサンプルしているので、収束後の残差が独立に乗る |
| 楽器の `waitMs` 評価粒度 | ±5 ms | 5 ms 周期ループでの再評価 |
| USB Serial 送信の **差** | ≤ 1 ms | 全楽器が同じ仕様の UNO R4 WiFi |
| **合計（楽器間）** | **数 ms〜10 ms** | 実測も同程度 |

[ADR-0006](/decisions/0006-sync-error-moe-20ms/) で MOE = 20 ms を採用しているので、
余裕を持って収まる。

### 指揮者 → 楽器の絶対遅延

絶対遅延（振りの瞬間から音が出るまで）は別の話：

| 要素 | 大きさ |
|---|---|
| 拍検出ループ周期 | ≤ 5 ms |
| BEAT 送信 + ネット遅延 | 1〜3 ms |
| `beatLookaheadMs` の意図的な遅延 | 50 ms |
| 楽器の評価粒度 | ≤ 5 ms |
| USB Serial → PC | 数 ms |
| PC の合成 → スピーカ | 10〜20 ms |
| **合計** | **70〜85 ms** |

音楽用途で 100 ms 以内なら違和感なし。実機もこの範囲に収まっている。

## ジッタの主因と対策

楽器間ズレが大きくなったら、まず以下を疑う。

| 症状 | 主因 | 対策 |
|---|---|---|
| 起動直後だけズレる | EMA が未収束 | `sync.converged` を見て収束まで待つ（実装済） |
| 偶発的に大きくズレる | WiFi の再送遅延 | 同じセル / チャネル 6 固定 / 距離を縮める |
| 一定方向にずれ続ける | EMA の $\alpha$ が小さすぎる | `clockSyncEmaAlpha` を 0.15〜0.20 へ |
| 全楽器が指揮より遅れる | `beatLookaheadMs` 不足 | 一時的に 80〜100 ms へ |
| 発音 / 沈黙の入れ替わり | パケロス + 不応期 | BEAT 2 連送を 3 連送に |

調整は **全部 `ProjectConfig.h`** で済む。`OrcReceiverConfig` / `OrcSenderConfig` を見ること。

## 「PC を途中起動しても合流できる」の仕組み

指揮者が止まらない限り、`beatNo` は単調増加し続ける。EMA オフセットも自時計が
動いている限り更新し続ける。よって：

- 楽器ノードがそのまま生きていて PC だけ再起動した場合: 即座に NOTE が
  USB Serial で流れ始め、Processing が受け取った瞬間から音が出る
- 楽器ノードも再起動した場合: 起動 → SoftAP に接続 → 数回 CTRL 受信で EMA 収束
  （0.5〜1 秒）→ 次の BEAT で `firedBeatNo` を得て楽譜の現在位置から発火

楽譜は拍番号で巡回参照されるので（[楽譜進行ロジック](/deep-dive/score-progression/) 参照）、
**いつ起動しても曲の途中から自然に鳴り始める**。

## デバッグの観点

楽器側に `SERIAL_DEBUG=1` で書き込むと、シリアル監視で以下が見える：

```
[N2 BEAT recv beatNo=42 playAtMaster=12395 localTarget=12180 waitMs=23 offset=215]
[N2 FIRE  beatNo=42 scoreIndex=10 note=67 dur=560]
```

オフセットが変動し続けていれば WiFi が荒れている。
`waitMs` が常に負（期限切れ即発火）なら `beatLookaheadMs` を増やす。

## 次に読むべきページ

- 通信路の中身: [UDP マルチキャスト](/deep-dive/udp-multicast/)
- パケットレベルの実体: [バイナリパケット](/deep-dive/binary-packet/)
- 受信した拍 → 楽譜進行: [楽譜進行ロジック](/deep-dive/score-progression/)
