#!/usr/bin/env python3
"""MOP2: 音階の誤差 (平均 < 3.6 cent) の解析.

計画書の MOP2 は「合成出力音を録音・周波数分析し、楽譜の平均律理論音高と比較する」と
定義されているが、実音の録音には録音環境の癖 (サウンドカード・A/D の標本化誤差・部屋鳴り)
が混入し、「JSON と合成方法に由来する音階誤差」を切り出せない。

そこで本スクリプトは **Processing の加算合成アルゴリズムを Python で忠実に再現** し、
「現在の楽器 JSON + 現在の発音方法で鳴るはずの波形」をそのまま生成して周波数解析する。
録音経路を挟まないぶん、検出される誤差は 100% 音源データ (JSON) と合成式に由来する。

移植元 (この 3 ファイルの式をそのまま写している):
  pc_app/common/SynthVoice.pde   — uGenerate() の加算合成 (倍音周波数・非調和性・ビブラート)
  pc_app/common/InstrModel.pde   — JSON → 合成パラメータの解釈
  pc_app/common/AudioManager.pde — triggerNote() (オクターブ移調・ゲイン)
楽器定義の正本: pc_app/production/orchestra_resynth/data/*.instrument.json
楽譜の正本:     firmware/production/node_02/src/score_data.cpp

音高が決まる式は SynthVoice.pde の 1 行だけ:
    f = targetF0 * harmRatio[k] * sqrt(1 + inharmB * n^2) * pitchMul
    targetF0 = 440 * 2^((midi - 69) / 12)          ← 平均律そのもの (誤差ゼロ)
つまり音階誤差は harmRatio (JSON の harmonics[].ratio) と inharmonicity_b にしか宿らない。

使い方:
  .venv/bin/python scripts/mop2_pitch_error.py              # セルフテスト → 解析 → グラフ
  .venv/bin/python scripts/mop2_pitch_error.py --selftest   # セルフテストのみ
"""

import argparse
import csv
import json
import logging
import math
import re
import sys
from datetime import datetime
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.patches as mpatches
import matplotlib.pyplot as plt
import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
VERIF_DIR = Path(__file__).resolve().parent.parent
RESULTS_DIR = VERIF_DIR / 'results'
GRAPHS_DIR = RESULTS_DIR / 'graphs'
MOP2_DIR = RESULTS_DIR / 'mop2'

DATA_DIR = REPO_ROOT / 'pc_app' / 'production' / 'orchestra_resynth' / 'data'
SCORE_CPP = REPO_ROOT / 'firmware' / 'production' / 'node_02' / 'src' / 'score_data.cpp'

# MOP2 の判定基準。出典: tools/verification/README.md「MOP2: 音階の誤差 (平均 < 3.6 cent)」
# / report「23_計画書・設計書」MOE-MOP 対応表 (ref:onkai の要旨「3.6 cent 未満」に由来)
THRESHOLD_CENT = 3.6

SAMPLE_RATE = 44100        # orchestra_resynth.pde: minim.getLineOut(STEREO, 512, 44100)
MASTER_VOLUME = 2.0        # orchestra_resynth.pde: float masterVolume = 2.0f
USE_SIMPLE_ADSR = False    # orchestra_resynth.pde: boolean useSimpleADSR = false ('a' キーで切替)
NOISE_SEED = 20260711      # makeShapedNoise() の random() を再現可能にする

# 楽器ノードと instrumentId の対応。
# instrumentId = data/*.json をファイル名昇順に並べたときの index (AudioManager.rescanInstruments)
# partId / instrumentId は firmware/production/node_0N/include/ProjectConfig.h より
NODE_BY_INSTRUMENT_ID = {
    0: ('node_02', 0x02),
    1: ('node_03', 0x03),
    2: ('node_04', 0x04),
    3: ('node_05', 0x05),
}
# 楽器の日本語表示名 (JSON の name は "trumpets (調整)" など英名なのでスライド用に別持ち)
LABEL_BY_INSTRUMENT_ID = {0: 'トランペット', 1: 'ホルン', 2: 'フルート', 3: 'オルガン'}


# ── Processing 実装の移植: AudioManager.pde ────────────────────────────────

def brass_octave_shift(instrument_id):
    """AudioManager.pde: brassOctaveShift() をそのまま移植。"""
    return {0: 12, 1: 0, 2: 12, 3: -12}.get(instrument_id, 0)


def brass_part_amplitude(instrument_id):
    """AudioManager.pde: brassPartAmplitude() をそのまま移植 (音高には影響しない)。"""
    return {0: 0.20, 1: 0.17, 2: 0.15, 3: 0.50}.get(instrument_id, 0.18)


def is_drum_instrument(instrument_id):
    """AudioManager.pde: isDrumInstrument()。id>=4 は打楽器 = 音高を持たない。"""
    return instrument_id >= 4


# ── Processing 実装の移植: InstrModel.pde ──────────────────────────────────

def band_gain(fc, bands_hz, band_levels):
    """InstrModel.pde: bandGain() をそのまま移植。"""
    for i in range(len(band_levels)):
        lo = bands_hz[min(i, len(bands_hz) - 1)]
        hi = bands_hz[min(i + 1, len(bands_hz) - 1)]
        if lo <= fc < hi:
            return band_levels[i]
    return band_levels[-1]


