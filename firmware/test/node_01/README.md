# node_01 — 指揮者ノード (テスト版)

XIAO ESP32-S3 Sense + MPU6050 (GY-521) で「指揮棒」を作るテスト用実装。
仕様書 (`meetings/0429_3回/事前課題共有/arduino_塩澤.pdf`) §2.4.2 に準拠。

## 仕様の核

- 役割: IMU から振り下ろしを検出し、CTRL (20 Hz) と BEAT (拍検出時) を
  WiFi UDP マルチキャストで楽器ノードに配信する
- WiFi: 自身が SoftAP `OrchestraAP` / `orchestra2026` を起動
- マルチキャスト: `239.0.0.1:5001`
- 状態: Idle → Calibrating (SoftAP 起動後 2 秒) → Conducting → (異常時) Fallback
- キャリブレーション: Calibrating の 2 秒間、生加速度の**ノルム**を平均して
  「静止ノルム ≒ 重力 1 g」をスカラー 1 個として保持する。軸ごとの重力ベクトル
  補正はしないので、校正時の姿勢と振るときの姿勢が違っても残留重力で誤検出しない
- 拍検出: **動加速度ノルム** `dynNorm` (= LPF 後の加速度ノルム − 静止ノルム) が
  1.20 g を超えると Armed に遷移し、Armed 中の擬似経路長 (`dynNorm` 方向に向けた
  `dynAcc` を時間積分した速度の絶対値をさらに時間積分した値) が 0.20 m に達した瞬間に
  拍を発火する**早期発火方式**。発火後も Armed は維持し、動加速度がピークの 40 % を
  割る・ノルムが 0.20 g 未満になる・Armed 開始から 800 ms 経過のいずれかでリリース
  判定 (40 ms デバウンス) して Idle に戻る。
  不応期 350 ms (≒170 BPM 上限) で連続スイングの 2 重発火も防止
- テンポ推定: 拍間隔 → 瞬時 BPM → EMA (α=0.30) で平滑化、40–240 BPM にクランプ

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

## シリアルデバッグ出力 (SERIAL_DEBUG)

`platformio.ini` の `-DSERIAL_DEBUG=1` (既定) でデバッグ出力が有効。
`pio device monitor` を開くと以下が流れる:

- 起動時: 各モジュール `init()` の OK/NG
- 周期 (200 ms): `[N1 t=… st=Conducting wifi=1 imu=1 acc=(…) n=… dyn=… peakRaw=… peakDyn=… bpm=… beatNo=… ctrlSeq=… beatSeq=…]`
  - `n` = LPF 後ノルム (重力込み)、`dyn` = 動加速度ノルム (拍判定対象)
  - `peakRaw` / `peakDyn` = 直近 200 ms 区間内の最大値 (毎ダンプ後リセット)
- イベント: `[N1 EVT STATE]` 状態遷移 / `[N1 EVT WIFI]` リンク変化 /
  `[N1 EVT BEAT]` 拍検出時の no/playAt/bpm

無効化したいときは `-DSERIAL_DEBUG=0` に変更。マクロが空展開されるので
コードサイズも実行時コストも 0 になる。

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
