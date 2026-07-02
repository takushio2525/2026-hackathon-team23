#!/usr/bin/env python3
"""
MOP7: 起動時間
各ノードを pio upload で書き込み（リセットを兼ねる）→ 直後にシリアルを開いて
M7 メッセージ（BOOT/INIT/WIFI/SYNC/READY）を収集し、起動時間を計測する。

指揮者を最初に書き込み、楽器は順番に 1 台ずつ処理する。
楽器の READY は指揮者の BEAT に依存するため、デフォルトでは SYNC を
「演奏準備完了」として扱う。--with-beat で READY まで待つモードも可。

CSV と summary は自動生成される。
"""

import argparse
import os
import re
import signal
import subprocess
import sys
import time
from collections import OrderedDict
from datetime import datetime

import common

# ── デフォルトのノード定義 ──
# (ファームウェアディレクトリ名, シリアルポート, nodeId)
DEFAULT_NODES = [
    ('node_01_devkitc', '/dev/cu.usbmodem5C4D0290571', 1),
    ('node_02', '/dev/cu.usbmodem34B7DA64482C2', 2),
    ('node_03', '/dev/cu.usbmodemF412FAA085582', 3),
    ('node_04', '/dev/cu.usbmodem34B7DA6375842', 4),
    ('node_05', '/dev/cu.usbmodem34B7DA6448002', 5),
    ('node_06', '/dev/cu.usbmodemF412FA649C9C2', 6),
]

DEFAULT_PIO = os.path.expanduser('~/.platformio/penv/bin/pio')
FIRMWARE_BASE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))))),
    'firmware', 'production')

RE_MOP7 = re.compile(r'^M7,(\d+),(\w+),(\d+)')

# SERIAL_DEBUG フォールバック用
RE_BOOT = re.compile(r'=== node_0?(\d+)')
RE_INIT = re.compile(r'\[N(\d) INIT\] done')
RE_WIFI = re.compile(r'\[N(\d) EVT WIFI\] connected=1')
RE_SYNC = re.compile(r'\[N(\d) EVT SYNC_CONVERGED\]')
RE_BEAT_NX = re.compile(r'\[N(\d) EVT BEAT\]')

CONDUCTOR_EVENTS = ['BOOT', 'INIT', 'READY']
INSTRUMENT_EVENTS_DEFAULT = ['BOOT', 'INIT', 'WIFI', 'SYNC']
INSTRUMENT_EVENTS_BEAT = ['BOOT', 'INIT', 'WIFI', 'SYNC', 'READY']


