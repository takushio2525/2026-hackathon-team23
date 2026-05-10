"""楽器の単音音源を解析してインストゥルメント定義(dict / JSON 化可能)を組み立てるコア。

抽出する内容:
  - 基音(pyin、失敗時は自己相関フォールバック) / 最近傍 MIDI ノート
  - 全体振幅エンベロープ(200 Hz) と そこから当てはめた ADSR + ループ点
  - 倍音列(振幅・位相・実周波数比) と 倍音ごとの時間エンベロープ
  - 非調和性係数 B  (f_n ≈ n·f0·√(1 + B·n²))
  - 残差ノイズ(調和成分をスペクトル減算した残り)の レベル / 時間包絡 / 帯域スペクトル
  - 定常部から取り出した単一周期波形(ウェーブテーブル用)
  - 表示用の各種スペクトル特徴量

フォーマットの詳細は sound_lab/library_format.md を参照。
"""

from __future__ import annotations

import math
import os
from datetime import datetime, timezone

import numpy as np

try:
    import librosa
except ImportError as exc:  # pragma: no cover - 環境依存
    raise ImportError(
        "librosa が見つかりません。`pip install -r requirements.txt` を実行してください。"
    ) from exc


# ── 解析パラメータ ─────────────────────────────────────────────
SR = 44100                       # 内部サンプルレート
ENV_HZ = 200                     # 振幅エンベロープのサンプルレート
ENV_HOP = SR // ENV_HZ           # = 220 サンプル
MAX_HARMONICS = 40               # 取り出す倍音の最大数
HARM_ENV_POINTS = 32             # 倍音ごとの時間エンベロープの点数
ENV_MAX_POINTS = 1200            # 全体エンベロープの最大点数(これを超えたら間引く ≒ 6 秒)
ONE_CYCLE_POINTS = 1024          # 単一周期波形の点数
NOISE_BANDS_HZ = [0, 125, 250, 500, 1000, 2000, 4000, 8000, 16000, SR // 2]
FMIN = 50.0                      # 基音探索の下限
FMAX = 2200.0                    # 基音探索の上限
_NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


class AnalysisError(ValueError):
    """ユーザーに見せる前提のエラー(無音・短すぎ・基音不明 など)。"""


# ── 小道具 ───────────────────────────────────────────────────
def _hz_to_midi(hz: float) -> float:
    return 69.0 + 12.0 * math.log2(hz / 440.0)


def _midi_to_name(midi: float) -> str:
    m = int(round(midi))
    return f"{_NOTE_NAMES[m % 12]}{m // 12 - 1}"


def _r(x, ndigits: int = 5):
    """np スカラ/配列を round して素の float / list に落とす(JSON 化用)。"""
    arr = np.round(np.asarray(x, dtype=float), ndigits)
    if arr.ndim == 0:
        v = float(arr)
        return 0.0 if v == 0.0 else v   # -0.0 を 0.0 に
    return [float(v) for v in arr]


def _resample_curve(values: np.ndarray, n_out: int) -> np.ndarray:
    """1 次元カーブを線形補間で n_out 点に貼り直す。"""
    values = np.asarray(values, dtype=float)
    if len(values) == n_out:
        return values
    if len(values) <= 1:
        return np.full(n_out, float(values[0]) if len(values) else 0.0)
    xp = np.linspace(0.0, 1.0, len(values))
    x = np.linspace(0.0, 1.0, n_out)
    return np.interp(x, xp, values)


def _autocorr_f0(seg: np.ndarray, sr: int) -> float | None:
    """pyin が使えないとき用の自己相関ベース基音推定。"""
    seg = seg - float(np.mean(seg))
    if np.allclose(seg, 0.0):
        return None
    corr = np.correlate(seg, seg, mode="full")[len(seg) - 1:]
    lo = max(1, int(sr / FMAX))
    hi = min(len(corr) - 1, int(sr / FMIN))
    if hi <= lo:
        return None
    lag = lo + int(np.argmax(corr[lo:hi]))
    return sr / lag if lag > 0 else None


# ── メイン ───────────────────────────────────────────────────
def analyze_file(path: str, name: str | None = None) -> dict:
    """音源ファイルを解析して {"instrument": {...}, "preview": {...}} を返す。"""
    source_file = os.path.basename(path)
    if name is None:
        name = os.path.splitext(source_file)[0]

    y, _ = librosa.load(path, sr=SR, mono=True)
    if y.size == 0 or float(np.max(np.abs(y))) < 1e-5:
        raise AnalysisError("無音、または音量が小さすぎて解析できません。")

    # 前後の無音を控えめにトリム(アタック頭を削りすぎないよう top_db は緩め)
    y_trim, _ = librosa.effects.trim(y, top_db=45)
    if y_trim.size >= SR // 20:          # 50 ms 以上残れば採用
        y = y_trim
    if y.size < SR // 10:                # 0.1 秒未満は短すぎ
        raise AnalysisError("音が短すぎます(0.1 秒以上の単音を渡してください)。")

    duration_sec = y.size / SR

    # ── 全体振幅エンベロープ(200 Hz) ──────────────────────
    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=ENV_HOP, center=True)[0]
    rms_peak = float(np.max(rms))
    env = rms / (rms_peak + 1e-12)        # 0..1, ピーク=1
    n_env = len(env)

    # ── 基音検出 ────────────────────────────────────────
    fundamental = _detect_fundamental(y)
    midi = _hz_to_midi(fundamental)

    # ── ADSR + ループ点の当てはめ ────────────────────────
    adsr = _fit_adsr(env, ENV_HZ)
    sustaining = adsr["sustain_level"] > 0.18

    # ── 定常部(倍音解析に使う窓) ────────────────────────
    a_idx = int(round(adsr["loop_start_sec"] * ENV_HZ))
    b_idx = int(round(adsr["loop_end_sec"] * ENV_HZ))
    a_samp = max(0, a_idx * ENV_HOP)
    b_samp = min(y.size, max(a_samp + 4096, b_idx * ENV_HOP))
    steady = y[a_samp:b_samp]
    if steady.size < 4096:                # 短ければアタック直後を使う
        peak_samp = int(np.argmax(np.abs(y)))
        steady = y[peak_samp:peak_samp + max(4096, int(0.3 * SR))]
    if steady.size < 2048:
        steady = y

    # ── 倍音列 + 倍音ごとの時間エンベロープ ──────────────
    harmonics, inharmonicity_b, spectrum_preview = _analyze_harmonics(
        y, steady, fundamental, n_env)

    # ── 残差ノイズ ──────────────────────────────────────
    noise = _analyze_noise(y, fundamental, harmonics, n_env)

    # ── 単一周期波形 ────────────────────────────────────
    one_cycle = _extract_one_cycle(steady, fundamental, SR)

    # ── 表示用特徴量 ────────────────────────────────────
    features = _spectral_features(y, steady)
    features["rms_peak"] = _r(rms_peak, 4)
    features["harmonic_count"] = int(sum(1 for h in harmonics if h["amp"] > 0.0))

    # ── 全体エンベロープを必要なら間引いて格納 ───────────
    env_out = env
    if n_env > ENV_MAX_POINTS:
        env_out = _resample_curve(env, ENV_MAX_POINTS)
    env_rate_out = ENV_HZ if env_out is env else ENV_MAX_POINTS / duration_sec

    instrument = {
        "format": "sound_lab.instrument/1",
        "name": name,
        "source_file": source_file,
        "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "sample_rate": SR,
        "fundamental_hz": _r(fundamental, 3),
        "midi_note": int(round(midi)),
        "note_name": _midi_to_name(midi),
        "duration_sec": _r(duration_sec, 4),
        "sustaining": bool(sustaining),
        "envelope": {
            "rate_hz": _r(env_rate_out, 3),
            "values": _r(env_out, 4),
            "attack_sec": _r(adsr["attack_sec"], 4),
            "decay_sec": _r(adsr["decay_sec"], 4),
            "sustain_level": _r(adsr["sustain_level"], 4),
            "release_sec": _r(adsr["release_sec"], 4),
            "loop_start_sec": _r(adsr["loop_start_sec"], 4),
            "loop_end_sec": _r(adsr["loop_end_sec"], 4),
        },
        "inharmonicity_b": _r(inharmonicity_b, 7),
        "harmonics": harmonics,
        "noise": noise,
        "waveform": {
            "one_cycle_points": len(one_cycle),
            "one_cycle": _r(one_cycle, 4),
        },
        "features": features,
    }

    preview = {
        "waveform": _waveform_preview(y, 2000),
        "spectrum_freq": spectrum_preview["freq"],
        "spectrum_db": spectrum_preview["db"],
    }
    return {"instrument": instrument, "preview": preview}


