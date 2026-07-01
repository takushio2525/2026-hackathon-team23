#!/usr/bin/env python3
"""
MOP5: 指揮→楽器 通信遅延
指揮者の BEAT 送信時刻と楽器側の受信時刻 (ahead 値) から通信遅延を計測する。

ahead = playAtMs - localMasterMs (受信時点)。
通信遅延 ≈ beatLookaheadMs - ahead (ahead が小さいほど遅延が大きい)。

MOP_TEST=5:
  指揮者: M5C,<beatNo>,<sendMs>
  楽器:   M5I,<partId>,<beatNo>,<recvMs>,<ahead>

SERIAL_DEBUG=1:
  [N1 EVT BEAT] no=<beatNo> t=<ms> playAt=<ms> bpm=<bpm>
  [NX EVT BEAT] no=<beatNo> playAt=<ms> ahead=<ahead> seq=<seq>
"""

import argparse
import re
import signal
import statistics
import sys
import time
from collections import defaultdict

import common

RE_M5C = re.compile(r'^M5C,(\d+),(\d+)')
RE_M5I = re.compile(r'^M5I,(\d+),(\d+),(\d+),(-?\d+)')
RE_BEAT_N1 = re.compile(
    r'\[N1 EVT BEAT\] no=(\d+) t=(\d+) playAt=(\d+)')
RE_BEAT_NX = re.compile(
    r'\[N(\d) EVT BEAT\] no=(\d+) playAt=(\d+) ahead=(-?\d+)')

BEAT_LOOKAHEAD_MS = 45  # ProjectConfig.h の beatLookaheadMs


def main():
    parser = argparse.ArgumentParser(description='MOP5: 指揮→楽器 通信遅延')
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

    print(f"通信遅延を {args.duration:.0f} 秒間計測します。")
    print("指揮棒を振って演奏を開始してください。Ctrl+C でも停止できます。")
    print()

    # ahead 値を収集 (楽器側基準: ahead が大きい = 余裕あり = 遅延少ない)
    ahead_by_node = defaultdict(list)  # nodeId -> [ahead_ms]
    ts = common.make_timestamp()
    csv_fields = ['source', 'beatNo', 'partId', 'ahead_ms', 'est_delay_ms']
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

                # MOP_TEST=5 楽器側
                m = RE_M5I.match(text)
                if m:
                    part_id = int(m.group(1))
                    beatNo = int(m.group(2))
                    ahead = int(m.group(4))
                    delay = BEAT_LOOKAHEAD_MS - ahead
                    ahead_by_node[part_id].append(ahead)
                    csv_writer.writerow({
                        'source': 'instrument',
                        'beatNo': beatNo,
                        'partId': f'0x{part_id:02X}',
                        'ahead_ms': ahead,
                        'est_delay_ms': delay,
                    })
                    csv_fh.flush()
                    continue

                # SERIAL_DEBUG 楽器側
                m = RE_BEAT_NX.search(text)
                if m:
                    node = int(m.group(1))
                    if node == 1:
                        continue
                    beatNo = int(m.group(2))
                    ahead = int(m.group(4))
                    delay = BEAT_LOOKAHEAD_MS - ahead
                    ahead_by_node[node].append(ahead)
                    csv_writer.writerow({
                        'source': 'instrument',
                        'beatNo': beatNo,
                        'partId': f'0x{node:02X}',
                        'ahead_ms': ahead,
                        'est_delay_ms': delay,
                    })
                    csv_fh.flush()
    finally:
        csv_fh.close()
        for _, ser in serials:
            ser.close()

    # ── 結果 ──
    common.print_header('MOP5: 指揮→楽器 通信遅延 (<= 30 ms)')
    stats_lines = []

    if not ahead_by_node:
        stats_lines.append('楽器の BEAT 受信データなし。')
        passed = None
    else:
        all_delays = []
        for node_id in sorted(ahead_by_node):
            aheads = ahead_by_node[node_id]
            delays = [BEAT_LOOKAHEAD_MS - a for a in aheads]
            all_delays.extend(delays)
            stats_lines.append(
                f'node_0{node_id}: ahead 平均={statistics.mean(aheads):.1f}ms '
                f'推定遅延 平均={statistics.mean(delays):.1f}ms '
                f'最大={max(delays):.1f}ms (n={len(delays)})')

        max_delay = max(all_delays)
        stats_lines.append(f'全体最大推定遅延: {max_delay:.1f} ms')
        passed = max_delay <= 30
        stats_lines.append(f'判定: {"PASS" if passed else "FAIL"}')

    for line in stats_lines:
        print(f'  {line}')

    summary_path = common.write_summary(5, ts, passed if passed is not None else False,
                                        '\n'.join(stats_lines))
    print(f'\n  CSV:     {csv_path}')
    print(f'  Summary: {summary_path}')


if __name__ == '__main__':
    main()
