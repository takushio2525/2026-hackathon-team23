#!/usr/bin/env python3
"""最終報告書用グラフ生成スクリプト。

tools/verification/results/ 配下の実測 CSV・生ログと
data/entertainment_survey_team23.csv から，報告書掲載用の PNG を fig/ に生成する。
スライド用グラフ（results/graphs/）とは別に，報告書向けの統一体裁
（タイトルなし＝キャプションが担う・落ち着いた配色・細いマーク）で描き直す。

使い方:
  cd work/shiozawa/最終報告書
  ../../../tools/verification/.venv/bin/python fig/make_report_graphs.py

数値の検算のため，各グラフの集計値を標準出力に出す。
"""

import csv
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np

HERE = Path(__file__).resolve().parent          # fig/
REPO = HERE.parents[3]                          # リポジトリルート
RESULTS = REPO / 'tools' / 'verification' / 'results'
DATA = HERE.parent / 'data'

DPI = 200
# 報告書は単段組（本文幅 ≈ 15 cm）なので横長 1 枚 = (8, 3.2) 前後を基本にする
C_MAIN = '#2563EB'      # 実測データ（青）
C_ACCENT = '#DC2626'    # 目標・閾値（赤）
C_GRAY = '#6B7280'
C_NODE = ['#2563EB', '#059669', '#D97706', '#7C3AED', '#DB2777']  # ノード別固定順


def setup():
    plt.rcParams['font.family'] = ['Hiragino Sans', 'sans-serif']
    plt.rcParams['axes.unicode_minus'] = False
    plt.rcParams['font.size'] = 11
    plt.rcParams['axes.linewidth'] = 0.8


def style_ax(ax):
    """上・右スパインを消し，水平グリッドのみ薄く敷く。"""
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.grid(axis='y', color='#E5E7EB', linewidth=0.7)
    ax.set_axisbelow(True)


def save(fig, name):
    out = HERE / name
    fig.savefig(out, dpi=DPI, bbox_inches='tight', facecolor='white')
    plt.close(fig)
    print(f'-> {out.name}')


def read_rows(path):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


# ── MOP1: 拍検出（拍間隔の時系列） ──────────────────────────

def mop1():
    rows = read_rows(RESULTS / 'mop1' / '20260702_205848.csv')
    ms = np.array([float(r['device_ms']) for r in rows])
    d = np.diff(ms)
    start = int(np.where(d > 5000)[0][0]) + 1 if (d > 5000).any() else 0
    seg = ms[start:]                      # 本計測（起動直後の残留 1 拍を除外）
    iv = np.diff(seg)
    mean, sd = iv.mean(), iv.std(ddof=1)
    print(f'MOP1: 拍数={len(seg)} 平均間隔={mean:.1f}ms SD={sd:.1f}ms '
          f'BPM={60000/mean:.1f} 計測={ (seg[-1]-seg[0])/1000:.1f}s')

    fig, ax = plt.subplots(figsize=(8, 3.0))
    x = np.arange(1, len(iv) + 1)
    ax.plot(x, iv, color=C_MAIN, linewidth=1.2, marker='o', markersize=2.2)
    ax.axhline(500, color=C_ACCENT, linestyle='--', linewidth=1.2)
    ax.annotate('メトロノームの理論間隔 500 ms', xy=(len(iv) * 0.99, 640),
                ha='right', va='bottom', fontsize=9.5, color=C_ACCENT)
    ax.set_xlabel('拍番号')
    ax.set_ylabel('拍間隔 (ms)')
    ax.set_ylim(300, 700)
    ax.set_xlim(0, len(iv) + 1)
    style_ax(ax)
    save(fig, 'mop1_beat_interval.png')


# ── MOP2: 音階誤差（楽器×音名の棒） ──────────────────────────

