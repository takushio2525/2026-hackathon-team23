#!/usr/bin/env python3
"""
MOE/MOP 全9項目の検証解析スクリプト。
serial_logger.py で収集したログファイルを読み込んで PASS/FAIL 判定する。

使い方:
  python3 analyze.py <logfile>
  python3 analyze.py <logfile> --expected-bpm 120 --test-duration 60

MOP1 の検出率を出すには --expected-bpm と --test-duration が必要。
MOP2 (音階誤差) はシリアルログでは計測不可。手動テスト手順は README.md を参照。
MOP8 (CPU負荷) は検証用ファーム (firmware/) を使ったログが必要。
"""

import argparse
import os
import re
import sys
import statistics
from collections import defaultdict

# ── 楽譜期待値（production score_data.cpp「かえるのうた」32 拍） ──
# (noteNumber, is_rest) — 全メロディノード (node_02〜05) 共通
EXPECTED_SCORE = [
    (60, False), (62, False), (64, False), (65, False),
    (64, False), (62, False), (60, False), (0,  True),
    (64, False), (65, False), (67, False), (69, False),
    (67, False), (65, False), (64, False), (0,  True),
    (60, False), (0,  True),  (60, False), (0,  True),
    (60, False), (0,  True),  (60, False), (0,  True),
    (60, False), (62, False), (64, False), (65, False),
    (64, False), (62, False), (60, False), (0,  True),
]
EXPECTED_NOTES_ONLY = [n for n, rest in EXPECTED_SCORE if not rest]

HEAD_REST = {'02': 0, '03': 8, '04': 16, '05': 24}
CANON_CYCLE = 56

# ── 正規表現 ──
RE_BEAT_N1 = re.compile(
    r'\[N1 EVT BEAT\] no=(\d+) t=(\d+) playAt=(\d+) bpm=(\S+)')
RE_BEAT_NX = re.compile(
    r'\[N(\d) EVT BEAT\] no=(\d+) playAt=(\d+) ahead=(-?\d+) seq=(\d+)')
RE_NOTE_ON = re.compile(
    r'\[N(\d) NOTE_ON\s*\] part=0x(\w+) instr=(\d+) note=(\d+) '
    r'vel=(\d+) dur=(\d+) seq=(\d+) t=(\d+)')
RE_STATE = re.compile(r'\[N(\d) EVT STATE\] (\w+) -> (\w+)')
RE_WIFI = re.compile(r'\[N(\d) EVT WIFI\] connected=1')
RE_SYNC = re.compile(r'\[N(\d) EVT SYNC_CONVERGED\] off=(-?\d+) n=(\d+)')
RE_BOOT = re.compile(r'=== node_0?(\d+)')
RE_INIT_DONE = re.compile(r'\[N(\d) INIT\] done')
RE_CTRL = re.compile(r'\[N(\d) EVT CTRL\] bpm=(\S+)')
RE_PERF = re.compile(
    r'\[N(\d) PERF\] in=(\d+) logic=(\d+) out=(\d+) total=(\d+)')


class Entry:
    __slots__ = ('pc_ts', 'port', 'text')

    def __init__(self, pc_ts, port, text):
        self.pc_ts = pc_ts
        self.port = port
        self.text = text


def parse_log(path):
    entries = []
    with open(path) as f:
        for line in f:
            line = line.rstrip('\n')
            if not line or line.startswith('#'):
                continue
            parts = line.split(' ', 2)
            if len(parts) < 3:
                continue
            try:
                ts = float(parts[0])
            except ValueError:
                continue
            entries.append(Entry(ts, parts[1], parts[2]))
    return entries


def _header(title):
    print(f"\n{'=' * 60}")
    print(title)
    print('=' * 60)


