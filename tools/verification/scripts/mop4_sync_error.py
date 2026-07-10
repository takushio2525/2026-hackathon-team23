#!/usr/bin/env python3
"""
MOP4: 楽器間同期誤差 (≤ 20 ms) — 発火時マスター時刻ベース

楽器ファーム (MOP_TEST=4 または 5 でビルド) が発火箇所 (applyPattern.cpp) で出力する
1 行ログ M45F を集計し、同一拍の localMasterMs (発火時点の推定マスタ時刻) の
ノード間レンジ (max - min) を同期誤差とする。

旧方式 (NOTE_ON の PC 受信タイムスタンプ) は USB シリアル到着ジッタ
(実測で平均 ~20ms、目標値と同桁) が乗るうえ、ライブ計測の逐次ポーリングで
秒オーダーまで破綻していたため廃止した (詳細:
results/MOP45_latency_investigation_20260710.md §3.2/§4.2)。
本方式はデバイス側で計算した値だけを使い、USB 受信時刻を判定に使わない。

入力: serial_logger.py が保存したログファイル (行形式 "pc_ts port text")。
      行中の M45F を正規表現で拾うため、pio device monitor の生ログでも解析できる。

ファーム側ログ形式 (MOP_TEST=4/5 共通):
  M45F,<partId>,<beatNo>,<playAtMasterMs>,<deviceMs>,<offsetMs>,<localMasterMs>
    - 発火 (発音予約の時刻到来) 時に applyPattern.cpp が 1 拍 1 回だけ出力
    - localMasterMs = deviceMs + offsetMs (発火時点の推定マスタ時刻)

使い方:
  python3 scripts/mop4_sync_error.py logs/test_YYYYMMDD_HHMMSS.log
"""

import argparse
import re
import statistics
import sys
from collections import defaultdict

import common

THRESHOLD_MS = 20

# M45F,<partId>,<beatNo>,<playAtMasterMs>,<deviceMs>,<offsetMs>,<localMasterMs>
RE_M45F = re.compile(
    r'\bM45F,(\d+),(\d+),(\d+),(\d+),(-?\d+),(\d+)\b')


def parse_log(log_path):
    """ログから M45F 発火記録を読む。

    返り値: {(beatNo, playAtMasterMs): {partId: record}}
      - 同一拍はマスタ時刻 playAtMasterMs が全ノード共通なので、
        (beatNo, playAt) をキーにすると指揮者リセットで beatNo が 1 から
        再開しても別の拍として正しく区別できる。
      - 同一 (拍, ノード) の重複行は初出のみ採用し、件数を報告する。
    """
    beats = defaultdict(dict)
    duplicates = 0
    with open(log_path, errors='replace') as f:
        for line in f:
            m = RE_M45F.search(line)
            if not m:
                continue
            part = int(m.group(1))
            rec = {
                'beatNo': int(m.group(2)),
                'playAtMasterMs': int(m.group(3)),
                'deviceMs': int(m.group(4)),
                'offsetMs': int(m.group(5)),
                'localMasterMs': int(m.group(6)),
            }
            key = (rec['beatNo'], rec['playAtMasterMs'])
            if part in beats[key]:
                duplicates += 1
                continue
            beats[key][part] = rec
    return beats, duplicates


