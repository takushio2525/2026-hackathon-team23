---
title: 基音検出・ADSR・ビブラート
description: pyin と自己相関による基音検出、振幅エンベロープの ADSR 当てはめ、ビブラート / トレモロ の周期成分検出
sidebar:
  order: 9
---

実体: `sound_lab/analyzer/analyzer.py`
- `_trim_silence`（103〜130 行）
- `_detect_fundamental`（251〜270 行）
- `_fit_adsr`（387〜445 行）
- `_detect_modulation` / `_periodicity`（280〜360 行）

このページは **「時間方向の解析」** を担当する関数たちの解剖。倍音まわりは
[倍音抽出・非調和性・残差ノイズ](/pc-audio/analyzer-harmonics/) に分けてある。

## トリム — 先頭と末尾の無音を切る

実楽器の録音には **準備音・暗騒音・呼吸** が前後に必ず入る。これを解析に渡すと:

- ADSR フィットが「立ち上がりがゆっくり」と誤判定（暗騒音を音と勘違い）
- 倍音 env の冒頭がフラットに見える

なので最初に `_trim_silence` で **積極的に無音を除去** する。

```python
TRIM_LEAD_DB = 20.0              # 先頭: -20dB 未満は無音とみなしてカット
TRIM_TRAIL_DB = 50.0             # 末尾: -50dB 未満をカット
TRIM_PRE_ROLL_MS = 20.0          # 先頭立ち上がり手前に残す余白
TRIM_POST_ROLL_MS = 80.0         # 末尾に残す余白

def _trim_silence(y, sr):
    if y.size < sr // 50:                                        # 20 ms 未満は触らない
        return y, 0, 0
    rms = librosa.feature.rms(y=y, frame_length=1024, hop_length=256, center=True)[0]
    peak = float(rms.max())
    lead_thr = peak * (10.0 ** (-TRIM_LEAD_DB / 20.0))           # -20dB
    trail_thr = peak * (10.0 ** (-TRIM_TRAIL_DB / 20.0))         # -50dB
    lead_idx = np.where(rms >= lead_thr)[0]
    trail_idx = np.where(rms >= trail_thr)[0]
    start = max(0, int(lead_idx[0]) * 256 - int(0.020 * sr))    # 20 ms 前
    end = min(y.size, (int(trail_idx[-1]) + 1) * 256 + int(0.080 * sr))  # 80 ms 後
    return y[start:end], start, y.size - end
```

**先頭と末尾で閾値を変える** のがコツ:

- 先頭は **-20dB の強めカット**: 準備音・暗騒音・息は十分大きいことが多い
- 末尾は **-50dB の緩めカット**: 減衰の尾を残すため（ピアノの残響など）

`PRE_ROLL_MS=20ms` / `POST_ROLL_MS=80ms` の余白を残すのは、フェードの自然な部分まで
切ってしまうのを防ぐため。

**保険**: トリム後の長さが 50 ms 未満なら諦めて元のまま返す（極短音への配慮）。

## 基音検出 — pyin と自己相関の 2 段

```python
def _detect_fundamental(y):
    try:
        f0, _, _ = librosa.pyin(
            y, fmin=max(FMIN, 55.0), fmax=min(FMAX, 2000.0),
            sr=SR, frame_length=PYIN_FRAME, hop_length=PYIN_HOP)
        f0v = f0[~np.isnan(f0)]
        if f0v.size >= 3:
            return float(np.median(f0v)), np.asarray(f0, dtype=float)
    except Exception:
        pass

    # フォールバック: 自己相関
    peak = int(np.argmax(np.abs(y)))
    seg = y[peak:peak + min(y.size - peak, int(0.2 * SR))]
    f0 = _autocorr_f0(seg if seg.size > 1024 else y, SR)
    if f0 is None or not (FMIN <= f0 <= FMAX):
        raise AnalysisError("基音を検出できませんでした。...")
    return float(f0), None
```

### なぜ 2 段か

**pyin** は確率モデル付き YIN で、近年の標準的な基音検出器。精度高いが:

- 音が短すぎると失敗（フレーム 2048 サンプル ≈ 46 ms に届かない）
- ノイズが極端に多い音は判定できない
- librosa のバージョン依存で例外を投げる

