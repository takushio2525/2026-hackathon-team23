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
ATTACK_SAMPLE_SR = 22050         # 原音アタック波形の保存サンプルレート
ATTACK_SAMPLE_SEC = 0.18         # トランペットのタンギング/バズ感として重ねる原音先頭の長さ
SUSTAIN_SAMPLE_SR = 44100        # トランペット定常部の保存サンプルレート
SUSTAIN_SAMPLE_SEC = 0.22        # トランペットの管鳴り/唇のバズ感として薄くループする長さ
DRUM_ATTACK_SAMPLE_SEC = 0.45     # ドラム用に保存する原音アタック/胴鳴りの長さ
DRUM_SAMPLE_SR = 44100           # ドラム本体サンプルの保存サンプルレート。ハイハットの高域を残すため 44.1kHz。
DRUM_SAMPLE_SEC = 3.0            # ドラム本体として保存する最大秒数
FMIN = 50.0                      # 基音探索の下限
FMAX = 2200.0                    # 基音探索の上限
INSTRUMENT_PROFILES = {
    "auto": {"label": "自動", "fmin": FMIN, "fmax": FMAX},
    # トランペットは倍音が明るく、基音候補を低く取りすぎると 1/2 倍音側に誤認しやすい。
    "trumpet": {"label": "トランペット", "fmin": 120.0, "fmax": 1400.0},
    # ドラムは明確な基音が無い音も多いため、低域ピークを再生時の便宜的な基準音として使う。
    "drum": {"label": "ドラム / 打楽器", "fmin": 35.0, "fmax": 900.0, "percussive": True},
}
PYIN_FRAME = 2048                # pyin のフレーム長(hop はその 1/4 = 512 → フレームレート ≒ SR/512)
PYIN_HOP = PYIN_FRAME // 4       # = 512
F0_TRACK_HZ = SR / PYIN_HOP      # ≒ 86.13 Hz (f0 トラックの時間解像度)
VIBRATO_BAND_HZ = (3.0, 9.0)     # ビブラート/トレモロとみなす周波数帯
F0_PREVIEW_POINTS = 600          # 描画用に f0(セント) トラックを間引く点数
# 先頭/末尾の無音トリム(ピーク RMS からの相対 dB)。録音のルームトーンや準備音を無音扱いする閾値。
TRIM_LEAD_DB = 20.0              # 先頭: -20dB 未満は無音とみなしてカット(準備音・息・暗騒音も切る)
TRIM_TRAIL_DB = 50.0             # 末尾: -50dB 未満をカット(減衰の尾は残すため緩め)
TRIM_PRE_ROLL_MS = 20.0          # 先頭の立ち上がり手前に残す余白
TRIM_POST_ROLL_MS = 80.0         # 末尾に残す余白
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


def _autocorr_f0(seg: np.ndarray, sr: int, fmin: float = FMIN, fmax: float = FMAX) -> float | None:
    """pyin が使えないとき用の自己相関ベース基音推定。"""
    seg = seg - float(np.mean(seg))
    if np.allclose(seg, 0.0):
        return None
    corr = np.correlate(seg, seg, mode="full")[len(seg) - 1:]
    lo = max(1, int(sr / fmax))
    hi = min(len(corr) - 1, int(sr / fmin))
    if hi <= lo:
        return None
    lag = lo + int(np.argmax(corr[lo:hi]))
    return sr / lag if lag > 0 else None