def make_shaped_noise(sr, bands_hz, band_levels, noise_level, rng):
    """InstrModel.pde: makeShapedNoise() を移植。

    Minim の FFT は既定で窓なし (矩形)、setBand(b, getBand(b)*g) は位相を保って振幅だけ
    スケールする = 複素ビンに実数ゲインを掛けるのと等価なので numpy の rfft/irfft で再現できる。
    """
    if noise_level <= 0.0005:
        return np.zeros(1)
    nfft = 16384
    buf = rng.uniform(-1.0, 1.0, nfft)
    spec = np.fft.rfft(buf)
    fc = np.arange(spec.size) * sr / nfft
    gains = np.array([band_gain(f, bands_hz, band_levels) for f in fc])
    buf = np.fft.irfft(spec * gains, n=nfft)
    mx = max(float(np.max(np.abs(buf))), 1e-9)
    return buf / mx


def load_model(path, sr, rng):
    """InstrModel.pde のコンストラクタを移植して合成パラメータの dict を返す。"""
    root = json.loads(path.read_text(encoding='utf-8'))
    m = {'file': path.name, 'name': root.get('name', 'instrument')}
    m['sustaining'] = bool(root.get('sustaining', True))
    m['inharmB'] = float(root.get('inharmonicity_b', 0.0))
    m['fundamentalHz'] = float(root.get('fundamental_hz', 261.626))  # 合成には未使用 (後述)
    m['midiNote'] = int(root.get('midi_note', 60))

    env = root['envelope']
    env_values = np.asarray(env['values'], dtype=np.float64)
    env_rate = float(env.get('rate_hz', 200))
    loop_start = float(env.get('loop_start_sec', (env_values.size - 1) / env_rate * 0.4))
    loop_end = float(env.get('loop_end_sec', (env_values.size - 1) / env_rate * 0.7))
    if env_values.size < 2:
        env_values, env_rate = np.array([0.0, 1.0, 1.0, 0.0]), 10.0
    if loop_end <= loop_start:
        loop_end = loop_start + max(0.05, 1.0 / env_rate)
    m['envValues'], m['envRate'] = env_values, env_rate
    m['releaseSec'] = float(env.get('release_sec', 0.08))
    m['loopStartSec'], m['loopEndSec'] = loop_start, loop_end
    m['origDur'] = (env_values.size - 1) / env_rate

    harmonics = root['harmonics']
    n = len(harmonics)
    m['N'] = n
    m['harmN'] = np.array([int(h.get('n', i + 1)) for i, h in enumerate(harmonics)])
    m['harmRatio'] = np.array([float(h.get('ratio', h.get('n', i + 1)))
                               for i, h in enumerate(harmonics)])
    m['harmAmp'] = np.array([float(h.get('amp', 0.0)) for h in harmonics])
    m['harmPhase'] = np.array([float(h.get('phase', 0.0)) for h in harmonics])
    m['harmEnv'] = []
    for h in harmonics:
        ev = h.get('env')
        m['harmEnv'].append(np.asarray(ev, dtype=np.float64)
                            if ev is not None and len(ev) >= 2 else np.array([1.0, 1.0]))
    m['harmEnvRate'] = [(e.size - 1) / max(m['origDur'], 1e-3) for e in m['harmEnv']]
    m['harmNorm'] = 1.0 / max(float(np.sum(m['harmAmp'][m['harmAmp'] > 0])), 1.0)

    noise = root.get('noise')
    m['noiseLevel'] = float(noise.get('level', 0.0)) if noise else 0.0
    m['noiseEnv'] = (np.asarray(noise['envelope'], dtype=np.float64)
                     if noise and 'envelope' in noise else np.array([1.0, 1.0]))
    m['noiseEnvRate'] = float(noise.get('rate_hz', 200)) if noise else 200.0
    bands_hz = (list(map(float, noise['bands_hz']))
                if noise and 'bands_hz' in noise else [0.0, sr / 2])
    band_levels = (list(map(float, noise['band_levels']))
                   if noise and 'band_levels' in noise else [1.0])
    m['noiseTable'] = make_shaped_noise(sr, bands_hz, band_levels, m['noiseLevel'], rng)

    mod = root.get('modulation') or {}
    vib = mod.get('vibrato') or {}
    trem = mod.get('tremolo') or {}
    detected_v = bool(vib.get('detected', False))
    detected_t = bool(trem.get('detected', False))
    m['vibRateHz'] = float(vib.get('rate_hz', 0.0)) if detected_v else 0.0
    m['vibDepthCents'] = float(vib.get('depth_cents', 0.0)) if detected_v else 0.0
    m['vibOnsetSec'] = float(vib.get('onset_sec', 0.0)) if vib else 0.0
    m['tremRateHz'] = float(trem.get('rate_hz', 0.0)) if detected_t else 0.0
    m['tremDepth'] = min(max(float(trem.get('depth', 0.0)), 0.0), 0.95) if detected_t else 0.0
    return m


def sample_curve(curve, rate, sec):
    """SynthVoice.pde: sampleCurve() を移植 (線形補間 + 両端クランプ)。sec は配列。"""
    if curve.size == 1:
        return np.full(np.shape(sec), curve[0])
    idx = np.clip(np.asarray(sec) * rate, 0.0, curve.size - 1)
    i0 = np.minimum(np.floor(idx).astype(np.int64), curve.size - 2)
    frac = idx - i0
    return curve[i0] + (curve[i0 + 1] - curve[i0]) * frac


def warp_body(t, m):
    """SynthVoice.pde: warpBody() を移植 (sustaining はループ区間を巻き戻す)。"""
    if not m['sustaining']:
        return np.minimum(t, m['origDur'])
    head_t = m['loopStartSec']
    loop_len = max(m['loopEndSec'] - m['loopStartSec'], 1e-3)
    return np.where(t < head_t, t, m['loopStartSec'] + np.mod(t - head_t, loop_len))


# ── Processing 実装の移植: SynthVoice.uGenerate() ──────────────────────────

