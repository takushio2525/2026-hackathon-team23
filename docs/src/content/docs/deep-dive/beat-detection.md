---
title: 拍検出アルゴリズム
description: IMU の生加速度から拍を取り出す全工程 — LPF・動加速度ノルム・状態機械・経路長積分・不応期・閾値根拠
sidebar:
  order: 1
---

:::note[この章で分かること]
- IMU の 3 軸加速度から「振り下ろし」を取り出す数式の流れ
- なぜ単純な閾値判定では誤検出するか、経路長積分で何が解決するか
- 状態機械（Idle / Armed / 早期発火 / リリース / タイムアウト）の各遷移条件
- 閾値が現在値（`1.20 g` / `0.20 m` / `350 ms` …）に落ち着いた経緯
:::

:::tip[読了目安]
**約 15 分**。前提: [同期戦略（±20ms）](/architecture/sync/) の概要、ベクトルと積分、C++ の基本構文。
:::

実装本体: `firmware/test_v2/node_01/src/applyPattern.cpp`
閾値定数: `firmware/test_v2/node_01/include/ProjectConfig.h` の `logic_params` 名前空間

## 問題設定

指揮者が手にした XIAO ESP32-S3 Sense + GY-521（MPU6050）から、5 ms 周期で
3 軸加速度 `acc[3]` が降ってくる。これだけを材料に「**いま振り下ろされた**」
という瞬間（= 拍）を、誤検出なく取り出したい。

求めたい性質：

1. **意図のある振り** だけ拾う。ちょっとした手ブレでは反応しない
2. **1 振り = 1 拍**。振り下ろし→振り戻しを 2 拍と数えない
3. **遅延が小さい**。振った瞬間と発火がずれない（音楽として崩壊する）
4. **姿勢に依存しない**。本体を 90° 傾けて振っても重力分が誤って混じらない

これらを同時に満たすために、以下の 5 ステップで段階的にフィルタする。

## ステップ 1: ローパスフィルタで瞬間ノイズを落とす

生 `acc[i]` には IMU 自身の電気ノイズと、振りの主動成分以外の高周波振動が乗る。
これを一次 IIR LPF で平滑化する：

$$
a_\text{lpf}[i] \leftarrow (1 - \alpha) \, a_\text{lpf}[i] + \alpha \, a[i]
$$

ここで $\alpha = 0.10$（`LPF_ALPHA`）。実コード：

```cpp
for (int i = 0; i < 3; ++i) {
    sLpfAcc[i] = (1.0f - LPF_ALPHA) * sLpfAcc[i] + LPF_ALPHA * data.imu.acc[i];
}
```

$\alpha$ が小さいほど平滑化が強くなるが、応答も遅くなる。逆に大きすぎると
ノイズが素通りする。0.10 にしているのは:

- 5 ms 周期のサンプルに対して時定数 ≒ 50 ms（人間の振りには十分速い）
- それ以下の高周波振動（=指のブレや基板の電気ノイズ）は十分減衰

### なぜ EMA で良いのか

理想的には Butterworth などの設計フィルタを使いたいが、

- マイコンでは **乗算 1 回・加算 1 回** で済む EMA が安い
- 拍検出には数 Hz 帯域だけ通れば十分なので、急峻な遮断は不要
- パラメータが $\alpha$ 1 つで直感的

これで 1 ステップ目は終わり。

## ステップ 2: 動加速度ノルムを計算する

LPF 後の加速度ベクトルから「**振りの強さ**」を 1 つのスカラーに集約する。

### 重力差し引きの罠

最初に思いつくのは「軸ごとに重力ベクトルを引く」だが、これは姿勢に依存する。
本体を水平に置いて校正した重力 $\mathbf{g}_\text{cal} = (0, 0, 1)\text{g}$ を引くと、
本体を 90° 傾けたとき、純粋に振っていない状態でも残留重力が 1g 残ってしまう。

これを避けるため、**スカラー量だけで判定する** 戦法を取る。

1. 起動時 2 秒のキャリブレーション中、加速度ノルム $|\mathbf{a}|$ の **平均** を計算
   → これを「静止時のノルム ≒ 重力 1g」として保存（`gravityMag`）

   ```cpp
   const float n = sqrtf(acc[0]*acc[0] + acc[1]*acc[1] + acc[2]*acc[2]);
   data.calibration.accumNorm += n;
   data.calibration.sampleCount++;
   // ...
   data.calibration.gravityMag = accumNorm / sampleCount;   // 確定値
   ```

