---
title: 倍音抽出・非調和性・残差ノイズ
description: _analyze_harmonics と _analyze_noise の数学を実コードで追う — FFT のピーク探索、放物線補間、非調和性 B フィット、倍音マスクによる残差抽出
sidebar:
  order: 8
---

実体: `sound_lab/analyzer/analyzer.py` 449〜611 行（`_analyze_harmonics` と `_analyze_noise`）。

このページは **「倍音と残差ノイズを実際にどう数学的に取り出しているか」** の解剖。
パイプライン全体は [音声解析パイプライン全体](/pc-audio/analyzer-overview/) を先に。

## 倍音抽出 — 何を作るか

最終的に欲しいのは、JSON の `harmonics[]` に入る次の配列:

```jsonc
"harmonics": [
  { "n": 1, "ratio": 1.000, "amp": 1.0,    "amp_db":   0.0, "phase":  0.32, "env": [...] },
  { "n": 2, "ratio": 2.003, "amp": 0.51,   "amp_db":  -5.8, "phase": -1.42, "env": [...] },
  { "n": 3, "ratio": 2.998, "amp": 0.23,   "amp_db": -12.7, "phase":  0.05, "env": [...] },
  ...
]
```

各倍音について **整数次数 n / 実周波数比 ratio / 正規化振幅 amp / 位相 phase / 時間 env** の
5 つを得る。さらに **非調和性係数 B**（f_n ≈ n·f0·√(1+B·n²)）も別途返す。

## 全体の流れ

```
y[]  (全長)            steady[]  (定常部 = ADSR の loop 区間)
    │                    │
    │                    │ ① 静的スペクトル: 長尺 ゼロパディング FFT
    │                    │     window = hanning
    │                    │     nfft = ≥ 32768 の 2 のべき乗
    │                    ▼
    │              mag[bin] (定常部の振幅スペクトル)
    │                    │
    │                    │ ② 倍音ごとに ±3.5% の窓でピーク探索
    │                    │    放物線補間で真のピーク周波数を推定
    │                    ▼
    │              n, freq_est, amp_lin, phase per harmonic
    │
    │ ③ STFT (全長): 倍音ごとの時間エンベロープ
    │     n_fft = 8192, hop = 220 (200 Hz)
    ▼
 S[bin, frame]
    │  各倍音の bin ±1 を加算 → track[frame] → 32 点にリサンプル
    ▼
 harm_env[k][32]
    │
    │ ④ 非調和性 B の最小二乗フィット
    │    x = n², y = (f_n/(n·f0))² - 1 → 振幅で重み付け原点通過直線
    ▼
 inharmonicity_b
```

## ① 静的スペクトル — 定常部の長尺 FFT

```python
win = np.hanning(len(steady))
sw = steady * win
nfft = 1
while nfft < max(len(sw), 1 << 15):
    nfft <<= 1
spec = np.fft.rfft(sw, n=nfft)
mag = np.abs(spec)
freqs = np.fft.rfftfreq(nfft, d=1.0 / SR)
bin_hz = SR / nfft
noise_floor = float(np.median(mag)) * 3.0 + 1e-9
```

**ポイント:**

- **窓関数は hanning** で側ローブを抑える（矩形窓だとピーク周辺ににじむ）
- **`nfft` を 2 のべき乗 + 32768 以上** に取ってゼロパディングする。サンプル数が
  16384 でも `nfft=32768` にすればビン幅が半分になり、補間精度が上がる
- **ノイズフロア** はスペクトルの中央値 × 3。ピーク振幅がこれ未満なら「検出できなかった」と扱う

`bin_hz = SR / nfft` がスペクトル分解能。`SR=44100, nfft=32768` なら ≈ 1.35 Hz/bin。

## ② 倍音ごとのピーク探索 + 放物線補間

```python
for n in range(1, MAX_HARMONICS + 1):
    target = n * f0
    if target > nyq - 2 * bin_hz:
        break
    tol = max(target * 0.035, 2 * bin_hz)        # ±3.5% の探索窓
    lo = max(0, int((target - tol) / bin_hz))
    hi = min(len(mag) - 1, int((target + tol) / bin_hz))
    if hi <= lo:
        continue
    k = lo + int(np.argmax(mag[lo:hi + 1]))      # 窓内のピーク bin
    amp_lin = float(mag[k])

    # 放物線補間で真のピーク周波数を推定
    if 0 < k < len(mag) - 1:
        a0, a1, a2 = mag[k - 1], mag[k], mag[k + 1]
        denom = (a0 - 2 * a1 + a2)
        delta = 0.5 * (a0 - a2) / denom if abs(denom) > 1e-12 else 0.0
        delta = float(np.clip(delta, -0.5, 0.5))
    else:
        delta = 0.0
    freq_est = (k + delta) * bin_hz
    phase = float(np.angle(spec[k]))
```

**放物線補間** の式の意味:

