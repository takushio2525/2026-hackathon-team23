#!/usr/bin/env python3
"""
MOP5: スレーブ間の発音同期 (≤ 30 ms)
NOTE_ON の PC 受信タイムスタンプで、スレーブ間の発音タイミング差を計測する。

MOP4 が「拍ごとの全ノード最大差」を見るのに対し、MOP5 は
「各ノードペア間の遅延分布」に焦点を当てる。

計測原理:
  各楽器は拍ごとに NOTE_ON をシリアル出力する。PC 側で各ポートの受信
  タイムスタンプ (time.time()) を記録し、同一拍に属する NOTE_ON の
  全ノードペア間の時間差を計測して分布を示す。

SERIAL_DEBUG=1:
  [NX EVT BEAT] no=<beatNo> playAt=<ms> ahead=<ms>
  [NX NOTE_ON ] part=0x0X instr=N note=N vel=N dur=N seq=N t=N
"""

import argparse
import itertools
import re
import signal
import statistics
import sys
import time
from collections import defaultdict

import common

THRESHOLD_MS = 30

RE_BEAT_NX = re.compile(
    r'\[N(\d) EVT BEAT\] no=(\d+)')
RE_NOTE_ON = re.compile(
    r'\[N(\d) NOTE_ON\s*\] part=0x(\w+) instr=(\d+) note=(\d+) '
    r'vel=(\d+) dur=(\d+) seq=(\d+) t=(\d+)')


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
    parser = argparse.ArgumentParser(
        description='MOP5: スレーブ間発音同期 — NOTE_ON ベース')
    parser.add_argument('--duration', type=float, default=60,
                        help='計測時間（秒）')
    parser.add_argument('--ports', nargs='*',
                        help='シリアルポート（省略で自動検出）')
    parser.add_argument('--baud', type=int, default=115200)
    parser.add_argument('--log', type=str, default=None,
                        help='既存ログファイルから解析（リアルタイム計測を省略）')
    args = parser.parse_args()

    if args.log:
        analyze_log(args.log)
        return

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

    print(f"スレーブ間発音同期を {args.duration:.0f} 秒間計測します（NOTE_ON ベース）。")
    print("指揮棒を振って演奏を開始してください。Ctrl+C でも停止できます。")
    print()

    last_beat = {}  # port -> beatNo
    # beatNo -> {partId -> pc_timestamp}
    beat_notes = defaultdict(dict)

    ts = common.make_timestamp()
    csv_fields = ['beatNo', 'partId', 'noteNumber', 'device_t', 'pc_timestamp']
    csv_writer, csv_fh, csv_path = common.open_csv(5, csv_fields, ts)

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
                pc_ts = time.time()

                m = RE_BEAT_NX.search(text)
                if m:
                    node = int(m.group(1))
                    if node >= 2:
                        last_beat[p] = int(m.group(2))
                    continue

                m = RE_NOTE_ON.search(text)
                if m:
                    node = int(m.group(1))
                    if node == 1:
                        continue
                    part_id = int(m.group(2), 16)
                    note_num = int(m.group(4))
                    device_t = int(m.group(8))
                    beat_no = last_beat.get(p)
                    if beat_no is None:
                        continue
                    if part_id not in beat_notes[beat_no]:
                        beat_notes[beat_no][part_id] = pc_ts
                        csv_writer.writerow({
                            'beatNo': beat_no,
                            'partId': f'0x{part_id:02X}',
                            'noteNumber': note_num,
                            'device_t': device_t,
                            'pc_timestamp': f'{pc_ts:.6f}',
                        })
                        csv_fh.flush()
    finally:
        csv_fh.close()
        for _, ser in serials:
            ser.close()

    report_results(beat_notes, ts)


