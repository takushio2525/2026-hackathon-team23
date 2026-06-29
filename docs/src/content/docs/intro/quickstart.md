---
title: クイックスタート
description: production版を書き込み、Processingで演奏するまで
---

:::caution[実機作業]
書き込み前にボードとポートを確認してください。楽器ノードで`SERIAL_DEBUG=1`にすると、
NOTEバイナリが停止するためProcessingでは鳴りません。
:::

## 必要なもの

- PlatformIOが使えるVS Code
- Processing 4とMinimライブラリ
- XIAO ESP32-S3 Sense + GY-521 × 1
- Arduino UNO R4 WiFi × 5
- USBケーブル、音声出力可能なPC

## 1. 指揮者を書き込む

```bash
pio run -d firmware/production/node_01 -t upload
```

ESP32-S3-DevKitC-1を使う場合は`node_01_devkitc`へ読み替えます。

## 2. 楽器5台を書き込む

```bash
pio run -d firmware/production/node_02 -t upload
pio run -d firmware/production/node_03 -t upload
pio run -d firmware/production/node_04 -t upload
pio run -d firmware/production/node_05 -t upload
pio run -d firmware/production/node_06 -t upload
```

## 3. PCアプリを起動する

Processingで次を開いて実行します。

```text
pc_app/production/orchestra_resynth/orchestra_resynth.pde
```

画面のポート一覧からArduinoのUSBポートを開きます。`node_02`の接続はメイン操作UI、
`node_03〜06`はアナライザとして自動判定されます。1つのアプリで複数ポートも開けます。

## 4. 演奏する

1. 指揮者を静止して、2秒間のキャリブレーションを待つ
2. メニューで左右に振ってモードを選ぶ
3. 縦に振って決定する
4. 一定のリズムで振り、拍を送る

## 動かないとき

- LEDがIdleのまま：SoftAP起動やIMU配線を確認
- PCが待機中のまま：`node_02`のポートと指揮者のMenu状態を確認
- 音が鳴らない：シリアルモニタを閉じ、`SERIAL_DEBUG=0`を確認
- 詳細：[トラブルシュート](/guide/troubleshooting/)
