#!/usr/bin/env python3
"""
MOP5: 発音予約の遅刻計測 (lateMs) — beatLookahead 45ms に間に合っているか

指標の再定義について:
  計画書の MOP5「指揮から楽器への通信遅延 ≤30ms」(絶対片道遅延) は、
  片方向の時計同期 (EMA が平均遅延を吸収する) では原理的に計測できない
  (詳細: results/MOP45_latency_investigation_20260710.md §4.1/§5-C)。
  絶対片道遅延の実測 (GPIO トグル + ロジックアナライザ / 往復同期) は将来課題とし、
  本スクリプトは「BEAT が beatLookahead (45ms) の発音予約に間に合っているか」を
  検証可能な形で定量化する:

    lateMs = max(0, localMasterMs - playAtMasterMs)
      - 受信時 (M45R): 受信時点で既に発音予定時刻を過ぎていた遅れ。
        0 なら予約が機能し、>0 なら到着即発火 (予約破綻) だった拍。
      - 発火時 (M45F): 実際の発音が予定時刻からどれだけ遅れたか。

  判定は「発火 lateMs の p95 ≤ 閾値 (デフォルト 30ms = 計画書 MOP5 の目標値を
  発音予定時刻に対する遅刻の許容として流用)」とする。

入力: serial_logger.py が保存したログファイル (行形式 "pc_ts port text")。
      MOP_TEST=5 (または 4) でビルドした楽器ノードのログ。
      行中の M45R/M45F を正規表現で拾うため pio device monitor の生ログでも解析できる。

ファーム側ログ形式 (MOP_TEST=4/5 共通):
  M45R,<partId>,<beatNo>,<playAtMasterMs>,<deviceMs>,<offsetMs>,<localMasterMs>
    - BEAT を受理 (連送の初回のみ = 1 拍 1 行) した時点の記録 (OrcReceiverModule.cpp)
  M45F,<partId>,<beatNo>,<playAtMasterMs>,<deviceMs>,<offsetMs>,<localMasterMs>
    - 発音予約が発火した時点の記録 (applyPattern.cpp)

使い方:
  python3 scripts/mop5_comm_delay.py logs/test_YYYYMMDD_HHMMSS.log
"""

import argparse
import re
import statistics
import sys
from collections import defaultdict

import common

THRESHOLD_MS = 30      # 発火 lateMs p95 の許容値 (計画書 MOP5 の 30ms を流用)
NOMINAL_LOOKAHEAD_MS = 45  # 指揮者 ProjectConfig.h beatLookaheadMs の名目値

# M45R / M45F 共通:
#   M45<kind>,<partId>,<beatNo>,<playAtMasterMs>,<deviceMs>,<offsetMs>,<localMasterMs>
RE_M45 = re.compile(
    r'\bM45([RF]),(\d+),(\d+),(\d+),(\d+),(-?\d+),(\d+)\b')


def parse_log(log_path):
    """ログから M45R/M45F を読む。

    返り値: {kind: {(beatNo, playAtMasterMs): {partId: record}}}, 重複件数
      kind は 'R' (受信) / 'F' (発火)。同一拍はマスタ時刻 playAtMasterMs が
      全ノード共通なので (beatNo, playAt) キーで指揮者リセットにも頑健。
      同一 (種別, 拍, ノード) の重複行は初出のみ採用する。
    """
    records = {'R': defaultdict(dict), 'F': defaultdict(dict)}
    duplicates = 0
    with open(log_path, errors='replace') as f:
        for line in f:
            m = RE_M45.search(line)
            if not m:
                continue
            kind = m.group(1)
            part = int(m.group(2))
            play_at = int(m.group(4))
            local_master = int(m.group(7))
            rec = {
                'beatNo': int(m.group(3)),
                'playAtMasterMs': play_at,
                'deviceMs': int(m.group(5)),
                'offsetMs': int(m.group(6)),
                'localMasterMs': local_master,
                # marginMs > 0 = 予定時刻より手前 (余裕あり) / < 0 = 遅刻
                'marginMs': play_at - local_master,
                'lateMs': max(0, local_master - play_at),
            }
            key = (rec['beatNo'], play_at)
            if part in records[kind][key]:
                duplicates += 1
                continue
            records[kind][key][part] = rec
    return records, duplicates


def flatten(kind_records):
    """{key: {part: rec}} → [rec] (partId を付与)。"""
    out = []
    for key in sorted(kind_records.keys()):
        for pid in sorted(kind_records[key].keys()):
            rec = dict(kind_records[key][pid])
            rec['partId'] = pid
            out.append(rec)
    return out


