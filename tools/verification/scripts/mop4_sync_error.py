#!/usr/bin/env python3
"""
MOP4: 楽器間同期誤差 (≤ 20 ms)
NOTE_ON の PC 受信タイムスタンプで同一拍のスレーブ間最大差を計測する。
EMA + lookahead 補正込みの「実際の発音ズレ」を直接測る。

計測原理:
  各楽器は拍ごとに NOTE_ON をシリアル出力する。PC 側で各ポートの受信
  タイムスタンプ (time.time()) を記録し、同一拍に属する NOTE_ON 間の
  最大時間差を同期誤差とする。

  beatNo の対応付け: 各ポートで直前の EVT BEAT の beatNo を追跡し、
  NOTE_ON に紐付ける。

SERIAL_DEBUG=1:
  [NX EVT BEAT] no=<beatNo> playAt=<ms> ahead=<ms>
  [NX NOTE_ON ] part=0x0X instr=N note=N vel=N dur=N seq=N t=N
"""

import argparse
import re
import signal
import statistics
import sys
import time
from collections import defaultdict

import common

THRESHOLD_MS = 20

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
        description='MOP4: 楽器間同期誤差 — NOTE_ON ベース')
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

    print(f"楽器間同期誤差を {args.duration:.0f} 秒間計測します（NOTE_ON ベース）。")
    print("指揮棒を振って演奏を開始してください。Ctrl+C でも停止できます。")
    print()

    # 各ポートの最新 beatNo を追跡
    last_beat = {}  # port -> beatNo
    # beatNo -> {partId -> pc_timestamp} (NOTE_ON 初到着のみ)
    beat_notes = defaultdict(dict)

    ts = common.make_timestamp()
    csv_fields = ['beatNo', 'partId', 'noteNumber', 'device_t', 'pc_timestamp']
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

                    # 同一拍・同一ノードの初到着のみ記録
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
    """既存ログファイルから MOP4 を解析する。"""
    last_beat = {}  # node_id -> beatNo
    beat_notes = defaultdict(dict)

    with open(log_path) as f:
        for line in f:
            line = line.rstrip()
            # pc_timestamp がタブ区切りで先頭にあるログ形式を想定
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
    """計測結果を集計・表示する。"""
    common.print_header(f'MOP4: 楽器間同期誤差 (<= {THRESHOLD_MS} ms)')
    stats_lines = []

    diffs_ms = []
    node_deviations = defaultdict(list)

    for beat_no, parts in sorted(beat_notes.items()):
        if len(parts) < 2:
            continue
        times = list(parts.values())
        diff_ms = (max(times) - min(times)) * 1000.0
        diffs_ms.append(diff_ms)

        group_mean = statistics.mean(times)
        for pid, t in parts.items():
            node_deviations[pid].append((t - group_mean) * 1000.0)

    observed_nodes = set()
    for parts in beat_notes.values():
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
        passed = max(diffs_ms) <= THRESHOLD_MS
        stats_lines.append(f'判定: {"PASS" if passed else "FAIL"} (閾値 {THRESHOLD_MS} ms)')

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

    summary_path = common.write_summary(
        4, ts, passed if passed is not None else False,
        '\n'.join(stats_lines))
    print(f'\n  Summary: {summary_path}')


if __name__ == '__main__':
    main()