# ── MOP1: 拍検出の正確性 ──
def mop1(entries, expected_bpm, test_duration):
    _header('MOP1: 拍検出の正確性 (正解率 >= 90%)')
    beats = []
    for e in entries:
        m = RE_BEAT_N1.search(e.text)
        if m:
            beats.append((e.pc_ts, int(m.group(1)), float(m.group(4))))

    if len(beats) < 2:
        print('  拍データ不足 (< 2)。')
        return None

    intervals_ms = [(beats[i][0] - beats[i - 1][0]) * 1000
                    for i in range(1, len(beats))]
    mean_iv = statistics.mean(intervals_ms)
    detected_bpm = 60000 / mean_iv if mean_iv > 0 else 0

    print(f'  検出拍数:     {len(beats)}')
    print(f'  計測区間:     {beats[-1][0] - beats[0][0]:.1f} 秒')
    print(f'  平均拍間隔:   {mean_iv:.1f} ms')
    print(f'  検出 BPM:     {detected_bpm:.1f}')

    if len(intervals_ms) >= 2:
        sd = statistics.stdev(intervals_ms)
        print(f'  拍間隔 SD:    {sd:.1f} ms  (CV {sd / mean_iv * 100:.1f}%)')

    if expected_bpm and test_duration:
        expected = int(test_duration * expected_bpm / 60)
        rate = len(beats) / expected * 100
        ok = rate >= 90
        print(f'  期待拍数:     {expected} (BPM={expected_bpm}, {test_duration}s)')
        print(f'  検出率:       {rate:.1f}%')
        print(f'  判定: {"PASS" if ok else "FAIL"}')
        return ok

    print('  --expected-bpm と --test-duration を指定すると検出率を計算')
    return None


# ── MOP2: 音階の誤差 ──
def mop2(_entries):
    _header('MOP2: 音階の誤差 (平均 < 3.6 cent)')
    print('  Processing の音声出力を録音して周波数分析が必要。')
    print('  シリアルログからは自動計測不可。README.md を参照。')
    return None


# ── MOP3: 楽譜との相違 ──
def mop3(entries):
    _header('MOP3: 楽譜との相違 (誤ノート発音数 0)')
    notes = defaultdict(list)
    for e in entries:
        m = RE_NOTE_ON.search(e.text)
        if m:
            notes[m.group(2)].append(int(m.group(4)))

    if not notes:
        print('  NOTE_ON なし。楽器を SERIAL_DEBUG=1 にしてください。')
        return None

    total_err = 0
    for part, seq in sorted(notes.items()):
        if part not in HEAD_REST:
            print(f'  part 0x{part}: 対象外 (ドラム等)')
            continue

        errs = 0
        for i, actual in enumerate(seq):
            expected = EXPECTED_NOTES_ONLY[i % len(EXPECTED_NOTES_ONLY)]
            if actual != expected:
                errs += 1
                if errs <= 3:
                    print(f'    誤 #{i}: 送出={actual} 期待={expected}')

        print(f'  part 0x{part} (headRest={HEAD_REST[part]}): '
              f'{len(seq)} ノート, {errs} 件誤り')
        total_err += errs

    ok = total_err == 0
    print(f'  合計誤ノート: {total_err}')
    print(f'  判定: {"PASS" if ok else "FAIL"}')
    return ok


# ── MOP4: 楽器間同期誤差 ──
def mop4(entries):
    _header('MOP4: 楽器間同期誤差 (<= 20 ms)')
    print('  参考値: USB 受信時刻ベースの近似 (到着ジッタ ~20ms が乗る)。')
    print('  正式判定は MOP_TEST=4 ビルド + mop4_sync_error.py を使う。')
    evts = []
    for e in entries:
        m = RE_NOTE_ON.search(e.text)
        if m:
            evts.append((e.pc_ts, m.group(1)))

    if len(evts) < 2:
        print('  NOTE_ON 不足。')
        return None

    # 50ms 窓で同時発音クラスタを形成
    clusters = []
    cur = [evts[0]]
    for i in range(1, len(evts)):
        if evts[i][0] - cur[-1][0] < 0.050:
            cur.append(evts[i])
        else:
            if len(set(n for _, n in cur)) >= 2:
                clusters.append(cur)
            cur = [evts[i]]
    if len(set(n for _, n in cur)) >= 2:
        clusters.append(cur)

    if not clusters:
        print('  複数ノード同時発音が見つかりません。')
        print('  headRestBeats の関係で全ノード同時は拍 25 以降。')
        return None

    diffs = [max(t for t, _ in c) - min(t for t, _ in c)
             for c in clusters]
    diffs_ms = [d * 1000 for d in diffs]

    print(f'  同時発音クラスタ: {len(clusters)}')
    print(f'  平均同期誤差:     {statistics.mean(diffs_ms):.1f} ms')
    print(f'  最大同期誤差:     {max(diffs_ms):.1f} ms')

    ok = max(diffs_ms) <= 20
    print(f'  判定: {"PASS" if ok else "FAIL"}')
    return ok