2. 動作中は LPF 後の加速度ノルムから、この `gravityMag` を引く：

   $$
   d = |\mathbf{a}_\text{lpf}| - g_\text{cal}, \quad d \geq 0
   $$

   ```cpp
   float dynN = data.imu.accNorm - data.calibration.gravityMag;
   if (dynN < 0.0f) dynN = 0.0f;
   data.imu.dynNorm = dynN;
   ```

これでスカラー `dynNorm` は「**重力以外の加速度の大きさ**」になり、姿勢に依存しない。

### 副作用と注意点

引く前の `|\mathbf{a}|$ は重力と動加速度のベクトル和のノルムなので、
重力に **直交する向きの振り** に対しては、$\sqrt{1 + a^2} - 1 < a$ の関係で
過小評価になる（小さい $a$ では特に顕著）。実機で取りこぼし／誤検出が出たら
`BEAT_DYN_THRESHOLD_G` を 1.0〜1.4 の範囲で再調整する。

### `dynAcc`（向きを保ったベクトル）

スカラー `dynNorm` だけだと積分（後述）の向きが失われる。そこで、LPF 後の
向きを保ったまま **大きさを `dynNorm` にスケール** した近似ベクトルを作る：

$$
\mathbf{a}_\text{dyn} = \frac{d}{|\mathbf{a}_\text{lpf}|} \, \mathbf{a}_\text{lpf}
$$

```cpp
if (data.imu.accNorm > 1e-3f) {
    const float k = dynN / data.imu.accNorm;
    for (int i = 0; i < 3; ++i) data.imu.dynAcc[i] = sLpfAcc[i] * k;
}
```

Armed 中の振りは加速度が十分大きく、向きはほぼ振り方向に支配されるため、
この近似で問題ない。

## ステップ 3: 単純な閾値判定では誤発火する話

最も素朴な実装は「`dynNorm > X` で発火」。だがこれだと:

- 軽い揺れ（ピーク 1.3 g 程度）でも、ノイズで一瞬閾値を超えて発火する
- ハッカソンでの実検証で、これが **「勝手に進む」** 不具合の主因となった

仕様書には初期値 1.8g が書かれていたが、実機では届かなかった。これを 0.8g に
下げると小揺れで誤検出。中間の 1.2g にしても、瞬間ノイズで触れることがある。

**閾値だけでは時間方向の構造を見ていない** のが根本原因。

## ステップ 4: 経路長積分で「振りの大きさ」を稼ぐ

そこで、`dynAcc` を時間積分して「**振りで進んだ距離（経路長）**」を計算し、
これが一定値（`BEAT_FIRE_PATH_M = 0.20 m`）に達したら発火することにする。

### 数式

加速度を 2 回積分すれば変位になるが、ここでは「ベクトルの距離」ではなく
「速度ベクトルのノルムの時間積分」を取る：

$$
\mathbf{v}(t) = \int_{t_\text{armed}}^{t} \mathbf{a}_\text{dyn}(\tau) \cdot g \, d\tau
$$

$$
L(t) = \int_{t_\text{armed}}^{t} |\mathbf{v}(\tau)| \, d\tau
$$

ここで $g = 9.80665 \,\text{m/s}^2$（`GRAVITY_MS2`）は加速度を g 単位から $\text{m/s}^2$ に直す係数。

実コード（オイラー積分）：

```cpp
const float dt = dtMs * 0.001f;
for (int i = 0; i < 3; ++i) {
    sVel[i] += data.imu.dynAcc[i] * GRAVITY_MS2 * dt;
}
const float vNorm = sqrtf(sVel[0]*sVel[0] + sVel[1]*sVel[1] + sVel[2]*sVel[2]);
sPathLen += vNorm * dt;
```

なぜ「変位ノルム $|\mathbf{x}(t)|$」ではなく「速度ノルムの積分 $L(t) = \int |\mathbf{v}| dt$」か:

- 変位ノルムは振り戻し（往復）で 0 に戻る
- 経路長は単調増加で、**振りの規模** を素直に表す

意図のある振りなら ~150 ms で 0.20 m に達する。手ブレ程度では到達しない。
**閾値（時間の弱い構造）+ 経路長（強い構造）の AND** で誤発火を排除している。

### なぜ Armed 中だけ積分するか

加速度の積分はノイズが時間と共に蓄積していく性質がある（バイアス誤差で速度が
発散する典型問題）。常時積分し続けると Idle 中のノイズが速度に乗り続け、
拍が来る頃には `pathLen` がでたらめな値になる。

そこで **Armed 状態のときだけ積分** する。閾値を超えた瞬間に積分器を 0 リセットして、
振り始めから「拍が確定するまで」の短い時間だけ積分する。

```cpp
if (data.conductor.state == ConductorState::Conducting &&
    data.calibration.done && sGate == BeatGate::Armed) {
    // ここでだけ sVel と sPathLen を更新
}
```

Armed セッションは長くて 800 ms（`BEAT_ARMED_TIMEOUT_MS`）。この時間スケールなら
ノイズの蓄積は無視できる。

## ステップ 5: 状態機械

ここまでの要素を組み合わせて、`BeatGate` という 2 状態のステートマシンを作る。
Idle / Armed の 2 つだけで、発火やリリースは「Armed 中の補助状態」として表現する。

```
   Idle
    │  dynNorm > BEAT_DYN_THRESHOLD_G (= 1.20 g)
    │  ⇒ 積分器を 0 リセットして Armed へ
    ▼
   Armed ──┐
    │     │ 早期発火（1 セッション 1 回まで）:
    │     │   sPathLen >= BEAT_FIRE_PATH_M (= 0.20 m)
    │     │   AND (now - lastBeatMs) >= BEAT_REFRACTORY_MS (= 350 ms)
    │     │   ⇒ 拍を確定。Armed は維持する
    │     └──→
    │
    │  リリース判定（armedFor >= MIN_HOLD_MS かつ release が HOLD_MS 連続）:
    │      (releaseAbs || releaseRatio) AND (firedInArmed || pathOk)
    │  または armedFor >= BEAT_ARMED_TIMEOUT_MS (= 800 ms)
    │  ⇒ Idle に戻す
    ▼
   Idle