def mop2():
    rows = read_rows(RESULTS / 'mop2' / '20260712_161617.csv')
    insts = []          # 楽器の出現順
    data = defaultdict(list)   # inst -> [(note, cent_error)]
    for r in rows:
        inst = r['instrument']
        if inst not in insts:
            insts.append(inst)
        data[inst].append((r['note_name'], float(r['cent_error'])))
    all_err = np.array([float(r['cent_error']) for r in rows])
    print(f'MOP2: n={len(rows)} 平均|誤差|={np.abs(all_err).mean():.3f} '
          f'最大|誤差|={np.abs(all_err).max():.3f} cent')

    notes = [n for n, _ in data[insts[0]]]
    x = np.arange(len(notes))
    w = 0.19
    fig, ax = plt.subplots(figsize=(8, 3.4))
    ax.axhspan(-3.6, 3.6, color='#DCFCE7', zorder=0)
    ax.annotate('許容範囲 ±3.6 cent', xy=(len(notes) - 0.55, 3.15),
                ha='right', va='top', fontsize=9.5, color='#047857')
    for i, inst in enumerate(insts):
        errs = [e for _, e in data[inst]]
        ax.bar(x + (i - 1.5) * w, errs, width=w * 0.92, color=C_NODE[i], label=inst)
    ax.axhline(0, color=C_GRAY, linewidth=0.8)
    ax.set_xticks(x)
    ax.set_xticklabels([n[:-1] for n in notes])   # C5 -> C（オクターブは凡例側でなく本文で述べる）
    ax.set_xlabel('音名（楽譜で使用する 6 音）')
    ax.set_ylabel('平均律からの誤差 (cent)')
    ax.set_ylim(-4.2, 4.2)
    ax.legend(ncol=4, fontsize=9, frameon=False, loc='lower center',
              bbox_to_anchor=(0.5, -0.42))
    style_ax(ax)
    save(fig, 'mop2_pitch_error.png')


# ── MOP4: 楽器間同期誤差（時系列＋ヒストグラム） ────────────────

def _mop4_ranges():
    rows = read_rows(RESULTS / 'mop4' / '20260711_154006.csv')
    beats = defaultdict(list)
    for r in rows:
        beats[int(r['beatNo'])].append(float(r['localMasterMs']))
    rng = {b: max(v) - min(v) for b, v in beats.items() if len(v) >= 2}
    order = sorted(rng)
    vals = np.array([rng[b] for b in order])
    return order, vals


def mop4():
    order, vals = _mop4_ranges()
    print(f'MOP4: 拍数={len(vals)} 平均={vals.mean():.1f} p50={np.percentile(vals, 50):.0f} '
          f'p95={np.percentile(vals, 95):.1f} 最大={vals.max():.0f} SD={vals.std(ddof=1):.1f} '
          f'20ms超過={(vals > 20).sum()}/{len(vals)} ({(vals > 20).mean()*100:.1f}%)')

    # 時系列
    fig, ax = plt.subplots(figsize=(8, 3.0))
    ax.bar(np.arange(len(vals)), vals, width=1.0, color=C_MAIN)
    ax.axhline(20, color=C_ACCENT, linestyle='--', linewidth=1.2)
    ax.annotate('目標 20 ms', xy=(len(vals) * 0.01, 21.5), fontsize=9.5,
                color=C_ACCENT, va='bottom')
    med = np.percentile(vals, 50)
    ax.axhline(med, color='#111827', linestyle=':', linewidth=1.2)
    ax.annotate(f'中央値 {med:.0f} ms', xy=(len(vals) * 0.99, med + 1.5),
                ha='right', fontsize=9.5, color='#111827')
    ax.set_xlabel('拍（演奏順・全 173 拍）')
    ax.set_ylabel('発音時刻差 (ms)')
    ax.set_xlim(-1, len(vals))
    style_ax(ax)
    save(fig, 'mop4_sync_error.png')

    # ヒストグラム
    fig, ax = plt.subplots(figsize=(8, 2.8))
    ax.hist(vals, bins=np.arange(0, 70, 2), color=C_MAIN, edgecolor='white',
            linewidth=0.4)
    ax.axvline(20, color=C_ACCENT, linestyle='--', linewidth=1.2)
    ax.annotate('目標 20 ms', xy=(21, ax.get_ylim()[1] * 0.9), fontsize=9.5,
                color=C_ACCENT)
    p95 = np.percentile(vals, 95)
    ax.axvline(p95, color=C_GRAY, linestyle=':', linewidth=1.2)
    ax.annotate(f'p95 = {p95:.1f} ms', xy=(p95 + 1, ax.get_ylim()[1] * 0.62),
                fontsize=9.5, color=C_GRAY)
    ax.set_xlabel('楽器間同期誤差 (ms)')
    ax.set_ylabel('拍数')
    style_ax(ax)
    save(fig, 'mop4_sync_hist.png')