def _trim_silence(y: np.ndarray, sr: int):
    """先頭と末尾の無音(デジタル無音やルームトーン)をトリムする。
    librosa.effects.trim より積極的に: 先頭は -TRIM_LEAD_DB、末尾は -TRIM_TRAIL_DB 未満を無音と
    みなしてカットし、立ち上がり手前と末尾に少しだけ余白を残す。極端に短くなる場合は何もしない。
    返り値: (トリム後の y, 先頭で削ったサンプル数, 末尾で削ったサンプル数)
    """
    n = y.size
    if n < sr // 50:                      # 20ms 未満は触らない
        return y, 0, 0
    hop, frame = 256, 1024
    rms = librosa.feature.rms(y=y, frame_length=frame, hop_length=hop, center=True)[0]
    if rms.size == 0:
        return y, 0, 0
    peak = float(rms.max())
    if peak <= 1e-7:
        return y, 0, 0
    lead_thr = peak * (10.0 ** (-TRIM_LEAD_DB / 20.0))
    trail_thr = peak * (10.0 ** (-TRIM_TRAIL_DB / 20.0))
    lead_idx = np.where(rms >= lead_thr)[0]
    trail_idx = np.where(rms >= trail_thr)[0]
    if lead_idx.size == 0 or trail_idx.size == 0:
        return y, 0, 0
    start = max(0, int(lead_idx[0]) * hop - int(TRIM_PRE_ROLL_MS / 1000.0 * sr))
    end = min(n, (int(trail_idx[-1]) + 1) * hop + int(TRIM_POST_ROLL_MS / 1000.0 * sr))
    if end - start < sr // 20:            # トリム後 50ms 未満になるなら諦めて元のまま
        return y, 0, 0
    return y[start:end], start, n - end


# ── メイン ───────────────────────────────────────────────────
def analyze_file(path: str, name: str | None = None, profile: str = "auto") -> dict:
    """音源ファイルを解析して {"instrument": {...}, "preview": {...}} を返す。"""
    source_file = os.path.basename(path)
    if name is None:
        name = os.path.splitext(source_file)[0]
    profile = profile if profile in INSTRUMENT_PROFILES else "auto"
    profile_info = INSTRUMENT_PROFILES[profile]
    is_percussive = bool(profile_info.get("percussive"))

    y, _ = librosa.load(path, sr=SR, mono=True)
    if y.size == 0 or float(np.max(np.abs(y))) < 1e-5:
        raise AnalysisError("無音、または音量が小さすぎて解析できません。")

    # 先頭/末尾の無音(デジタル無音・ルームトーン)を自動トリム
    raw_sec = y.size / SR
    y, n_lead, n_trail = _trim_silence(y, SR)
    if y.size < SR // 10:                # 0.1 秒未満は短すぎ
        raise AnalysisError("音が短すぎます(0.1 秒以上の単音を渡してください)。元ファイルがほぼ無音の可能性があります。")

    duration_sec = y.size / SR

    # ── 全体振幅エンベロープ(200 Hz) ──────────────────────
    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=ENV_HOP, center=True)[0]
    rms_peak = float(np.max(rms))
    env = rms / (rms_peak + 1e-12)        # 0..1, ピーク=1
    n_env = len(env)

    # ── 基音検出 (f0 トラックも保持: ビブラート解析と描画に使う) ──
    fundamental, f0_track = _detect_fundamental(y, profile)
    midi = _hz_to_midi(fundamental)

    # ── ビブラート / トレモロ の検出 ───────────────────
    modulation = _detect_modulation(f0_track, env, ENV_HZ)

    # ── ADSR + ループ点の当てはめ ────────────────────────
    adsr = _fit_adsr(env, ENV_HZ)
    sustaining = False if is_percussive else adsr["sustain_level"] > 0.18

    # ── 定常部(倍音解析に使う窓) ────────────────────────
    a_idx = int(round(adsr["loop_start_sec"] * ENV_HZ))
    b_idx = int(round(adsr["loop_end_sec"] * ENV_HZ))
    a_samp = max(0, a_idx * ENV_HOP)
    b_samp = min(y.size, max(a_samp + 4096, b_idx * ENV_HOP))
    steady = y[a_samp:b_samp]
    if is_percussive:
        peak_samp = int(np.argmax(np.abs(y)))
        head = max(0, peak_samp - int(0.005 * SR))
        steady = y[head:head + max(4096, int(0.35 * SR))]
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
    attack_sample = None
    sustain_sample = None
    drum_sample = None
    if profile == "trumpet":
        attack_sample = _extract_attack_sample(y, SR, midi, ATTACK_SAMPLE_SEC)
        sustain_sample = _extract_sustain_sample(steady, SR, midi, fundamental)
    elif is_percussive:
        attack_sample = _extract_attack_sample(y, SR, midi, DRUM_ATTACK_SAMPLE_SEC)
        drum_sample = _extract_drum_sample(y, SR, midi)

    # ── 表示用特徴量 ────────────────────────────────────
    features = _spectral_features(y, steady)
    if is_percussive:
        features.update(_drum_features(y, steady, fundamental))
    features["rms_peak"] = _r(rms_peak, 4)
    features["harmonic_count"] = int(sum(1 for h in harmonics if h["amp"] > 0.0))
    features["source_duration_sec"] = _r(raw_sec, 3)        # トリム前の長さ
    features["trimmed_lead_sec"] = _r(n_lead / SR, 3)       # 先頭で削った無音
    features["trimmed_trail_sec"] = _r(n_trail / SR, 3)     # 末尾で削った無音

    # ── 全体エンベロープを必要なら間引いて格納 ───────────
    env_out = env
    if n_env > ENV_MAX_POINTS:
        env_out = _resample_curve(env, ENV_MAX_POINTS)
    env_rate_out = ENV_HZ if env_out is env else ENV_MAX_POINTS / duration_sec

    instrument = {
        "format": "sound_lab.instrument/1",
        "name": name,
        "source_file": source_file,
        "instrument_profile": profile,
        "instrument_profile_label": profile_info["label"],
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
        "modulation": modulation,
        "harmonics": harmonics,
        "noise": noise,
        "waveform": {
            "one_cycle_points": len(one_cycle),
            "one_cycle": _r(one_cycle, 4),
        },
        "features": features,
    }
    if attack_sample is not None:
        instrument["attack_sample"] = attack_sample
    if sustain_sample is not None:
        instrument["sustain_sample"] = sustain_sample
    if drum_sample is not None:
        instrument["drum_sample"] = drum_sample

    # 描画用 f0 トラック(中央値からのセント差)
    f0_cents_prev, f0_prev_rate = _f0_cents_preview(f0_track, duration_sec)

    preview = {
        "waveform": _waveform_preview(y, 2000),
        "spectrum_freq": spectrum_preview["freq"],
        "spectrum_db": spectrum_preview["db"],
        "f0_cents": f0_cents_prev,
        "f0_rate_hz": _r(f0_prev_rate, 3),
    }
    return {"instrument": instrument, "preview": preview}


