#!/usr/bin/env python3
"""
MOP 検証結果のグラフ生成スクリプト。
results/mop*/ 配下の最新 CSV からグラフを生成し results/graphs/ に保存する。

使い方:
  .venv/bin/python scripts/mop_graphs.py          # 全 MOP
  .venv/bin/python scripts/mop_graphs.py --mop 1 4 8  # 個別指定
"""

import argparse
import csv
import os
import sys
from collections import defaultdict
from itertools import combinations
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

RESULTS_DIR = Path(__file__).resolve().parent.parent / 'results'
GRAPHS_DIR = RESULTS_DIR / 'graphs'

FIGSIZE = (10, 6)
DPI = 150

# 色の定義
COLOR_PASS = '#2563EB'
COLOR_FAIL = '#DC2626'
COLOR_THRESHOLD = '#DC2626'
COLOR_DATA = '#2563EB'
COLOR_DATA_ALT = '#059669'
NODE_COLORS = ['#2563EB', '#059669', '#D97706', '#7C3AED', '#DB2777']


def setup_font():
    """日本語フォントのフォールバック設定。"""
    plt.rcParams['font.family'] = ['Hiragino Sans', 'Yu Gothic', 'sans-serif']
    plt.rcParams['axes.unicode_minus'] = False


def find_latest_csv(mop_num):
    """mop<N>/ 配下で最も新しい非空 .csv を返す。なければ None。"""
    mop_dir = RESULTS_DIR / f'mop{mop_num}'
    if not mop_dir.exists():
        return None
    csvs = [p for p in mop_dir.glob('*.csv') if p.stat().st_size > 0]
    if not csvs:
        return None
    return max(csvs, key=lambda p: p.stat().st_mtime)