def render_note(m, midi, gain, note_on_sec, sr):
    """ResynthVoice を 1 音ぶんレンダリングする (note_on_sec 後に noteOff → release)。

    Processing は 1 サンプルずつ位相を積算するが、位相増分は
        Δφ_k(i) = 2π * base_k * pitchMul(i) / sr        (base_k は時間によらない定数)
    と分解できるので、cumsum でベクトル化しても逐次実装とビット単位で同じ軌跡になる
    (Processing は float32、こちらは float64 で、丸め誤差はこちらの方が小さい)。
    """
    rel_sec = max(m['releaseSec'], 0.02)
    total = note_on_sec + rel_sec + 0.02
    n = int(total * sr)
    idx = np.arange(n)
    t = idx / sr                       # uGenerate 内の tSec (使用時点の値)
    target_f0 = 440.0 * 2.0 ** ((midi - 69) / 12.0)
    nyquist = sr * 0.5

    # ── ビブラート: pitchMul(t) = 2^(depth * 0.5 * vg * sin(vibPhase) / 1200)
    if (not USE_SIMPLE_ADSR) and m['vibDepthCents'] > 0.01 and m['vibRateHz'] > 0.001:
        vg = (np.minimum(1.0, t / m['vibOnsetSec']) if m['vibOnsetSec'] > 0.001
              else np.ones(n))
        vib_phase = 2 * np.pi * m['vibRateHz'] * t
        pitch_mul = 2.0 ** (m['vibDepthCents'] * 0.5 * vg * np.sin(vib_phase) / 1200.0)
    else:
        pitch_mul = np.ones(n)

    # ── 振幅包絡 (noteOff 後は releaseStartLevel * (1-u)^2、包絡の時間軸は凍結)
    off_i = min(int(round(note_on_sec * sr)), n)
    warp = warp_body(t, m)
    amp = sample_curve(m['envValues'], m['envRate'], warp)
    warp_env = warp.copy()             # harmEnv / noiseEnv 用 (release 中は凍結)
    rel_mul = np.ones(n)
    if off_i < n:
        t_off = off_i / sr
        warp_off = float(warp_body(np.array([t_off]), m)[0])
        level_off = float(sample_curve(m['envValues'], m['envRate'], np.array([warp_off]))[0])
        u = (t[off_i:] - t_off) / rel_sec
        k = np.maximum(1.0 - u, 0.0)
        amp[off_i:] = level_off * k * k
        warp_env[off_i:] = warp_off
        rel_mul[off_i:] = np.maximum(0.0, 1.0 - u)

    # ── 倍音の加算合成
    s = np.zeros(n)
    for k in range(m['N']):
        a_k = m['harmAmp'][k]
        if a_k <= 0:
            continue
        n1 = m['harmN'][k]
        base = target_f0 * m['harmRatio'][k] * math.sqrt(1.0 + m['inharmB'] * n1 * n1)
        f = base * pitch_mul
        valid = f < nyquist            # Nyquist 以上の倍音は出さない (位相も進めない)
        inc = np.where(valid, 2 * np.pi * f / sr, 0.0)
        phase = m['harmPhase'][k] + np.cumsum(inc)
        h_env = (np.ones(n) if USE_SIMPLE_ADSR
                 else sample_curve(m['harmEnv'][k], m['harmEnvRate'][k], warp_env))
        s += np.where(valid, a_k * h_env * np.sin(phase), 0.0)
    s *= m['harmNorm']

    # ── 整形ノイズ (アタックノイズ・息の成分)
    if (not USE_SIMPLE_ADSR) and m['noiseLevel'] > 0 and m['noiseTable'].size > 1:
        n_env = sample_curve(m['noiseEnv'], m['noiseEnvRate'], warp_env) * m['noiseLevel'] * rel_mul
        s += m['noiseTable'][idx % m['noiseTable'].size] * n_env

    # ── トレモロ (振幅変調のみ = 音高には影響しない)
    if (not USE_SIMPLE_ADSR) and m['tremDepth'] > 0.001 and m['tremRateHz'] > 0.001:
        trem_phase = 2 * np.pi * m['tremRateHz'] * t
        s *= 1.0 - m['tremDepth'] * 0.5 + m['tremDepth'] * 0.5 * np.sin(trem_phase)

    s *= amp * gain * 0.9

    # uGenerate 末尾の done 判定 (振幅が落ちきったら以降は無音)
    silent = (amp <= 1e-4) & (t > 0.15)
    if silent.any():
        s[int(np.argmax(silent)):] = 0.0
    return s


# ── 基音推定 ───────────────────────────────────────────────────────────────

def analytic_band(x, sr, f_lo, f_hi):
    """帯域制限した解析信号 (正の周波数のみ・帯域外を 0) を返す。

    零位相 (周波数領域でのマスクは実ゲイン) なので瞬時位相を歪ませない。
    """
    n = x.size
    spec = np.fft.fft(x)
    freqs = np.fft.fftfreq(n, 1.0 / sr)
    out = np.zeros(n, dtype=complex)
    sel = (freqs >= f_lo) & (freqs <= f_hi)
    out[sel] = 2.0 * spec[sel]
    return np.fft.ifft(out)


CENT_PER_LN = 1200.0 / math.log(2.0)


