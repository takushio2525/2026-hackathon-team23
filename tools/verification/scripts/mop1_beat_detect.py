#!/usr/bin/env python3
"""
MOP1: 拍検出の正確性
指揮者ノード (node_01) のシリアル出力から拍検出イベントを収集し、
検出率・BPM 精度・拍間隔ばらつきを評価する。

使い方:
  python3 mop1_beat_detect.py [--bpm 120] [--duration 60] [--port /dev/cu.usbmodemXXXX]

MOP_TEST=1 モード:
  ファームが MOP_TEST=1 でビルドされている場合、各拍で以下を出力する:
    M1,<beatNo>,<timestamp_ms>,<bpmQ8>
  このフォーマットを優先的にパースし、従来の SERIAL_DEBUG ログにもフォールバックする。

従来モード (SERIAL_DEBUG=1):
  [N1 EVT BEAT] no=<beatNo> t=<ms> playAt=<ms> bpm=<bpm>
"""

import argparse
import re
import signal
import statistics
import sys
import time

import common

# ── パーサ ──
RE_MOP1 = re.compile(r'^M1,(\d+),(\d+),(\d+)')
RE_BEAT_DBG = re.compile(
    r'\[N1 EVT BEAT\] no=(\d+) t=(\d+) playAt=(\d+) bpm=(\S+)')


def parse_beat(text):
    """拍検出行をパースして (beatNo, timestamp_ms, bpmQ8) を返す。該当なしなら None。"""
    m = RE_MOP1.match(text)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3))
    m = RE_BEAT_DBG.search(text)
    if m:
        bpm_float = float(m.group(4))
        return int(m.group(1)), int(m.group(2)), int(bpm_float * 8 + 0.5)
    return None