def pio_upload(pio_path, firmware_dir, upload_port):
    """pio run -t upload を実行し、成功したら True を返す。"""
    cmd = [
        pio_path, 'run', '-t', 'upload',
        '-d', firmware_dir,
        '--upload-port', upload_port,
    ]
    print(f"    $ {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        print(f"    upload 失敗 (exit {result.returncode})", file=sys.stderr)
        for line in result.stderr.strip().splitlines()[-5:]:
            print(f"      {line}", file=sys.stderr)
        return False
    print("    upload 成功")
    return True


def collect_events(port, node_id, target_events, timeout_sec, raw_log_fh,
                   csv_writer, csv_fh):
    """シリアルポートから M7 メッセージを読み取り、必要なイベントを収集する。

    Returns:
        dict: {event: device_ms} の辞書。device_ms が取れなかったイベントは値が None。
    """
    collected = OrderedDict()
    final_event = target_events[-1]

    ser = common.open_serial(port, 115200)
    if ser is None:
        return collected

    # upload 直後のゴミを捨てる
    time.sleep(0.3)
    ser.reset_input_buffer()

    start = time.time()
    try:
        while (time.time() - start) < timeout_sec:
            text = common.read_line(ser)
            if not text:
                continue

            raw_log_fh.write(f"[{time.time():.3f}] node_0{node_id}: {text}\n")
            raw_log_fh.flush()

            # M7 マーカー
            m = RE_MOP7.match(text)
            if m:
                nid = m.group(1)
                event = m.group(2)
                dev_ms = int(m.group(3))
                if nid == str(node_id) and event in target_events:
                    if event not in collected:
                        collected[event] = dev_ms
                        csv_writer.writerow({
                            'nodeId': node_id,
                            'node_name': f'node_0{node_id}',
                            'event': event,
                            'device_ms': dev_ms,
                            'pc_timestamp': f'{time.time():.6f}',
                        })
                        csv_fh.flush()
                        print(f"    {event}: {dev_ms} ms")
                        if event == final_event:
                            break
                continue

            # SERIAL_DEBUG フォールバック
            for regex, event in [
                (RE_BOOT, 'BOOT'), (RE_INIT, 'INIT'),
                (RE_WIFI, 'WIFI'), (RE_SYNC, 'SYNC'),
                (RE_BEAT_NX, 'READY'),
            ]:
                rm = regex.search(text)
                if rm and rm.group(1) == str(node_id) and event in target_events:
                    if event not in collected:
                        collected[event] = None
                        csv_writer.writerow({
                            'nodeId': node_id,
                            'node_name': f'node_0{node_id}',
                            'event': event,
                            'device_ms': '',
                            'pc_timestamp': f'{time.time():.6f}',
                        })
                        csv_fh.flush()
                        elapsed = time.time() - start
                        print(f"    {event}: +{elapsed:.1f}s (SERIAL_DEBUG)")
                        if event == final_event:
                            break
                    break

            if final_event in collected:
                break
    finally:
        ser.close()

    return collected


def main():
    parser = argparse.ArgumentParser(
        description='MOP7: 起動時間 (pio upload 方式)')
    parser.add_argument('--timeout', type=float, default=15,
                        help='ノードごとの最大シリアル読み取り時間 (秒, デフォルト: 15)')
    parser.add_argument('--pio-path', default=DEFAULT_PIO,
                        help=f'pio 実行ファイルのパス (デフォルト: {DEFAULT_PIO})')
    parser.add_argument('--ports', nargs='*',
                        help='ポートをオーバーライド (ノード順に指定)')
    parser.add_argument('--with-beat', action='store_true',
                        help='楽器の READY (初回 BEAT 受信) まで待つ。'
                             '指揮棒を振る必要がある')
    parser.add_argument('--nodes', nargs='*',
                        help='処理するノードを限定 (例: 1 2 3)')
    args = parser.parse_args()

    # ノード定義を構築
    nodes = list(DEFAULT_NODES)
    if args.ports:
        if len(args.ports) != len(nodes):
            print(f"--ports は {len(nodes)} 個必要です（{len(args.ports)} 個指定）",
                  file=sys.stderr)
            sys.exit(1)
        nodes = [(n[0], p, n[2]) for n, p in zip(nodes, args.ports)]

    if args.nodes:
        target_ids = set(int(x) for x in args.nodes)
        nodes = [n for n in nodes if n[2] in target_ids]

    if not nodes:
        print("処理するノードがありません。", file=sys.stderr)
        sys.exit(1)

    # pio の存在確認
    if not os.path.isfile(args.pio_path):
        print(f"pio が見つかりません: {args.pio_path}", file=sys.stderr)
        sys.exit(1)

    # 出力ファイルの準備
    ts = common.make_timestamp()
    csv_fields = ['nodeId', 'node_name', 'event', 'device_ms', 'pc_timestamp']
    csv_writer, csv_fh, csv_path = common.open_csv(7, csv_fields, ts)

    raw_log_path = os.path.join(common.results_dir(7), f'{ts}_raw.log')
    raw_log_fh = open(raw_log_path, 'w')

    # Ctrl+C ハンドリング
    stop = False
    def on_sigint(s, f):
        nonlocal stop
        stop = True
        print("\n中断します...")
    signal.signal(signal.SIGINT, on_sigint)

    # ── 全ノードを順番に処理 ──
    all_results = OrderedDict()  # nodeId -> {event: device_ms}

    common.print_header('MOP7: 起動時間計測 (pio upload 方式)')
    print(f"対象ノード: {len(nodes)} 台")
    print(f"シリアル読み取りタイムアウト: {args.timeout:.0f} 秒/台")
    if args.with_beat:
        print("楽器の READY (初回 BEAT 受信) まで待機します")
    else:
        print("楽器は SYNC まで計測 (READY には指揮棒の振りが必要)")
    print()

    for fw_dir_name, port, node_id in nodes:
        if stop:
            break

        is_conductor = (node_id == 1)
        label = f"node_0{node_id} ({fw_dir_name})"
        print(f"── {label} ──")
        print(f"  ポート: {port}")

        # ポートの存在確認
        if not os.path.exists(port):
            print(f"  スキップ: ポート {port} が見つかりません")
            print()
            continue

        # pio upload
        fw_path = os.path.join(FIRMWARE_BASE, fw_dir_name)
        if not os.path.isdir(fw_path):
            print(f"  スキップ: ファームウェア {fw_path} が見つかりません")
            print()
            continue

        print("  書き込み中...")
        if not pio_upload(args.pio_path, fw_path, port):
            print(f"  スキップ: upload 失敗")
            print()
            continue

        # upload 後にポートが再出現するまで少し待つ
        time.sleep(1.0)

        # シリアル読み取り
        if is_conductor:
            target_events = CONDUCTOR_EVENTS
        elif args.with_beat:
            target_events = INSTRUMENT_EVENTS_BEAT
        else:
            target_events = INSTRUMENT_EVENTS_DEFAULT

        print(f"  シリアル読み取り中 (待機イベント: {', '.join(target_events)})...")
        events = collect_events(
            port, node_id, target_events, args.timeout,
            raw_log_fh, csv_writer, csv_fh)

        all_results[node_id] = events

        missing = [e for e in target_events if e not in events]
        if missing:
            print(f"  未検出: {', '.join(missing)}")

        if args.with_beat and not is_conductor and node_id == nodes[-1][2]:
            pass  # 最後のノードなら表示不要
        elif args.with_beat and not is_conductor:
            print("  (指揮棒を振ってください)")

        print()

    # ── クリーンアップ ──
    csv_fh.close()
    raw_log_fh.close()

    # ── 結果集計 ──
    common.print_header('MOP7: 起動時間 (<= 5 s)')
    stats_lines = []

    max_startup_ms = 0
    has_any_data = False

    for node_id, events in all_results.items():
        is_conductor = (node_id == 1)
        if not events:
            stats_lines.append(f'node_0{node_id}: イベント未検出')
            continue

        has_any_data = True
        line_parts = [f'node_0{node_id}:']
        boot_ms = events.get('BOOT')

        all_labels = CONDUCTOR_EVENTS if is_conductor else (
            INSTRUMENT_EVENTS_BEAT if args.with_beat else INSTRUMENT_EVENTS_DEFAULT)

        for label in all_labels:
            if label in events and events[label] is not None:
                if boot_ms is not None:
                    dt = events[label] - boot_ms
                    line_parts.append(f'{label}={dt}ms')
                else:
                    line_parts.append(f'{label}={events[label]}ms(abs)')

        # 起動時間: 最終到達イベントの device_ms
        if is_conductor:
            final = 'READY'
        elif args.with_beat:
            final = 'READY'
        else:
            final = 'SYNC'

        if final in events and events[final] is not None:
            startup_ms = events[final]
            max_startup_ms = max(max_startup_ms, startup_ms)
            line_parts.append(f'→ 起動{startup_ms}ms')
        elif final in events:
            line_parts.append(f'→ {final}検出 (device_ms なし)')

        stats_lines.append(' '.join(line_parts))

    if not args.with_beat:
        stats_lines.append('')
        stats_lines.append('※ 楽器の計測は SYNC まで (READY には指揮棒の BEAT が必要)')
        stats_lines.append('  SYNC = WiFi接続＋時刻同期完了 = 自律的な起動完了地点')

    if max_startup_ms > 0:
        max_sec = max_startup_ms / 1000
        passed = max_sec <= 5.0
        stats_lines.append(f'最大起動時間: {max_startup_ms} ms ({max_sec:.2f} 秒)')
        stats_lines.append(f'判定: {"PASS" if passed else "FAIL"} (<= 5 s)')
    elif has_any_data:
        stats_lines.append('起動時間 (device_ms) を特定できませんでした。')
        passed = None
    else:
        stats_lines.append('いずれのノードからもイベントを検出できませんでした。')
        passed = None

    for line in stats_lines:
        print(f'  {line}')

    summary_path = common.write_summary(
        7, ts, passed if passed is not None else False,
        '\n'.join(stats_lines))

    print(f'\n  CSV:     {csv_path}')
    print(f'  Raw log: {raw_log_path}')
    print(f'  Summary: {summary_path}')


if __name__ == '__main__':
    main()