# ── 基音 ─────────────────────────────────────────────────────
def _detect_fundamental(y: np.ndarray) -> float:
    try:
        f0, _, voiced_prob = librosa.pyin(
            y, fmin=max(FMIN, 55.0), fmax=min(FMAX, 2000.0), sr=SR, frame_length=2048)
        f0v = f0[~np.isnan(f0)]
        if f0v.size >= 3:
            # 安定区間(中央あたり)の中央値を採る
            return float(np.median(f0v))
    except Exception:
        pass
    # フォールバック: 振幅最大付近の自己相関
    peak = int(np.argmax(np.abs(y)))
    seg = y[peak:peak + min(y.size - peak, int(0.2 * SR))]
    f0 = _autocorr_f0(seg if seg.size > 1024 else y, SR)
    if f0 is None or not (FMIN <= f0 <= FMAX):
        raise AnalysisError(
            "基音を検出できませんでした。和音やノイズではなく、ピッチのはっきりした単音を渡してください。")
    return float(f0)


# ── ADSR ─────────────────────────────────────────────────────
def _fit_adsr(env: np.ndarray, rate_hz: int) -> dict:
    """0..1 正規化済みエンベロープから ADSR とループ点(秒)を当てはめる。"""
    n = len(env)
    if n < 3:
        return dict(attack_sec=0.005, decay_sec=0.05, sustain_level=0.5,
                    release_sec=0.05, loop_start_sec=0.0, loop_end_sec=max(0.0, (n - 1) / rate_hz))

    peak_idx = int(np.argmax(env))
    # アタック: 振幅 10% 到達点 → ピーク
    above10 = np.where(env >= 0.10)[0]
    start_idx = int(above10[0]) if above10.size else 0
    attack_sec = max(peak_idx - start_idx, 1) / rate_hz

    # ピーク後の有効区間 [peak_idx, end_idx](末尾の無音を除く)
    above5 = np.where(env >= 0.05)[0]
    end_idx = int(above5[-1]) if above5.size else n - 1
    if end_idx <= peak_idx:
        end_idx = n - 1
    tail = end_idx - peak_idx

    if tail < 4:        # 打撃音などピーク即終了
        return dict(attack_sec=attack_sec, decay_sec=max(tail, 1) / rate_hz,
                    sustain_level=float(env[end_idx]),
                    release_sec=max(tail, 1) / rate_hz,
                    loop_start_sec=peak_idx / rate_hz, loop_end_sec=end_idx / rate_hz)

    # ピーク後を 0.35〜0.70 の窓で見て「中盤レベル」をサステインとみなす
    m0 = peak_idx + int(0.35 * tail)
    m1 = peak_idx + int(0.70 * tail)
    sustain_level = float(np.clip(np.median(env[m0:m1 + 1]), 0.0, 1.0))

    # ディケイ: ピークから sustain_level に下がるまで(無ければ 1/e まで)
    target = max(sustain_level, math.e ** -1) if sustain_level < 0.05 else sustain_level
    decay_end = peak_idx
    for i in range(peak_idx, end_idx + 1):
        if env[i] <= target:
            decay_end = i
            break
    else:
        decay_end = m0
    decay_sec = max(decay_end - peak_idx, 1) / rate_hz

    # リリース: 中盤の窓の終わり(m1)から end_idx までの尻尾
    release_sec = max(end_idx - m1, 1) / rate_hz

    # ループ区間(持続音を伸ばすときに使う): 中盤の窓そのもの
    loop_start_sec = m0 / rate_hz
    loop_end_sec = m1 / rate_hz
    if loop_end_sec <= loop_start_sec:
        loop_end_sec = (m0 + 1) / rate_hz

    return dict(attack_sec=attack_sec, decay_sec=decay_sec, sustain_level=sustain_level,
                release_sec=release_sec, loop_start_sec=loop_start_sec, loop_end_sec=loop_end_sec)