# ── MOP5: 指揮→楽器 通信遅延 ──
def mop5(entries):
    _header('MOP5: 指揮→楽器 通信遅延 (<= 30 ms)')
    print('  参考値: USB 受信時刻の差で絶対片道遅延は測れない。')
    print('  正式判定は MOP_TEST=5 ビルド + mop5_comm_delay.py (lateMs 方式) を使う。')
    cond = {}
    for e in entries:
        m = RE_BEAT_N1.search(e.text)
        if m:
            cond[int(m.group(1))] = e.pc_ts

    inst = defaultdict(dict)
    for e in entries:
        m = RE_BEAT_NX.search(e.text)
        if m:
            inst[m.group(1)][int(m.group(2))] = e.pc_ts

    if not cond or not inst:
        print('  指揮者・楽器両方の EVT BEAT が必要。')
        return None

    all_delays = []
    for node, beats in sorted(inst.items()):
        delays = []
        for bno, its in beats.items():
            if bno in cond:
                d = (its - cond[bno]) * 1000
                if d >= 0:
                    delays.append(d)
        if delays:
            print(f'  node_{node}: 平均={statistics.mean(delays):.1f}ms '
                  f'最大={max(delays):.1f}ms (n={len(delays)})')
            all_delays.extend(delays)

    if not all_delays:
        print('  同一 beatNo のペアなし。')
        return None

    mx = max(all_delays)
    print(f'  全体最大: {mx:.1f} ms  (USB 遅延 ~1-3ms を含む)')
    ok = mx <= 30
    print(f'  判定: {"PASS" if ok else "FAIL"}')
    return ok


# ── MOP6: テンポ追従の遅延 ──
def mop6(entries):
    _header('MOP6: テンポ追従の遅延 (<= 2 拍)')
    cbeats = []
    for e in entries:
        m = RE_BEAT_N1.search(e.text)
        if m:
            cbeats.append((e.pc_ts, int(m.group(1)), float(m.group(4))))

    ibpms = defaultdict(list)
    for e in entries:
        m = RE_CTRL.search(e.text)
        if m:
            ibpms[m.group(1)].append((e.pc_ts, float(m.group(2))))

    if len(cbeats) < 5:
        print('  拍データ不足。テンポ変更を含むテストを実行してください。')
        return None

    # BPM 10% 以上の変化を検出
    changes = []
    for i in range(1, len(cbeats)):
        old, new = cbeats[i - 1][2], cbeats[i][2]
        if old > 0 and abs(new - old) / old > 0.10:
            changes.append((cbeats[i][0], cbeats[i][1], old, new))

    if not changes:
        print('  テンポ変化未検出。指揮テンポを大きく変えてください。')
        return None

    max_delay = 0
    for ts, bno, old_bpm, new_bpm in changes:
        tol = abs(new_bpm) * 0.15
        for node, bpms in sorted(ibpms.items()):
            after = [(t, b) for t, b in bpms if t > ts]
            for t, b in after:
                if abs(b - new_bpm) <= tol:
                    dt = t - ts
                    beat_iv = 60.0 / new_bpm
                    delay_beats = dt / beat_iv
                    max_delay = max(max_delay, delay_beats)
                    print(f'  beat {bno} ({old_bpm:.0f}->{new_bpm:.0f}): '
                          f'node_{node} {delay_beats:.1f} 拍で追従')
                    break

    ok = max_delay <= 2
    print(f'  最大追従遅延: {max_delay:.1f} 拍')
    print(f'  判定: {"PASS" if ok else "FAIL"}')
    return ok


# ── MOP7: 起動時間 ──
def mop7(entries):
    _header('MOP7: 起動時間 (<= 5 s)')
    boot = {}
    init = {}
    wifi = {}
    sync = {}
    fbeat = {}

    for e in entries:
        m = RE_BOOT.search(e.text)
        if m:
            n = m.group(1)
            boot.setdefault(n, e.pc_ts)
        m = RE_INIT_DONE.search(e.text)
        if m:
            init.setdefault(m.group(1), e.pc_ts)
        m = RE_WIFI.search(e.text)
        if m:
            wifi.setdefault(m.group(1), e.pc_ts)
        m = RE_SYNC.search(e.text)
        if m:
            sync.setdefault(m.group(1), e.pc_ts)
        m = RE_BEAT_NX.search(e.text)
        if m:
            fbeat.setdefault(m.group(1), e.pc_ts)

    if not boot:
        print('  boot メッセージなし。ノードを電源入れ直してからログ収集してください。')
        return None

    max_startup = 0
    for n in sorted(boot):
        t0 = boot[n]
        print(f'  node_{n}:')
        if n in init:
            print(f'    INIT 完了:     {(init[n] - t0) * 1000:.0f} ms')
        if n in wifi:
            print(f'    WiFi 接続:     {(wifi[n] - t0) * 1000:.0f} ms')
        if n in sync:
            print(f'    同期収束:      {(sync[n] - t0) * 1000:.0f} ms')

        ready = None
        if n == '1':
            ready = wifi.get(n)
        else:
            ready = fbeat.get(n)

        if ready:
            dt = ready - t0
            max_startup = max(max_startup, dt)
            print(f'    演奏可能まで:  {dt:.1f} 秒')

    if max_startup > 0:
        ok = max_startup <= 5
        print(f'  最大起動時間: {max_startup:.1f} 秒')
        print(f'  判定: {"PASS" if ok else "FAIL"}')
        return ok

    print('  演奏可能時刻を特定できませんでした。')
    return None