3 点 `(k-1, a0), (k, a1), (k+1, a2)` を 2 次関数で結ぶと、頂点のオフセットは
`δ = 0.5 · (a0 - a2) / (a0 - 2a1 + a2)`。これで **ビン幅以下の精度** で真のピーク周波数が
推定できる（典型 1/10 ビン精度、≈ 0.1 Hz）。

**±3.5% の探索窓** は半音弱に相当。非調和性で倍音が `n·f0` からずれてもこの窓内に
収まる（B=0.001 でも 40 倍音目で ≈ 1.5% のずれ）。

**位相** は `np.angle(spec[k])`。複素 FFT 係数の偏角。これを `InstrModel.harmPhase[k]` の
初期値にする。

## ③ STFT で倍音ごとの時間エンベロープ

```python
n_fft_stft = 8192
S = np.abs(librosa.stft(y, n_fft=n_fft_stft, hop_length=ENV_HOP, center=True))
stft_bin_hz = SR / n_fft_stft

# 各倍音について最近傍 bin ± 1 を加算して時間トラックを取る
for n in range(...):
    kb = int(round(target / stft_bin_hz))
    b0, b1 = max(0, kb - 1), min(S.shape[0] - 1, kb + 1)
    track = S[b0:b1 + 1, :].sum(axis=0)        # 形状: (frames,)
    tmax = float(np.max(track))
    h_env = (track / tmax) if tmax > 1e-12 else np.zeros_like(track)
    h_env = _resample_curve(h_env, HARM_ENV_POINTS)   # 32 点に揃える
```

**ポイント:**

- **STFT は全長** で取る（定常部ではない）。倍音は時間とともに振幅が変わるので、その変化を
  キャプチャするため
- **bin ±1 を加算** することで、bin 境界をまたぐエネルギーも拾う
- 各倍音 env は **自分の最大が 1** になるよう正規化（後段で `amp` と掛けるので）
- **32 点に揃える** ことで JSON のサイズが楽器によらず固定になる（持続音の長い env も
  打楽器の短い env も同じ表現）

`hop_length=ENV_HOP=220` で 200 Hz のフレームレート。

## ④ 非調和性 B のフィット

物理: 弦楽器の倍音は完全な整数倍ではなく、

```
f_n = n · f_0 · √(1 + B · n²)
```

（B はヤング率 × 弦の直径⁴ / (張力 × 長さ⁴) に依存する係数）

両辺を `n·f0` で割って 2 乗:

```
(f_n / (n · f_0))² = 1 + B · n²
```

これを **`x = n²`、`y = (f_n / (n·f_0))² - 1`** と置けば、`y = B · x` の **原点通過直線**。
**振幅 `amp_lin` で重み付けた最小二乗** で B を求める:

```python
det_n = np.asarray(det_n, dtype=float)
det_f = np.asarray(det_f, dtype=float)
wts = np.asarray(det_a, dtype=float)
x = det_n ** 2
yv = (det_f / (det_n * f0)) ** 2 - 1.0
denom = float(np.sum(wts * x * x))
if denom > 1e-12:
    inharmonicity_b = float(np.sum(wts * x * yv) / denom)
inharmonicity_b = float(np.clip(inharmonicity_b, 0.0, 0.01))
```

公式: `B = Σ w·x·y / Σ w·x²`（原点通過なので普通の OLS より簡単）。

**`0.01` でクランプ** している理由: ピアノでも B は ≈ 0.0005 程度。0.01 を超える値は
ほぼ確実に検出ミスなので物理的に妥当な範囲に丸める。

:::tip[B の典型値]
| 楽器 | 典型的な B |
|---|---|
| オルガン / フルート | ≈ 0 |
| バイオリン / チェロ | 1e-5 〜 1e-4 |
| アコースティックギター | 1e-4 〜 5e-4 |
| ピアノ低音域 | 1e-4 〜 1e-3 |
| ピアノ高音域 | 1e-3 〜 5e-3 |
:::

## 倍音振幅の正規化

```python
amax = max((h["amp_lin"] for h in harmonics), default=1.0) or 1.0
out = []
for h in harmonics:
    amp = h["amp_lin"] / amax
    out.append({
        "n": h["n"],
        "ratio": _r(h["freq_hz"] / f0, 4),
        "amp": _r(amp, 5),
        "amp_db": _r(20.0 * math.log10(amp + 1e-9), 2),
        "phase": _r(h["phase"], 4),
        "env": _r(h["env"], 4),
    })
```

**倍音中の最大が 1.0** になるよう全部を割る。再合成側は `amp` の総和で正規化（`harmNorm`）
するので、ここでスケールを揃えておくと合成側がスッキリする。

`amp_db = 20·log10(amp)` は UI 表示用。

## 残差ノイズ — 倍音マスクからの抽出

`_analyze_noise()` の中身（564〜611 行）。

### ① STFT を取る

```python
n_fft = 4096
S = librosa.stft(y, n_fft=n_fft, hop_length=ENV_HOP, center=True)
mag = np.abs(S)
freqs = librosa.fft_frequencies(sr=SR, n_fft=n_fft)
bin_hz = SR / n_fft
```