# ── MOP5: 生の配送遅延・バースト・吸収効果・対策前後 ─────────────

def _read_mop5(path, lookahead):
    """R 行から (partId, deviceMs, sample=送信スタンプ−受信ローカル時刻) を返す。"""
    rows = read_rows(path)
    recv = defaultdict(list)
    fire_late = []
    recv_late = 0
    n_recv = 0
    for r in rows:
        if r['type'] == 'R':
            dev = float(r['deviceMs'])
            ts = float(r['playAtMasterMs']) - lookahead
            recv[int(r['partId'])].append((dev, ts - dev))
            n_recv += 1
            if float(r['lateMs']) > 0:
                recv_late += 1
        else:
            fire_late.append(float(r['lateMs']))
    return recv, np.array(fire_late), recv_late, n_recv


def _relative_delay(recv):
    """時計オフセットとクロックスキューが未知のため，ノードごとに
    sample（送信スタンプ − 受信ローカル時刻 = 真のオフセット − 配送遅延）を
    受信時刻で一次回帰してスキューを補正し，残差の上側 98 パーセンタイルを
    「最小配送遅延の基準線」とみなす（MOP5_countermeasure_eval の再集計方式と同じ
    上側包絡推定）。基準線からの下方距離を見かけの配送遅延とする。
    真のゼロ点は原理的に測れないため，得られる値は真の遅延の下限側の推定である。"""
    delays = []
    for part, lst in recv.items():
        lst.sort()
        devs = np.array([d for d, _ in lst])
        smps = np.array([s for _, s in lst])
        coef = np.polyfit(devs, smps, 1)
        resid = smps - np.polyval(coef, devs)
        base = np.percentile(resid, 98)
        delays.extend(np.maximum(base - resid, 0.0))
    return np.array(delays)


