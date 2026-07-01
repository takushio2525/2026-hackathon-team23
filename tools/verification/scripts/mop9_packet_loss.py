#!/usr/bin/env python3
"""
MOP9: パケットロス耐性
楽器ノードの BEAT 受信ログから beatNo の欠番を検出し、ロス率を計測する。

MOP定義: 5% パケロス環境下で聴感破綻なし（テスト条件）
本スクリプト: 自然環境での beatNo レベルの実測ロス率を計測する。
  beatRedundancy=4（4連送）のため seq の欠番 ≠ 拍の欠落。
  beatNo の欠番のみが「楽器が拍を受け取れなかった」ことを示す。
  5% 疑似パケロスのストレステストは別途環境構築が必要。

MOP_TEST=9: M9,<partId>,<beatNo>,<seq>,<localMs>
SERIAL_DEBUG=1: [NX EVT BEAT] no=<beatNo> playAt=<ms> ahead=<ahead> seq=<seq>
"""

import argparse
import re
import signal
import sys
import time
from collections import defaultdict

import common

RE_MOP9 = re.compile(r'^M9,(\d+),(\d+),(\d+),(\d+)')
RE_BEAT_NX = re.compile(
    r'\[N(\d) EVT BEAT\] no=(\d+) playAt=(\d+) ahead=(-?\d+) seq=(\d+)')


def analyze_node_beats(beat_nos):
    """beatNo リストからロス統計を計算する。

    指揮者再起動で beatNo がリセットされる場合があるため、
    beatNo が減少した箇所で区間分割し、各区間のロスを独立計算して集計する。
    """
    if len(beat_nos) < 2:
        return None

    # beatNo の減少箇所で区間分割（リセット検出）
    segments = []
    seg = [beat_nos[0]]
    for i in range(1, len(beat_nos)):
        if beat_nos[i] <= beat_nos[i - 1]:
            segments.append(seg)
            seg = [beat_nos[i]]
        else:
            seg.append(beat_nos[i])
    segments.append(seg)

    total_expected = 0
    total_received = 0
    all_missing = []
    max_consec = 0

    for seg in segments:
        expected = seg[-1] - seg[0] + 1
        unique = set(seg)
        received = len(unique)
        total_expected += expected
        total_received += received

        missing = sorted(set(range(seg[0], seg[-1] + 1)) - unique)
        all_missing.extend(missing)

        if missing:
            run = 1
            best = 1
            for j in range(1, len(missing)):
                if missing[j] == missing[j - 1] + 1:
                    run += 1
                    best = max(best, run)
                else:
                    run = 1
            max_consec = max(max_consec, best)

    missed = total_expected - total_received
    loss_pct = missed / total_expected * 100 if total_expected > 0 else 0.0

    return {
        'total': total_expected,
        'received': total_received,
        'missed': missed,
        'loss_pct': loss_pct,
        'max_consecutive_loss': max_consec,
        'missing_beats': all_missing,
        'resets': len(segments) - 1,
    }


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

    beats_by_node = defaultdict(list)
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

                m = RE_MOP9.match(text)
                if m:
                    part_id = int(m.group(1))
                    beat_no = int(m.group(2))
                    seq = int(m.group(3))
                    local_ms = int(m.group(4))
                    beats_by_node[part_id].append(beat_no)
                    csv_writer.writerow({
                        'partId': f'0x{part_id:02X}',
                        'beatNo': beat_no, 'seq': seq, 'localMs': local_ms,
                    })
                    csv_fh.flush()
                    continue

                m = RE_BEAT_NX.search(text)
                if m:
                    node = int(m.group(1))
                    if node == 1:
                        continue
                    beat_no = int(m.group(2))
                    seq = int(m.group(5))
                    beats_by_node[node].append(beat_no)
                    csv_writer.writerow({
                        'partId': f'0x{node:02X}',
                        'beatNo': beat_no, 'seq': seq, 'localMs': '',
                    })
                    csv_fh.flush()
    finally:
        csv_fh.close()
        for _, ser in serials:
            ser.close()

    # ── 結果 ──
    common.print_header('MOP9: パケットロス耐性 — 実測ロス率（beatNo ベース）')
    stats_lines = []
    overall_pass = True

    for node_id in sorted(beats_by_node):
        beat_nos = beats_by_node[node_id]
        result = analyze_node_beats(beat_nos)
        if result is None:
            stats_lines.append(f'node_{node_id:02d}: データ不足（2拍未満）')
            continue

        line = (f'node_{node_id:02d}: '
                f'期待={result["total"]} 受信={result["received"]} '
                f'欠落={result["missed"]} ({result["loss_pct"]:.1f}%) '
                f'最大連続欠落={result["max_consecutive_loss"]}拍')
        stats_lines.append(line)

        if result['resets'] > 0:
            stats_lines.append(
                f'  指揮者リセット検出: {result["resets"]}回（区間分割して計測）')

        if result['missing_beats']:
            show = result['missing_beats'][:10]
            gap_str = f'  欠番beatNo: {show}'
            if len(result['missing_beats']) > 10:
                gap_str += f'... 他{len(result["missing_beats"]) - 10}件'
            stats_lines.append(gap_str)

        if result['loss_pct'] > 5:
            overall_pass = False

    passed = overall_pass if beats_by_node else None
    if passed is not None:
        if passed:
            stats_lines.append('判定: PASS（自然環境ロス率 ≤ 5%）')
            stats_lines.append(
                '  注: MOP定義の5%ストレステストには'
                '疑似パケロス環境が別途必要')
        else:
            stats_lines.append('判定: FAIL（自然環境でロス率 > 5%）')

    for line in stats_lines:
        print(f'  {line}')

    summary_path = common.write_summary(
        9, ts, passed if passed is not None else False,
        '\n'.join(stats_lines))
    print(f'\n  CSV:     {csv_path}')
    print(f'  Summary: {summary_path}')


if __name__ == '__main__':
    main()