def estimate_pitch(x, sr, f_ref, guard_sec=0.15):
    """波形 x の基音を推定し (中心 cent, 変調の振れ幅 cent, 変調周波数, 残差 SD cent) を返す.

    手法:
      1. 基音だけを帯域抽出して解析信号 z(t) を作る (零位相なので位相を歪めない)。
      2. 瞬時周波数を **隣接サンプルの位相差** angle(z[n]·conj(z[n-1])) から求める。
         位相を unwrap して微分する素直な方法は、振幅が落ちた瞬間に位相が乱れると
         2π の取り違え (位相スリップ) を起こし、周波数が数 cent 単位で狂う。
         位相差は (-π, π] に収まるので原理的にスリップしない。
      3. ビブラートがあると瞬時周波数は正弦波状に揺れるので
             f(t) ≈ d0 + d1·sin(2πf_m t) + d2·cos(2πf_m t)
         を **振幅の 2 乗で重み付けした最小二乗** で当てる。振幅が落ちた瞬間 (= ノイズが
         支配して位相が信用できない瞬間) の重みが自動的に小さくなる。
         d0 = 平均音高、2·√(d1²+d2²) 相当を「変調の振れ幅 (peak-to-peak)」とする。
         単純平均だと解析窓が変調周期の整数倍でないときに偏るが、この当てはめなら偏らない。

    振幅が落ちる瞬間が実在するのはフルートで、包絡ループの折返し (loop_end→loop_start) に
    88% の段差があり基音が一瞬ほぼ無音になるため。これは振幅の話で音高には影響しない。

    x の両端 guard_sec は帯域抽出のリンギングを含むので捨てる (呼び出し側で余分に渡す)。
    """
    z = analytic_band(x, sr, f_ref * 0.62, f_ref * 1.45)
    g = int(guard_sec * sr)
    z = z[g:z.size - g] if g > 0 and z.size > 2 * g else z

    inst_hz = np.angle(z[1:] * np.conj(z[:-1])) * sr / (2 * np.pi)
    weight = np.abs(z[1:]) * np.abs(z[:-1])
    weight = weight / max(float(weight.max()), 1e-30)
    n = inst_hz.size
    t = np.arange(n) / sr

    # 変調周波数を瞬時周波数トラックのスペクトルから推定 (2–20 Hz)。
    # ・解析窓 2 秒の素の FFT では 0.5 Hz 刻みしかなく、5.7 Hz を 5.5 Hz と取り違えて
    #   最小二乗の振幅が 25% 目減りする → ゼロ詰め + 放物線補間で 0.01 Hz 精度に詰める。
    # ・探索の下限を 2 Hz にするのは、窓内 1 周期程度の低周波を拾うとその正弦波が定数項と
    #   直交せず平均音高を引っ張るため (楽器のビブラートは 4–8 Hz。2 Hz なら窓内 4 周期以上)。
    # ・振幅が落ちた瞬間のスパイクがスペクトルを汚さないよう ±85 cent 相当でクリップする
    #   (ビブラートは高々 ±10 cent なので切り落とされない)。
    clipped = np.clip(inst_hz, f_ref * 0.95, f_ref * 1.05)
    f_mod = fft_peak_hz(clipped - clipped.mean(), sr, 2.0, 20.0, zero_pad=16)

    design = np.column_stack([np.ones(n),
                              np.sin(2 * np.pi * f_mod * t),
                              np.cos(2 * np.pi * f_mod * t)])
    sw = np.sqrt(weight)
    coef, *_ = np.linalg.lstsq(design * sw[:, None], inst_hz * sw, rcond=None)
    d0, d1, d2 = coef
    radius = math.hypot(d1, d2)
    resid = inst_hz - design @ coef
    resid_sd = float(np.sqrt(np.average(resid ** 2, weights=weight))) / d0 * CENT_PER_LN

    swing = 1200.0 * math.log2((d0 + radius) / (d0 - radius)) if radius < d0 else float('nan')
    if not (swing >= 0.05):   # 変調なし (ホルン・オルガン) — 重み付き平均が最良の中心推定
        d0 = float(np.average(inst_hz, weights=weight))
        return 1200.0 * math.log2(d0 / f_ref), 0.0, 0.0, resid_sd
    return 1200.0 * math.log2(d0 / f_ref), swing, f_mod, resid_sd


def fft_peak_hz(x, sr, f_lo, f_hi, zero_pad=8):
    """クロスチェック用: Hann 窓 + ゼロ詰め FFT のピークを対数振幅の放物線補間で求める。

    README の手動手順 (録音を Sonic Visualiser 等でスペクトル分析する) に相当する、
    瞬時周波数法とは独立な推定。両者が一致すれば推定手法起因の間違いを排除できる。
    """
    n = x.size
    nfft = 1 << int(math.ceil(math.log2(n * zero_pad)))
    spec = np.abs(np.fft.rfft(x * np.hanning(n), n=nfft))
    fr = np.fft.rfftfreq(nfft, 1.0 / sr)
    sel = np.where((fr >= f_lo) & (fr <= f_hi))[0]
    k = int(sel[np.argmax(spec[sel])])
    y0, y1, y2 = (math.log(spec[k - 1] + 1e-30), math.log(spec[k] + 1e-30),
                  math.log(spec[k + 1] + 1e-30))
    denom = y0 - 2 * y1 + y2
    delta = 0.5 * (y0 - y2) / denom if abs(denom) > 1e-30 else 0.0
    return (k + delta) * sr / nfft


def pad(s, width):
    """全角を 2 桁と数えて左詰めする (summary の表がガタつかないように)。"""
    import unicodedata
    w = sum(2 if unicodedata.east_asian_width(c) in 'FWA' else 1 for c in s)
    return s + ' ' * max(0, width - w)


def cents(f_measured, f_theory):
    return 1200.0 * math.log2(f_measured / f_theory)


def midi_to_hz(midi):
    """SynthVoice.pde の targetF0 と同じ式 = 平均律 (A4=440Hz)。"""
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']