def mop5():
    final_csv = RESULTS / 'mop5' / '20260711_154006.csv'
    recv, fire_late, r_late, n_recv = _read_mop5(final_csv, 220.0)

    # (1) 生の配送遅延の分布（当初定義 MOP5 の評価）
    delays = _relative_delay(recv)
    print(f'MOP5生遅延: n={len(delays)} 平均={delays.mean():.0f} p50={np.percentile(delays, 50):.0f} '
          f'p95={np.percentile(delays, 95):.0f} 最大={delays.max():.0f} ms '
          f'30ms以下率={(delays <= 30).mean()*100:.1f}%')
    fig, ax = plt.subplots(figsize=(8, 2.9))
    ax.hist(delays, bins=np.arange(0, 230, 5), color=C_MAIN, edgecolor='white',
            linewidth=0.4)
    ax.axvline(30, color=C_ACCENT, linestyle='--', linewidth=1.2)
    ax.annotate('目標 30 ms', xy=(33, ax.get_ylim()[1] * 0.88), fontsize=9.5,
                color=C_ACCENT)
    mean = delays.mean()
    ax.axvline(mean, color=C_GRAY, linestyle=':', linewidth=1.2)
    ax.annotate(f'平均 {mean:.0f} ms', xy=(mean + 3, ax.get_ylim()[1] * 0.62),
                fontsize=9.5, color=C_GRAY)
    ax.set_xlabel('BEAT の配送遅延（最小遅延サンプル基準の相対値，ms）')
    ax.set_ylabel('受信数')
    style_ax(ax)
    save(fig, 'mop5_raw_delay.png')

    # (2) 受信間隔のヒストグラム（バースト配送の証拠）
    fig, ax = plt.subplots(figsize=(8, 2.9))
    intervals = []
    for part, lst in recv.items():
        lst.sort()
        devs = np.array([d for d, _ in lst])
        intervals.extend(np.diff(devs))
    intervals = np.array(intervals)
    grid = 204.8
    near = np.abs((intervals % grid + grid / 2) % grid - grid / 2)
    print(f'MOP5受信間隔: n={len(intervals)} 204.8ms格子から±15ms内={ (near <= 15).mean()*100:.1f}%')
    ax.hist(intervals, bins=np.arange(0, 700, 10), color=C_MAIN,
            edgecolor='white', linewidth=0.4)
    for k in range(0, 4):
        ax.axvline(grid * k, color=C_ACCENT, linestyle=':', linewidth=1.0)
    ax.annotate('204.8 ms の整数倍（ビーコン間隔 102.4 ms × 2 の格子）',
                xy=(240, ax.get_ylim()[1] * 0.88), fontsize=9.5, color=C_ACCENT)
    ax.set_xlabel('同一ノードにおける BEAT 受信間隔 (ms)')
    ax.set_ylabel('受信数')
    style_ax(ax)
    save(fig, 'mop5_burst_interval.png')

    # (3) 発音予約によるジッタ吸収の効果
    #   受信直後に発音した場合: 予定時刻とのずれ = |margin| = |playAt − localMaster(R)|
    margins = []
    rows = read_rows(final_csv)
    for r in rows:
        if r['type'] == 'R':
            margins.append(abs(float(r['playAtMasterMs']) - float(r['localMasterMs'])))
    margins = np.array(margins)
    print(f'MOP5吸収: 受信即発音のずれ 平均={margins.mean():.1f} 最大={margins.max():.0f} / '
          f'予約発音の遅れ 平均={fire_late.mean():.1f} p50={np.percentile(fire_late, 50):.0f} '
          f'最大={fire_late.max():.0f} ms')
    fig, ax = plt.subplots(figsize=(7.2, 3.0))
    labels = ['受信直後に発音した場合\n（発音予約なし）', '予約時刻まで待って発音\n（本システムの実測）']
    means = [margins.mean(), fire_late.mean()]
    maxes = [margins.max(), fire_late.max()]
    bars = ax.bar(labels, means, width=0.5, color=[C_GRAY, C_MAIN])
    for b, m, mx in zip(bars, means, maxes):
        ax.annotate(f'平均 {m:.1f} ms', xy=(b.get_x() + b.get_width() / 2, m + 3),
                    ha='center', fontsize=10.5, fontweight='bold')
        ax.plot(b.get_x() + b.get_width() / 2, mx, marker='_', markersize=18,
                color=C_ACCENT, markeredgewidth=2)
        ax.annotate(f'最大 {mx:.0f}', xy=(b.get_x() + b.get_width() / 2 + 0.28, mx),
                    fontsize=9.5, color=C_ACCENT, va='center')
    ax.set_ylabel('発音予定時刻とのずれ (ms)')
    ax.set_ylim(0, 240)
    style_ax(ax)
    save(fig, 'mop5_jitter_absorption.png')

    # (4) 対策前後の受信遅刻率
    cases = [
        ('対策前\n(先読み 45 ms・EMA)', RESULTS / 'mop5' / '20260710_221532.csv', 45.0),
        ('対策後\n(先読み 220 ms・min)', RESULTS / 'mop5' / '20260710_231356.csv', 220.0),
        ('最終構成\n(ビーコン設定撤去)', RESULTS / 'mop5' / '20260711_154006.csv', 220.0),
    ]
    rates, ns = [], []
    for label, path, la in cases:
        _, _, late, n = _read_mop5(path, la)
        rates.append(late / n * 100)
        ns.append((late, n))
    print(f'MOP5前後: ' + ' / '.join(f'{late}/{n}={r:.1f}%' for (late, n), r in zip(ns, rates)))
    fig, ax = plt.subplots(figsize=(7.2, 3.0))
    bars = ax.bar([c[0] for c in cases], rates, width=0.5,
                  color=[C_GRAY, C_MAIN, C_MAIN])
    for b, r, (late, n) in zip(bars, rates, ns):
        ax.annotate(f'{r:.1f}%\n({late}/{n} 拍)',
                    xy=(b.get_x() + b.get_width() / 2, r + 1.2),
                    ha='center', fontsize=10, fontweight='bold')
    ax.set_ylabel('受信遅刻率 (%)')
    ax.set_ylim(0, 55)
    style_ax(ax)
    save(fig, 'mop5_before_after.png')