def read_csv(path):
    """CSV を辞書のリストとして読む。空行・データなしなら空リスト。"""
    rows = []
    with open(path, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
    return rows


def save_fig(fig, name):
    """グラフを保存。"""
    GRAPHS_DIR.mkdir(parents=True, exist_ok=True)
    out = GRAPHS_DIR / name
    fig.savefig(out, dpi=DPI, bbox_inches='tight', facecolor='white')
    plt.close(fig)
    print(f'  -> {out}')


def make_title(mop_label, passed):
    """PASS/FAIL 付きタイトル文字列を返す。"""
    verdict = 'PASS' if passed else 'FAIL'
    return f'{mop_label}  [{verdict}]'


# ── MOP1: 拍検出率 ≥ 90% ────────────────────────────────

def graph_mop1(csv_path):
    print(f'MOP1: {csv_path.name}')
    rows = read_csv(csv_path)
    if len(rows) < 2:
        print('  データ不足、スキップ')
        return

    device_ms = [float(r['device_ms']) for r in rows]
    bpms = [float(r['bpm']) for r in rows]

    intervals = np.diff(device_ms)

    median_bpm = float(np.median(bpms))
    expected_interval_ms = 60000.0 / median_bpm if median_bpm > 0 else 500
    # 期待間隔の 3 倍を超える外れ値（長い休止区間）を除外して表示
    cutoff = expected_interval_ms * 3
    valid = intervals[intervals < cutoff]
    valid_s = valid / 1000.0
    expected_interval_s = expected_interval_ms / 1000.0

    total_duration_s = (device_ms[-1] - device_ms[0]) / 1000.0
    expected_beats = int(total_duration_s * median_bpm / 60.0)
    detected_beats = len(rows)
    detection_rate = (detected_beats / expected_beats * 100) if expected_beats > 0 else 0
    passed = detection_rate >= 90

    fig, ax = plt.subplots(figsize=FIGSIZE)
    ax.hist(valid_s, bins=30, color=COLOR_DATA, alpha=0.8, edgecolor='white')
    ax.axvline(expected_interval_s, color=COLOR_THRESHOLD, linestyle='--',
               linewidth=2, label=f'目標間隔 {expected_interval_ms:.0f} ms ({median_bpm:.0f} BPM)')

    stats_text = (
        f'検出拍数: {detected_beats}\n'
        f'期待拍数: {expected_beats}\n'
        f'検出率: {detection_rate:.1f}%\n'
        f'中央値 BPM: {median_bpm:.1f}'
    )
    ax.text(0.97, 0.95, stats_text, transform=ax.transAxes,
            verticalalignment='top', horizontalalignment='right',
            fontsize=11,
            bbox=dict(boxstyle='round,pad=0.5', facecolor='#F3F4F6', alpha=0.9))

    ax.set_xlabel('拍間隔 (秒)')
    ax.set_ylabel('頻度')
    ax.set_title(make_title('MOP1: 拍検出の正確性 (≥ 90%)', passed),
                 fontsize=14, fontweight='bold',
                 color=COLOR_PASS if passed else COLOR_FAIL)
    ax.legend(loc='upper left')
    ax.grid(axis='y', alpha=0.3)
    fig.tight_layout()
    save_fig(fig, 'mop1_beat_detection.png')


# ── MOP4: 楽器間同期誤差 ≤ 20ms ─────────────────────────

def graph_mop4(csv_path):
    print(f'MOP4: {csv_path.name}')
    rows = read_csv(csv_path)
    if not rows:
        print('  データなし、スキップ')
        return

    headers = list(rows[0].keys())
    # 廃止済みの NOTE_ON PC タイムスタンプ方式 CSV (秒単位)。過去データ用に残す
    is_pc_ts_format = 'noteNumber' in headers and 'device_t' in headers

    beat_groups = defaultdict(list)

    if 'localMasterMs' in headers and 'playAtMasterMs' in headers:
        # 現行 M45F 方式 (mop4_sync_error.py): 発火時の推定マスタ時刻 (ms)。
        # 指揮者リセットで beatNo が 1 から再開しても混ざらないよう playAt もキーに含める
        for r in rows:
            beat_groups[(int(r['beatNo']), int(r['playAtMasterMs']))].append(
                float(r['localMasterMs']))
    elif is_pc_ts_format:
        for r in rows:
            beat_groups[int(r['beatNo'])].append(float(r['pc_timestamp']))
    elif 'localMs' in headers or 'localMasterMs' in headers:
        local_col = 'localMs' if 'localMs' in headers else 'localMasterMs'
        for r in rows:
            beat_groups[int(r['beatNo'])].append(float(r[local_col]))
    else:
        print('  未知の CSV フォーマット、スキップ')
        return

    threshold_ms = 20
    beats_sorted = sorted(beat_groups.keys())
    errors = []
    for b in beats_sorted:
        times = beat_groups[b]
        if len(times) < 2:
            continue  # 1 台しか揃わない拍を誤差 0 で混ぜると平均が実態より下がる
        diff = max(times) - min(times)
        if is_pc_ts_format:
            diff *= 1000
        errors.append(diff)

    errors = np.array(errors)
    max_error = float(np.max(errors)) if len(errors) > 0 else 0
    mean_error = float(np.mean(errors)) if len(errors) > 0 else 0
    passed = max_error <= threshold_ms

    fig, ax = plt.subplots(figsize=FIGSIZE)
    ax.plot(range(len(errors)), errors, color=COLOR_DATA, linewidth=1.2, alpha=0.8)
    ax.axhline(threshold_ms, color=COLOR_THRESHOLD, linestyle='--',
               linewidth=2, label=f'閾値 {threshold_ms} ms')

    over_mask = errors > threshold_ms
    if np.any(over_mask):
        ax.scatter(np.where(over_mask)[0], errors[over_mask],
                   color=COLOR_FAIL, s=20, zorder=5, label='閾値超過')

    stats_text = (
        f'最大: {max_error:.1f} ms\n'
        f'平均: {mean_error:.1f} ms\n'
        f'計測拍数: {len(errors)}'
    )
    ax.text(0.97, 0.95, stats_text, transform=ax.transAxes,
            verticalalignment='top', horizontalalignment='right',
            fontsize=11,
            bbox=dict(boxstyle='round,pad=0.5', facecolor='#F3F4F6', alpha=0.9))

    ax.set_xlabel('集計拍 (時系列順)')
    ax.set_ylabel('同期誤差 (ms)')
    ax.set_title(make_title('MOP4: 楽器間同期誤差 (≤ 20 ms)', passed),
                 fontsize=14, fontweight='bold',
                 color=COLOR_PASS if passed else COLOR_FAIL)
    ax.legend(loc='upper left')
    ax.set_ylim(bottom=0)
    ax.grid(axis='y', alpha=0.3)
    fig.tight_layout()
    save_fig(fig, 'mop4_sync_error.png')


# ── MOP5: スレーブ間発音同期 ≤ 30ms ──────────────────────

def graph_mop5(csv_path):
    print(f'MOP5: {csv_path.name}')
    rows = read_csv(csv_path)
    if not rows:
        print('  データなし、スキップ')
        return

    headers = list(rows[0].keys())
    is_pc_ts_format = 'noteNumber' in headers and 'device_t' in headers

    threshold_ms = 30
    pairwise_delays = []
    is_late_format = 'lateMs' in headers  # 現行 M45R/M45F 方式 (mop5_comm_delay.py)

    if is_late_format:
        # 発火時の遅刻 lateMs のヒストグラム。判定は p95 <= 閾値 (スクリプトと同基準)
        for r in rows:
            if r.get('type', '') == 'F':
                pairwise_delays.append(float(r['lateMs']))
    elif is_pc_ts_format:
        beat_groups = defaultdict(list)
        for r in rows:
            beat_groups[int(r['beatNo'])].append(float(r['pc_timestamp']))
        for times in beat_groups.values():
            if len(times) >= 2:
                for a, b in combinations(times, 2):
                    pairwise_delays.append(abs(a - b) * 1000)
    elif 'ahead' in headers:
        beat_groups = defaultdict(list)
        for r in rows:
            if r.get('type', '') == 'M5I' and r.get('ahead', ''):
                beat_groups[int(r['beatNo'])].append(float(r['ahead']))
        for aheads in beat_groups.values():
            if len(aheads) >= 2:
                for a, b in combinations(aheads, 2):
                    pairwise_delays.append(abs(a - b))
    else:
        print('  未知の CSV フォーマット、スキップ')
        return

    if not pairwise_delays:
        print('  ペアデータなし、スキップ')
        return

    delays = np.array(pairwise_delays)
    max_delay = float(np.max(delays))
    mean_delay = float(np.mean(delays))
    p95 = float(np.percentile(delays, 95))
    passed = (p95 <= threshold_ms) if is_late_format else (max_delay <= threshold_ms)

    fig, ax = plt.subplots(figsize=FIGSIZE)
    ax.hist(delays, bins=40, color=COLOR_DATA_ALT, alpha=0.8, edgecolor='white')
    ax.axvline(threshold_ms, color=COLOR_THRESHOLD, linestyle='--',
               linewidth=2, label=f'閾値 {threshold_ms} ms')

    stats_text = (
        f'最大: {max_delay:.1f} ms\n'
        f'平均: {mean_delay:.1f} ms\n'
        f'P95: {p95:.1f} ms\n'
        f'サンプル数: {len(delays)}'
    )
    ax.text(0.97, 0.95, stats_text, transform=ax.transAxes,
            verticalalignment='top', horizontalalignment='right',
            fontsize=11,
            bbox=dict(boxstyle='round,pad=0.5', facecolor='#F3F4F6', alpha=0.9))

    ax.set_xlabel('発火遅刻 lateMs (ms)' if is_late_format
                  else 'ノードペア間遅延 (ms)')
    ax.set_ylabel('頻度')
    ax.set_title(make_title('MOP5: 発音予約の遅刻 (発火 lateMs p95 ≤ 30 ms)'
                            if is_late_format
                            else 'MOP5: スレーブ間発音同期 (≤ 30 ms)', passed),
                 fontsize=14, fontweight='bold',
                 color=COLOR_PASS if passed else COLOR_FAIL)
    ax.legend(loc='upper left')
    ax.grid(axis='y', alpha=0.3)
    fig.tight_layout()
    save_fig(fig, 'mop5_comm_delay.png')


# ── MOP6: テンポ追従 ≤ 2拍 ──────────────────────────────

def graph_mop6(csv_path):
    print(f'MOP6: {csv_path.name}')
    rows = read_csv(csv_path)
    if not rows:
        print('  データなし、スキップ')
        return

    nodes = defaultdict(lambda: {'beats': [], 'bpms': []})
    for r in rows:
        name = r.get('node_name', f"node_{r.get('partId', '?')}")
        nodes[name]['beats'].append(int(r['beatNo']))
        nodes[name]['bpms'].append(float(r['bpm']))

    fig, ax = plt.subplots(figsize=FIGSIZE)
    for i, (name, data) in enumerate(sorted(nodes.items())):
        color = NODE_COLORS[i % len(NODE_COLORS)]
        ax.plot(data['beats'], data['bpms'], color=color,
                linewidth=1.5, alpha=0.8, label=name)

    ax.set_xlabel('拍番号')
    ax.set_ylabel('BPM')
    ax.set_title('MOP6: テンポ追従 (≤ 2拍で追従)',
                 fontsize=14, fontweight='bold', color=COLOR_DATA)
    ax.legend(loc='best')
    ax.grid(axis='y', alpha=0.3)
    fig.tight_layout()
    save_fig(fig, 'mop6_tempo_track.png')


# ── MOP7: 起動時間 ≤ 5秒 ─────────────────────────────────

def graph_mop7(csv_path):
    print(f'MOP7: {csv_path.name}')
    rows = read_csv(csv_path)
    if not rows:
        print('  データなし、スキップ')
        return

    node_times = {}
    for r in rows:
        name = r.get('node_name', f"node_{r.get('nodeId', '?')}")
        ms = float(r['device_ms'])
        node_times[name] = max(node_times.get(name, 0), ms)

    if not node_times:
        print('  ノードデータなし、スキップ')
        return

    threshold_ms = 5000
    names = sorted(node_times.keys())
    times_ms = [node_times[n] for n in names]
    times_s = [t / 1000.0 for t in times_ms]

    max_time_ms = max(times_ms)
    passed = max_time_ms <= threshold_ms

    fig, ax = plt.subplots(figsize=FIGSIZE)
    colors = [COLOR_PASS if t <= threshold_ms else COLOR_FAIL for t in times_ms]
    bars = ax.barh(names, times_s, color=colors, alpha=0.8, edgecolor='white', height=0.5)
    ax.axvline(threshold_ms / 1000.0, color=COLOR_THRESHOLD, linestyle='--',
               linewidth=2, label=f'閾値 {threshold_ms/1000:.0f} 秒')

    for bar, t_s in zip(bars, times_s):
        ax.text(bar.get_width() + 0.05, bar.get_y() + bar.get_height() / 2,
                f'{t_s:.2f} s', va='center', fontsize=10)

    ax.set_xlabel('起動時間 (秒)')
    ax.set_title(make_title('MOP7: 起動時間 (≤ 5秒)', passed),
                 fontsize=14, fontweight='bold',
                 color=COLOR_PASS if passed else COLOR_FAIL)
    ax.legend(loc='lower right')
    ax.grid(axis='x', alpha=0.3)
    ax.set_xlim(right=max(max(times_s) * 1.3, threshold_ms / 1000.0 * 1.2))
    fig.tight_layout()
    save_fig(fig, 'mop7_startup.png')


# ── MOP8: CPU負荷 入力フェーズ ≤ 2ms ─────────────────────

def graph_mop8(csv_path):
    print(f'MOP8: {csv_path.name}')
    rows = read_csv(csv_path)
    if not rows:
        print('  データなし、スキップ')
        return

    input_us = np.array([float(r['inputUs']) for r in rows])
    threshold_us = 2000

    max_val = float(np.max(input_us))
    mean_val = float(np.mean(input_us))
    p99 = float(np.percentile(input_us, 99))
    passed = max_val <= threshold_us

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=FIGSIZE,
                                    gridspec_kw={'width_ratios': [3, 1]})

    ax1.hist(input_us, bins=50, color=COLOR_DATA, alpha=0.8, edgecolor='white')
    ax1.axvline(threshold_us, color=COLOR_THRESHOLD, linestyle='--',
                linewidth=2, label=f'閾値 {threshold_us} μs')
    ax1.set_xlabel('入力フェーズ時間 (μs)')
    ax1.set_ylabel('頻度')
    ax1.legend(loc='upper left')
    ax1.grid(axis='y', alpha=0.3)

    bp = ax2.boxplot(input_us, vert=True, patch_artist=True,
                     boxprops=dict(facecolor=COLOR_DATA, alpha=0.5),
                     medianprops=dict(color=COLOR_DATA, linewidth=2))
    ax2.axhline(threshold_us, color=COLOR_THRESHOLD, linestyle='--', linewidth=2)
    ax2.set_ylabel('入力フェーズ時間 (μs)')
    ax2.set_xticklabels(['inputUs'])
    ax2.grid(axis='y', alpha=0.3)

    stats_text = (
        f'最大: {max_val:.0f} μs\n'
        f'平均: {mean_val:.1f} μs\n'
        f'P99: {p99:.0f} μs\n'
        f'N = {len(input_us)}'
    )
    ax1.text(0.97, 0.95, stats_text, transform=ax1.transAxes,
             verticalalignment='top', horizontalalignment='right',
             fontsize=11,
             bbox=dict(boxstyle='round,pad=0.5', facecolor='#F3F4F6', alpha=0.9))

    fig.suptitle(make_title('MOP8: CPU負荷 入力フェーズ (≤ 2 ms)', passed),
                 fontsize=14, fontweight='bold',
                 color=COLOR_PASS if passed else COLOR_FAIL)
    fig.tight_layout()
    save_fig(fig, 'mop8_cpu_load.png')