```

実コードはこの構造を `enum class BeatGate { Idle, Armed }` + 5 つのフラグ変数で
実現している。

### 補助変数の意味

| 変数 | 意味 |
|---|---|
| `sGate` | 現ステート（Idle / Armed） |
| `sArmedAtMs` | Armed に入った時刻 |
| `sArmedPeakDyn` | Armed 中の `dynNorm` 最大値（リリース比率判定用） |
| `sVel[3]` | Armed 中の速度ベクトル積分 |
| `sPathLen` | Armed 中の経路長 |
| `sBeatFiredInArmed` | この Armed セッションで既に発火したか |
| `sReleaseStartMs` | リリース条件が連続成立し始めた時刻（デバウンス用） |
| `sLastBeatMs` | 直近に拍を発火した時刻（不応期判定用） |

### 早期発火（path 閾値）

```cpp
const bool pathOk = sPathLen >= BEAT_FIRE_PATH_M;
const bool minHoldOk = (now - sArmedAtMs) >= BEAT_ARMED_MIN_HOLD_MS;

if (!sBeatFiredInArmed && pathOk &&
    (now - sLastBeatMs) >= BEAT_REFRACTORY_MS) {
    data.beat.event   = true;
    data.beat.beatNo += 1;
    data.beat.lastBeatMs = now;
    sLastBeatMs       = now;
    sBeatFiredInArmed = true;
    // ※ Armed は維持する（重要）
}
```

**発火しても Armed のまま** にしておくのが鍵。これにより:

- 同じ振りの中で 2 回発火するのを構造的に防ぐ（1 Armed セッションに 1 回まで）
- 連続スイングで「発火 → 即 Idle → すぐ再 Arm → 不応期境界で再発火」という
  暴走ループも構造的に発生しない

発火後は **リリースかタイムアウトで Idle に戻る** のを待つ。

### リリース判定（デバウンス付き）

Armed を抜ける条件は **絶対値リリース** か **相対値リリース** の OR で、
さらに **連続成立** をチェックする：

```cpp
const bool releaseAbs   = data.imu.dynNorm < BEAT_RELEASE_G;
const bool releaseRatio = (sArmedPeakDyn > 0) &&
                          (data.imu.dynNorm < sArmedPeakDyn * BEAT_RELEASE_RATIO);
const bool releaseInst  = releaseAbs || releaseRatio;

// デバウンス: HOLD_MS 連続で成立し続けたら真のリリース
if (releaseInst) {
    if (sReleaseStartMs == 0) sReleaseStartMs = now;
} else {
    sReleaseStartMs = 0;
}
const bool releaseHeld = (sReleaseStartMs != 0) &&
                         (now - sReleaseStartMs >= BEAT_RELEASE_HOLD_MS);