def note_name(midi):
    return f'{NOTE_NAMES[midi % 12]}{midi // 12 - 1}'


# ── セルフテスト ───────────────────────────────────────────────────────────

def run_selftest(sr, verbose=True):
    """既知の信号を入れて推定器の分解能を検証する。全部 PASS しないと解析に進まない。"""
    results = []
    win_sec, guard = 2.0, 0.15
    n = int((win_sec + 2 * guard) * sr)
    t = np.arange(n) / sr

    # T1: 純音 (アタック無し) — 推定誤差がサブセントであること
    for f in (130.8128, 261.6256, 440.0, 880.0):
        x = np.sin(2 * np.pi * f * t + 0.7)
        c0, swing, _, _ = estimate_pitch(x, sr, f, guard)
        results.append((f'T1 純音 {f:8.3f} Hz', abs(c0) < 0.05,
                        f'誤差 {c0:+.5f} cent (< 0.05)'))

    # T2: 既知のデチューン (+7.3 cent) を復元できること
    f_ref = 440.0
    f_act = f_ref * 2 ** (7.3 / 1200)
    x = np.sin(2 * np.pi * f_act * t)
    c0, _, _, _ = estimate_pitch(x, sr, f_ref, guard)
    results.append(('T2 デチューン純音 +7.3 cent', abs(c0 - 7.3) < 0.05,
                    f'復元 {c0:+.5f} cent (誤差 {c0 - 7.3:+.5f})'))

    # T3: ビブラート付き (中心 523.251 Hz・深さ 20 cent p-p・5.7 Hz)
    #     合成側と同じ式で作る: pitchMul = 2^(depth*0.5*sin/1200)
    f_ref = 523.251
    depth, rate = 20.0, 5.7
    ph = np.cumsum(2 * np.pi * f_ref * 2 ** (depth * 0.5 * np.sin(2 * np.pi * rate * t) / 1200) / sr)
    x = np.sin(ph)
    c0, swing, f_mod, _ = estimate_pitch(x, sr, f_ref, guard)
    results.append(('T3 ビブラート 20cent/5.7Hz 中心', abs(c0) < 0.05,
                    f'中心 {c0:+.5f} cent (< 0.05)'))
    results.append(('T3 ビブラート 振れ幅', abs(swing - depth) / depth < 0.03,
                    f'振れ幅 {swing:.3f} cent (真値 {depth}, 誤差 {100 * (swing - depth) / depth:+.2f}%)'))
    results.append(('T3 ビブラート 変調周波数', abs(f_mod - rate) < 0.05,
                    f'{f_mod:.2f} Hz (真値 {rate})'))

    # T4: トレモロ (振幅変調) が音高推定を汚さないこと
    f_ref = 261.6256
    x = np.sin(2 * np.pi * f_ref * t) * (1 - 0.03 + 0.03 * np.sin(2 * np.pi * 6.0 * t))
    c0, _, _, _ = estimate_pitch(x, sr, f_ref, guard)
    results.append(('T4 トレモロ (AM) 混入', abs(c0) < 0.05,
                    f'誤差 {c0:+.5f} cent (< 0.05)'))

    # T5: クロスチェック側 (FFT ピーク) も cent 単位の議論に足りること
    f_ref = 261.6256
    f_act = f_ref * 2 ** (-1.9 / 1200)
    x = np.sin(2 * np.pi * f_act * t)
    c_fft = cents(fft_peak_hz(x, sr, f_ref * 0.62, f_ref * 1.45), f_ref)
    results.append(('T5 FFT ピーク法 -1.9 cent', abs(c_fft - (-1.9)) < 0.20,
                    f'復元 {c_fft:+.5f} cent (誤差 {c_fft + 1.9:+.5f}, < 0.20)'))

    if verbose:
        print('=' * 72)
        print('セルフテスト (基音推定器の分解能検証)')
        print('=' * 72)
        for name, ok, detail in results:
            print(f'  [{"PASS" if ok else "FAIL"}] {name:32s} {detail}')
        n_pass = sum(1 for _, ok, _ in results if ok)
        print(f'  → {n_pass}/{len(results)} PASS')
        print()
    return results


# ── 楽譜の読み込み ─────────────────────────────────────────────────────────

ROW_RE = re.compile(r'\{\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(0x[0-9A-Fa-f]+)'
                    r'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\}')


def load_score_notes(path):
    """score_data.cpp から実際に鳴らす MIDI ノート番号を抽出する (休符 0 は除く)。

    kScore の 1 行 = {beatAt, noteNumber, velocity, durationQ8, flags, subNote, ...}。
    subNote (8 分音符の裏拍) も発音されるので拾う。
    """
    notes = {}
    for mo in ROW_RE.finditer(path.read_text(encoding='utf-8')):
        beat_at, note, vel, dur_q8, flags, sub_note, sub_vel, _, _ = mo.groups()
        note, vel, sub_note, sub_vel = int(note), int(vel), int(sub_note), int(sub_vel)
        if note > 0 and (int(flags, 16) & 0x01):
            notes.setdefault(note, int(vel))
        if sub_note > 0:
            notes.setdefault(sub_note, int(sub_vel))
    return dict(sorted(notes.items()))


# ── 解析本体 ───────────────────────────────────────────────────────────────