def describe(label, recs, stats_lines):
    """受信/発火それぞれの lateMs・marginMs 統計を stats_lines に追記する。"""
    lates = [r['lateMs'] for r in recs]
    margins = [r['marginMs'] for r in recs]
    n_late = sum(1 for v in lates if v > 0)
    stats_lines.append(f'--- {label} (n={len(recs)}) ---')
    stats_lines.append(
        f'  遅刻 (lateMs>0): {n_late} / {len(recs)} 件'
        f' ({100.0 * n_late / len(recs):.1f}%)')
    stats_lines.append(
        f'  lateMs:   平均={statistics.mean(lates):.1f}'
        f' p50={common.percentile(lates, 50):.1f}'
        f' p95={common.percentile(lates, 95):.1f}'
        f' 最大={max(lates):.1f} ms')
    stats_lines.append(
        f'  marginMs: 平均={statistics.mean(margins):+.1f}'
        f' p50={common.percentile(margins, 50):+.1f}'
        f' 最小={min(margins):+.1f} 最大={max(margins):+.1f} ms'
        f' (正=予定時刻より手前)')


def report_results(records, duplicates, threshold_ms, lookahead_ms, ts):
    common.print_header(
        f'MOP5: 発音予約の遅刻計測 (発火 lateMs p95 <= {threshold_ms} ms)')
    stats_lines = []

    recv = flatten(records['R'])
    fire = flatten(records['F'])

    if duplicates:
        stats_lines.append(f'注意: 同一 (種別, 拍, ノード) の重複記録 {duplicates} 件を初出のみ採用')

    stats_lines.append('指標: 計画書の「通信遅延 ≤30ms」(絶対片道遅延) は片方向同期では')
    stats_lines.append('計測不能のため、「発音予定時刻に対する遅刻 lateMs」で再定義 (ヘッダ参照)。')
    stats_lines.append('')

    if recv:
        describe('BEAT 受信時', recv, stats_lines)
        recv_margins = [r['marginMs'] for r in recv]
        mean_margin = statistics.mean(recv_margins)
        stats_lines.append(
            f'  名目 lookahead {lookahead_ms}ms に対する受信マージン平均: '
            f'{mean_margin:+.1f} ms (系統シフト {mean_margin - lookahead_ms:+.1f} ms)')
        stats_lines.append('')
    else:
        stats_lines.append('M45R (受信記録) なし。')
        stats_lines.append('')

    passed = None
    if fire:
        describe('発火時', fire, stats_lines)
        stats_lines.append('')
        stats_lines.append('--- ノード別 発火 lateMs ---')
        by_node = defaultdict(list)
        for r in fire:
            by_node[r['partId']].append(r['lateMs'])
        for pid in sorted(by_node.keys()):
            vals = by_node[pid]
            n_late = sum(1 for v in vals if v > 0)
            stats_lines.append(
                f'  node_0{pid}: 遅刻 {n_late}/{len(vals)} 件'
                f' p95={common.percentile(vals, 95):.1f}'
                f' 最大={max(vals):.1f} ms')

        fire_lates = [r['lateMs'] for r in fire]
        p95 = common.percentile(fire_lates, 95)
        passed = p95 <= threshold_ms
        stats_lines.append('')
        stats_lines.append(
            f'判定: {"PASS" if passed else "FAIL"} '
            f'(発火 lateMs p95 = {p95:.1f} ms, 閾値 {threshold_ms} ms)')
    else:
        stats_lines.append('M45F (発火記録) なし。判定不能。')

    for line in stats_lines:
        print(f'  {line}')

    summary_path = common.write_summary(
        5, ts, passed if passed is not None else False,
        '\n'.join(stats_lines))
    print(f'\n  Summary: {summary_path}')
    return passed


def main():
    parser = argparse.ArgumentParser(
        description='MOP5: 発音予約の遅刻計測 (M45R/M45F の lateMs) ')
    parser.add_argument('log', help='serial_logger.py のログファイル')
    parser.add_argument('--threshold', type=float, default=THRESHOLD_MS,
                        help=f'発火 lateMs p95 の許容値 ms (デフォルト {THRESHOLD_MS})')
    parser.add_argument('--lookahead', type=float, default=NOMINAL_LOOKAHEAD_MS,
                        help=f'指揮者 beatLookaheadMs の名目値 (デフォルト {NOMINAL_LOOKAHEAD_MS})')
    args = parser.parse_args()

    records, duplicates = parse_log(args.log)
    if not records['R'] and not records['F']:
        print('M45R/M45F 行が見つかりません。MOP_TEST=5 (または 4) でビルドした'
              '楽器ノードのログか確認してください。', file=sys.stderr)
        sys.exit(1)

    ts = common.make_timestamp()
    csv_fields = ['type', 'beatNo', 'partId', 'playAtMasterMs',
                  'deviceMs', 'offsetMs', 'localMasterMs', 'lateMs']
    csv_writer, csv_fh, csv_path = common.open_csv(5, csv_fields, ts)
    try:
        for kind in ('R', 'F'):
            for rec in flatten(records[kind]):
                csv_writer.writerow({
                    'type': kind,
                    'beatNo': rec['beatNo'],
                    'partId': rec['partId'],
                    'playAtMasterMs': rec['playAtMasterMs'],
                    'deviceMs': rec['deviceMs'],
                    'offsetMs': rec['offsetMs'],
                    'localMasterMs': rec['localMasterMs'],
                    'lateMs': rec['lateMs'],
                })
    finally:
        csv_fh.close()
    print(f'CSV: {csv_path}')

    report_results(records, duplicates, args.threshold, args.lookahead, ts)


if __name__ == '__main__':
    main()
