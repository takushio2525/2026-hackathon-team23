#!/usr/bin/env python3
"""
MOP8: CPU 負荷
指揮者ノードの各フェーズ処理時間を計測する。

MOP_TEST=8: M8,<inputUs>,<logicUs>,<outputUs>
SERIAL_DEBUG=1: [N1 PERF] in=<us> logic=<us> out=<us> total=<us>
"""

import argparse
import math
import re
import signal
import statistics
import sys
import time

import common

WARMUP_SAMPLES = 20

RE_MOP8 = re.compile(r'^M8,(\d+),(\d+),(\d+)')
RE_PERF = re.compile(
    r'\[N(\d) PERF\] in=(\d+) logic=(\d+) out=(\d+)')


def percentile(data, pct):
    """ソート済みリストから p-th パーセンタイルを返す（線形補間なし、切り上げ index）。"""
    s = sorted(data)
    k = math.ceil(len(s) * pct / 100) - 1
    return s[max(0, min(k, len(s) - 1))]


def parse_perf(text):
    """CPU 負荷行をパースして (inputUs, logicUs, outputUs) を返す。"""
    m = RE_MOP8.match(text)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3))
    m = RE_PERF.search(text)
    if m:
        return int(m.group(2)), int(m.group(3)), int(m.group(4))
    return None


def main():
    parser = argparse.ArgumentParser(description='MOP8: CPU 負荷')
    parser.add_argument('--duration', type=float, default=30)
    parser.add_argument('--port', type=str, default=None,
                        help='指揮者ノードのポート')
    parser.add_argument('--baud', type=int, default=115200)
    args = parser.parse_args()

    if args.port:
        ports = [args.port]
    else:
        ports = common.find_usb_serial_ports()

    if not ports:
        print("USB シリアルポートが見つかりません。", file=sys.stderr)
        sys.exit(1)

    node_mapper = common.NodeMapper()

    # 指揮者ノードを探す
    print("指揮者ノード (node_01) を検出中...")
    conductor_ser = None
    conductor_port = None
    opened = []
    for p in ports:
        ser = common.open_serial(p, args.baud)
        if ser:
            opened.append((p, ser))

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
                # PERF データがあれば指揮者と推定
                if parse_perf(text) is not None:
                    conductor_ser = ser
                    conductor_port = p
                    break

    for p, ser in opened:
        if ser is not conductor_ser:
            ser.close()

    if conductor_ser is None:
        if len(opened) == 1:
            conductor_port, conductor_ser = opened[0]
        else:
            print("  node_01 が見つかりません。--port で指定してください。",
                  file=sys.stderr)
            for _, ser in opened:
                ser.close()
            sys.exit(1)

    print(f"  → {node_mapper.get_name(conductor_port)} ({conductor_port})")
    print(f"CPU 負荷を {args.duration:.0f} 秒間計測します。Ctrl+C でも停止できます。")
    print()

    samples = []  # (inputUs, logicUs, outputUs)
    ts_str = common.make_timestamp()
    csv_fields = ['inputUs', 'logicUs', 'outputUs', 'totalUs']
    csv_writer, csv_fh, csv_path = common.open_csv(8, csv_fields, ts_str)

    stop = False
    def on_sigint(s, f):
        nonlocal stop
        stop = True
    signal.signal(signal.SIGINT, on_sigint)

    start = time.time()
    try:
        while not stop and (time.time() - start) < args.duration:
            text = common.read_line(conductor_ser)
            if not text:
                continue
            result = parse_perf(text)
            if result is None:
                continue
            inp, logic, out = result
            samples.append(result)
            csv_writer.writerow({
                'inputUs': inp, 'logicUs': logic,
                'outputUs': out, 'totalUs': inp + logic + out,
            })
            csv_fh.flush()
    finally:
        csv_fh.close()
        conductor_ser.close()

    # ── 結果 ──
    common.print_header('MOP8: CPU 負荷 入力フェーズ (<= 2 ms)')
    stats_lines = []

    if not samples:
        stats_lines.append('[PERF] ログなし。MOP_TEST=8 のファームを使用してください。')
        passed = None
    else:
        # ウォームアップ期間をスキップ（起動直後の I2C 初回読取等で最大値が歪むため）
        if len(samples) > WARMUP_SAMPLES:
            stats_lines.append(f'全サンプル数: {len(samples)}（先頭 {WARMUP_SAMPLES} 件をウォームアップとして除外）')
            samples = samples[WARMUP_SAMPLES:]
        else:
            stats_lines.append(f'サンプル数: {len(samples)}（{WARMUP_SAMPLES} 件未満のためウォームアップ除外なし）')

        inputs = [s[0] for s in samples]
        logics = [s[1] for s in samples]
        outputs = [s[2] for s in samples]
        totals = [s[0] + s[1] + s[2] for s in samples]

        stats_lines.append(f'有効サンプル数: {len(samples)}')
        for label, vals in [('入力', inputs), ('ロジック', logics),
                            ('出力', outputs), ('合計', totals)]:
            mx = max(vals)
            p99 = percentile(vals, 99)
            stats_lines.append(
                f'{label}: 平均={statistics.mean(vals):.0f}us '
                f'p99={p99}us ({p99 / 1000:.2f}ms) '
                f'最大={mx}us ({mx / 1000:.2f}ms)')

        worst_input = max(inputs)
        worst_total = max(totals)
        passed = worst_input / 1000 <= 2.0
        stats_lines.append(f'入力フェーズ最大: {worst_input}us ({worst_input / 1000:.2f}ms) → {"PASS" if passed else "FAIL"}')

        total_ok = worst_total / 1000 <= 5.0
        stats_lines.append(f'合計最大: {worst_total}us ({worst_total / 1000:.2f}ms) → {"OK" if total_ok else "WARNING (>5ms)"}')
        stats_lines.append(f'判定: {"PASS" if passed else "FAIL"}')

    for line in stats_lines:
        print(f'  {line}')

    summary_path = common.write_summary(8, ts_str, passed if passed is not None else False,
                                        '\n'.join(stats_lines))
    print(f'\n  CSV:     {csv_path}')
    print(f'  Summary: {summary_path}')


if __name__ == '__main__':
    main()