def analyze(sr, note_sec, win_start, win_len):
    rng = np.random.default_rng(NOISE_SEED)
    files = sorted([p for p in DATA_DIR.glob('*.json')], key=lambda p: p.name.lower())
    score_notes = load_score_notes(SCORE_CPP)

    print('=' * 72)
    print('MOP2: 音階の誤差 — 合成波形の基音 vs 平均律理論値')
    print('=' * 72)
    print(f'  楽器定義 : {DATA_DIR.relative_to(REPO_ROOT)}  ({len(files)} 個)')
    print(f'  楽譜     : {SCORE_CPP.relative_to(REPO_ROOT)}')
    print(f'  対象ノート: {", ".join(f"{note_name(n)}({n})" for n in score_notes)}')
    print(f'  合成      : {sr} Hz / 発音長 {note_sec}s / 解析窓 {win_start}–{win_start + win_len}s')
    print()

    rows = []
    for inst_id, path in enumerate(files):
        if is_drum_instrument(inst_id):
            continue                    # 打楽器 (kick/snare/hi-hat/crash) は音高を持たない
        model = load_model(path, sr, rng)
        shift = brass_octave_shift(inst_id)
        node, part_id = NODE_BY_INSTRUMENT_ID[inst_id]
        label = LABEL_BY_INSTRUMENT_ID[inst_id]

        # JSON パラメータからの理論予測 (手計算のクロスチェック用)。
        #   基音 = targetF0 * ratio(n=1) * sqrt(1 + B * 1^2)
        # 内訳を 2 つに分けておくと「誤差がどのパラメータ由来か」がそのまま読める。
        i1 = int(np.argmax(model['harmN'] == 1))
        ratio1 = float(model['harmRatio'][i1])
        cent_ratio = 1200.0 * math.log2(ratio1)                       # ratio(n=1) 由来
        cent_b = 600.0 * math.log2(1.0 + model['inharmB'])            # inharmonicity_b 由来
        predicted = cent_ratio + cent_b

        print(f'[{inst_id}] {label:6s} {path.name}')
        print(f'    ratio(n=1)={ratio1:.6f}  inharmonicity_b={model["inharmB"]:.3e}  '
              f'→ 理論予測 {predicted:+.3f} cent')
        print(f'    vibrato={model["vibDepthCents"]:.0f}cent/{model["vibRateHz"]:.1f}Hz  '
              f'tremolo={model["tremDepth"]:.2f}/{model["tremRateHz"]:.1f}Hz  '
              f'octave_shift={shift:+d}')

        for score_midi, velocity in score_notes.items():
            played_midi = score_midi + shift
            f_theory = midi_to_hz(played_midi)
            gain = min(velocity / 127.0, 1.0) * brass_part_amplitude(inst_id) * MASTER_VOLUME

            wav = render_note(model, played_midi, gain, note_sec, sr)
            guard = 0.15
            i0 = int((win_start - guard) * sr)
            i1e = int((win_start + win_len + guard) * sr)
            seg = wav[i0:i1e]

            c0, swing, f_mod, resid = estimate_pitch(seg, sr, f_theory, guard)
            f_meas = f_theory * 2 ** (c0 / 1200)
            c_fft = cents(fft_peak_hz(wav[int(win_start * sr):int((win_start + win_len) * sr)],
                                      sr, f_theory * 0.62, f_theory * 1.45), f_theory)

            rows.append({
                'instrument_id': inst_id, 'instrument': label, 'json': path.name,
                'node': node, 'part_id': f'0x{part_id:02X}',
                'score_midi': score_midi, 'octave_shift': shift, 'played_midi': played_midi,
                'note_name': note_name(played_midi), 'velocity': velocity,
                'f_theory_hz': f'{f_theory:.4f}', 'f_measured_hz': f'{f_meas:.4f}',
                'cent_error': f'{c0:.4f}', 'cent_abs': f'{abs(c0):.4f}',
                'ratio_n1': f'{ratio1:.6f}', 'inharmonicity_b': f'{model["inharmB"]:.3e}',
                'cent_from_ratio': f'{cent_ratio:.4f}', 'cent_from_inharm_b': f'{cent_b:.4f}',
                'cent_predicted': f'{predicted:.4f}',
                'cent_diff_vs_predicted': f'{c0 - predicted:.4f}',
                'cent_fft_peak': f'{c_fft:.4f}',
                'vib_swing_cents': f'{swing:.3f}', 'vib_rate_hz': f'{f_mod:.2f}',
                'if_resid_sd_cent': f'{resid:.4f}',
            })
            print(f'      {note_name(played_midi):4s} ({f_theory:8.3f} Hz)  '
                  f'実測 {f_meas:8.3f} Hz  誤差 {c0:+7.3f} cent  '
                  f'(予測差 {c0 - predicted:+.3f} / FFT法 {c_fft:+7.3f} / '
                  f'振れ幅 {swing:5.2f} cent)')
        print()
    return rows


def summarize(rows):
    """楽器ごとの集計を返す (グラフと summary.txt が同じこの値を使う)。"""
    stats = []
    for inst_id in sorted({r['instrument_id'] for r in rows}):
        sub = [r for r in rows if r['instrument_id'] == inst_id]
        abs_c = np.array([abs(float(r['cent_error'])) for r in sub])
        signed = np.array([float(r['cent_error']) for r in sub])
        swing = np.array([float(r['vib_swing_cents']) for r in sub])
        stats.append({
            'instrument_id': inst_id,
            'instrument': sub[0]['instrument'],
            'node': sub[0]['node'],
            'json': sub[0]['json'],
            'n': len(sub),
            'mean_abs': float(np.mean(abs_c)),
            'median_abs': float(np.median(abs_c)),
            'max_abs': float(np.max(abs_c)),
            'mean_signed': float(np.mean(signed)),
            'predicted': float(sub[0]['cent_predicted']),
            'ratio_n1': float(sub[0]['ratio_n1']),
            'cent_from_ratio': float(sub[0]['cent_from_ratio']),
            'cent_from_inharm_b': float(sub[0]['cent_from_inharm_b']),
            'swing_mean': float(np.mean(swing)),
            'max_diff_vs_predicted': float(np.max(np.abs(
                [float(r['cent_diff_vs_predicted']) for r in sub]))),
            'max_diff_vs_fft': float(np.max(np.abs(
                [float(r['cent_error']) - float(r['cent_fft_peak']) for r in sub]))),
        })
    return stats


