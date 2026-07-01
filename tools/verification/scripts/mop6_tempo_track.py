#!/usr/bin/env python3
"""
MOP6: テンポ追従の遅延
指揮者のテンポ変化から楽器側が追従するまでの拍数を計測する。

データソース（いずれか / 併用可）:
  MOP_TEST=6 (楽器側): M6,<partId>,<beatNo>,<bpmQ8>,<localMs>  毎 BEAT 出力
  SERIAL_DEBUG=1:
    指揮者: [N1 EVT BEAT] no=<beatNo> t=<ms> playAt=<ms> bpm=<bpm>
    楽器:   [NX EVT CTRL] bpm=<bpm> ...
"""

import argparse
import re
import signal
import sys
import time
from collections import defaultdict

import common

RE_MOP6 = re.compile(r'^M6,(\d+),(\d+),(\d+),(\d+)')
RE_BEAT_N1 = re.compile(
    r'\[N1 EVT BEAT\] no=(\d+) t=(\d+) playAt=(\d+) bpm=(\S+)')
RE_CTRL_NX = re.compile(r'\[N(\d) EVT CTRL\] bpm=(\S+)')

CHANGE_THRESHOLD = 0.10
CONVERGE_TOLERANCE = 0.15


def main():
    parser = argparse.ArgumentParser(description='MOP6: テンポ追従の遅延')
    parser.add_argument('--duration', type=float, default=120,
                        help='計測時間 (秒)')
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

    print("=" * 55)
    print("MOP6: テンポ追従テスト手順")
    print("=" * 55)
    print("  1. 80 BPM 程度で安定して振る（約 10 拍）")
    print("  2. 急に 140 BPM へ加速する")
    print("  3. 140 BPM で安定（約 10 拍）")
    print("  4. 急に 80 BPM へ減速する")
    print("  5. 上記を 2〜3 回繰り返す")
    print("=" * 55)
    print(f"\n{args.duration:.0f} 秒間計測します。Ctrl+C でも停止できます。\n")

    conductor_beats = []
    instrument_bpms = defaultdict(list)
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

                m = RE_MOP6.match(text)
                if m:
                    partId = int(m.group(1))
                    bpmQ8 = int(m.group(3))
                    bpm = bpmQ8 / 8.0
                    if bpm > 0:
                        instrument_bpms[partId].append((pc_time, bpm))
                        csv_writer.writerow({
                            'source': 'instrument_m6',
                            'nodeId': str(partId),
                            'beatNo': m.group(2),
                            'bpm': f'{bpm:.1f}',
                            'pc_time': f'{pc_time:.6f}',
                        })
                        csv_fh.flush()
                    continue

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

    common.print_header('MOP6: テンポ追従の遅延 (<= 2 拍)')
    stats_lines = []

    if len(conductor_beats) < 5:
        stats_lines.append('拍データ不足（5 拍未満）。')
        stats_lines.append('指揮者の SERIAL_DEBUG=1 を確認してください。')
        passed = None
    elif not instrument_bpms:
        stats_lines.append('楽器の BPM データなし。')
        stats_lines.append('MOP_TEST=6 または SERIAL_DEBUG=1 を確認してください。')
        passed = None
    else:
        changes = []
        for i in range(1, len(conductor_beats)):
            old_bpm = conductor_beats[i - 1][2]
            new_bpm = conductor_beats[i][2]
            if old_bpm > 0 and abs(new_bpm - old_bpm) / old_bpm > CHANGE_THRESHOLD:
                changes.append(conductor_beats[i])

        if not changes:
            stats_lines.append('テンポ変化が検出されませんでした（10% 以上の BPM 変化なし）。')
            stats_lines.append('80→140 BPM のように大きくテンポを変えてください。')
            passed = None
        else:
            stats_lines.append(f'検出テンポ変化: {len(changes)} 回')
            max_delay_beats = 0.0
            any_not_tracked = False

            for ts_change, bno, new_bpm in changes:
                tol = abs(new_bpm) * CONVERGE_TOLERANCE
                beat_iv = 60.0 / new_bpm if new_bpm > 0 else 1.0
                for node, bpms in sorted(instrument_bpms.items()):
                    converged = False
                    for t, b in bpms:
                        if t > ts_change and abs(b - new_bpm) <= tol:
                            dt = t - ts_change
                            delay_beats = dt / beat_iv
                            max_delay_beats = max(max_delay_beats, delay_beats)
                            stats_lines.append(
                                f'  beat {bno} (→{new_bpm:.0f} BPM): '
                                f'node_0{node} {delay_beats:.1f} 拍で追従')
                            converged = True
                            break
                    if not converged:
                        stats_lines.append(
                            f'  beat {bno} (→{new_bpm:.0f} BPM): '
                            f'node_0{node} 追従未確認')
                        any_not_tracked = True

            if any_not_tracked:
                passed = False
                stats_lines.append('最大追従遅延: 追従未確認あり')
                stats_lines.append('判定: FAIL（一部楽器で追従が確認できず）')
            else:
                passed = max_delay_beats <= 2
                stats_lines.append(f'最大追従遅延: {max_delay_beats:.1f} 拍')
                stats_lines.append(f'判定: {"PASS" if passed else "FAIL"}')

    for line in stats_lines:
        print(f'  {line}')

    summary_path = common.write_summary(6, ts,
                                        passed if passed is not None else False,
                                        '\n'.join(stats_lines))
    print(f'\n  CSV:     {csv_path}')
    print(f'  Summary: {summary_path}')


if __name__ == '__main__':
    main()