# ── 倍音 ─────────────────────────────────────────────────────
def _analyze_harmonics(y: np.ndarray, steady: np.ndarray, f0: float, n_env: int):
    """定常部の長尺 FFT で倍音の振幅/位相/実周波数を取り、STFT で倍音ごとの時間包絡を取る。"""
    # --- 静的スペクトル(定常部、長尺ゼロ詰め FFT) ---
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

    # --- STFT(倍音ごとの時間包絡用) ---
    n_fft_stft = 8192
    S = np.abs(librosa.stft(y, n_fft=n_fft_stft, hop_length=ENV_HOP, center=True))
    stft_freqs = librosa.fft_frequencies(sr=SR, n_fft=n_fft_stft)
    stft_bin_hz = SR / n_fft_stft

    harmonics = []
    det_n, det_f, det_a = [], [], []   # 非調和性フィット用
    nyq = SR / 2.0
    h1_amp = None
    for n in range(1, MAX_HARMONICS + 1):
        target = n * f0
        if target > nyq - 2 * bin_hz:
            break
        # ±3.5%(高々半音弱)の窓で静的スペクトルのピークを探す
        tol = max(target * 0.035, 2 * bin_hz)
        lo = max(0, int((target - tol) / bin_hz))
        hi = min(len(mag) - 1, int((target + tol) / bin_hz))
        if hi <= lo:
            continue
        k = lo + int(np.argmax(mag[lo:hi + 1]))
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

        weak = amp_lin < noise_floor
        # 倍音ごとの時間包絡(STFT の最近傍ビン ± 1 を加算)
        kb = int(round(target / stft_bin_hz))
        kb = min(max(kb, 0), S.shape[0] - 1)
        b0, b1 = max(0, kb - 1), min(S.shape[0] - 1, kb + 1)
        track = S[b0:b1 + 1, :].sum(axis=0)
        tmax = float(np.max(track))
        h_env = (track / tmax) if tmax > 1e-12 else np.zeros_like(track)
        h_env = _resample_curve(h_env, HARM_ENV_POINTS)

        if n == 1:
            h1_amp = amp_lin if amp_lin > 0 else 1.0
        harmonics.append({
            "n": n,
            "freq_hz": freq_est,
            "amp_lin": 0.0 if weak else amp_lin,
            "phase": phase,
            "env": h_env,
        })
        if not weak:
            det_n.append(n)
            det_f.append(freq_est)
            det_a.append(amp_lin)

    if not harmonics:
        raise AnalysisError("倍音を検出できませんでした(音量が小さすぎる可能性があります)。")

    # 振幅の正規化(倍音中の最大 = 1.0)
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

    # 非調和性 B のフィット: (f_n/(n·f0))² = 1 + B·n²  → x=n², y=その左辺-1 の最小二乗
    inharmonicity_b = 0.0
    if len(det_n) >= 3:
        det_n = np.asarray(det_n, dtype=float)
        det_f = np.asarray(det_f, dtype=float)
        wts = np.asarray(det_a, dtype=float)
        x = det_n ** 2
        yv = (det_f / (det_n * f0)) ** 2 - 1.0
        # 振幅で重み付けした原点通過直線フィット  B = Σ w·x·y / Σ w·x²
        denom = float(np.sum(wts * x * x))
        if denom > 1e-12:
            inharmonicity_b = float(np.sum(wts * x * yv) / denom)
        inharmonicity_b = float(np.clip(inharmonicity_b, 0.0, 0.01))

    # スペクトル描画用(対数間引き 512 点)
    fmax_disp = min(nyq, 16000.0)
    fsel = np.geomspace(max(f0 * 0.4, 20.0), fmax_disp, 512)
    msel = np.interp(fsel, freqs, mag)
    mref = float(np.max(msel)) + 1e-12
    spectrum_preview = {
        "freq": _r(fsel, 1),
        "db": _r(20.0 * np.log10(msel / mref + 1e-9), 2),
    }
    return out, inharmonicity_b, spectrum_preview