これらに当たったとき **完全に解析を諦めるのは惜しい** ので、自己相関フォールバックを置く。

### pyin の中身（概要）

YIN: 自己相関の改良版。差分関数:

```
d(τ) = Σ_t (x(t) - x(t+τ))²
```

を計算し、正規化版 `d'(τ)` の最小値が周期に対応する。pYIN は確率モデルを乗せて
ピッチの分布を出力し、`fmin..fmax` の範囲外を抑える。

実装は librosa.pyin に任せて、結果は **NaN を除いた中央値**:

```python
f0v = f0[~np.isnan(f0)]
return float(np.median(f0v))
```

中央値を使うのは外れ値（アタック直後の倍音誤検出など）への頑強性のため。

### 自己相関フォールバック

```python
def _autocorr_f0(seg, sr):
    seg = seg - float(np.mean(seg))                     # DC 除去
    corr = np.correlate(seg, seg, mode="full")[len(seg) - 1:]
    lo = max(1, int(sr / FMAX))                         # 探索範囲下限
    hi = min(len(corr) - 1, int(sr / FMIN))             # 上限
    lag = lo + int(np.argmax(corr[lo:hi]))              # ピーク位置 → 周期
    return sr / lag                                      # 周期 → 周波数
```

最も単純な自己相関ベース。**精度は pyin より落ちる**（オクターブエラーの可能性が高い）が、
最後の保険として置いてある。

### f0 トラックの保持

`f0_track` を `_detect_modulation` でビブラート解析に使う。pyin は時間方向の f0 トラック
（フレームごとの Hz）を返すので、それを保持して別の関数に渡す。

自己相関フォールバックでは f0 トラックを取れないので `None` を返す。

## 全体振幅エンベロープ

`librosa.feature.rms` で計算:

```python
rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=ENV_HOP, center=True)[0]
rms_peak = float(np.max(rms))
env = rms / (rms_peak + 1e-12)                          # 0..1 に正規化
```

- **`frame_length=2048`** ≈ 46 ms の窓で RMS（典型的なエンベロープ追従の解像度）
- **`hop_length=220`** で 200 Hz 出力（5 ms ごとに 1 サンプル）
- **ピーク=1 に正規化**: 後段で都合がいい

`center=True` は librosa の慣習で、フレームの中心を時刻とする（境界誤差を半フレームに抑える）。

## ADSR 当てはめ — 振幅エンベロープから 4 値を取る

ADSR は「Attack（立ち上がり）/ Decay（減衰）/ Sustain（持続レベル）/ Release（後尾）」の 4 つ
だけで音の包絡を近似する古典的モデル。**実際の楽器音はこの 4 値で表せない** が、
合成側の **簡易モード** やループ点計算のために当てはめる。

```python
_ATTACK_NEAR_PEAK = 0.85   # ピークの 85% に最初に達した点をアタック終了
_ONSET_LEVEL = 0.10        # 立ち上がり開始とみなすレベル
_END_LEVEL = 0.05          # 末尾無音切り
```

### アルゴリズム

```python
def _fit_adsr(env, rate_hz):
    # ① 立ち上がり開始 onset
    above_onset = np.where(env >= _ONSET_LEVEL)[0]
    onset_idx = int(above_onset[0]) if above_onset.size else 0

    # ② アタック終了 body_start (ピークの 85%)
    near_peak = np.where(env[onset_idx:] >= _ATTACK_NEAR_PEAK)[0]
    body_start = onset_idx + int(near_peak[0]) if near_peak.size else int(np.argmax(env))
    attack_sec = max(body_start - onset_idx, 1) / rate_hz

    # ③ 末尾 end_idx
    above_end = np.where(env >= _END_LEVEL)[0]
    end_idx = int(above_end[-1]) if above_end.size else n - 1
    tail = end_idx - body_start

    # ④ サステイン: 中盤 [0.30, 0.70] の中央値
    m0 = body_start + int(0.30 * tail)
    m1 = body_start + int(0.70 * tail)
    sustain_level = float(np.clip(np.median(env[m0:m1 + 1]), 0.0, 1.0))

    # ⑤ ディケイ: body_start から sustain_level まで下がる時間
    target = max(sustain_level, math.e ** -1) if sustain_level < 0.05 else sustain_level
    decay_end = body_start
    for i in range(body_start, end_idx + 1):
        if env[i] <= target:
            decay_end = i
            break
    else:
        decay_end = m0
    decay_sec = max(decay_end - body_start, 1) / rate_hz

    # ⑥ リリース: m1 から end_idx までの尻尾
    release_sec = max(end_idx - m1, 1) / rate_hz

    # ⑦ ループ点: 中盤の窓
    loop_start_sec = m0 / rate_hz
    loop_end_sec = m1 / rate_hz
    return dict(attack_sec=..., decay_sec=..., sustain_level=..., release_sec=...,
                loop_start_sec=..., loop_end_sec=...)
```

