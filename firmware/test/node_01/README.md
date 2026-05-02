# node_01 — 指揮者ノード (テスト版)

XIAO ESP32-S3 Sense + MPU6050 (GY-521) で「指揮棒」を作るテスト用実装。
仕様書 (`meetings/0429_3回/事前課題共有/arduino_塩澤.pdf`) §2.4.2 に準拠。

## 仕様の核

- 役割: IMU から振り下ろしを検出し、CTRL (20 Hz) と BEAT (拍検出時) を
  WiFi UDP マルチキャストで楽器ノードに配信する
- WiFi: 自身が SoftAP `OrchestraAP` / `orchestra2026` を起動
- マルチキャスト: `239.0.0.1:5001`
- 状態: Idle → Calibrating (起動から 2 秒) → Conducting → (異常時) Fallback
- 拍検出: 加速度ノルムが 1.80 g を超え、不応期 250 ms 経過で拍確定
- テンポ推定: 拍間隔 → 瞬時 BPM → EMA (α=0.30) で平滑化

## 配線 (GY-521 ↔ XIAO ESP32-S3 Sense)

| GY-521 | XIAO ESP32-S3 Sense |
|---|---|
| VCC  | 3V3 |
| GND  | GND |
| SDA  | D4 (GPIO5) |
| SCL  | D5 (GPIO6) |
| AD0  | GND (I2C アドレス 0x68 固定) |
| INT  | 未接続 |

## ビルド

```bash
cd firmware/test/node_01
pio run                  # ビルド
pio run -t upload        # 書き込み
pio device monitor       # シリアルモニタ
```

## 構成

```
node_01/
├── platformio.ini
├── include/
│   ├── ProjectConfig.h    # ピン/定数/閾値の集約
│   └── SystemData.h       # モジュール間共有データ
├── src/
│   ├── main.cpp           # 3 フェーズループのエントリ
│   └── applyPattern.cpp   # 拍検出/テンポ推定/状態遷移
└── lib/
    ├── ImuModule/         # MPU6050 を I2C で読む
    └── OrcSenderModule/   # CTRL/BEAT をパケット化して送信予約
```

共通モジュール (`OrcNetModule` `StatusLedModule` `OrcProtocol` `ModuleCore`) は
`firmware/test/common/lib/` を `lib_extra_dirs` 経由で参照する。