def report_results(beats, duplicates, threshold_ms, ts):
    common.print_header(f'MOP4: 楽器間同期誤差 (<= {threshold_ms} ms) — 発火時マスター時刻ベース')
    stats_lines = []

    diffs_ms = []            # 拍ごとのノード間レンジ
    node_deviations = defaultdict(list)  # partId -> [グループ平均からの偏差]

    for key in sorted(beats.keys()):
        parts = beats[key]
        if len(parts) < 2:
            continue
        times = [r['localMasterMs'] for r in parts.values()]
        diffs_ms.append(float(max(times) - min(times)))
        group_mean = statistics.mean(times)
        for pid, r in parts.items():
            node_deviations[pid].append(r['localMasterMs'] - group_mean)

    observed_nodes = set()
    for parts in beats.values():
        observed_nodes.update(parts.keys())

    if duplicates:
        stats_lines.append(f'注意: 同一 (拍, ノード) の重複記録 {duplicates} 件を初出のみ採用')

    if not diffs_ms:
        stats_lines.append('複数ノードが揃った拍が見つかりません。')
        if len(observed_nodes) < 2:
            stats_lines.append(f'検出ノード数: {len(observed_nodes)}（2 台以上必要）')
        else:
            stats_lines.append('headRestBeats の差で同一拍に複数楽器が揃わなかった可能性あり。')
            stats_lines.append('計測時間を延ばして再試行してください。')
        passed = None
    else:
        over = [d for d in diffs_ms if d > threshold_ms]
        stats_lines.append(f'検出ノード数:   {len(observed_nodes)}')
        stats_lines.append(f'集計拍数:       {len(diffs_ms)} (2 台以上が発火した拍)')
        stats_lines.append(f'平均同期誤差:   {statistics.mean(diffs_ms):.1f} ms')
        stats_lines.append(f'p50:           {common.percentile(diffs_ms, 50):.1f} ms')
        stats_lines.append(f'p95:           {common.percentile(diffs_ms, 95):.1f} ms')
        stats_lines.append(f'最大同期誤差:   {max(diffs_ms):.1f} ms')
        if len(diffs_ms) >= 2:
            stats_lines.append(f'誤差 SD:       {statistics.stdev(diffs_ms):.1f} ms')
        stats_lines.append(
            f'{threshold_ms}ms 超過:     {len(over)} / {len(diffs_ms)} 拍'
            f' ({100.0 * len(over) / len(diffs_ms):.1f}%)')
        passed = max(diffs_ms) <= threshold_ms
        stats_lines.append(f'判定: {"PASS" if passed else "FAIL"} (最大値 <= {threshold_ms} ms)')

        stats_lines.append('')
        stats_lines.append('--- ノード別偏差（負=先行, 正=遅延）---')
        for pid in sorted(node_deviations.keys()):
            devs = node_deviations[pid]
            stats_lines.append(
                f'  node_0{pid}: 平均偏差 {statistics.mean(devs):+.1f} ms'
                f' (拍数 {len(devs)})')

    for line in stats_lines:
        print(f'  {line}')

    summary_path = common.write_summary(
        4, ts, passed if passed is not None else False,
        '\n'.join(stats_lines))
    print(f'\n  Summary: {summary_path}')
    return passed


def main():
    parser = argparse.ArgumentParser(
        description='MOP4: 楽器間同期誤差 — 発火時マスター時刻 (M45F) ベース')
    parser.add_argument('log', help='serial_logger.py のログファイル')
    parser.add_argument('--threshold', type=float, default=THRESHOLD_MS,
                        help=f'PASS 閾値 ms (デフォルト {THRESHOLD_MS})')
    args = parser.parse_args()

    beats, duplicates = parse_log(args.log)
    if not beats:
        print('M45F 行が見つかりません。MOP_TEST=4 (または 5) でビルドした楽器ノードの'
              'ログか確認してください。', file=sys.stderr)
        sys.exit(1)

    # 計測レコードを CSV に保存 (グラフ生成 mop_graphs.py が localMasterMs 列を読む)
    ts = common.make_timestamp()
    csv_fields = ['beatNo', 'partId', 'playAtMasterMs',
                  'deviceMs', 'offsetMs', 'localMasterMs']
    csv_writer, csv_fh, csv_path = common.open_csv(4, csv_fields, ts)
    try:
        for key in sorted(beats.keys()):
            for pid in sorted(beats[key].keys()):
                r = beats[key][pid]
                csv_writer.writerow({
                    'beatNo': r['beatNo'],
                    'partId': pid,
                    'playAtMasterMs': r['playAtMasterMs'],
                    'deviceMs': r['deviceMs'],
                    'offsetMs': r['offsetMs'],
                    'localMasterMs': r['localMasterMs'],
                })
    finally:
        csv_fh.close()
    print(f'CSV: {csv_path}')

    report_results(beats, duplicates, args.threshold, ts)


if __name__ == '__main__':
    main()
