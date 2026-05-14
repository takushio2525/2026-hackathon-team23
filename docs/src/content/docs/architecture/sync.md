---
title: 同期戦略（±20ms）
description: 拍検出ロジック・時刻同期・playAtMasterMs 先読みの仕組み
sidebar:
  order: 5
---

:::note[この章で分かること]
- IMU の加速度から拍を取り出すアルゴリズム
- 指揮者と楽器の時計をどう合わせているか
- なぜ同期誤差が 20 ms 以内に収まるのか
:::

:::tip[読了目安]
**約 10 分**。前提: 信号処理の基本（LPF、EMA）、絶対時間の概念。
:::

同期は **「拍を取る」→「時刻を合わせる」→「先読みで遅延を吸収する」** の 3 段構成。

## 第 1 段: 拍検出（指揮者ノード内）

実装: `firmware/test_v2/node_01/src/applyPattern.cpp`
パラメータ: `firmware/test_v2/node_01/include/ProjectConfig.h` の `logic_params` 名前空間

### ステップ 1: ローパスフィルタで重力分離

IMU の生加速度 `acc[3]` をローパスフィルタにかけて重力ベクトルを抽出する：

```cpp
acc_lpf = alpha * acc_lpf + (1 - alpha) * acc;   // alpha = 0.10
```

その上で、重力ノルム（≒ 1g）を差し引いて **動加速度ノルム** `dynNorm` を計算：

```cpp
dynNorm = |acc_lpf| - gravityMag
```

`gravityMag` は起動時 2 秒のキャリブレーションで決定（静止時のノルム平均）。

### ステップ 2: 状態機械（Idle → Armed → Fire → Idle）

```
Idle
  │ dynNorm > 1.20 g
  ↓
Armed（拍候補）
  │ Armed 中の経路長 pathLenM が 0.20 m に達した
  ↓
Fire（拍発火！）
  │ リリース判定（停止 or ピークの 40% 以下、40 ms 連続）
  │   または Armed 8 ms 経過してタイムアウト
  ↓
Idle
```

#### なぜ「経路長」で判定するのか

- 単純な閾値判定（`dynNorm > X` で発火）だと**小さな揺れで誤発火**しがち
- Armed 中の `dynNorm` を時間積分して「振りの大きさ」を稼ぐ
- 経路長 0.20 m に達するには **意図のある振り** が必要

#### 不応期（refractory）

拍発火後 350 ms は次の拍を受け付けない（≒ 170 BPM 上限）。
これは「振り下ろし → 振り上げ」で 2 拍として誤検出するのを防ぐ。

### ステップ 3: BPM 推定

拍が発火したら、前回拍からの時間差で BPM を計算：

```cpp
delta_ms = thisBeatMs - lastBeatMs;
bpm_new = 60000.0f / delta_ms;
bpm = alpha_ema * bpm_new + (1 - alpha_ema) * bpm;   // alpha = 0.30
```

範囲外（40〜240 BPM）はリジェクトし、現在の `bpm` を維持。

### 閾値の根拠（一部）

| 定数 | 値 | 根拠 |
|---|---|---|
| `BEAT_DYN_THRESHOLD_G` | 1.20 g | 仕様書の 1.8g は届かず、0.8g は小揺れで誤検出 → 中間で調整 |
| `BEAT_REFRACTORY_MS` | 350 ms | ≒ 170 BPM 上限。普通の指揮には十分 |
| `BEAT_FIRE_PATH_M` | 0.20 m | Armed 突入から ~150 ms で到達、振りと音がほぼ同時に感じられる |
| `LPF_ALPHA` | 0.10 | 重力分離と応答性のバランス |
| `BPM_EMA_ALPHA` | 0.30 | テンポ変化に追従しつつ、ジッタを抑える |

すべての閾値の詳細経緯は `ProjectConfig.h` 内のコメントに残してある。

## 第 2 段: 時刻同期（楽器ノード内）

楽器ノードは、CTRL / BEAT パケットを受信するたびに **指揮者時計とのオフセット** を更新する。

```cpp
// 受信時
offset_sample = packet.timestampMs - millis();   // 指揮者時計 - 自時計
offset = alpha * offset_sample + (1 - alpha) * offset;   // EMA で平滑化
```

- ネットワーク遅延の分だけ `offset_sample` は揺れるが、EMA で滑らかになる
- 20 Hz の CTRL で常時更新されるため、片方向 1 ms 程度の精度に収束

