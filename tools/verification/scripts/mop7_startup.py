#!/usr/bin/env python3
"""
MOP7: 起動時間
各ノードの電源投入から演奏可能状態までの時間を計測する。

MOP_TEST=7: M7,<nodeId>,<event>,<ms>  (event=BOOT/INIT/WIFI/SYNC/READY)
SERIAL_DEBUG=1:
  === node_0X ...
  [NX INIT] done
  [NX EVT WIFI] connected=1
  [NX EVT SYNC_CONVERGED] ...
  [NX EVT BEAT] ... (最初の BEAT = 演奏可能)

指揮者 (nodeId=1): BOOT → INIT → READY (Calibrating 完了)
楽器 (nodeId=2〜6): BOOT → INIT → WIFI → SYNC → READY (初回 BEAT 受信)
"""

import argparse
import re
import signal
import sys
import time
from collections import defaultdict

import common

RE_MOP7 = re.compile(r'^M7,(\d+),(\w+),(\d+)')
RE_BOOT = re.compile(r'=== node_0?(\d+)')
RE_INIT = re.compile(r'\[N(\d) INIT\] done')
RE_WIFI = re.compile(r'\[N(\d) EVT WIFI\] connected=1')
RE_SYNC = re.compile(r'\[N(\d) EVT SYNC_CONVERGED\]')
RE_BEAT_NX = re.compile(r'\[N(\d) EVT BEAT\]')


def main():
    parser = argparse.ArgumentParser(description='MOP7: 起動時間')
    parser.add_argument('--timeout', type=float, default=30,
                        help='最大待ち時間 (秒, デフォルト: 30)')
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

    print("ノードの電源を入れ直してください。")
    print(f"最大 {args.timeout:.0f} 秒待機します。Ctrl+C でも停止できます。")
    print()

    # nodeId -> {event -> pc_time}
    events = defaultdict(dict)
    # nodeId -> {event -> device_ms} (MOP_TEST=7 のみ)
    device_ms_events = defaultdict(dict)
    ts = common.make_timestamp()
    csv_fields = ['nodeId', 'event', 'pc_time', 'device_ms']
    csv_writer, csv_fh, csv_path = common.open_csv(7, csv_fields, ts)

    stop = False
    def on_sigint(s, f):
        nonlocal stop
        stop = True
    signal.signal(signal.SIGINT, on_sigint)

    start = time.time()
    try:
        while not stop and (time.time() - start) < args.timeout:
            for p, ser in serials:
                text = common.read_line(ser)
                if not text:
                    continue
                node_mapper.try_detect(p, text)
                pc_time = time.time()

                # MOP_TEST=7
                m = RE_MOP7.match(text)
                if m:
                    node = m.group(1)
                    event = m.group(2)
                    dev_ms = int(m.group(3))
                    events[node][event] = pc_time
                    device_ms_events[node][event] = dev_ms
                    csv_writer.writerow({
                        'nodeId': node, 'event': event,
                        'pc_time': f'{pc_time:.6f}', 'device_ms': dev_ms,
                    })
                    csv_fh.flush()
                    name = node_mapper.get_name(p)
                    print(f"  {name}: {event} ({dev_ms} ms)")
                    continue

                # SERIAL_DEBUG フォールバック
                for regex, event in [
                    (RE_BOOT, 'BOOT'), (RE_INIT, 'INIT'),
                    (RE_WIFI, 'WIFI'), (RE_SYNC, 'SYNC'),
                    (RE_BEAT_NX, 'READY'),
                ]:
                    rm = regex.search(text)
                    if rm:
                        node = rm.group(1)
                        events[node].setdefault(event, pc_time)
                        csv_writer.writerow({
                            'nodeId': node, 'event': event,
                            'pc_time': f'{pc_time:.6f}', 'device_ms': '',
                        })
                        csv_fh.flush()
                        name = node_mapper.get_name(p)
                        elapsed = pc_time - start
                        print(f"  {name}: {event} (+{elapsed:.1f}s)")
                        break
    finally:
        csv_fh.close()
        for _, ser in serials:
            ser.close()

    # ── 結果 ──
    common.print_header('MOP7: 起動時間 (<= 5 s)')
    stats_lines = []

    max_startup = 0
    for node in sorted(events):
        ev = events[node]
        dev_ev = device_ms_events.get(node, {})
        boot_t = ev.get('BOOT')
        if boot_t is None:
            stats_lines.append(f'node_0{node}: BOOT 未検出')
            continue

        line_parts = [f'node_0{node}:']
        for label in ['INIT', 'WIFI', 'SYNC', 'READY']:
            if label in dev_ev:
                # device_ms がある場合はデバイス時刻で算出（より正確）
                dt = dev_ev[label] - dev_ev.get('BOOT', 0)
                line_parts.append(f'{label}={dt}ms')
            elif label in ev:
                dt = (ev[label] - boot_t) * 1000
                line_parts.append(f'{label}={dt:.0f}ms')

        # 起動時間の算出: device_ms があればそちらを優先
        if 'READY' in dev_ev:
            startup_ms = dev_ev['READY']
            max_startup = max(max_startup, startup_ms / 1000)
            line_parts.append(f'→ {startup_ms}ms (電源投入から)')
        elif 'READY' in ev:
            startup = ev['READY'] - boot_t
            max_startup = max(max_startup, startup)
            line_parts.append(f'→ {startup:.1f}s (BOOT起点)')

        stats_lines.append(' '.join(line_parts))

    if max_startup > 0:
        passed = max_startup <= 5
        stats_lines.append(f'最大起動時間: {max_startup:.1f} 秒')
        stats_lines.append(f'判定: {"PASS" if passed else "FAIL"}')
    else:
        stats_lines.append('演奏可能時刻を特定できませんでした。')
        passed = None

    for line in stats_lines:
        print(f'  {line}')

    summary_path = common.write_summary(7, ts, passed if passed is not None else False,
                                        '\n'.join(stats_lines))
    print(f'\n  CSV:     {csv_path}')
    print(f'  Summary: {summary_path}')


if __name__ == '__main__':
    main()