# ── MOP8: CPU 負荷 ──
def mop8(entries):
    _header('MOP8: CPU 負荷 入力フェーズ (<= 2 ms)')
    perf = defaultdict(list)
    for e in entries:
        m = RE_PERF.search(e.text)
        if m:
            perf[m.group(1)].append(int(m.group(2)))

    if not perf:
        print('  [PERF] ログなし。検証用ファーム (firmware/) を使用してください。')
        return None

    worst = 0
    for n, times in sorted(perf.items()):
        mx = max(times)
        worst = max(worst, mx)
        print(f'  node_{n}: 平均={statistics.mean(times):.0f}us '
              f'最大={mx}us ({mx / 1000:.2f}ms)  n={len(times)}')

    ok = worst / 1000 <= 2.0
    print(f'  全体最大: {worst}us ({worst / 1000:.2f}ms)')
    print(f'  判定: {"PASS" if ok else "FAIL"}')
    return ok


# ── MOP9: パケットロス耐性 ──
def mop9(entries):
    _header('MOP9: パケットロス耐性 (ロス <= 5%)')
    beats = defaultdict(list)
    for e in entries:
        m = RE_BEAT_NX.search(e.text)
        if m:
            beats[m.group(1)].append(int(m.group(2)))

    if not beats:
        print('  楽器の EVT BEAT なし。')
        return None

    ok = True
    for n, seq in sorted(beats.items()):
        if len(seq) < 2:
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

        print(f'  node_{n}: 期待={total} 受信={received} '
              f'欠落={missed} ({pct:.1f}%)')
        if gap_str:
            print(f'    {gap_str}')

        if pct > 5:
            ok = False

    # NOTE_ON の最大無音区間
    note_ts = [e.pc_ts for e in entries if RE_NOTE_ON.search(e.text)]
    if len(note_ts) >= 2:
        max_gap = max(note_ts[i] - note_ts[i - 1] for i in range(1, len(note_ts)))
        print(f'  NOTE_ON 最大間隔: {max_gap * 1000:.0f} ms')

    print(f'  判定: {"PASS" if ok else "FAIL"}')
    return ok


def main():
    parser = argparse.ArgumentParser(description='MOE/MOP 全9項目 検証解析')
    parser.add_argument('logfile', help='serial_logger.py の出力ファイル')
    parser.add_argument('--expected-bpm', type=float, default=None,
                        help='MOP1: テスト時の期待 BPM')
    parser.add_argument('--test-duration', type=float, default=None,
                        help='MOP1: テスト時間 (秒)')
    args = parser.parse_args()

    if not os.path.exists(args.logfile):
        print(f'ファイルが見つかりません: {args.logfile}', file=sys.stderr)
        sys.exit(1)

    entries = parse_log(args.logfile)
    print(f'ログエントリ数: {len(entries)}')

    results = {}
    results['MOP1'] = mop1(entries, args.expected_bpm, args.test_duration)
    results['MOP2'] = mop2(entries)
    results['MOP3'] = mop3(entries)
    results['MOP4'] = mop4(entries)
    results['MOP5'] = mop5(entries)
    results['MOP6'] = mop6(entries)
    results['MOP7'] = mop7(entries)
    results['MOP8'] = mop8(entries)
    results['MOP9'] = mop9(entries)

    _header('判定サマリ')
    for name, r in results.items():
        if r is True:
            s = 'PASS'
        elif r is False:
            s = 'FAIL'
        else:
            s = 'N/A'
        print(f'  {name}: {s}')

    pc = sum(1 for r in results.values() if r is True)
    fc = sum(1 for r in results.values() if r is False)
    nc = sum(1 for r in results.values() if r is None)
    print(f'\n  PASS={pc}  FAIL={fc}  N/A={nc}')

    sys.exit(0 if fc == 0 else 1)


if __name__ == '__main__':
    main()