倍音解析の STFT より小さい `n_fft=4096` を使う。ノイズは細かい周波数分解能を必要としない
（むしろ細かいと残差が「倍音」として残りやすい）。

### ② 倍音マスクを作る

```python
harm_mask = np.zeros(mag.shape[0], dtype=bool)
for h in harmonics:
    if h["amp"] <= 0.0:
        continue
    fc = h["ratio"] * f0
    tol = max(fc * 0.03, 1.5 * bin_hz)             # ±3%
    lo = max(0, int((fc - tol) / bin_hz))
    hi = min(mag.shape[0] - 1, int((fc + tol) / bin_hz))
    harm_mask[lo:hi + 1] = True

# DC 近傍 (40 Hz 未満) も調和扱い（ハム/オフセット）
harm_mask[:max(1, int(40.0 / bin_hz))] = True
```

各倍音の **±3%** の bin を「調和成分」とみなしてマスク。DC 近傍も入れる（電源ハム 50/60 Hz
を取り除くため）。

### ③ 残差スペクトルを作る

```python
resid = mag.copy()
resid[harm_mask, :] = 0.0
full_rms = np.sqrt(np.mean(mag ** 2, axis=0)) + 1e-12     # フレームごとの全体 RMS
res_rms = np.sqrt(np.mean(resid ** 2, axis=0))             # フレームごとの残差 RMS

res_peak = float(np.max(res_rms))
sig_peak = float(np.max(full_rms))
level = float(np.clip(res_peak / (sig_peak + 1e-12), 0.0, 1.0))
env_shape = _resample_curve(res_rms / (res_peak + 1e-12), min(n_env, ENV_MAX_POINTS))
```

**`level`** は「全体のピーク振幅に対するノイズのピーク振幅の比」。0.05 でも息音が
聞こえる感じ、0.2 で明らかな粒立ち、0.5 でぼやけた音。

**`envelope`** は時間方向の形状を `n_env` 点にリサンプル。アタックに山が出る楽器が多い
（撥弦のスナップ、息のバースト）。

### ④ 帯域別レベル

```python
res_mean = np.mean(resid, axis=1)              # 全フレーム平均
bands = NOISE_BANDS_HZ                          # [0,125,250,500,1000,2000,4000,8000,16000,22050]
band_vals = []
for i in range(len(bands) - 1):
    sel = (freqs >= bands[i]) & (freqs < bands[i + 1])
    band_vals.append(float(np.mean(res_mean[sel])) if np.any(sel) else 0.0)
bmax = max(band_vals) or 1.0
band_levels = [v / bmax for v in band_vals]
```

**残差スペクトルの帯域平均** を取って、最大値で正規化。これが Processing 側の
`makeShapedNoise()` で **FFT 整形ノイズの色** になる。

オクターブ近い境界（125 / 250 / 500 / 1000 / ...）にしてあるのは、聴覚特性に合わせるため
（メル尺度に近い）。

## 全体としての品質

このアルゴリズムが **何を捉え、何を逃すか**:

| 捉えられるもの | 逃すもの |
|---|---|
| 整音された倍音列（管弦・声・ピアノ） | アタックのトランジェント詳細（時間方向 5 ms 程度で平均化される） |
| 非調和性のずれ | 高速で揺れる倍音（200 Hz 以下の env サンプリングなので 100 Hz 以上の変動は失われる） |
| 持続的な息音・弓擦り音 | 短い打撃ノイズの正確な時間波形（envelope は時間形状のみ、波形そのものは整形ノイズで近似） |
| ビブラート・トレモロ | フリーキーな表現（ピッチベンド・グロウル・グロッタル） |

これらの限界は **加算合成の根本的な制約**。サンプル再生にすれば全部取れるが、JSON
サイズが MB 単位に膨らむ。トレードオフを理解した上で選んでいる。

## どこを書き換えるか

| やりたいこと | 触る場所 |
|---|---|
| 倍音数を 40 → 80 に増やす | `MAX_HARMONICS = 80`、`nfft` を上げてビン幅を狭く |
| 非調和性を整数次数に戻す | `harmonics[k].ratio` を `n` で上書き（高音域がチープになる） |
| ノイズの時間分解能を上げる | `ENV_HOP` を下げる（200 Hz → 500 Hz）、`InstrModel` 側のロードは無変更 |
| 倍音マスクを ±3% から狭く | `tol = max(fc * 0.015, ...)` に。倍音のすぐ脇のノイズが残るので「弓擦り感」が増える |
| 非調和性 B を負も許す | `clip(b, -0.01, 0.01)` に。スリップした管楽器など |

## 次のページ

- 基音検出と揺れ判定 → [基音検出・ADSR・ビブラート](/pc-audio/analyzer-modulation/)
- ここで作った数値の使い手 → [音色定義モデル（InstrModel）と JSON](/pc-audio/instr-model/)
- 合成側の数学 → [加算合成ボイス（ResynthVoice）](/pc-audio/resynth-voice/)
