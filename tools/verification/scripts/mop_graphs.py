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
import matplotlib.lines as mlines
import matplotlib.patches as mpatches
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

    graph_mop4_sync_error_slide()


def graph_mop4_sync_error_slide():
    """楽器間同期誤差 (MOP4) のスライド用シンプル版 (説明文なし・データのみ)。

    各拍で最も早く発音したノードと最も遅く発音したノードの時刻差 (= 従来の
    同期誤差と同じ量) を、最終構成 (7/11) の全 173 拍の時系列 (青棒) で示す。
    体裁は確立済みスライド版と同じ色の言語: 平均値 (青破線)・中央値 (白抜き◇)・
    最大値 (赤マーク)・合格範囲の緑帯を 16:9 横長・大きめフォントで描き、
    解説は口頭で行う前提のためサブタイトル・判定ボックス・注記・出典行は載せない。
    """
    threshold_ms = 20
    path = RESULTS_DIR / 'mop4' / '20260711_154006.csv'
    if not path.exists():
        print(f'  mop4/{path.name} なし、スライド版はスキップ')
        return
    groups = defaultdict(list)
    for r in read_csv(path):
        # 指揮者リセットで beatNo が再開しても混ざらないよう playAt もキーに含める
        groups[(int(r['beatNo']), int(r['playAtMasterMs']))].append(
            float(r['localMasterMs']))
    # playAt 順 = 演奏の時系列順に「最速発火 → 最遅発火」の差を並べる
    keys = sorted((k for k, v in groups.items() if len(v) >= 2),
                  key=lambda k: k[1])
    errors = np.array([max(groups[k]) - min(groups[k]) for k in keys])

    mean_v = float(np.mean(errors))
    p50_v = float(np.percentile(errors, 50))
    max_v = float(np.max(errors))
    max_i = int(np.argmax(errors))

    color_band = '#16A34A'
    color_mean = COLOR_PASS   # 青 (緑帯 alpha 0.12 の上でも沈まない濃さ)
    color_max = COLOR_FAIL    # 赤
    color_p50 = '#111827'     # 中央値の縁と数値 (白抜き◇が青棒に埋もれない濃さ)

    fig, ax = plt.subplots(figsize=(12.8, 7.2))
    x = np.arange(len(errors))
    n = len(errors)

    ax.axhspan(0, threshold_ms, facecolor=color_band, alpha=0.12, zorder=0)
    ax.axhline(threshold_ms, color=color_band, linestyle='--', linewidth=2.5, zorder=1)

    ax.bar(x, errors, width=1.0, color=color_mean, alpha=0.9, zorder=2)

    # 平均は水平破線。数値は線の左端寄り、中央値の◇ (右端外) と水平に分離する
    ax.axhline(mean_v, color=color_mean, linestyle='--', linewidth=2.5, zorder=3)
    ax.text(2, mean_v + 1.2, f'{mean_v:.1f}', ha='left', va='bottom',
            fontsize=17, fontweight='bold', color=color_mean)

    # 最大値は該当拍に赤マーク
    ax.scatter([max_i], [max_v], marker='_', s=800, linewidths=3,
               color=color_max, zorder=4)
    ax.text(max_i, max_v + 1.8, f'{max_v:.0f}', ha='center', va='bottom',
            fontsize=14, color=color_max)

    # 中央値 7 ms は平均 10.8 ms と近く水平線 2 本では読み分けにくいため、
    # 白抜き◇を軸の右外に置き数値を添える (clip_on=False で軸外に描く)
    ax.scatter([n + 3], [p50_v], marker='D', s=170, facecolor='white',
               edgecolor=color_p50, linewidths=2, zorder=5, clip_on=False)
    ax.text(n + 7, p50_v, f'{p50_v:.0f}', ha='left', va='center',
            fontsize=14, color=color_p50, clip_on=False)

    legend_handles = [
        mpatches.Patch(color=color_mean, alpha=0.9, label='各拍の時刻差'),
        mlines.Line2D([], [], linestyle='--', linewidth=2.5, color=color_mean,
                      label='平均値'),
        mlines.Line2D([], [], marker='D', markersize=11, linestyle='None',
                      markerfacecolor='white', markeredgecolor=color_p50,
                      markeredgewidth=2, label='中央値'),
        mlines.Line2D([], [], marker='_', markersize=22, markeredgewidth=3,
                      linestyle='None', color=color_max, label='最大値'),
        mpatches.Patch(facecolor=color_band, alpha=0.25, edgecolor=color_band,
                       linestyle='--', label=f'合格範囲 (≤ {threshold_ms} ms)'),
    ]
    # 凡例は横 1 行で上部に置き、最大値ラベルとの重なりを避ける
    ax.legend(handles=legend_handles, loc='upper center', ncol=5, fontsize=14,
              columnspacing=1.0, borderpad=0.5, framealpha=0.95)

    ax.set_xlim(-1, n)
    ax.tick_params(axis='both', labelsize=14)
    ax.set_xlabel(f'拍（演奏順・全 {n} 拍）', fontsize=17)
    ax.set_ylabel('最速ノードと最遅ノードの発音時刻差 (ms)', fontsize=17)
    ax.set_ylim(0, 80)
    ax.grid(axis='y', alpha=0.3, zorder=0)

    ax.set_title('楽器間同期誤差（各拍の最速 vs 最遅）', fontsize=21,
                 fontweight='bold', pad=14)

    fig.tight_layout()
    save_fig(fig, 'mop4_sync_error_slide.png')


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

    if is_late_format:
        graph_mop5_fire_delay_by_node(rows, csv_path)