# ── 基音 ─────────────────────────────────────────────────────
def _detect_fundamental(y: np.ndarray, profile: str = "auto"):
    """基音 (中央値, Hz) と f0 トラック(フレームごとの Hz・無声は NaN / 失敗時 None) を返す。"""
    p = INSTRUMENT_PROFILES.get(profile, INSTRUMENT_PROFILES["auto"])
    fmin, fmax = p["fmin"], p["fmax"]
    if p.get("percussive"):
        return _detect_drum_reference_f0(y, fmin, fmax), None
    try:
        f0, _, _ = librosa.pyin(
            y, fmin=max(fmin, 55.0), fmax=min(fmax, 2000.0),
            sr=SR, frame_length=PYIN_FRAME, hop_length=PYIN_HOP)
        f0v = f0[~np.isnan(f0)]
        if f0v.size >= 3:
            # 安定区間(中央あたり)の中央値を採る
            return float(np.median(f0v)), np.asarray(f0, dtype=float)
    except Exception:
        pass
    # フォールバック: 振幅最大付近の自己相関(トラックは取れない)
    peak = int(np.argmax(np.abs(y)))
    seg = y[peak:peak + min(y.size - peak, int(0.2 * SR))]
    f0 = _autocorr_f0(seg if seg.size > 1024 else y, SR, fmin=fmin, fmax=fmax)
    if f0 is None or not (fmin <= f0 <= fmax):
        raise AnalysisError(
            "基音を検出できませんでした。和音やノイズではなく、ピッチのはっきりした単音を渡してください。")
    return float(f0), None