def analyze_log(log_path):
    """既存ログファイルから MOP5 を解析する。"""
    last_beat = {}  # node_id -> beatNo
    beat_notes = defaultdict(dict)

    with open(log_path) as f:
        for line in f:
            line = line.rstrip()
            parts = line.split('\t', 1)
            if len(parts) == 2:
                try:
                    pc_ts = float(parts[0])
                except ValueError:
                    pc_ts = None
                text = parts[1]
            else:
                pc_ts = None
                text = line

            m = RE_BEAT_NX.search(text)
            if m:
                node = int(m.group(1))
                if node >= 2:
                    last_beat[node] = int(m.group(2))
                continue

            m = RE_NOTE_ON.search(text)
            if m:
                node = int(m.group(1))
                if node == 1 or pc_ts is None:
                    continue
                part_id = int(m.group(2), 16)
                beat_no = last_beat.get(node)
                if beat_no is None:
                    continue
                if part_id not in beat_notes[beat_no]:
                    beat_notes[beat_no][part_id] = pc_ts

    ts = common.make_timestamp()
    report_results(beat_notes, ts)


def report_results(beat_notes, ts):
    """計測結果を集計・表示する。ノードペアごとの遅延分布を分析する。"""
    common.print_header(f'MOP5: スレーブ間発音同期 (<= {THRESHOLD_MS} ms)')
    stats_lines = []

    # ペアごとの遅延を収集
    pair_diffs = defaultdict(list)  # (min_pid, max_pid) -> [diff_ms]
    all_max_diffs = []  # 拍ごとの最大ペア差

    for beat_no, parts in sorted(beat_notes.items()):
        if len(parts) < 2:
            continue
        pids = sorted(parts.keys())
        max_diff = 0.0
        for a, b in itertools.combinations(pids, 2):
            diff_ms = abs(parts[a] - parts[b]) * 1000.0
            pair_diffs[(a, b)].append(diff_ms)
            max_diff = max(max_diff, diff_ms)
        all_max_diffs.append(max_diff)

    observed_nodes = set()
    for parts in beat_notes.values():
        observed_nodes.update(parts.keys())

    if not all_max_diffs:
        stats_lines.append('複数ノード同時発音が見つかりません。')
        passed = None
    else:
        stats_lines.append(f'検出ノード数:     {len(observed_nodes)}')
        stats_lines.append(f'同時発音拍数:     {len(all_max_diffs)}')
        stats_lines.append(f'ノードペア数:     {len(pair_diffs)}')
        stats_lines.append('')

        stats_lines.append('--- 全ペア合算 ---')
        all_diffs = []
        for diffs in pair_diffs.values():
            all_diffs.extend(diffs)
        stats_lines.append(f'  平均:   {statistics.mean(all_diffs):.1f} ms')
        stats_lines.append(f'  p50:    {percentile(all_diffs, 50):.1f} ms')
        stats_lines.append(f'  p95:    {percentile(all_diffs, 95):.1f} ms')
        stats_lines.append(f'  最大:   {max(all_diffs):.1f} ms')
        stats_lines.append('')

        stats_lines.append('--- ノードペア別 ---')
        max_pair_delay = 0.0
        for (a, b), diffs in sorted(pair_diffs.items()):
            mean_d = statistics.mean(diffs)
            max_d = max(diffs)
            p95_d = percentile(diffs, 95)
            max_pair_delay = max(max_pair_delay, max_d)
            stats_lines.append(
                f'  node_0{a} - node_0{b}: '
                f'平均={mean_d:.1f}ms p95={p95_d:.1f}ms '
                f'最大={max_d:.1f}ms (n={len(diffs)})')

        passed = max_pair_delay <= THRESHOLD_MS
        stats_lines.append('')
        stats_lines.append(
            f'判定: {"PASS" if passed else "FAIL"} '
            f'(最大ペア遅延 {max_pair_delay:.1f}ms, 閾値 {THRESHOLD_MS} ms)')

    for line in stats_lines:
        print(f'  {line}')

    summary_path = common.write_summary(
        5, ts, passed if passed is not None else False,
        '\n'.join(stats_lines))
    print(f'\n  Summary: {summary_path}')


if __name__ == '__main__':
    main()
