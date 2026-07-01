#!/usr/bin/env python3
"""
MOP6: テンポ追従の遅延
指揮者のテンポ変化から楽器側が追従するまでの拍数を計測する。

MOP_TEST=6: M6,<partId>,<beatNo>,<bpmQ8>,<localMs>  (BPM 変化時のみ)
SERIAL_DEBUG=1:
  指揮者: [N1 EVT BEAT] no=<beatNo> t=<ms> playAt=<ms> bpm=<bpm>
  楽器:   [NX EVT CTRL] bpm=<bpm> ...
"""

import argparse
import re
import signal
import statistics
import sys
import time
from collections import defaultdict

import common

RE_MOP6 = re.compile(r'^M6,(\d+),(\d+),(\d+),(\d+)')
RE_BEAT_N1 = re.compile(
    r'\[N1 EVT BEAT\] no=(\d+) t=(\d+) playAt=(\d+) bpm=(\S+)')
RE_CTRL_NX = re.compile(r'\[N(\d) EVT CTRL\] bpm=(\S+)')


def main():
    parser = argparse.ArgumentParser(description='MOP6: テンポ追従の遅延')
    parser.add_argument('--duration', type=float, default=90,
                        help='計測時間 (テンポを数回変えるので長めに)')
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

    print(f"テンポ追従を {args.duration:.0f} 秒間計測します。")
    print("途中でテンポを大きく変えてください (例: 100→140 BPM)。")
    print("Ctrl+C でも停止できます。")
    print()

    conductor_beats = []  # (pc_time, beatNo, bpm)
    instrument_bpms = defaultdict(list)  # nodeId -> [(pc_time, bpm)]
    ts = common.make_timestamp()
    csv_fields = ['source', 'nodeId', 'beatNo', 'bpm', 'pc_time']
    csv_writer, csv_fh, csv_path = common.open_csv(6, csv_fields, ts)

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
                pc_time = time.time()

                # 指揮者の拍
                m = RE_BEAT_N1.search(text)
                if m:
                    beatNo = int(m.group(1))
                    bpm = float(m.group(4))
                    conductor_beats.append((pc_time, beatNo, bpm))
                    csv_writer.writerow({
                        'source': 'conductor', 'nodeId': '1',
                        'beatNo': beatNo, 'bpm': f'{bpm:.1f}',
                        'pc_time': f'{pc_time:.6f}',
                    })
                    csv_fh.flush()
                    continue

                # 楽器の CTRL 受信
                m = RE_CTRL_NX.search(text)
                if m:
                    node = int(m.group(1))
                    bpm = float(m.group(2))
                    instrument_bpms[node].append((pc_time, bpm))
                    csv_writer.writerow({
                        'source': 'instrument', 'nodeId': str(node),
                        'beatNo': '', 'bpm': f'{bpm:.1f}',
                        'pc_time': f'{pc_time:.6f}',
                    })
                    csv_fh.flush()
    finally:
        csv_fh.close()
        for _, ser in serials:
            ser.close()

    # ── 結果 ──
    common.print_header('MOP6: テンポ追従の遅延 (<= 2 拍)')
    stats_lines = []

    if len(conductor_beats) < 5:
        stats_lines.append('拍データ不足。テンポ変更を含むテストを実行してください。')
        passed = None
    else:
        # 10% 以上の BPM 変化を検出
        changes = []
        for i in range(1, len(conductor_beats)):
            old_bpm = conductor_beats[i - 1][2]
            new_bpm = conductor_beats[i][2]
            if old_bpm > 0 and abs(new_bpm - old_bpm) / old_bpm > 0.10:
                changes.append(conductor_beats[i])

        if not changes:
            stats_lines.append('テンポ変化未検出。テンポを大きく変えてください。')
            passed = None
        else:
            max_delay_beats = 0
            for ts_change, bno, new_bpm in changes:
                tol = abs(new_bpm) * 0.15
                for node, bpms in sorted(instrument_bpms.items()):
                    for t, b in bpms:
                        if t > ts_change and abs(b - new_bpm) <= tol:
                            dt = t - ts_change
                            beat_iv = 60.0 / new_bpm
                            delay_beats = dt / beat_iv
                            max_delay_beats = max(max_delay_beats, delay_beats)
                            stats_lines.append(
                                f'beat {bno} (→{new_bpm:.0f} BPM): '
                                f'node_0{node} {delay_beats:.1f} 拍で追従')
                            break

            passed = max_delay_beats <= 2
            stats_lines.append(f'最大追従遅延: {max_delay_beats:.1f} 拍')
            stats_lines.append(f'判定: {"PASS" if passed else "FAIL"}')

    for line in stats_lines:
        print(f'  {line}')

    summary_path = common.write_summary(6, ts, passed if passed is not None else False,
                                        '\n'.join(stats_lines))
    print(f'\n  CSV:     {csv_path}')
    print(f'  Summary: {summary_path}')


if __name__ == '__main__':
    main()