# ── 残差ノイズ ───────────────────────────────────────────────
def _analyze_noise(y: np.ndarray, f0: float, harmonics: list, n_env: int) -> dict:
    """STFT 上で倍音まわりのビンをマスクして残差を取り出し、レベル/時間包絡/帯域色を出す。"""
    n_fft = 4096
    S = librosa.stft(y, n_fft=n_fft, hop_length=ENV_HOP, center=True)
    mag = np.abs(S)
    freqs = librosa.fft_frequencies(sr=SR, n_fft=n_fft)
    bin_hz = SR / n_fft

    # 倍音マスク(各 n·f0 の ±max(3%, 1.5bin) を「調和」とみなす)
    harm_mask = np.zeros(mag.shape[0], dtype=bool)
    for h in harmonics:
        if h["amp"] <= 0.0:
            continue
        fc = h["ratio"] * f0
        tol = max(fc * 0.03, 1.5 * bin_hz)
        lo = max(0, int((fc - tol) / bin_hz))
        hi = min(mag.shape[0] - 1, int((fc + tol) / bin_hz))
        harm_mask[lo:hi + 1] = True
    # DC 近傍も調和扱い(ハム/オフセット)
    harm_mask[:max(1, int(40.0 / bin_hz))] = True

    resid = mag.copy()
    resid[harm_mask, :] = 0.0
    full_rms = np.sqrt(np.mean(mag ** 2, axis=0)) + 1e-12
    res_rms = np.sqrt(np.mean(resid ** 2, axis=0))

    res_peak = float(np.max(res_rms))
    sig_peak = float(np.max(full_rms))
    level = float(np.clip(res_peak / (sig_peak + 1e-12), 0.0, 1.0))
    env_shape = _resample_curve(res_rms / (res_peak + 1e-12), min(n_env, ENV_MAX_POINTS))

    # 帯域スペクトル色(残差の全フレーム平均マグニチュードを帯域集約)
    res_mean = np.mean(resid, axis=1)
    bands = NOISE_BANDS_HZ
    band_vals = []
    for i in range(len(bands) - 1):
        sel = (freqs >= bands[i]) & (freqs < bands[i + 1])
        band_vals.append(float(np.mean(res_mean[sel])) if np.any(sel) else 0.0)
    bmax = max(band_vals) or 1.0
    band_levels = [v / bmax for v in band_vals]

    return {
        "level": _r(level, 4),
        "rate_hz": ENV_HZ,
        "envelope": _r(env_shape, 4),
        "bands_hz": bands,
        "band_levels": _r(band_levels, 4),
    }