# ── MOP9: パケロス ≤ 5% ──────────────────────────────────

def graph_mop9(csv_path):
    print(f'MOP9: {csv_path.name}')
    rows = read_csv(csv_path)
    if not rows:
        print('  データなし、スキップ')
        return

    node_beats = defaultdict(set)
    for r in rows:
        name = r.get('node_name', f"node_{r.get('partId', '?')}")
        node_beats[name].add(int(r['beatNo']))

    if not node_beats:
        print('  ノードデータなし、スキップ')
        return

    threshold_pct = 5
    names = sorted(node_beats.keys())
    loss_rates = []
    for name in names:
        beats = sorted(node_beats[name])
        if len(beats) < 2:
            loss_rates.append(0)
            continue
        expected = beats[-1] - beats[0] + 1
        received = len(beats)
        lost = expected - received
        rate = (lost / expected * 100) if expected > 0 else 0
        loss_rates.append(rate)

    max_rate = max(loss_rates) if loss_rates else 0
    passed = max_rate <= threshold_pct

    fig, ax = plt.subplots(figsize=FIGSIZE)
    colors = [COLOR_PASS if r <= threshold_pct else COLOR_FAIL for r in loss_rates]
    bars = ax.bar(names, loss_rates, color=colors, alpha=0.8, edgecolor='white', width=0.5)
    ax.axhline(threshold_pct, color=COLOR_THRESHOLD, linestyle='--',
               linewidth=2, label=f'閾値 {threshold_pct}%')

    for bar, rate in zip(bars, loss_rates):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.2,
                f'{rate:.1f}%', ha='center', va='bottom', fontsize=11, fontweight='bold')

    ax.set_ylabel('パケットロス率 (%)')
    ax.set_title(make_title('MOP9: パケットロス耐性 (≤ 5%)', passed),
                 fontsize=14, fontweight='bold',
                 color=COLOR_PASS if passed else COLOR_FAIL)
    ax.legend(loc='upper right')
    ax.set_ylim(bottom=0, top=max(max_rate * 1.5, threshold_pct * 1.5))
    ax.grid(axis='y', alpha=0.3)
    fig.tight_layout()
    save_fig(fig, 'mop9_packet_loss.png')


