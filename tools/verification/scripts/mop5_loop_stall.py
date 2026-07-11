#!/usr/bin/env python3
"""
MOP5 補助: ループストール (M45S) の簡易集計 — 粒度・分布・バースト位相との相関

背景 (results/MOP5_countermeasure_eval_20260710.md §3.3/§5(b)-2):
  7/10-11 の再計測で、バースト到着から位相 ~120〜165ms の区間で発火が消える
  「周期ストール」(発火 lateMs p95 47ms・MOP4 尾悪化の共通原因) が観測された。
  楽器ファーム (MOP_TEST=4/5) は OrcReceiverModule::updateInput のハートビートで
  ループ 1 周が 10ms を超えた区間を 1 行記録する:

    M45S,<partId>,<deviceMs>,<gapMs>
      - deviceMs = ストール明け (今回呼び出しの millis())
      - gapMs    = 前回呼び出しからの経過 (= ループが回らなかった時間)

  本スクリプトは M45S を集計し、(a) ストールの粒度 (単一の長ブロックか短い
  ブロックの連なりか)、(b) バースト格子に対する位相 (どの位相で止まるか)、
  (c) 発火遅刻 (M45F の lateMs>0) との時間相関を出す。判定 (PASS/FAIL) はしない。

位相の基準: 同一ノードの直近 M45R (BEAT 受信 = バースト到着) の deviceMs を格子
  アンカーとし、経過を 204.8ms (実測バースト周期) で折り返す。拍間隔 ~500ms・
  クロックスキュー ≤0.3% なので折り返し誤差は ~1.5ms に収まる。

使い方:
  python3 scripts/mop5_loop_stall.py logs/test_YYYYMMDD_HHMMSS.log
"""

import argparse
import bisect
import re
import statistics
import sys
from collections import defaultdict

import common

BURST_PERIOD_MS = 204.8   # 実測バースト周期 (SoftAP DTIM フラッシュ)
PHASE_BIN_MS = 10

RE_M45S = re.compile(r'\bM45S,(\d+),(\d+),(\d+)\b')
RE_M45R = re.compile(r'\bM45R,(\d+),(\d+),(\d+),(\d+),(-?\d+),(\d+)\b')
RE_M45F = re.compile(r'\bM45F,(\d+),(\d+),(\d+),(\d+),(-?\d+),(\d+)\b')


def parse_log(log_path):
    """M45S / M45R / M45F を partId 別に読む。"""
    stalls = defaultdict(list)   # part -> [(deviceMs, gapMs)]
    recvs = defaultdict(list)    # part -> [deviceMs] (バースト到着アンカー)
    fires = defaultdict(list)    # part -> [(deviceMs, lateMs)]
    with open(log_path, errors='replace') as f:
        for line in f:
            m = RE_M45S.search(line)
            if m:
                stalls[int(m.group(1))].append(
                    (int(m.group(2)), int(m.group(3))))
                continue
            m = RE_M45R.search(line)
            if m:
                recvs[int(m.group(1))].append(int(m.group(4)))
                continue
            m = RE_M45F.search(line)
            if m:
                late = max(0, int(m.group(6)) - int(m.group(3)))
                fires[int(m.group(1))].append((int(m.group(4)), late))
    for part in recvs:
        recvs[part].sort()
    return stalls, recvs, fires


def phase_of(dev_ms, anchors):
    """直近の受信アンカーからの経過を バースト周期 で折り返した位相 [0, P)。"""
    i = bisect.bisect_right(anchors, dev_ms)
    if i == 0:
        return None   # アンカー前 (起動直後) は位相を定義できない
    return (dev_ms - anchors[i - 1]) % BURST_PERIOD_MS


def main():
    parser = argparse.ArgumentParser(
        description='MOP5 補助: ループストール (M45S) の簡易集計')
    parser.add_argument('log', help='serial_logger.py のログファイル')
    args = parser.parse_args()

    stalls, recvs, fires = parse_log(args.log)
    if not stalls:
        print('M45S 行が見つかりません。ストール検出付き MOP_TEST=4/5 ビルド'
              ' (2026-07-11 以降の楽器ファーム) のログか確認してください。',
              file=sys.stderr)
        sys.exit(1)

    common.print_header('MOP5 補助: ループストール (M45S) 集計')

    # (a) ノード別: 件数・gap 分布 (粒度)
    print('  --- ノード別 gap 分布 (粒度: 長 gap 少数=単一ブロック /'
          ' 短 gap 多数=細切れ) ---')
    for part in sorted(stalls):
        gaps = [g for _, g in stalls[part]]
        dur_s = None
        if recvs.get(part):
            dur_s = (recvs[part][-1] - recvs[part][0]) / 1000.0
        rate = f' {len(gaps)/dur_s:.1f} 件/s' if dur_s else ''
        print(f'  node_0{part}: n={len(gaps)}{rate}'
              f' gap 平均={statistics.mean(gaps):.1f}'
              f' p50={common.percentile(gaps, 50):.0f}'
              f' p95={common.percentile(gaps, 95):.0f}'
              f' 最大={max(gaps)} ms'
              f' 合計={sum(gaps)} ms')

    # (b) バースト格子に対する位相 (ストール開始/終了)
    print('  --- ストール位相 (直近 M45R 起点、'
          f'{PHASE_BIN_MS}ms ビン、全ノード合算) ---')
    start_hist = defaultdict(int)
    end_hist = defaultdict(int)
    n_phased = 0
    for part, rows in stalls.items():
        anchors = recvs.get(part, [])
        if not anchors:
            continue
        for dev, gap in rows:
            ph_end = phase_of(dev, anchors)
            if ph_end is None:
                continue
            n_phased += 1
            ph_start = (ph_end - gap) % BURST_PERIOD_MS
            end_hist[int(ph_end // PHASE_BIN_MS)] += 1
            start_hist[int(ph_start // PHASE_BIN_MS)] += 1
    n_bins = int(BURST_PERIOD_MS // PHASE_BIN_MS) + 1
    for label, hist in (('開始', start_hist), ('終了', end_hist)):
        line = ' '.join(f'{b*PHASE_BIN_MS}:{hist.get(b, 0)}'
                        for b in range(n_bins) if hist.get(b, 0))
        print(f'  {label}: {line}  (n={n_phased}, 一様なら各ビン'
              f'≈{n_phased/n_bins:.0f})')

    # (c) 発火遅刻との相関: late>15ms の発火の直前 (gap 終了から 20ms 以内) に
    #     ストール明けがあった割合
    print('  --- 発火遅刻との相関 ---')
    for part in sorted(fires):
        stall_ends = sorted(dev for dev, _ in stalls.get(part, []))
        late_fires = [(dev, late) for dev, late in fires[part] if late > 15]
        if not late_fires:
            print(f'  node_0{part}: late>15ms の発火なし')
            continue
        covered = 0
        for dev, late in late_fires:
            i = bisect.bisect_right(stall_ends, dev)
            if i > 0 and dev - stall_ends[i - 1] <= 20:
                covered += 1
        print(f'  node_0{part}: late>15ms 発火 {len(late_fires)} 件中、'
              f'直前 20ms 以内にストール明けあり {covered} 件'
              f' ({100.0 * covered / len(late_fires):.0f}%)')


if __name__ == '__main__':
    main()