# ── MOP6: テンポ追従 ─────────────────────────────────────

def mop6():
    rows = read_rows(RESULTS / 'mop6' / '20260702_212701.csv')
    t0 = min(float(r['pc_timestamp']) for r in rows)
    series = defaultdict(list)
    for r in rows:
        series[r['node_name']].append((float(r['pc_timestamp']) - t0, float(r['bpm'])))
    fig, ax = plt.subplots(figsize=(8, 3.2))
    for i, name in enumerate(sorted(series)):
        pts = sorted(series[name])
        ax.plot([p[0] for p in pts], [p[1] for p in pts], color=C_NODE[i],
                linewidth=1.4, label=name)
    ax.axvline(29.1, color=C_GRAY, linestyle=':', linewidth=1.2)
    ax.annotate('テンポ変化を検出 (29.1 s)', xy=(30, 137), fontsize=9.5, color=C_GRAY)
    ax.set_xlabel('経過時間 (s)')
    ax.set_ylabel('楽器ノードが受信したテンポ (BPM)')
    ax.set_ylim(60, 150)
    ax.legend(ncol=4, fontsize=9, frameon=False, loc='lower center',
              bbox_to_anchor=(0.5, -0.44))
    style_ax(ax)
    print(f'MOP6: 系列={sorted(series)} 範囲={min(min(b for _, b in v) for v in series.values()):.1f}'
          f'-{max(max(b for _, b in v) for v in series.values()):.1f} BPM')
    save(fig, 'mop6_tempo_track.png')


# ── MOP7: 起動時間 ──────────────────────────────────────

def mop7():
    rows = read_rows(RESULTS / 'mop7' / '20260702_205051.csv')
    names = [r['node_name'] for r in rows]
    vals = [float(r['device_ms']) / 1000 for r in rows]
    print(f'MOP7: ' + ' '.join(f'{n}={v:.2f}s' for n, v in zip(names, vals)))
    fig, ax = plt.subplots(figsize=(8, 2.8))
    y = np.arange(len(names))
    ax.barh(y, vals, height=0.55, color=[C_MAIN if n != 'node_01' else '#1E40AF' for n in names])
    for yi, v in zip(y, vals):
        ax.annotate(f'{v:.2f} s', xy=(v + 0.05, yi), va='center', fontsize=9.5)
    ax.axvline(5.0, color=C_ACCENT, linestyle='--', linewidth=1.2)
    ax.annotate('目標 5 s', xy=(5.0, -0.55), fontsize=9.5, color=C_ACCENT,
                ha='center', va='top', annotation_clip=False)
    ax.set_yticks(y)
    ax.set_yticklabels([f'{n}（{"指揮者" if n == "node_01" else "楽器"}）' for n in names])
    ax.invert_yaxis()
    ax.set_xlabel('起動時間 (s)')
    ax.set_xlim(0, 5.5)
    ax.grid(axis='x', color='#E5E7EB', linewidth=0.7)
    ax.grid(axis='y', visible=False)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.set_axisbelow(True)
    save(fig, 'mop7_startup.png')