def graph_mop5_fire_delay_by_node(rows, csv_path):
    """発声タイミングの遅延をノード別に示す発表用グラフ (予備知識なしで読める版)。

    棒 = 発火 lateMs の p95 (MOP5 の判定統計量)、◆ = 中央値、― = 最大値。
    合格範囲 (0〜30 ms) を緑帯で明示し、判定・計測条件・出典を図中に書き込む。
    """
    threshold_ms = 30
    fire = [r for r in rows if r.get('type', '') == 'F']
    if not fire:
        print('  発火 (F) レコードなし、ノード別グラフはスキップ')
        return

    by_node = defaultdict(list)
    for r in fire:
        by_node[int(r['partId'])].append(float(r['lateMs']))

    part_ids = sorted(by_node.keys())
    p50s = [float(np.percentile(by_node[p], 50)) for p in part_ids]
    p95s = [float(np.percentile(by_node[p], 95)) for p in part_ids]
    maxs = [float(np.max(by_node[p])) for p in part_ids]

    all_late = np.array([float(r['lateMs']) for r in fire])
    total_p50 = float(np.percentile(all_late, 50))
    total_p95 = float(np.percentile(all_late, 95))
    total_max = float(np.max(all_late))
    passed = total_p95 <= threshold_ms

    color_band = '#16A34A'
    color_max = '#374151'
    bar_colors = [COLOR_PASS if v <= threshold_ms else COLOR_FAIL for v in p95s]

    fig, ax = plt.subplots(figsize=(11.5, 7))
    x = np.arange(len(part_ids))

    # 合格範囲の緑帯 + 基準線 (ラベルは凡例で示す)
    ax.axhspan(0, threshold_ms, facecolor=color_band, alpha=0.12, zorder=0)
    ax.axhline(threshold_ms, color=color_band, linestyle='--', linewidth=2, zorder=1)

    # 棒 = p95 (判定に使う値)
    bars = ax.bar(x, p95s, width=0.55, color=bar_colors, alpha=0.85,
                  edgecolor='white', zorder=2)
    for xi, (bar, v) in enumerate(zip(bars, p95s)):
        ax.text(xi, v + 1.2, f'p95: {v:.1f}', ha='center', va='bottom',
                fontsize=11, fontweight='bold', color=bar_colors[xi])

    # ― = 最大値 (単発の最悪値)
    ax.scatter(x, maxs, marker='_', s=600, linewidths=2.5, color=color_max, zorder=4)
    for xi, v in enumerate(maxs):
        ax.text(xi, v + 1.2, f'最大 {v:.0f}', ha='center', va='bottom',
                fontsize=9.5, color=color_max)

    # ◆ = 中央値 (ふだんの遅れ)
    ax.scatter(x, p50s, marker='D', s=70, facecolor='white',
               edgecolor='#111827', linewidths=1.5, zorder=5)
    for xi, v in enumerate(p50s):
        ax.text(xi + 0.13, v, f'{v:.0f}', ha='left', va='center',
                fontsize=9.5, color='#111827')

    # 凡例 (読み方をそのまま文で書く)
    legend_handles = [
        mpatches.Patch(color=COLOR_FAIL, alpha=0.85,
                       label='発音の遅れ p95 ＝ 判定に使う値（20 回中 19 回はこれ以内）'),
        mlines.Line2D([], [], marker='D', markersize=9, linestyle='None',
                      markerfacecolor='white', markeredgecolor='#111827',
                      label='中央値（ふだんの遅れ）'),
        mlines.Line2D([], [], marker='_', markersize=18, markeredgewidth=2.5,
                      linestyle='None', color=color_max, label='最大値（単発の最悪値）'),
        mpatches.Patch(facecolor=color_band, alpha=0.25, edgecolor=color_band,
                       linestyle='--',
                       label=f'合格範囲（基準: 遅れ {threshold_ms} ms 以内）'),
    ]
    # 凡例が「最大」ラベル (最大 67 ms + 文字高) と重ならないよう y 上限に余白を取る
    ax.legend(handles=legend_handles, loc='upper left', fontsize=10,
              labelspacing=0.4, borderpad=0.5, framealpha=0.95)

    # 判定サマリボックス
    verdict = 'PASS' if passed else 'FAIL（基準超過）'
    stats_text = (
        f'判定: {verdict}\n'
        f'基準: 遅れの p95 ≤ {threshold_ms} ms\n'
        f'全ノード集計 (n={len(all_late)} 発音):\n'
        f'  中央値 {total_p50:.0f} ms / p95 {total_p95:.1f} ms / 最大 {total_max:.0f} ms'
    )
    ax.text(0.99, 0.97, stats_text, transform=ax.transAxes,
            va='top', ha='right', fontsize=11,
            bbox=dict(boxstyle='round,pad=0.6', facecolor='#FEF2F2' if not passed
                      else '#EFF6FF', edgecolor=COLOR_FAIL if not passed
                      else COLOR_PASS, alpha=0.95))

    ax.set_xticks(x)
    ax.set_xticklabels([f'楽器{i + 1}\n(node_{p:02d})' for i, p in enumerate(part_ids)],
                       fontsize=11)
    ax.set_xlabel('楽器ノード（指揮者の拍指示を受信して発音する 5 台）', fontsize=12)
    ax.set_ylabel('発音予定時刻からの遅れ (ms)', fontsize=12)
    ax.set_ylim(0, 96)
    ax.grid(axis='y', alpha=0.3, zorder=0)

    fig.suptitle('MOP5 検証: 発声タイミングの遅延 — 発音は予定時刻からどれだけ遅れたか'
                 f'　[判定 {verdict}]',
                 fontsize=15, fontweight='bold', y=0.97,
                 color=COLOR_PASS if passed else COLOR_FAIL)
    ax.set_title('ふだんの遅れ（中央値 5〜8 ms）は基準内だが、まれな単発の遅れ'
                 f'（最大 {total_max:.0f} ms）が p95 を押し上げ、基準 {threshold_ms} ms を超過した',
                 fontsize=11.5, color='#374151', pad=12)

    footnote = (
        '※ 計測対象は楽器ノード 5 台（各 173 拍）。指揮者は発音予定時刻を送る側＝比較の基準であり、'
        'PC（Processing）の音声出力遅延は本計測の対象外。\n'
        '※ 超過の主因は楽器マイコン WiFi モジュール内部の周期ストール（単発・約 30〜60 ms）。'
        '最終レポートでは指標を「発音予約の成立」（受信遅刻率 3.1%）へ再定義して受け入れ。\n'
        f'データ出典: results/mop5/{csv_path.name}'
        '（2026-07-11 最終構成: lookahead 220 ms・min フィルタ時計同期）'
        '　詳細: results/MOP_REPORT_20260711.md'
    )
    fig.text(0.01, 0.01, footnote, fontsize=8.5, color='#6B7280', va='bottom')

    fig.tight_layout(rect=(0, 0.09, 1, 0.95))
    save_fig(fig, 'mop5_fire_delay_by_node.png')

    graph_mop5_fire_delay_by_node_slide(rows)


