#!/usr/bin/env python3
"""
MOP9: パケットロス耐性
楽器ノードの BEAT 受信ログから beatNo の欠番を検出し、ロス率を計測する。

MOP_TEST=9: M9,<partId>,<beatNo>,<seq>,<localMs>
SERIAL_DEBUG=1: [NX EVT BEAT] no=<beatNo> playAt=<ms> ahead=<ahead> seq=<seq>
"""

import argparse
import re
import signal
import statistics
import sys
import time
from collections import defaultdict

import common

RE_MOP9 = re.compile(r'^M9,(\d+),(\d+),(\d+),(\d+)')
RE_BEAT_NX = re.compile(
    r'\[N(\d) EVT BEAT\] no=(\d+) playAt=(\d+) ahead=(-?\d+) seq=(\d+)')


def main():
    parser = argparse.ArgumentParser(description='MOP9: パケットロス耐性')
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

    print(f"パケットロスを {args.duration:.0f} 秒間計測します。")
    print("指揮棒を振って演奏を開始してください。Ctrl+C でも停止できます。")
    print()

    beats_by_node = defaultdict(list)  # nodeId -> [beatNo]
    ts = common.make_timestamp()
    csv_fields = ['partId', 'beatNo', 'seq', 'localMs']
    csv_writer, csv_fh, csv_path = common.open_csv(9, csv_fields, ts)

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

                # MOP_TEST=9
                m = RE_MOP9.match(text)
                if m:
                    part_id = int(m.group(1))
                    beatNo = int(m.group(2))
                    seq = int(m.group(3))
                    localMs = int(m.group(4))
                    beats_by_node[part_id].append(beatNo)
                    csv_writer.writerow({
                        'partId': f'0x{part_id:02X}',
                        'beatNo': beatNo, 'seq': seq, 'localMs': localMs,
                    })
                    csv_fh.flush()
                    continue

                # SERIAL_DEBUG フォールバック
                m = RE_BEAT_NX.search(text)
                if m:
                    node = int(m.group(1))
                    if node == 1:
                        continue
                    beatNo = int(m.group(2))
                    seq = int(m.group(5))
                    beats_by_node[node].append(beatNo)
                    csv_writer.writerow({
                        'partId': f'0x{node:02X}',
                        'beatNo': beatNo, 'seq': seq, 'localMs': '',
                    })
                    csv_fh.flush()
    finally:
        csv_fh.close()
        for _, ser in serials:
            ser.close()

    # ── 結果 ──
    common.print_header('MOP9: パケットロス耐性 (ロス <= 5%)')
    stats_lines = []
    overall_pass = True

    for node_id in sorted(beats_by_node):
        seq = beats_by_node[node_id]
        if len(seq) < 2:
            stats_lines.append(f'node_0{node_id}: データ不足')
            continue

        total = seq[-1] - seq[0] + 1
        received = len(seq)
        missed = total - received
        pct = missed / total * 100 if total > 0 else 0

        gaps = sorted(set(range(seq[0], seq[-1] + 1)) - set(seq))
        gap_str = ''
        if gaps:
            show = gaps[:10]
            gap_str = f'  欠番: {show}'
            if len(gaps) > 10:
                gap_str += f'... 他{len(gaps) - 10}件'

        stats_lines.append(
            f'node_0{node_id}: 期待={total} 受信={received} '
            f'欠落={missed} ({pct:.1f}%)')
        if gap_str:
            stats_lines.append(f'  {gap_str}')
        if pct > 5:
            overall_pass = False

    passed = overall_pass if beats_by_node else None
    if passed is not None:
        stats_lines.append(f'判定: {"PASS" if passed else "FAIL"}')

    for line in stats_lines:
        print(f'  {line}')

    summary_path = common.write_summary(9, ts, passed if passed is not None else False,
                                        '\n'.join(stats_lines))
    print(f'\n  CSV:     {csv_path}')
    print(f'  Summary: {summary_path}')


if __name__ == '__main__':
    main()