# ── MOP8: CPU 負荷 ──────────────────────────────────────

def mop8():
    rows = read_rows(RESULTS / 'mop8' / '20260702_210538.csv')[20:]   # ウォームアップ除外
    inp = np.array([float(r['inputUs']) for r in rows])
    total = np.array([float(r['totalUs']) for r in rows])
    print(f'MOP8: n={len(inp)} 入力 平均={inp.mean():.0f}us p99={np.percentile(inp, 99):.0f}us '
          f'最大={inp.max():.0f}us / 合計最大={total.max():.0f}us')
    fig, ax = plt.subplots(figsize=(8, 2.9))
    ax.hist(inp, bins=np.arange(0, 2150, 25), color=C_MAIN, edgecolor='white',
            linewidth=0.3)
    ax.set_yscale('log')
    ax.axvline(2000, color=C_ACCENT, linestyle='--', linewidth=1.2)
    ax.annotate('目標 2000 µs', xy=(1980, 1500), fontsize=9.5,
                color=C_ACCENT, ha='right')
    ax.axvline(inp.max(), color=C_GRAY, linestyle=':', linewidth=1.2)
    ax.annotate(f'最大 {inp.max():.0f} µs', xy=(inp.max() + 20, 1500), fontsize=9.5,
                color=C_GRAY)
    ax.set_xlabel('入力フェーズの処理時間 (µs)')
    ax.set_ylabel('サンプル数（対数）')
    ax.set_xlim(-30, 2130)
    style_ax(ax)
    save(fig, 'mop8_cpu_load.png')


# ── エンタテインメント性アンケート ─────────────────────────────

def survey():
    rows = read_rows(DATA / 'entertainment_survey_team23.csv')
    items = ['没入感・臨場感', '一体感・同期の心地よさ', '演出の華やかさ', '楽しさ・高揚感']
    cols = [f'評価項目：{i}' for i in items]
    vals = {i: np.array([int(r[c]) for r in rows]) for i, c in zip(items, cols)}
    n = len(rows)
    comments = [r['システム全体に対するご意見・ご感想（任意）'] for r in rows
                if r['システム全体に対するご意見・ご感想（任意）'].strip()]
    print(f'Survey: n={n} 自由記述={len(comments)}件')
    for i in items:
        v = vals[i]
        print(f'  {i}: 平均={v.mean():.2f} 中央値={np.median(v):.0f} SD={v.std(ddof=1):.2f}')

    fig, axes = plt.subplots(2, 2, figsize=(8, 4.6), sharex=True, sharey=True)
    for ax, item in zip(axes.flat, items):
        v = vals[item]
        counts = [(v == k).sum() for k in range(1, 8)]
        ax.bar(range(1, 8), counts, width=0.7, color=C_MAIN)
        for k, c in zip(range(1, 8), counts):
            if c:
                ax.annotate(str(c), xy=(k, c + 0.4), ha='center', fontsize=8.5)
        ax.axvline(v.mean(), color=C_ACCENT, linestyle='--', linewidth=1.2)
        ax.set_title(f'{item}（平均 {v.mean():.2f}・中央値 {np.median(v):.0f}）',
                     fontsize=10)
        ax.set_xticks(range(1, 8))
        ax.set_ylim(0, 24)
        style_ax(ax)
    for ax in axes[1]:
        ax.set_xlabel('評価（1: 低い 〜 7: 高い）')
    for ax in axes[:, 0]:
        ax.set_ylabel('回答数')
    fig.tight_layout()
    save(fig, 'survey_dist.png')


if __name__ == '__main__':
    setup()
    mop1()
    mop2()
    mop4()
    mop5()
    mop6()
    mop7()
    mop8()
    survey()
    print('done.')
