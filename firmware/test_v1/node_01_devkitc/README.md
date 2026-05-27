# node_01_devkitc — 指揮者ノード (DevKitC アンテナ切り分け版)

ESP32-S3-DevKitC-1 (PCB 内蔵アンテナ / WROOM-1 N 版) + MPU6050 (GY-521) で
指揮棒を作る、`node_01` (XIAO ESP32-S3 Sense / 外付け IPEX アンテナ) と
**同一ロジックの派生ファーム**。test_v1 で 5/11 以降 UDP パケロスが多発する
症状の原因がアンテナ起因かどうかを切り分けるために用意した。

## なぜ作ったか

`firmware/test_v1/node_01` (XIAO ESP32-S3 Sense) は外付け IPEX アンテナを
使用しており、コネクタの半挿し・半田クラック・基板裏の 0Ω アンテナ切替を
含めて電波経路に「壊れる/接触不良になる」要素が複数ある。同一ロジックを
PCB 内蔵アンテナのボードで動かして UDP パケロスを比較すれば、原因が

- (A) RF 経路 (アンテナ・コネクタ・整合回路)
- (B) WiFi 環境 (チャンネル混雑等)
- (C) ファーム/プロトコル

のどこに集中しているか切り分けられる。(A) であれば DevKitC 版は明らかに
ロスが減るはず。

## node_01 との差分

ロジック (`src/`, `lib/`, `include/SystemData.h`) は **完全に同一**。
差分はビルド設定とコメントのみ。

| 項目 | node_01 (XIAO) | node_01_devkitc (DevKitC) |
|---|---|---|
| board | `seeed_xiao_esp32s3` | `esp32-s3-devkitc-1` |
| アンテナ | 外付け IPEX (W.FL) | PCB 内蔵 (WROOM-1) |
| USB CDC on Boot | 有効 (`-DARDUINO_USB_*`) | 無効 (UART ブリッジ経由) |
| upload_protocol | `esp-builtin` (USB JTAG) | PIO デフォルト (esptool / UART) |
| User LED | GPIO21 単色 active LOW | GPIO48 WS2812 (digitalWrite では光らない) |
| I2C ピン GPIO 番号 | GPIO5/GPIO6 | **同一 GPIO5/GPIO6** (左列に配置) |

## 配線 (GY-521 ↔ ESP32-S3-DevKitC-1 左列)

ブレッドボード配線のため、DevKitC の **左列ピンヘッダ** から I2C を取り出す。

| GY-521 | DevKitC ピン | 備考 |
|---|---|---|
| VCC  | 3V3 | 左列 最上段 |
| GND  | GND | 左列 最下段 |
| SDA  | GPIO5 | 左列 上から 5 番目 |
| SCL  | GPIO6 | 左列 上から 6 番目 |
| AD0  | GND | I2C アドレス 0x68 固定 |
| INT  | 未接続 | |

左列の並びは上から `3V3, 3V3, RST, GPIO4, GPIO5, GPIO6, GPIO7, GPIO15, ...`
の順なので、GY-521 を DevKitC の真横に並べてジャンパ 4 本で配線できる。
GPIO5/GPIO6 はストラッピングピンではないため I2C で安全に使える。

## ビルド・書き込み

```bash
# プロジェクトルートから
pio run -d firmware/test_v1/node_01_devkitc
pio run -d firmware/test_v1/node_01_devkitc -t upload
pio device monitor -d firmware/test_v1/node_01_devkitc
```

書き込み先は DevKitC の **UART ブリッジ側 Type-C ポート**
(CP210x / シルクで "UART" 側)。BOOT ボタンを押しながらリセットが必要な
個体もある (PlatformIO のメッセージに従う)。
ネイティブ USB 側ポートから JTAG 書き込みしたい場合は `platformio.ini` の
`upload_protocol = esp-builtin` を再度有効化する。

## LED 状態表示

DevKitC-1 の User LED は GPIO48 の **WS2812 (ネオピクセル)**。`digitalWrite`
では光らないので、本ファームでは LED の点滅は **観測できない**。
状態確認は `SERIAL_DEBUG=1` の Serial ログで行う:

```
[N1 t=12345 st=Conducting wifi=1 imu=1 acc=(...) n=... dyn=... bpm=... beatSeq=...]
[N1 EVT BEAT no=12 playAt=... bpm=...]
```

外部 LED で点滅を観測したい場合は、左列で空いている GPIO7 等に
`LED + 330Ω 抵抗 → GND` を付けて `ProjectConfig.h` の
`STATUS_LED_CONFIG.pin` を 7 に、`activeLow` を `false` のまま使う。

## 切り分け実験プラン

1. `node_01_devkitc` を DevKitC に書き込む
2. 楽器ノード (`node_02〜04`) はそのまま起動
3. Processing PC アプリ (`pc_app/test_v1/...`) で NOTE 受信ログを観察
4. 同じ位置・距離・時間帯で XIAO 版 (`node_01`) と比較
5. パケロスが顕著に減っていれば **(A) RF 経路** が主犯と確定
6. ロスが変わらなければ **(B) WiFi 環境** または **(C) ファーム** を疑う

## 構成

`node_01` と同じ。差分はビルド設定のみで `src/` `lib/` `include/SystemData.h`
は触っていない。

```
node_01_devkitc/
├── platformio.ini        ★ board と USB CDC / upload_protocol を変更
├── include/
│   ├── ProjectConfig.h   ★ コメントを DevKitC 用に更新、StatusLed を WS2812 注記
│   └── SystemData.h      ── node_01 と同一
├── src/                  ── node_01 と同一 (ロジック未変更)
└── lib/                  ── node_01 と同一
```