# ── グラフ (スライド用) ────────────────────────────────────────────────────

def graph_slide(stats, out_name='mop2_pitch_error_slide.png'):
    """楽器別の音階誤差 (スライド用シンプル版)。

    MOP2 は誤差が音高によらずほぼ一定 (= 系統オフセット) で中央値・最大が平均と
    ほぼ同値のため、統計量を並べず「音階誤差」の青棒 1 本だけで見せる (ユーザー判断)。
    合格範囲の緑帯・16:9 横長・大きめフォントは MOP4/MOP5 スライド版と共通。
    解説は口頭で行う前提のため説明文・判定ボックス・注記は載せない。
    """
    # mop_graphs.py の setup_font() と同じフォールバック順。macOS には Yu Gothic が無く
    # findfont が 1 テキストごとに警告を出して出力が埋まるのでロガーだけ黙らせる
    # (Hiragino Sans が先に見つかるので描画には影響しない)。
    logging.getLogger('matplotlib.font_manager').setLevel(logging.ERROR)
    plt.rcParams['font.family'] = ['Hiragino Sans', 'Yu Gothic', 'sans-serif']
    plt.rcParams['axes.unicode_minus'] = False

    color_band = '#16A34A'
    color_mean = '#2563EB'

    labels = [f'{s["instrument"]}\n({s["node"]})' for s in stats]
    means = [s['mean_abs'] for s in stats]
    x = np.arange(len(stats))

    fig, ax = plt.subplots(figsize=(12.8, 7.2))
    ax.axhspan(0, THRESHOLD_CENT, facecolor=color_band, alpha=0.12, zorder=0)
    ax.axhline(THRESHOLD_CENT, color=color_band, linestyle='--', linewidth=2.5, zorder=1)

    ax.bar(x, means, width=0.5, color=color_mean, alpha=0.9, zorder=2)

    y_top = max(THRESHOLD_CENT * 1.35, max(means) * 1.6)
    dy = y_top * 0.042
    for i, mean_v in enumerate(means):
        ax.text(i, mean_v + dy, f'{mean_v:.2f}', ha='center', va='bottom',
                fontsize=17, fontweight='bold', color=color_mean)

    legend_handles = [
        mpatches.Patch(color=color_mean, alpha=0.9, label='音階誤差'),
        mpatches.Patch(facecolor=color_band, alpha=0.25, edgecolor=color_band,
                       linestyle='--', label=f'合格範囲 (< {THRESHOLD_CENT} cent)'),
    ]
    ax.legend(handles=legend_handles, loc='upper center', ncol=2, fontsize=14,
              columnspacing=1.0, borderpad=0.5, framealpha=0.95)

    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=17)
    ax.set_xlim(-0.7, len(stats) - 0.3)
    ax.set_ylim(0, y_top)
    ax.tick_params(axis='y', labelsize=14)
    ax.set_ylabel('平均律からの音高のズレ（絶対値, cent）', fontsize=17)
    ax.grid(axis='y', alpha=0.3, zorder=0)
    ax.set_title('音階の誤差（楽器別）', fontsize=21, fontweight='bold', pad=14)

    fig.tight_layout()
    GRAPHS_DIR.mkdir(parents=True, exist_ok=True)
    out = GRAPHS_DIR / out_name
    fig.savefig(out, dpi=150, bbox_inches='tight', facecolor='white')
    plt.close(fig)
    print(f'  -> {out}')
    return out


# ── 出力 ───────────────────────────────────────────────────────────────────

