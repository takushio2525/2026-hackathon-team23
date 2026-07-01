#!/usr/bin/env python3
"""
MOP3: 楽譜との相違
楽器ノードが送出する noteNumber が楽譜 (score_data.cpp) と一致するか検証する。

MOP_TEST=3: M3,<partId>,<noteNumber>,<velocity>,<seq>
SERIAL_DEBUG=1: [N2 NOTE_ON ] part=0x02 instr=0 note=60 vel=64 dur=500 seq=1 t=12345
"""

import argparse
import re
import signal
import sys
import time

import common

RE_MOP3 = re.compile(r'^M3,(\d+),(\d+),(\d+),(\d+)')
RE_NOTE_DBG = re.compile(
    r'\[N\d NOTE_(?:ON|SUB)\s*\] part=0x(\w+) instr=\d+ note=(\d+) vel=(\d+) dur=\d+ seq=(\d+)')

# production score_data.cpp「かえるのうた」32拍 (金管ノード node_02-05 共通)
# (noteNumber, isRest, subNoteNumber or None)
# フレーズ4 拍25-28 は8分音符ペア: main→sub の順で2音ずつ発火する
SCORE_DATA = [
    # フレーズ 1 (拍 1-8)
    (60, False, None), (62, False, None), (64, False, None), (65, False, None),
    (64, False, None), (62, False, None), (60, False, None), (0,  True,  None),
    # フレーズ 2 (拍 9-16)
    (64, False, None), (65, False, None), (67, False, None), (69, False, None),
    (67, False, None), (65, False, None), (64, False, None), (0,  True,  None),
    # フレーズ 3 (拍 17-24)
    (60, False, None), (0,  True,  None), (60, False, None), (0,  True,  None),
    (60, False, None), (0,  True,  None), (60, False, None), (0,  True,  None),
    # フレーズ 4 (拍 25-32): 8分音符ペア (sub=拍の後半)
    (60, False, 60),   (62, False, 62),   (64, False, 64),   (65, False, 65),
    (64, False, None), (62, False, None), (60, False, None), (0,  True,  None),
]
EXPECTED_NOTES = []
for _n, _rest, _sub in SCORE_DATA:
    if not _rest:
        EXPECTED_NOTES.append(_n)
    if _sub is not None:
        EXPECTED_NOTES.append(_sub)


def parse_note(text):
    """ノート行をパースして (partId_int, noteNumber, velocity, seq) を返す。"""
    m = RE_MOP3.match(text)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
    m = RE_NOTE_DBG.search(text)
    if m:
        return int(m.group(1), 16), int(m.group(2)), int(m.group(3)), int(m.group(4))
    return None


def main():
    parser = argparse.ArgumentParser(description='MOP3: 楽譜との相違')
    parser.add_argument('--duration', type=float, default=120,
                        help='計測時間 (秒, デフォルト: 120)')
    parser.add_argument('--ports', nargs='*', help='ポートを手動指定')
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

    print(f"楽器ノードのノート送出を {args.duration:.0f} 秒間収集します。")
    print("指揮棒を振って演奏を開始してください。Ctrl+C でも停止できます。")
    print()

    notes_by_part = {}  # partId -> [(noteNumber, seq)]
    ts = common.make_timestamp()
    csv_fields = ['partId', 'noteNumber', 'velocity', 'seq', 'expected', 'match']
    csv_writer, csv_fh, csv_path = common.open_csv(3, csv_fields, ts)

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
                result = parse_note(text)
                if result is None:
                    continue
                part_id, note, vel, seq = result
                notes_by_part.setdefault(part_id, []).append((note, seq))

                # 期待値との比較
                part_notes = notes_by_part[part_id]
                idx = (len(part_notes) - 1) % len(EXPECTED_NOTES)
                expected = EXPECTED_NOTES[idx]
                match = note == expected

                csv_writer.writerow({
                    'partId': f'0x{part_id:02X}',
                    'noteNumber': note,
                    'velocity': vel,
                    'seq': seq,
                    'expected': expected,
                    'match': 'OK' if match else 'NG',
                })
                csv_fh.flush()

                name = node_mapper.get_name(p)
                if not match:
                    print(f"  {name} NG: note={note} expected={expected} (#{len(part_notes)})")
    finally:
        csv_fh.close()
        for _, ser in serials:
            ser.close()

    # ── 結果 ──
    common.print_header('MOP3: 楽譜との相違 (誤ノート発音数 0)')
    total_err = 0
    stats_lines = []
    for part_id in sorted(notes_by_part):
        # ドラム (partId=6) は楽譜構造が異なるため対象外
        if part_id == 6:
            stats_lines.append(f'part 0x{part_id:02X}: ドラム (対象外)')
            continue
        part_notes = notes_by_part[part_id]
        errs = sum(1 for i, (n, _) in enumerate(part_notes)
                   if n != EXPECTED_NOTES[i % len(EXPECTED_NOTES)])
        total_err += errs
        stats_lines.append(f'part 0x{part_id:02X}: {len(part_notes)} ノート, {errs} 件誤り')

    passed = total_err == 0
    stats_lines.append(f'合計誤ノート: {total_err}')
    stats_lines.append(f'判定: {"PASS" if passed else "FAIL"}')

    for line in stats_lines:
        print(f'  {line}')

    summary_path = common.write_summary(3, ts, passed, '\n'.join(stats_lines))
    print(f'\n  CSV:     {csv_path}')
    print(f'  Summary: {summary_path}')


if __name__ == '__main__':
    main()