# ── 単一周期波形 ─────────────────────────────────────────────
def _extract_one_cycle(steady: np.ndarray, f0: float, sr: int) -> np.ndarray:
    period = sr / f0
    if not np.isfinite(period) or period < 4 or steady.size < 2 * period:
        # 取り出せない場合は基音 1 周期分のサイン波を返す
        t = np.linspace(0, 2 * math.pi, ONE_CYCLE_POINTS, endpoint=False)
        return np.sin(t)
    # 中央付近で立ち上がりゼロクロスを探す
    mid = steady.size // 2
    search0 = max(0, mid - int(period))
    search1 = min(steady.size - 1, mid + int(period))
    zc = search0
    for i in range(search0, search1):
        if steady[i] <= 0.0 < steady[i + 1]:
            zc = i
            break
    seg = steady[zc:zc + int(round(period))]
    if seg.size < 4:
        t = np.linspace(0, 2 * math.pi, ONE_CYCLE_POINTS, endpoint=False)
        return np.sin(t)
    cyc = _resample_curve(seg, ONE_CYCLE_POINTS)
    m = float(np.max(np.abs(cyc)))
    return cyc / m if m > 1e-9 else cyc


# ── 表示用特徴量 ─────────────────────────────────────────────
def _spectral_features(y: np.ndarray, steady: np.ndarray) -> dict:
    try:
        cent = float(np.mean(librosa.feature.spectral_centroid(y=y, sr=SR)))
        roll = float(np.mean(librosa.feature.spectral_rolloff(y=y, sr=SR, roll_percent=0.85)))
        bw = float(np.mean(librosa.feature.spectral_bandwidth(y=y, sr=SR)))
        zcr = float(np.mean(librosa.feature.zero_crossing_rate(y)))
        flat = float(np.mean(librosa.feature.spectral_flatness(y=steady)))
    except Exception:
        cent = roll = bw = zcr = flat = 0.0
    return {
        "spectral_centroid_hz": _r(cent, 1),
        "spectral_rolloff_hz": _r(roll, 1),
        "spectral_bandwidth_hz": _r(bw, 1),
        "zero_crossing_rate": _r(zcr, 4),
        "spectral_flatness": _r(flat, 5),
    }


# ── 描画用 波形プレビュー ────────────────────────────────────
def _waveform_preview(y: np.ndarray, buckets: int) -> list:
    n = y.size
    if n <= buckets:
        return [[_r(v, 4), _r(v, 4)] for v in y]
    edges = np.linspace(0, n, buckets + 1, dtype=int)
    out = []
    for i in range(buckets):
        seg = y[edges[i]:max(edges[i] + 1, edges[i + 1])]
        out.append([_r(float(np.min(seg)), 4), _r(float(np.max(seg)), 4)])
    return out