def graph_mop5_fire_delay_by_node_slide(rows):
    """ジッタ吸収の効果 (MOP5) のスライド用シンプル版 (説明文なし・データのみ)。

    「吸収なし = 受信した瞬間に鳴らした場合」と「吸収あり = 予約時刻まで待って
    発音した実測」の 2 グループで、発音予定時刻とのズレを比較する。
    - 吸収なし: R 行の |localMasterMs − playAtMasterMs|。SoftAP のバースト配送
      (204.8ms 周期) で受信は予定より平均 ~100ms 手前に届くため、そのまま鳴らすと
      ズレは巨大 (MOP_REPORT_20260711.md の marginMs 分析と符号反転で同値)
    - 吸収あり: F 行の lateMs (発火は予定より遅れる側のみなので絶対値と同値)
    符号 (早い/遅い) は絶対値に統一し、y 軸ラベルで明示する。
    体裁は確立済みスライド版と同一: 平均値 (青棒)・中央値 (白抜き◇)・
    最大値 (赤マーク)・合格範囲の緑帯を 16:9 横長・大きめフォントで描き、
    サブタイトル・判定ボックス・注記・出典行は載せない。
    """
    threshold_ms = 30
    recv = [r for r in rows if r.get('type', '') == 'R']
    fire = [r for r in rows if r.get('type', '') == 'F']
    if not recv or not fire:
        return

    raw = np.abs([float(r['localMasterMs']) - float(r['playAtMasterMs'])
                  for r in recv])
    absorbed = np.array([float(r['lateMs']) for r in fire])
    groups = [
        ('ジッタ吸収なし\n（受信した瞬間に鳴らした場合）', raw),
        ('ジッタ吸収あり\n（予約時刻まで待って発音・実測）', absorbed),
    ]

    labels = [label for label, _ in groups]
    means = [float(np.mean(v)) for _, v in groups]
    p50s = [float(np.percentile(v, 50)) for _, v in groups]
    maxs = [float(np.max(v)) for _, v in groups]

    color_band = '#16A34A'
    color_mean = COLOR_PASS   # 青 (緑帯 alpha 0.12 の上でも沈まない濃さ)
    color_max = COLOR_FAIL    # 赤
    color_p50 = '#111827'     # 中央値の縁と数値 (白抜き◇が青棒に埋もれない濃さ)

    fig, ax = plt.subplots(figsize=(12.8, 7.2))
    x = np.arange(len(groups))

    ax.axhspan(0, threshold_ms, facecolor=color_band, alpha=0.12, zorder=0)
    ax.axhline(threshold_ms, color=color_band, linestyle='--', linewidth=2.5, zorder=1)

    ax.bar(x, means, width=0.45, color=color_mean, alpha=0.9,
           edgecolor='white', zorder=2)
    for xi, v in enumerate(means):
        ax.text(xi, v + 3.5, f'{v:.1f}', ha='center', va='bottom',
                fontsize=17, fontweight='bold', color=color_mean)

    ax.scatter(x, maxs, marker='_', s=800, linewidths=3, color=color_max, zorder=4)
    for xi, v in enumerate(maxs):
        ax.text(xi, v + 3.5, f'{v:.0f}', ha='center', va='bottom',
                fontsize=14, color=color_max)

    # 吸収なしの中央値 99 ms は青棒 (平均 101.2 ms) の頂上付近に来るため、
    # 白抜き◇＋濃い縁で埋もれを防ぎ、数値は棒の右外側 (半幅 0.225 の外) に
    # 置いて平均ラベルと分離する
    ax.scatter(x, p50s, marker='D', s=170, facecolor='white',
               edgecolor=color_p50, linewidths=2, zorder=5)
    for xi, v in enumerate(p50s):
        ax.text(xi + 0.27, v, f'{v:.0f}', ha='left', va='center',
                fontsize=14, color=color_p50)

    legend_handles = [
        mpatches.Patch(color=color_mean, alpha=0.9, label='平均値'),
        mlines.Line2D([], [], marker='D', markersize=11, linestyle='None',
                      markerfacecolor='white', markeredgecolor=color_p50,
                      markeredgewidth=2, label='中央値'),
        mlines.Line2D([], [], marker='_', markersize=22, markeredgewidth=3,
                      linestyle='None', color=color_max, label='最大値'),
        mpatches.Patch(facecolor=color_band, alpha=0.25, edgecolor=color_band,
                       linestyle='--', label=f'合格範囲 (≤ {threshold_ms} ms)'),
    ]
    # 凡例は横 1 行で上部に置き、最大値ラベルとの重なりを避ける
    ax.legend(handles=legend_handles, loc='upper center', ncol=4, fontsize=15,
              columnspacing=1.2, borderpad=0.5, framealpha=0.95)

    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=16)
    ax.tick_params(axis='y', labelsize=14)
    ax.set_ylabel('発音予定時刻とのズレ（絶対値, ms）', fontsize=17)
    ax.set_ylim(0, 260)
    ax.grid(axis='y', alpha=0.3, zorder=0)

    ax.set_title('ジッタ吸収の効果（発音タイミングのズレ）', fontsize=21,
                 fontweight='bold', pad=14)

    fig.tight_layout()
    save_fig(fig, 'mop5_fire_delay_by_node_slide.png')


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