const bool released = minHoldOk && releaseHeld &&
                      (sBeatFiredInArmed || pathOk);
const bool timeout  = (now - sArmedAtMs) >= BEAT_ARMED_TIMEOUT_MS;

if (released || timeout) {
    gateToIdle();
}
```

二段の安全装置：

1. **絶対値（`releaseAbs`）**: 完全停止（`dynNorm < 0.20 g`）したか
2. **相対値（`releaseRatio`）**: Armed 中ピークの 40% 以下まで減衰したか
3. **デバウンス（`HOLD_MS = 40 ms`）**: 一瞬の dip でリリース誤判定しないために連続成立を要求
4. **最小保持（`MIN_HOLD_MS = 50 ms`）**: Armed 突入直後の単発ノイズで即リリースしない

連続スイング（パン・パン・パン）では `dynNorm` が 0 まで落ちきらないので、
相対値リリースが必要。

### タイムアウト

`armedFor >= 800 ms` で強制 Idle。普通の振り下ろしは 200〜500 ms 程度なので、
これは本当の保険。タイムアウトでも `pathOk` を満たしていれば拍として採用される
（取りこぼし防止）。

## ステップ 6: BPM を EMA で平滑化

拍を発火したら、前回拍からの間隔から BPM を計算する：

$$
\text{BPM}_\text{inst} = \frac{60000}{\Delta t_\text{ms}}
$$

これを EMA で滑らかにする：

$$
\text{BPM} \leftarrow (1 - \alpha_\text{bpm}) \, \text{BPM} + \alpha_\text{bpm} \, \text{BPM}_\text{inst}
$$

ここで $\alpha_\text{bpm} = 0.30$（`BPM_EMA_ALPHA`）。実コード：

```cpp
const float instBpm = 60000.0f / (float)intervalMs;
if (!sBpmInit) {
    sBpmEma  = instBpm;   // 2 拍目で簡易テンポを確定
    sBpmInit = true;
} else {
    sBpmEma = (1.0f - BPM_EMA_ALPHA) * sBpmEma + BPM_EMA_ALPHA * instBpm;
}
if (sBpmEma < BPM_MIN) sBpmEma = BPM_MIN;
if (sBpmEma > BPM_MAX) sBpmEma = BPM_MAX;
```

### 初期テンポの段取り

| 拍 | BPM の決め方 |
|---|---|
| 1 拍目 | `sLastBeatMs == 0` なので測れない。初期値 `100 BPM` のまま CTRL を流す |
| 2 拍目 | `sBpmInit == false` なので **「1→2 拍目の間隔」をそのまま BPM とする**（簡易テンポ確定） |
| 3 拍目以降 | `BPM_EMA_ALPHA = 0.30` で随時補正 |

1 拍目から音を出すためには、テンポが取れていない状態でも CTRL を送り続ける必要がある。
初期値 100 BPM はこの「最初の 1 音を鳴らすため」だけに使う。
2 拍目で実テンポに置き換わるので、誤差は 1 拍ぶんだけ。

### なぜ EMA の $\alpha = 0.30$

- $\alpha = 0$: 永遠に最初の値を信じる → テンポ変化に追従しない
- $\alpha = 1$: 直近のジッタが BPM に直接乗る → 音の長さがガタガタする
- $\alpha = 0.30$: 4〜5 拍で新テンポに収束しつつ、単発のジッタは抑え込む

`60000 / BPM` の関係から、BPM の 10% 誤差は durationMs の 10% 誤差になる。
聴感上は 5% 以内なら気にならないので、EMA の残差はそれ未満に抑える必要がある。

## 閾値の根拠

`ProjectConfig.h` 内のコメントから抜粋。すべて実機での試行錯誤で落ち着いた値。

| 定数 | 値 | 経緯 |
|---|---|---|
| `LPF_ALPHA` | 0.10 | 5 ms 周期で時定数 ≒ 50 ms。応答と平滑化のバランス |
| `BEAT_DYN_THRESHOLD_G` | 1.20 g | 仕様書の 1.8g は届かず、0.8g は小揺れで誤発火 → 中間 |
| `BEAT_REFRACTORY_MS` | 350 ms | 170 BPM 上限。指揮の上限としては十分 |
| `BEAT_FIRE_PATH_M` | 0.20 m | 0.10 m では peak 1.3 g 程度の軽い振れで誤発火、0.20 m で安定 |
| `BEAT_RELEASE_G` | 0.20 g | 完全停止判定（連続スイングでは効きにくいので相対値と OR） |
| `BEAT_RELEASE_RATIO` | 0.40 | 連続スイングで Armed を抜けるための主装置 |
| `BEAT_RELEASE_HOLD_MS` | 40 ms | 5 ms 周期で 8 サンプル。チャタリング防止のデバウンス |
| `BEAT_ARMED_MIN_HOLD_MS` | 50 ms | Armed 突入直後の単発ノイズで誤リリースしないため |
| `BEAT_ARMED_TIMEOUT_MS` | 800 ms | 通常 200〜500 ms に対して保険。長すぎても短すぎてもダメ |
| `BPM_EMA_ALPHA` | 0.30 | テンポ変化に 4〜5 拍で追従、ジッタは抑え込む |
| `CALIBRATION_MS` | 2000 ms | 200〜400 サンプル取れる。SoftAP 立ち上がり時間と同程度 |

調整する場合は **`ProjectConfig.h` だけ** を触る。`applyPattern.cpp` のロジックは
これらの定数を引いて動くだけなので、書き換えなくていい（書き換えると EMA の原則に違反する）。

## 全体のデータフロー

```
acc[3] (生)            …… ImuModule::updateInput
   │
   │ LPF (α=0.10)
   ▼
