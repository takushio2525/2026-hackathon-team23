#!/usr/bin/env python3
"""
複数シリアルポートを同時に開いてログを収集するスクリプト。
各行に PC 側タイムスタンプとポート名を付与して保存する。

使い方:
  python3 serial_logger.py [--baud 115200] [--output logs/test_YYYYMMDD_HHMMSS.log]
  python3 serial_logger.py --ports /dev/cu.usbmodem1234 /dev/cu.usbmodem5678

ポートを指定しなければ USB シリアルデバイスを自動検出する。
Ctrl+C で停止。
"""

import argparse
import os
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


def read_serial(port_name, baud, log_file, lock, stop_event):
    """1 ポート分のシリアル読み取りスレッド"""
    try:
        ser = serial.Serial(port_name, baud, timeout=0.1)
    except serial.SerialException as e:
        with lock:
            msg = f"# ERROR: {port_name}: {e}\n"
            sys.stderr.write(msg)
            log_file.write(msg)
        return

    with lock:
        msg = f"# OPENED: {port_name} @ {baud}bps\n"
        print(msg, end='')
        log_file.write(msg)

    try:
        while not stop_event.is_set():
            try:
                line = ser.readline()
            except serial.SerialException:
                break
            if not line:
                continue
            try:
                text = line.decode('utf-8', errors='replace').rstrip('\r\n')
            except Exception:
                continue
            if not text:
                continue
            ts = time.time()
            entry = f"{ts:.6f} {port_name} {text}\n"
            with lock:
                print(f"  {port_name}: {text}")
                log_file.write(entry)
                log_file.flush()
    finally:
        ser.close()
        with lock:
            msg = f"# CLOSED: {port_name}\n"
            print(msg, end='')
            log_file.write(msg)


def main():
    parser = argparse.ArgumentParser(description='複数シリアルポート同時ログ収集')
    parser.add_argument('--baud', '-b', type=int, default=115200,
                        help='ボーレート (デフォルト: 115200)')
    parser.add_argument('--output', '-o', type=str, default=None,
                        help='出力ファイルパス (デフォルト: logs/test_YYYYMMDD_HHMMSS.log)')
    parser.add_argument('--ports', '-p', nargs='*',
                        help='ポートを手動指定 (省略時は自動検出)')
    args = parser.parse_args()

    if args.ports:
        ports = args.ports
    else:
        ports = find_usb_serial_ports()
        if not ports:
            print("USB シリアルポートが見つかりません。--ports で手動指定してください。",
                  file=sys.stderr)
            sys.exit(1)

    print(f"ポート: {', '.join(ports)}")

    if args.output:
        output_path = args.output
    else:
        log_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'logs')
        os.makedirs(log_dir, exist_ok=True)
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_path = os.path.join(log_dir, f'test_{timestamp}.log')

    print(f"ログ出力: {output_path}")
    print("Ctrl+C で停止\n")

    lock = threading.Lock()
    stop_event = threading.Event()

    with open(output_path, 'w') as log_file:
        log_file.write(f"# Serial Logger — {datetime.now().isoformat()}\n")
        log_file.write(f"# Baud: {args.baud}\n")
        log_file.write(f"# Ports: {', '.join(ports)}\n\n")

        threads = []
        for port in ports:
            t = threading.Thread(
                target=read_serial,
                args=(port, args.baud, log_file, lock, stop_event),
                daemon=True,
            )
            t.start()
            threads.append(t)

        try:
            while True:
                time.sleep(0.5)
        except KeyboardInterrupt:
            print("\n停止中...")
            stop_event.set()
            for t in threads:
                t.join(timeout=2.0)

    print(f"ログ保存完了: {output_path}")


if __name__ == '__main__':
    main()