def _detect_drum_reference_f0(y: np.ndarray, fmin: float, fmax: float) -> float:
    """ドラム用の便宜的な基準周波数を返す。

    ドラムは基音が無い/時間で急変する音が多いので、pyin ではなくアタック直後のスペクトルから
    低域寄りに重み付けしたピークを拾う。これは「音名表示と移調の基準」であり、調和音としての
    厳密な基音ではない。
    """
    peak = int(np.argmax(np.abs(y)))
    start = max(0, peak - int(0.01 * SR))
    end = min(y.size, peak + int(0.35 * SR))
    seg = y[start:end]
    if seg.size < 2048:
        seg = y[:min(y.size, int(0.45 * SR))]
    if seg.size < 128:
        return 120.0

    win = np.hanning(seg.size)
    nfft = 1
    while nfft < max(seg.size, 1 << 15):
        nfft <<= 1
    mag = np.abs(np.fft.rfft(seg * win, n=nfft))
    freqs = np.fft.rfftfreq(nfft, d=1.0 / SR)
    sel = (freqs >= fmin) & (freqs <= fmax)
    if not np.any(sel):
        return 120.0
    idxs = np.where(sel)[0]
    # シンバルやスネアの広帯域ノイズに引っ張られすぎないよう、低域を少し優先する。
    score = mag[idxs] / np.sqrt(np.maximum(freqs[idxs], fmin))
    k = int(idxs[np.argmax(score)])
    freq = float(freqs[k])
    return float(np.clip(freq, fmin, fmax))


# ── ビブラート / トレモロ ────────────────────────────────────
def _zero_modulation() -> dict:
    z = lambda: {"rate_hz": 0.0, "depth_cents": 0.0, "depth": 0.0,
                 "onset_sec": 0.0, "regularity": 0.0, "detected": False}
    return {"vibrato": z(), "tremolo": z()}


def _periodicity(seg: np.ndarray, rate_hz: float, band: tuple):
    """中央を切り出し済みの 1 次元信号から、band 内の最強周期成分を推定する。
    返り値: (周波数 Hz, 振幅 = 元信号と同じ単位の正弦波振幅, 卓越度 regularity, RMS, ピーク到達インデックス)
    周期性が弱いときは None。
    """
    n = seg.size
    if n < 32:
        return None
    seg = seg - float(np.mean(seg))
    # 低周波ドリフト(band 下限の半分以下)を移動平均で除去
    w = max(3, int(round(rate_hz / (band[0] * 0.5))))
    if 3 <= w < n:
        seg = seg - np.convolve(seg, np.ones(w) / w, mode="same")
    rms = float(np.sqrt(np.mean(seg ** 2)))
    if rms < 1e-9:
        return None
    win = np.hanning(n)
    win_sum = float(np.sum(win)) + 1e-12
    sp = np.abs(np.fft.rfft(seg * win))
    fq = np.fft.rfftfreq(n, d=1.0 / rate_hz)
    sel = (fq >= band[0]) & (fq <= band[1])
    if not np.any(sel) or float(sp[sel].max()) < 1e-12:
        return None
    band_idx = np.where(sel)[0]
    k = int(band_idx[np.argmax(sp[band_idx])])
    freq = float(fq[k])
    amp = 2.0 * float(sp[k]) / win_sum               # 窓補正つき振幅推定(片振幅)
    med = float(np.median(sp[sel])) + 1e-12
    regularity = float(sp[k] / med)
    # ピーク到達: |seg| が片振幅の半分を最初に超えるフレーム
    over = np.where(np.abs(seg) >= amp * 0.5)[0]
    onset_idx = int(over[0]) if over.size else 0
    return freq, amp, regularity, rms, onset_idx


