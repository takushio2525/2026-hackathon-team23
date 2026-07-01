#!/usr/bin/env python3
"""
MOP4: 楽器間同期誤差
各楽器ノードの発音タイミング（マスタクロック同期済み localMasterMs）を比較し、
同一拍に対する楽器間の発音時刻差を計測する。

計測原理:
  各楽器は localMasterMs >= playAtMasterMs で発音する。playAtMasterMs は全ノード
  共通（指揮者が決める）なので、同一拍の localMasterMs の楽器間最大差が
  そのまま発音タイミング差（= 同期誤差）になる。

MOP_TEST=4: M4,<partId>,<beatNo>,<localMasterMs>,<playAtMasterMs>
SERIAL_DEBUG=1: [NX EVT BEAT] no=<beatNo> playAt=<ms> ahead=<ms>
  ※ ahead = playAtMasterMs - localMasterMs → localMasterMs = playAt - ahead
"""

import argparse
import re
import signal
import statistics
import sys
import time
from collections import defaultdict

import common

RE_MOP4 = re.compile(r'^M4,(\d+),(\d+),(\d+),(\d+)')
RE_BEAT_NX = re.compile(
    r'\[N(\d) EVT BEAT\] no=(\d+) playAt=(\d+) ahead=(-?\d+)')


def parse_sync(text):
    """同期行をパースして (partId, beatNo, localMasterMs, playAtMasterMs) を返す。"""
    m = RE_MOP4.match(text)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
    m = RE_BEAT_NX.search(text)
    if m:
        node = int(m.group(1))
        if node == 1:
            return None
        beatNo = int(m.group(2))
        playAt = int(m.group(3))
        ahead = int(m.group(4))
        localMasterMs = playAt - ahead
        return node, beatNo, localMasterMs, playAt
    return None


def percentile(data, p):
    """ソート済みリストから第 p パーセンタイルを線形補間で返す。"""
    if not data:
        return 0.0
    s = sorted(data)
    k = (len(s) - 1) * p / 100.0
    f = int(k)
    c = f + 1 if f + 1 < len(s) else f
    return s[f] + (s[c] - s[f]) * (k - f)


def main():
    parser = argparse.ArgumentParser(description='MOP4: 楽器間同期誤差')
    parser.add_argument('--duration', type=float, default=60)
    parser.add_argument('--ports', nargs='*')
    parser.add_argument('--baud', type=int, default=115200)
    args = parser.parse_args()

    ports = args.ports or common.find_usb_serial_ports()
    if not ports:
        print("USB シリアルポートが見つかりません。", file=sys.stderr)
        sys.exit(1)

    node_mapper = common.NodeMapper()
    serials = []
    for p in ports:
        ser = common.open_serial(p, args.baud)
        if ser:
            serials.append((p, ser))

    print(f"楽器間同期誤差を {args.duration:.0f} 秒間計測します。")
    print("指揮棒を振って演奏を開始してください。Ctrl+C でも停止できます。")
    print()

    # beatNo -> {partId -> localMasterMs}
    beat_times = defaultdict(dict)
    ts = common.make_timestamp()
    csv_fields = ['beatNo', 'partId', 'localMasterMs', 'playAtMasterMs']
    csv_writer, csv_fh, csv_path = common.open_csv(4, csv_fields, ts)

    stop = False
    def on_sigint(s, f):
        nonlocal stop
        stop = True
    signal.signal(signal.SIGINT, on_sigint)

    start = time.time()
    try:
        while not stop and (time.time() - start) < args.duration:
            for p, ser in serials:
                text = common.read_line(ser)
                if not text:
                    continue
                node_mapper.try_detect(p, text)
                result = parse_sync(text)
                if result is None:
                    continue
                part_id, beatNo, localMasterMs, playAtMasterMs = result
                beat_times[beatNo][part_id] = localMasterMs
                csv_writer.writerow({
                    'beatNo': beatNo,
                    'partId': f'0x{part_id:02X}',
                    'localMasterMs': localMasterMs,
                    'playAtMasterMs': playAtMasterMs,
                })
                csv_fh.flush()
    finally:
        csv_fh.close()
        for _, ser in serials:
            ser.close()

    # ── 結果 ──
    common.print_header('MOP4: 楽器間同期誤差 (<= 20 ms)')
    stats_lines = []

    # 2台以上の楽器が同一拍で発音した beatNo を対象に最大差を計算
    diffs_ms = []
    node_deviations = defaultdict(list)

    for beatNo, parts in sorted(beat_times.items()):
        if len(parts) < 2:
            continue
        times = list(parts.values())
        diff = max(times) - min(times)
        diffs_ms.append(diff)

        group_mean = statistics.mean(times)
        for pid, t in parts.items():
            node_deviations[pid].append(t - group_mean)

    observed_nodes = set()
    for parts in beat_times.values():
        observed_nodes.update(parts.keys())

    if not diffs_ms:
        stats_lines.append('複数ノード同時発音が見つかりません。')
        if len(observed_nodes) < 2:
            stats_lines.append(f'検出ノード数: {len(observed_nodes)}（2 台以上必要）')
        else:
            stats_lines.append('headRestBeats の差で同一拍に複数楽器が揃わなかった可能性あり。')
            stats_lines.append('計測時間を延ばして再試行してください。')
        passed = None
    else:
        stats_lines.append(f'検出ノード数:   {len(observed_nodes)}')
        stats_lines.append(f'同時発音拍数:   {len(diffs_ms)}')
        stats_lines.append(f'平均同期誤差:   {statistics.mean(diffs_ms):.1f} ms')
        stats_lines.append(f'最大同期誤差:   {max(diffs_ms):.1f} ms')
        stats_lines.append(f'p50:           {percentile(diffs_ms, 50):.1f} ms')
        stats_lines.append(f'p95:           {percentile(diffs_ms, 95):.1f} ms')
        stats_lines.append(f'p99:           {percentile(diffs_ms, 99):.1f} ms')
        if len(diffs_ms) >= 2:
            stats_lines.append(f'誤差 SD:       {statistics.stdev(diffs_ms):.1f} ms')
        passed = max(diffs_ms) <= 20
        stats_lines.append(f'判定: {"PASS" if passed else "FAIL"}')

        stats_lines.append('')
        stats_lines.append('--- ノード別偏差（正=先行, 負=遅延）---')
        for pid in sorted(node_deviations.keys()):
            devs = node_deviations[pid]
            mean_dev = statistics.mean(devs)
            stats_lines.append(
                f'  node_0{pid}: 平均偏差 {mean_dev:+.1f} ms'
                f' (拍数 {len(devs)})')

    for line in stats_lines:
        print(f'  {line}')

    summary_path = common.write_summary(4, ts, passed if passed is not None else False,
                                        '\n'.join(stats_lines))
    print(f'\n  CSV:     {csv_path}')
    print(f'  Summary: {summary_path}')


if __name__ == '__main__':
    main()