# ── メイン ────────────────────────────────────────────────

GRAPH_FUNCS = {
    1: graph_mop1,
    4: graph_mop4,
    5: graph_mop5,
    6: graph_mop6,
    7: graph_mop7,
    8: graph_mop8,
    9: graph_mop9,
}


def main():
    parser = argparse.ArgumentParser(
        description='MOP 検証結果のグラフ生成')
    parser.add_argument('--mop', nargs='*', type=int,
                        help='生成する MOP 番号（例: --mop 1 4 8）。省略で全 MOP')
    args = parser.parse_args()

    setup_font()

    targets = args.mop if args.mop else sorted(GRAPH_FUNCS.keys())
    generated = 0

    for mop_num in targets:
        if mop_num not in GRAPH_FUNCS:
            print(f'MOP{mop_num}: グラフ生成未対応、スキップ')
            continue
        csv_path = find_latest_csv(mop_num)
        if csv_path is None:
            print(f'MOP{mop_num}: CSV なし、スキップ')
            continue
        if csv_path.stat().st_size == 0:
            print(f'MOP{mop_num}: CSV 空、スキップ')
            continue

        try:
            GRAPH_FUNCS[mop_num](csv_path)
            generated += 1
        except Exception as e:
            print(f'MOP{mop_num}: エラー — {e}', file=sys.stderr)

    print(f'\n生成完了: {generated} グラフ → {GRAPHS_DIR}/')


if __name__ == '__main__':
    main()