def main():
    parser = argparse.ArgumentParser(description='MOP1: 拍検出の正確性')
    parser.add_argument('--bpm', type=float, default=None,
                        help='テスト時の期待 BPM')
    parser.add_argument('--duration', type=float, default=60,
                        help='テスト時間 (秒, デフォルト: 60)')
    parser.add_argument('--port', type=str, default=None,
                        help='指揮者ノードのシリアルポート (省略時は自動検出)')
    parser.add_argument('--baud', type=int, default=115200)
    args = parser.parse_args()

    # ポート検出
    if args.port:
        ports = [args.port]
    else:
        ports = common.find_usb_serial_ports()
        if not ports:
            print("USB シリアルポートが見つかりません。", file=sys.stderr)
            sys.exit(1)

    node_mapper = common.NodeMapper()

    # 指揮者ノードを探す: 全ポートを開いて [N1 を見つける
    print("指揮者ノード (node_01) を検出中...")
    conductor_ser = None
    conductor_port = None
    opened = []

    for p in ports:
        ser = common.open_serial(p, args.baud)
        if ser:
            opened.append((p, ser))

    # 最大 5 秒待って node_01 を特定
    deadline = time.time() + 5
    while time.time() < deadline and conductor_ser is None:
        for p, ser in opened:
            text = common.read_line(ser)
            if text:
                node_mapper.try_detect(p, text)
                if node_mapper.get_name(p) == 'node_01':
                    conductor_ser = ser
                    conductor_port = p
                    break

    # 指揮者以外は閉じる
    for p, ser in opened:
        if ser is not conductor_ser:
            ser.close()

    if conductor_ser is None:
        # 指揮者が見つからない場合、ポートが 1 つだけならそれを使う
        if len(opened) == 1:
            conductor_port, conductor_ser = opened[0]
            print(f"  ノード判定できず。唯一のポート {conductor_port} を使用します。")
        else:
            print("  node_01 が見つかりません。--port で指定してください。",
                  file=sys.stderr)
            for _, ser in opened:
                ser.close()
            sys.exit(1)

    print(f"  → {node_mapper.get_name(conductor_port)} ({conductor_port})")
    print()

    # 計測開始
    if args.bpm:
        print(f"期待 BPM: {args.bpm}、計測時間: {args.duration} 秒")
    else:
        print(f"計測時間: {args.duration} 秒（BPM 未指定 → 検出率は計算しません）")
    print(f"指揮棒を振り始めてください。Ctrl+C でも停止できます。")
    print()

    beats = []  # (beatNo, timestamp_ms, bpmQ8)
    ts = common.make_timestamp()
    csv_fields = ['beatNo', 'timestamp_ms', 'bpmQ8', 'bpm', 'interval_ms']
    csv_writer, csv_fh, csv_path = common.open_csv(1, csv_fields, ts)

    stop = False

    def on_sigint(sig, frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, on_sigint)

    start_time = time.time()
    last_print_count = 0

    try:
        while not stop and (time.time() - start_time) < args.duration:
            text = common.read_line(conductor_ser)
            if not text:
                continue
            node_mapper.try_detect(conductor_port, text)
            result = parse_beat(text)
            if result is None:
                continue

            beatNo, ts_ms, bpmQ8 = result
            bpm = bpmQ8 / 8.0
            interval_ms = ''
            if beats:
                interval_ms = ts_ms - beats[-1][1]
            beats.append(result)

            csv_writer.writerow({
                'beatNo': beatNo,
                'timestamp_ms': ts_ms,
                'bpmQ8': bpmQ8,
                'bpm': f'{bpm:.1f}',
                'interval_ms': interval_ms,
            })
            csv_fh.flush()

            # 5 拍ごとに進捗表示
            if len(beats) % 5 == 0 and len(beats) != last_print_count:
                elapsed = time.time() - start_time
                print(f"  {len(beats)} 拍検出 ({elapsed:.0f}s / {args.duration:.0f}s) "
                      f"BPM={bpm:.1f}")
                last_print_count = len(beats)

    finally:
        csv_fh.close()
        conductor_ser.close()

    # ── 結果分析 ──
    common.print_header('MOP1: 拍検出の正確性 (正解率 >= 90%)')

    if len(beats) < 2:
        print('  拍データ不足 (< 2)。')
        return

    intervals_ms = [beats[i][1] - beats[i - 1][1]
                    for i in range(1, len(beats))]
    mean_iv = statistics.mean(intervals_ms)
    detected_bpm = 60000 / mean_iv if mean_iv > 0 else 0
    elapsed_s = (beats[-1][1] - beats[0][1]) / 1000.0

    stats_lines = []
    stats_lines.append(f'検出拍数:     {len(beats)}')
    stats_lines.append(f'計測区間:     {elapsed_s:.1f} 秒')
    stats_lines.append(f'平均拍間隔:   {mean_iv:.1f} ms')
    stats_lines.append(f'検出 BPM:     {detected_bpm:.1f}')

    if len(intervals_ms) >= 2:
        sd = statistics.stdev(intervals_ms)
        stats_lines.append(f'拍間隔 SD:    {sd:.1f} ms  (CV {sd / mean_iv * 100:.1f}%)')

    passed = None
    if args.bpm:
        expected = int(args.duration * args.bpm / 60)
        rate = len(beats) / expected * 100
        passed = rate >= 90
        stats_lines.append(f'期待拍数:     {expected} (BPM={args.bpm}, {args.duration}s)')
        stats_lines.append(f'検出率:       {rate:.1f}%')
        stats_lines.append(f'判定: {"PASS" if passed else "FAIL"}')
    else:
        stats_lines.append('--bpm を指定すると検出率を計算します')

    for line in stats_lines:
        print(f'  {line}')

    # summary 保存
    stats_text = '\n'.join(stats_lines)
    summary_path = common.write_summary(1, ts, passed if passed is not None else False,
                                        stats_text)

    print(f'\n  CSV:     {csv_path}')
    print(f'  Summary: {summary_path}')


if __name__ == '__main__':
    main()