### 自時計 → 指揮者時計の変換

```cpp
master_ms = millis() + offset;
```

逆も同様：

```cpp
local_ms = master_ms - offset;
```

## 第 3 段: `playAtMasterMs` 先読み

指揮者が BEAT を投げる際、次の式で**未来時刻**を載せる：

```cpp
playAtMasterMs = millis() + 50;   // beatLookaheadMs = 50 ms
```

楽器側（実装は `firmware/test_v2/node_02/src/applyPattern.cpp`）：

1. BEAT 受信時に `OrcReceiverModule` が `pending` キューに積む
2. `applyPattern()` 毎ループで `targetLocalMs = playAtMasterMs - sync.offsetMs` を計算
3. `waitMs = targetLocalMs - millis()` を見て、`waitMs <= 0`（到達済み）なら発火、`> 0` なら次ループに先送り
4. 期限切れでも捨てず即発火する（捨てると鳴らなくなるので、遅延吸収より「鳴らす」を優先）

`delay()` でビジーウェイトしないのがポイント。EMA の 3 フェーズループは 5 ms 周期で回り続けるので、
**最大でも次ループ（5 ms 後）で発火判定が更新される**。これにより `waitMs` の解像度は ±5 ms。

ネットワーク遅延が `beatLookaheadMs = 50 ms` 未満であれば、各楽器は同じ `playAtMasterMs` を
それぞれの `sync.offsetMs` だけ補正した自時計時刻で発火するため、**楽器間の発音は揃う**。

### なぜ 50 ms

- 実測のネットワーク遅延 1〜3 ms に対して十分な余裕
- 体感遅延としては気にならない（音楽用途で 50 ms は許容範囲）
- 大きすぎると指揮の応答性が悪く感じる

## なぜ 20 ms 以内に収まるのか

楽器間の同期誤差を構成する要素：

| 要素 | 大きさ |
|---|---|
| 指揮者 → 楽器のネットワーク遅延の差 | ≤ 1 ms（同じマルチキャストグループ） |
| 楽器の時刻オフセット EMA 残差 | ≤ 1 ms（20 Hz で更新） |
| 楽器 `delay()` の精度 | ≤ 1 ms |
| 楽器 → PC のシリアル遅延 | 数 ms（だが全楽器で同じなのでキャンセル） |
| **合計（楽器間）** | **数 ms** |

実測でも楽器間ピア・ピア比較で ≤ 20 ms を達成。
[ADR-0006](/decisions/0006-sync-error-moe-20ms/) で「数 10 ms」の中の安全側として 20 ms を設定した
理由とも整合する。

## フォールバック（Fallback 状態）

IMU が反応しない or WiFi が切れた場合：

1. **指揮者**: IMU タイムアウト（200 ms 連続でデータなし）→ `Fallback` 状態に
   - LED が 5 Hz 高速点滅で警告
   - CTRL は最後の BPM で送り続ける
   - BEAT は止める
2. **楽器**: 数秒間 CTRL が来ない → `Fallback` 状態に
   - LED が高速点滅
   - 受信再開を待つ

`Fallback` は復帰可能。指揮者の `Idle` ボタン的扱いではなく、
あくまで「異常時の保護」モード。

## デバッグツール

指揮者ノードは `SERIAL_DEBUG=1` で 200 ms ごとに状態をシリアル出力する：

```
[N1 t=12345 st=Conducting wifi=1 imu=1 acc=(0.10,0.85,-0.05) n=0.88 dyn=0.03 peakRaw=2.15 peakDyn=1.45 gate=I armedPk=1.20 path=0.000 bpm=100.5 beatNo=42 ctrlSeq=247 beatSeq=42]
```

各フィールドの意味は `firmware/test_v2/node_01/src/main.cpp` の `dumpPeriodic()` を参照。
拍が検出されないとき、これを見ながら閾値を調整する。

## 次に読むべきページ

- パケット仕様 → [通信プロトコル](/architecture/protocol/)
- コード本体 → [firmware の歩き方](/code/firmware/)
- 全体図 → [全体図](/architecture/overview/)

### さらに深掘りしたい

- 拍検出の数学・状態機械を完全に追う → [拍検出アルゴリズム](/deep-dive/beat-detection/)
- 時刻同期 EMA の収束特性・誤差予算 → [時刻同期メカニズム](/deep-dive/time-sync/)