def _detect_modulation(f0_track, env: np.ndarray, env_rate: int) -> dict:
    """f0 トラックから ビブラート(ピッチの周期揺れ)を、振幅エンベロープから トレモロ(音量の周期揺れ)を
    検出する。検出できなければ各値 0 / detected=False(キーは常に出す)。中央 20〜80% の区間で評価する。"""
    out = _zero_modulation()

    # ── ビブラート ──────────────────────────────────
    if f0_track is not None:
        ft = np.asarray(f0_track, dtype=float)
        good = ~np.isnan(ft)
        if good.sum() >= 24 and good.sum() >= ft.size * 0.6:
            ft = np.interp(np.arange(ft.size), np.flatnonzero(good), ft[good])
            cents = 1200.0 * np.log2(ft / (np.median(ft) + 1e-12))
            lo, hi = int(cents.size * 0.2), int(cents.size * 0.8)
            r = _periodicity(cents[lo:hi], F0_TRACK_HZ, VIBRATO_BAND_HZ)
            if r is not None:
                freq, amp, reg, rms, onset_idx = r
                pp = 2.0 * amp                       # 全振幅(セント)
                if pp >= 8.0 and reg >= 4.0 and rms >= 3.0:
                    out["vibrato"] = {
                        "rate_hz": _r(freq, 2),
                        "depth_cents": _r(min(pp, 200.0), 1),
                        "depth": _r(min(pp, 200.0) / 100.0, 3),   # 半音=1.0 の換算値も置いておく
                        "onset_sec": _r((lo + onset_idx) / F0_TRACK_HZ, 3),
                        "regularity": _r(min(reg / 12.0, 1.0), 3),
                        "detected": True,
                    }

    # ── トレモロ ────────────────────────────────────
    e = np.asarray(env, dtype=float)
    if e.size >= 48:
        lo, hi = int(e.size * 0.2), int(e.size * 0.8)
        base = float(np.mean(e[lo:hi])) + 1e-9
        r = _periodicity(e[lo:hi], env_rate, VIBRATO_BAND_HZ)
        if r is not None:
            freq, amp, reg, rms, onset_idx = r
            depth = 2.0 * amp / base                  # 全振幅 / 平均レベル(相対)
            if depth >= 0.04 and reg >= 4.0 and rms / base >= 0.015:
                out["tremolo"] = {
                    "rate_hz": _r(freq, 2),
                    "depth": _r(min(depth, 1.0), 3),
                    "depth_cents": 0.0,
                    "onset_sec": _r((lo + onset_idx) / env_rate, 3),
                    "regularity": _r(min(reg / 12.0, 1.0), 3),
                    "detected": True,
                }
    return out


def _f0_cents_preview(f0_track, duration_sec: float):
    """描画用に f0 トラックを「中央値からのセント差」にして間引く。返り値 (値リスト, レート Hz)。"""
    if f0_track is None:
        return [], 0.0
    ft = np.asarray(f0_track, dtype=float)
    good = ~np.isnan(ft)
    if good.sum() < 8:
        return [], 0.0
    ft = np.interp(np.arange(ft.size), np.flatnonzero(good), ft[good])
    cents = 1200.0 * np.log2(ft / (np.median(ft) + 1e-12))
    if cents.size > F0_PREVIEW_POINTS:
        cents = _resample_curve(cents, F0_PREVIEW_POINTS)
        rate = F0_PREVIEW_POINTS / max(duration_sec, 1e-6)
    else:
        rate = F0_TRACK_HZ
    return _r(cents, 2), rate


# ── ADSR ─────────────────────────────────────────────────────
_ATTACK_NEAR_PEAK = 0.85   # 「ピークにほぼ到達」とみなす相対レベル(= アタック終了点)
_ONSET_LEVEL = 0.10        # 立ち上がり開始とみなす相対レベル
_END_LEVEL = 0.05          # これ未満が続いたら「音は終わった」とみなす(末尾の無音切り)


def _fit_adsr(env: np.ndarray, rate_hz: int) -> dict:
    """0..1 正規化済みエンベロープ(ピーク=1)から ADSR とループ点(秒)を当てはめる。

    アタックは「ピーク到達まで」ではなく「ピークの 85% に最初に達するまで」で測る。
    こうすると、本体に強弱の揺らぎがある(= 最大瞬間が中盤に来る)音でも、立ち上がりだけを拾える。
    ディケイ以降は「アタック終了点」を起点に評価する。
    """
    n = len(env)
    if n < 3:
        return dict(attack_sec=0.005, decay_sec=0.05, sustain_level=0.5,
                    release_sec=0.05, loop_start_sec=0.0, loop_end_sec=max(0.0, (n - 1) / rate_hz))

    # 立ち上がり開始 onset → アタック終了(ピークの 85% に最初に到達)body_start
    above_onset = np.where(env >= _ONSET_LEVEL)[0]
    onset_idx = int(above_onset[0]) if above_onset.size else 0
    near_peak = np.where(env[onset_idx:] >= _ATTACK_NEAR_PEAK)[0]
    body_start = onset_idx + int(near_peak[0]) if near_peak.size else int(np.argmax(env))
    attack_sec = max(body_start - onset_idx, 1) / rate_hz

    # アタック以降の有効区間 [body_start, end_idx](末尾の無音は除く)
    above_end = np.where(env >= _END_LEVEL)[0]
    end_idx = int(above_end[-1]) if above_end.size else n - 1
    if end_idx <= body_start:
        end_idx = n - 1
    tail = end_idx - body_start

    if tail < 4:        # 打撃音などアタック即終了
        return dict(attack_sec=attack_sec, decay_sec=max(tail, 1) / rate_hz,
                    sustain_level=float(env[end_idx]),
                    release_sec=max(tail, 1) / rate_hz,
                    loop_start_sec=body_start / rate_hz, loop_end_sec=end_idx / rate_hz)

    # 中盤 0.30〜0.70 の窓を「サステイン」とみなす
    m0 = body_start + int(0.30 * tail)
    m1 = body_start + int(0.70 * tail)
    sustain_level = float(np.clip(np.median(env[m0:m1 + 1]), 0.0, 1.0))

    # ディケイ: body_start から sustain_level(無ければ 1/e)まで下がるのにかかる時間
    target = max(sustain_level, math.e ** -1) if sustain_level < 0.05 else sustain_level
    decay_end = body_start
    for i in range(body_start, end_idx + 1):
        if env[i] <= target:
            decay_end = i
            break
    else:
        decay_end = m0
    decay_sec = max(decay_end - body_start, 1) / rate_hz

    # リリース: 中盤の窓の終わり(m1)から end_idx までの尻尾
    release_sec = max(end_idx - m1, 1) / rate_hz

    # ループ区間(持続音を要求長まで伸ばすときに使う): 中盤の窓そのもの
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


