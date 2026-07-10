#!/usr/bin/env python3
"""
MOP 検証スクリプト共通モジュール。
シリアルポート検出・ノード名自動判定・CSV 書き出し・タイムスタンプ生成を提供する。
"""

import csv
import os
import re
import sys
import time
import threading
from datetime import datetime

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("pyserial が必要です: pip install pyserial", file=sys.stderr)
    sys.exit(1)

# シリアル出力の [N1, [N2, ... プレフィックスからノード番号を抽出する正規表現
RE_NODE_PREFIX = re.compile(r'\[N(\d)')

# ── ポート検出 ──

def find_usb_serial_ports():
    """USB シリアルポートを自動検出して返す"""
    ports = []
    for p in serial.tools.list_ports.comports():
        name = p.device.lower()
        if any(k in name for k in (
            'usbmodem', 'usbserial', 'ttyusb', 'ttyacm', 'cu.wchusbserial',
        )):
            ports.append(p.device)
    return sorted(ports)


# ── ノード名マッピング ──

class NodeMapper:
    """ポート名 → ノード名 (node_01 等) の自動マッピング。

    シリアルから最初に受信した [N1, [N2 等のプレフィックスで判定する。
    判定前は短縮ポート名を返し、判定後はノード名に切り替わる。
    """

    def __init__(self):
        self._map = {}       # port -> "node_0X"
        self._lock = threading.Lock()

    def try_detect(self, port, text):
        """テキスト行からノード番号を検出してマッピングに登録する。
        既に登録済みのポートは無視する。"""
        with self._lock:
            if port in self._map:
                return
        m = RE_NODE_PREFIX.search(text)
        if m:
            node_name = f"node_0{m.group(1)}"
            with self._lock:
                self._map[port] = node_name

    def get_name(self, port):
        """ポートに対応するノード名を返す。未判定なら短縮ポート名。"""
        with self._lock:
            if port in self._map:
                return self._map[port]
        # /dev/cu.usbmodemXXXX → usbmodemXXXX
        base = os.path.basename(port)
        if base.startswith('cu.'):
            base = base[3:]
        return base

    def get_all(self):
        """現在のマッピング全体を返す (コピー)。"""
        with self._lock:
            return dict(self._map)


# ── CSV 書き出し ──

def results_dir(mop_number):
    """MOP 番号に対応する results ディレクトリパスを返す。なければ作成する。"""
    base = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        'results', f'mop{mop_number}')
    os.makedirs(base, exist_ok=True)
    return base


def make_timestamp():
    """ファイル名用タイムスタンプ文字列を返す (YYYYMMDD_HHMMSS)。"""
    return datetime.now().strftime('%Y%m%d_%H%M%S')


def open_csv(mop_number, fieldnames, timestamp=None):
    """MOP 結果 CSV を開き、(writer, file_handle, path) を返す。
    呼び出し側が file_handle.close() する責任を持つ。"""
    if timestamp is None:
        timestamp = make_timestamp()
    path = os.path.join(results_dir(mop_number), f'{timestamp}.csv')
    fh = open(path, 'w', newline='')
    writer = csv.DictWriter(fh, fieldnames=fieldnames)
    writer.writeheader()
    return writer, fh, path


def write_summary(mop_number, timestamp, passed, stats_text):
    """PASS/FAIL 判定と統計テキストを summary ファイルに書く。
    passed が None の場合は「判定なし」として記録する。"""
    path = os.path.join(results_dir(mop_number),
                        f'{timestamp}_summary.txt')
    if passed is None:
        verdict = '判定なし (--bpm 未指定)'
    elif passed:
        verdict = 'PASS'
    else:
        verdict = 'FAIL'
    with open(path, 'w') as f:
        f.write(f"MOP{mop_number} — {datetime.now().isoformat()}\n")
        f.write(f"判定: {verdict}\n\n")
        f.write(stats_text)
    return path


# ── シリアル読み取りヘルパー ──

def open_serial(port, baud=115200):
    """シリアルポートを開いて返す。失敗時は None。"""
    try:
        return serial.Serial(port, baud, timeout=0.1)
    except serial.SerialException as e:
        print(f"  ERROR: {port}: {e}", file=sys.stderr)
        return None


def read_line(ser):
    """シリアルから 1 行読んで UTF-8 文字列で返す。データなしなら None。"""
    try:
        raw = ser.readline()
    except serial.SerialException:
        return None
    if not raw:
        return None
    try:
        return raw.decode('utf-8', errors='replace').rstrip('\r\n')
    except Exception:
        return None


# ── 統計ヘルパー ──

def percentile(data, p):
    """リストから第 p パーセンタイルを線形補間で返す (numpy 不要版)。"""
    if not data:
        return 0.0
    s = sorted(data)
    k = (len(s) - 1) * p / 100.0
    f = int(k)
    c = f + 1 if f + 1 < len(s) else f
    return s[f] + (s[c] - s[f]) * (k - f)


# ── 表示ヘルパー ──

def print_header(title):
    """セクションヘッダを表示する。"""
    print(f"\n{'=' * 60}")
    print(title)
    print('=' * 60)


def print_ports(ports, node_mapper=None):
    """検出したポート一覧を表示する。"""
    print(f"検出ポート数: {len(ports)}")
    for p in ports:
        name = node_mapper.get_name(p) if node_mapper else p
        print(f"  {name} ({p})")