### なぜ「ピークの 85%」をアタック終了とするか

「ピーク到達まで」を attack とすると、本体に強弱の揺らぎがある音（vibrato 中の音、
息継ぎ後の最大点）で **attack が極端に長く** 出てしまう。85% で打ち切ると **立ち上がりだけ**
を確実に捉えられる。

### サステインの取り方

「中盤 30〜70% の中央値」というシンプルなルール。**平均** ではなく **中央値** を使うのは、
ビブラートやトレモロで揺れている部分の影響を平準化するため。

### ディケイのターゲット

`target = max(sustain_level, 1/e) if sustain_level < 0.05 else sustain_level` の意味:

- 通常は sustain_level を目標値にする
- ただし sustain がほぼ 0（減衰音）なら **1/e ≈ 0.37** を目標にする
  （定石: 自然な減衰の時定数）

これで「ピアノのような減衰音でも decay_sec が妥当な値になる」よう設計されている。

### ループ点 (`loop_start_sec` / `loop_end_sec`)

中盤 30〜70% の窓そのものをループ区間とする。**持続音を要求長まで伸ばす** とき、
Processing 側はこの区間を循環参照する。

## ビブラート / トレモロ — 周期成分の検出

`_detect_modulation` で f0 トラックと env から **3〜9 Hz の周期揺れ** を検出する。

### 共通の `_periodicity()`

```python
def _periodicity(seg, rate_hz, band):
    seg = seg - float(np.mean(seg))                     # DC 除去

    # 低周波ドリフト除去（移動平均を引く）
    w = max(3, int(round(rate_hz / (band[0] * 0.5))))
    if 3 <= w < n:
        seg = seg - np.convolve(seg, np.ones(w) / w, mode="same")

    rms = float(np.sqrt(np.mean(seg ** 2)))
    win = np.hanning(n)
    sp = np.abs(np.fft.rfft(seg * win))                 # 窓掛け FFT
    fq = np.fft.rfftfreq(n, d=1.0 / rate_hz)
    sel = (fq >= band[0]) & (fq <= band[1])

    band_idx = np.where(sel)[0]
    k = int(band_idx[np.argmax(sp[band_idx])])           # 帯域内のピーク
    freq = float(fq[k])
    amp = 2.0 * float(sp[k]) / win_sum                   # 窓補正つき振幅 (片振幅)
    med = float(np.median(sp[sel])) + 1e-12
    regularity = float(sp[k] / med)                      # 卓越度

    # ピーク到達: |seg| が片振幅の半分を最初に超えるフレーム
    over = np.where(np.abs(seg) >= amp * 0.5)[0]
    onset_idx = int(over[0]) if over.size else 0
    return freq, amp, regularity, rms, onset_idx
```

要点:

- **DC とドリフト除去**: ビブラートは「平均値からのずれ」なので、長期トレンドを除く
- **`np.hanning(n)` で窓掛け** してから FFT: 側ローブを抑える
- **窓補正つき振幅** `amp = 2·|spec| / sum(window)`: 窓関数で振幅が減衰した分を補正
- **regularity（卓越度）** = 帯域内のピーク振幅 / 中央値。** 周期性の強さ** を 1 つの数値で
  表す（4 以上で周期的、12 以上で明瞭）

### ビブラート (`vibrato`)