def _extract_attack_sample(y: np.ndarray, sr: int, midi: float, duration_sec: float = ATTACK_SAMPLE_SEC) -> dict:
    """原音のアタックを再合成に重ねられるよう、先頭だけを短く保存する。"""
    n = min(y.size, int(round(duration_sec * sr)))
    seg = np.array(y[:n], dtype=float, copy=True)
    if seg.size < 16:
        seg = np.zeros(16, dtype=float)

    # 再合成音に重ねたときクリックしないよう、末尾だけ短くフェードアウトする。
    fade_n = min(seg.size, int(round(0.025 * sr)))
    if fade_n > 1:
        seg[-fade_n:] *= np.linspace(1.0, 0.0, fade_n)

    peak = float(np.max(np.abs(seg))) or 1.0
    seg = seg / peak
    if sr != ATTACK_SAMPLE_SR:
        seg = librosa.resample(seg, orig_sr=sr, target_sr=ATTACK_SAMPLE_SR)

    return {
        "sample_rate": ATTACK_SAMPLE_SR,
        "duration_sec": _r(seg.size / ATTACK_SAMPLE_SR, 4),
        "root_midi_note": int(round(midi)),
        "source_peak": _r(peak, 5),
        "values": _r(seg, 4),
    }


def _extract_sustain_sample(steady: np.ndarray, sr: int, midi: float, f0: float) -> dict | None:
    """トランペットの定常部を短いループ素材として保存する。

    倍音加算だけでは出にくい唇の細かいバズと管鳴りを、薄く混ぜるための補助素材。
    ループ境界で大きなクリックが出ないよう、基音周期の整数倍に近い長さで切り出す。
    """
    if steady.size < int(0.06 * sr) or not np.isfinite(f0) or f0 <= 0:
        return None

    period = sr / f0
    if period < 8:
        return None
    cycles = max(8, int(round(SUSTAIN_SAMPLE_SEC * f0)))
    n = int(round(cycles * period))
    n = min(n, steady.size)
    if n < int(0.045 * sr):
        return None

    mid = steady.size // 2
    start_min = 0
    start_max = max(0, steady.size - n - 1)
    search0 = max(start_min, mid - n)
    search1 = min(start_max, mid + n)
    start = min(max(0, mid - n // 2), start_max)
    for i in range(search0, max(search0 + 1, search1)):
        if steady[i] <= 0.0 < steady[i + 1] and i + n < steady.size:
            start = i
            break

    seg = np.array(steady[start:start + n], dtype=float, copy=True)
    if seg.size < 16:
        return None
    seg -= float(np.mean(seg))

    # ループ素材はピーク正規化しすぎると主音を食うため、RMS 基準で穏やかに整える。
    rms = float(np.sqrt(np.mean(seg ** 2))) or 1.0
    seg = seg / max(rms * 4.0, 1e-9)
    peak = float(np.max(np.abs(seg))) or 1.0
    if peak > 1.0:
        seg = seg / peak

    if sr != SUSTAIN_SAMPLE_SR:
        seg = librosa.resample(seg, orig_sr=sr, target_sr=SUSTAIN_SAMPLE_SR)

    return {
        "sample_rate": SUSTAIN_SAMPLE_SR,
        "duration_sec": _r(seg.size / SUSTAIN_SAMPLE_SR, 4),
        "root_midi_note": int(round(midi)),
        "loop_start_sec": 0.0,
        "loop_end_sec": _r(seg.size / SUSTAIN_SAMPLE_SR, 4),
        "source_rms": _r(rms, 5),
        "values": _r(seg, 4),
    }


def _extract_drum_sample(y: np.ndarray, sr: int, midi: float) -> dict:
    """ドラムの1打をサンプル駆動で再現するため、トリム後の原音本体を保存する。"""
    n = min(y.size, int(round(DRUM_SAMPLE_SEC * sr)))
    seg = np.array(y[:n], dtype=float, copy=True)
    if seg.size < 16:
        seg = np.zeros(16, dtype=float)

    # アタックは残しつつ、ファイル先頭/末尾のクリックだけ避ける。
    fade_in = min(seg.size, int(round(0.0003 * sr)))
    if fade_in > 1:
        seg[:fade_in] *= np.linspace(0.0, 1.0, fade_in)
    fade_out = min(seg.size, int(round(0.035 * sr)))
    if fade_out > 1:
        seg[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)

    peak = float(np.max(np.abs(seg))) or 1.0
    seg = seg / peak
    if sr != DRUM_SAMPLE_SR:
        seg = librosa.resample(seg, orig_sr=sr, target_sr=DRUM_SAMPLE_SR)

    return {
        "sample_rate": DRUM_SAMPLE_SR,
        "duration_sec": _r(seg.size / DRUM_SAMPLE_SR, 4),
        "root_midi_note": int(round(midi)),
        "source_peak": _r(peak, 5),
        "values": _r(seg, 4),
    }


def _drum_features(y: np.ndarray, steady: np.ndarray, reference_f0: float) -> dict:
    """ドラムモード用の表示/初期調整向け特徴量を返す。"""
    try:
        n_fft = 4096
        mag = np.abs(librosa.stft(y, n_fft=n_fft, hop_length=ENV_HOP, center=True))
        freqs = librosa.fft_frequencies(sr=SR, n_fft=n_fft)
        pow_mean = np.mean(mag ** 2, axis=1)
        total = float(np.sum(pow_mean)) + 1e-12
        low = float(np.sum(pow_mean[freqs < 180.0]) / total)
        mid = float(np.sum(pow_mean[(freqs >= 180.0) & (freqs < 2500.0)]) / total)
        high = float(np.sum(pow_mean[freqs >= 2500.0]) / total)
        onset = librosa.onset.onset_strength(y=y, sr=SR)
        transient = float(np.max(onset) / (np.mean(onset) + 1e-9)) if onset.size else 0.0
        rms = librosa.feature.rms(y=y, frame_length=1024, hop_length=256, center=True)[0]
        if rms.size:
            peak_i = int(np.argmax(rms))
            thr = float(np.max(rms)) * (10.0 ** (-34.0 / 20.0))
            tail = np.where(rms[peak_i:] >= thr)[0]
            decay_sec = float((tail[-1] if tail.size else 0) * 256 / SR)
        else:
            decay_sec = 0.0
    except Exception:
        low = mid = high = transient = decay_sec = 0.0

    if low > 0.36 and reference_f0 < 150 and high < 0.45:
        guess = "kick"
        label = "キック系"
    elif high > 0.45 and low < 0.24:
        if decay_sec < 0.75:
            guess = "hihat"
            label = "ハイハット系"
        else:
            guess = "crash"
            label = "クラッシュシンバル系"
    elif mid > 0.32 or transient > 6.0:
        guess = "snare"
        label = "スネア / タム系"
    else:
        guess = "drum"
        label = "ドラム系"

    return {
        "drum_type_guess": guess,
        "drum_type_label": label,
        "drum_low_energy": _r(low, 4),
        "drum_mid_energy": _r(mid, 4),
        "drum_high_energy": _r(high, 4),
        "drum_transient_strength": _r(transient, 3),
        "drum_decay_sec": _r(decay_sec, 4),
    }


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