def write_outputs(rows, stats, selftest, stamp, sr, note_sec, win_start, win_len):
    MOP2_DIR.mkdir(parents=True, exist_ok=True)
    csv_path = MOP2_DIR / f'{stamp}.csv'
    with csv_path.open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f'  -> {csv_path}')

    overall_mean = float(np.mean([abs(float(r['cent_error'])) for r in rows]))
    overall_max = float(np.max([abs(float(r['cent_error'])) for r in rows]))
    passed = overall_mean < THRESHOLD_CENT

    lines = []
    lines.append('=' * 72)
    lines.append('MOP2: 音階の誤差 (平均 < 3.6 cent)')
    lines.append('=' * 72)
    lines.append('')
    lines.append('【計測方法】')
    lines.append('  Processing (pc_app/production/orchestra_resynth) の加算合成を Python で再現し、')
    lines.append('  生成波形の基音を推定して平均律の理論音高と比較した (実音の録音はしていない)。')
    lines.append('  基音推定 = 基音帯域の解析信号の瞬時周波数 → 変調成分を最小二乗で分離した中心値。')
    lines.append(f'  移植元: pc_app/common/{{SynthVoice,InstrModel,AudioManager}}.pde')
    lines.append(f'  楽器定義: {DATA_DIR.relative_to(REPO_ROOT)}/*.instrument.json')
    lines.append(f'  楽譜:     {SCORE_CPP.relative_to(REPO_ROOT)}')
    lines.append(f'  合成条件: {sr} Hz / 発音長 {note_sec} s / 解析窓 {win_start}–{win_start + win_len} s')
    lines.append(f'  判定基準の出典: tools/verification/README.md「MOP2: 音階の誤差 (平均 < 3.6 cent)」')
    lines.append('')
    lines.append('【セルフテスト (基音推定器の分解能)】')
    for name, ok, detail in selftest:
        lines.append(f'  [{"PASS" if ok else "FAIL"}] {name:32s} {detail}')
    lines.append('')
    lines.append('【楽器別の集計 (楽譜の 6 音 C/D/E/F/G/A を各楽器のオクターブで発音 = 各 6 音)】')
    lines.append('')
    lines.append('  ' + pad('楽器', 14) + pad('ノード', 10)
                 + '平均|誤差|   中央値     最大   符号付き平均   ビブラート振れ幅')
    lines.append('  ' + '-' * 80)
    for s in stats:
        lines.append('  ' + pad(s['instrument'], 14) + pad(s['node'], 10)
                     + f'{s["mean_abs"]:8.2f} {s["median_abs"]:9.2f} {s["max_abs"]:8.2f}'
                     + f'{s["mean_signed"]:+13.2f} {s["swing_mean"]:15.2f}')
    lines.append('')
    lines.append(f'  全 {len(rows)} 音の平均 |誤差| : {overall_mean:.3f} cent  (基準 < {THRESHOLD_CENT} cent)')
    lines.append(f'  全 {len(rows)} 音の最大 |誤差| : {overall_max:.3f} cent')
    lines.append(f'  判定: {"PASS" if passed else "FAIL"}')
    lines.append('')
    lines.append('【誤差の出どころ (JSON のどのパラメータか)】')
    lines.append('')
    lines.append('  合成の音高は SynthVoice.pde の次の式だけで決まる:')
    lines.append('      f = targetF0 * harmRatio[k] * sqrt(1 + inharmonicity_b * n^2) * pitchMul')
    lines.append('      targetF0 = 440 * 2^((midi-69)/12)   ← 平均律そのもの (ここに誤差はない)')
    lines.append('  よって音階誤差は harmonics[n=1].ratio と inharmonicity_b にしか宿らない。')
    lines.append('  (fundamental_hz / midi_note は合成に使われないので、録音が平均律からずれていても')
    lines.append('   その分は音高に出ない。倍音比が録音の基音に対する相対値だから。)')
    lines.append('')
    lines.append('  ' + pad('楽器', 14) + 'ratio(n=1)  ratio 由来  inharm_b 由来   理論合計    実測との差')
    lines.append('  ' + '-' * 80)
    for s in stats:
        lines.append('  ' + pad(s['instrument'], 14)
                     + f'{s["ratio_n1"]:10.6f} {s["cent_from_ratio"]:+11.3f} '
                     + f'{s["cent_from_inharm_b"]:+13.3f} {s["predicted"]:+11.3f} '
                     + f'{s["max_diff_vs_predicted"]:12.4f}')
    lines.append('')
    lines.append('  実測値は「瞬時周波数法」と「FFT ピーク法」の独立 2 手法で一致を確認している:')
    for s in stats:
        lines.append('    ' + pad(s['instrument'], 14)
                     + f'2 手法の最大差 {s["max_diff_vs_fft"]:.3f} cent / '
                     f'理論予測との最大差 {s["max_diff_vs_predicted"]:.4f} cent')
    lines.append('')
    lines.append('【ビブラートの扱い】')
    lines.append('  ビブラートは瞬時音高を周期的に振るが平均音高は動かさないため、上表の「平均|誤差|」')
    lines.append('  とは分けて「振れ幅 (peak-to-peak)」として集計した。これは音楽的な表現であって')
    lines.append('  音階誤差ではない (JSON の modulation.vibrato.depth_cents がそのまま出ている:')
    lines.append('  トランペット 5 cent・フルート 20 cent)。瞬時値はフルートで ±10 cent 振れるので、')
    lines.append('  「ある一瞬を切り取れば 3.6 cent を超える」が、これは狙って入れた揺れである。')
    lines.append('')
    lines.append('【対象外】')
    lines.append('  instrumentId 4-7 (kick/snare/hi-hat/crash, node_06) は打楽器で音高を持たないため')
    lines.append('  MOP2 の対象外 (AudioManager.isDrumInstrument が別経路で発音する)。')
    lines.append('')

    summary_path = MOP2_DIR / f'{stamp}_summary.txt'
    summary_path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'  -> {summary_path}')
    print()
    print('\n'.join(lines))
    return passed


def main():
    ap = argparse.ArgumentParser(description='MOP2 音階誤差の解析')
    ap.add_argument('--selftest', action='store_true', help='セルフテストのみ実行')
    ap.add_argument('--sample-rate', type=int, default=SAMPLE_RATE)
    ap.add_argument('--note-sec', type=float, default=3.5,
                    help='合成する発音長 (秒)。音高は発音長に依存しないので解析しやすい長さを取る')
    ap.add_argument('--win-start', type=float, default=1.0, help='解析窓の開始 (秒)')
    ap.add_argument('--win-len', type=float, default=2.0, help='解析窓の長さ (秒)')
    args = ap.parse_args()

    selftest = run_selftest(args.sample_rate)
    if not all(ok for _, ok, _ in selftest):
        print('セルフテストが FAIL。推定器を直すまで解析しない。', file=sys.stderr)
        return 1
    if args.selftest:
        return 0

    rows = analyze(args.sample_rate, args.note_sec, args.win_start, args.win_len)
    stats = summarize(rows)
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    write_outputs(rows, stats, selftest, stamp, args.sample_rate,
                  args.note_sec, args.win_start, args.win_len)
    graph_slide(stats)
    return 0


if __name__ == '__main__':
    sys.exit(main())