```python
ft = np.interp(np.arange(ft.size), np.flatnonzero(good), ft[good])  # NaN を埋める
cents = 1200.0 * np.log2(ft / (np.median(ft) + 1e-12))               # 中央値からのセント差
lo, hi = int(cents.size * 0.2), int(cents.size * 0.8)
r = _periodicity(cents[lo:hi], F0_TRACK_HZ, VIBRATO_BAND_HZ)
if r is not None:
    freq, amp, reg, rms, onset_idx = r
    pp = 2.0 * amp                          # 全振幅 (セント)
    if pp >= 8.0 and reg >= 4.0 and rms >= 3.0:
        out["vibrato"] = {
            "rate_hz": freq,
            "depth_cents": min(pp, 200.0),
            "depth": min(pp, 200.0) / 100.0,
            "onset_sec": (lo + onset_idx) / F0_TRACK_HZ,
            "regularity": min(reg / 12.0, 1.0),
            "detected": True,
        }
```

**判定の閾値:**

| 条件 | 値 | 意味 |
|---|---|---|
| `pp >= 8.0` | 全幅 8 セント以上 | 自然なビブラートの下限 |
| `reg >= 4.0` | 卓越度 4 以上 | 帯域内で明確に出ている |
| `rms >= 3.0` | セント単位 RMS 3 以上 | ピッチの揺れ自体が一定量ある |

3 つ全部クリアして初めて「ビブラートあり」と判定。**`detected: false` ならその揺れは合成に
乗らない**。

**中央 20〜80%** の区間で評価するのは、頭と末尾の不安定なピッチを除外するため。

### トレモロ (`tremolo`)

```python
e = np.asarray(env, dtype=float)
lo, hi = int(e.size * 0.2), int(e.size * 0.8)
base = float(np.mean(e[lo:hi])) + 1e-9
r = _periodicity(e[lo:hi], env_rate, VIBRATO_BAND_HZ)
if r is not None:
    freq, amp, reg, rms, onset_idx = r
    depth = 2.0 * amp / base                              # 平均レベルに対する全幅
    if depth >= 0.04 and reg >= 4.0 and rms / base >= 0.015:
        out["tremolo"] = {
            "rate_hz": freq,
            "depth": min(depth, 1.0),
            ...
            "detected": True,
        }
```

ビブラートとほぼ同じ構造だが、対象が **振幅エンベロープ** で、深さは **平均レベルに対する比率**:

| 条件 | 値 |
|---|---|
| `depth >= 0.04` | 平均の 4% 以上の振幅変動 |
| `reg >= 4.0` | 卓越度 4 以上 |
| `rms / base >= 0.015` | 平均レベルの 1.5% 以上の RMS |

## 全体としての設計判断

| 判断 | なぜ |
|---|---|
| トリムを積極的に | 解析の最初で確実に無音を切る、後段が全部楽になる |
| pyin + 自己相関 2 段 | pyin は精度高いが失敗することがあるので保険 |
| ADSR は実エンベロープと併存 | 実エンベロープを主、ADSR は簡易合成 / ループ点計算のため |
| 揺れの検出は閾値ベース | ML 不要。閾値を 3 つ AND して誤検出を抑える |
| `detected` フラグで明示 | 合成側が「自動スキップ」できるよう、不可で値ゼロでなくフラグで切る |

## どこを書き換えるか

| やりたいこと | 触る場所 |
|---|---|
| 別の基音検出（CREPE 等） | `_detect_fundamental` を差し替え、f0_track を同じ形で返す |
| ADSR をやめて実エンベロープのみに | `_fit_adsr` を呼ばずに `envelope.values[]` だけ出す。`InstrModel` 側は ADSR 4 値が無くてもデフォルトで動く |
| ビブラート閾値を厳しく / 緩く | `pp >= 8.0`, `reg >= 4.0`, `rms >= 3.0` を調整 |
| トリム閾値を変える | `TRIM_LEAD_DB` / `TRIM_TRAIL_DB` を変える。本番リハで暗騒音多い環境なら -15dB / -45dB に |
| 揺れの周波数帯を広げる | `VIBRATO_BAND_HZ = (2.0, 12.0)` 等。歌声のシェイク（10 Hz 超）も拾える |

## 次のページ

- 倍音まわりの数学 → [倍音抽出・非調和性・残差ノイズ](/pc-audio/analyzer-harmonics/)
- パイプライン全体 → [音声解析パイプライン全体](/pc-audio/analyzer-overview/)
- これらの数値の使い手 → [音色定義モデル（InstrModel）と JSON](/pc-audio/instr-model/)