accLpf[3]               …… data.imu.accLpf
   │
   │ ノルム計算
   ▼
accNorm (scalar)        …… data.imu.accNorm
   │
   │ - gravityMag (キャリブ済み)
   ▼
dynNorm (scalar)        …… data.imu.dynNorm
   │             ┌── スカラー: 状態機械の入力
   │             │
   │             └── 向き付きベクトル dynAcc (= accLpf × dynNorm / accNorm)
   │                              │
   │                              │ Armed 中だけ二重積分
   │                              ▼
   │                          sVel[3], sPathLen
   │                              │
   ▼                              ▼
状態機械 (Idle/Armed) ─→ 早期発火 (pathOk + refractory)
   │                                  │
   │                                  ▼
   │                           data.beat.event = true
   │                           data.beat.beatNo += 1
   ▼
リリース / タイムアウト ─→ gateToIdle()
   │
   ▼
BPM EMA (α=0.30) ─→ data.tempo.bpm
                          │
                          ▼
                      OrcSenderModule が CTRL/BEAT を組み立てて UDP に流す
```

## デバッグの観点

`SERIAL_DEBUG = 1` のとき、`main.cpp` の `dumpPeriodic()` が 200 ms ごとに状態を出す：

```
[N1 t=12345 st=Conducting wifi=1 imu=1 acc=(0.10,0.85,-0.05) n=0.88
 dyn=0.03 peakRaw=2.15 peakDyn=1.45 gate=I armedPk=1.20 path=0.000
 bpm=100.5 beatNo=42 ctrlSeq=247 beatSeq=42]
```

各フィールドの意味：

| フィールド | 意味 |
|---|---|
| `acc=(x,y,z)` | LPF 後の加速度 |
| `n` | `accNorm`（LPF 後の加速度ノルム） |
| `dyn` | `dynNorm`（n - gravityMag） |
| `peakRaw` / `peakDyn` | 直近の最大値（リセット可能） |
| `gate` | `I`=Idle / `A`=Armed |
| `armedPk` | 直近 Armed セッションの `dynNorm` ピーク |
| `path` | 直近 Armed セッションの経路長 |
| `bpm` | EMA 後の BPM |
| `beatNo` | 拍番号 |

拍が発火しないとき、まずこれを見ながら：

1. `dyn` が `BEAT_DYN_THRESHOLD_G` を超えているか
2. 超えていれば `gate=A` になっているか
3. `path` が `BEAT_FIRE_PATH_M` まで伸びているか
4. 直前の `beatNo` 増加から `BEAT_REFRACTORY_MS` 経っているか

の順で当たりを付ける。経緯は `Armed → ARM_END` ログ（リリース理由付き）でも分かる：

```
[N1 ARM_END dur=412 peak=1.85 path=0.234 reason=ratio fired=YES]
```

## 次に読むべきページ

- 拍の先の話: [時刻同期メカニズム](/deep-dive/time-sync/)
- センサ生データを取り込むモジュール: `firmware/test_v2/node_01/lib/ImuModule/`
- 拍検出が CTRL/BEAT になる過程: [バイナリパケット](/deep-dive/binary-packet/)
- 新しい入力センサを足したい: [モジュール拡張ガイド](/deep-dive/module-extension/)
