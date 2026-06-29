---
title: ハードウェア構成
description: ボード、センサー、ノード割り当て
---

## ノード一覧

| ノード | ハードウェア | `partId` | 役割 |
|---|---|---:|---|
| node_01 | XIAO ESP32-S3 Sense + GY-521 | — | 指揮者、SoftAP |
| node_02 | Arduino UNO R4 WiFi | `0x02` | トランペット、メインUI中継 |
| node_03 | Arduino UNO R4 WiFi | `0x03` | ホルン |
| node_04 | Arduino UNO R4 WiFi | `0x04` | トロンボーン |
| node_05 | Arduino UNO R4 WiFi | `0x05` | チューバ |
| node_06 | Arduino UNO R4 WiFi | `0x06` | ドラム |

## IMU配線

GY-521はI2Cアドレス`0x68`で使用します。

| XIAO | GY-521 |
|---|---|
| D4 / GPIO5 | SDA |
| D5 / GPIO6 | SCL |
| 3.3V | VCC |
| GND | GND / AD0 |

IMUは5 ms周期、加速度±4 g、角速度±2000 dps設定です。

## 代替指揮者ボード

ESP32-S3-DevKitC-1用に`firmware/production/node_01_devkitc/`があります。
演奏ロジックは同じで、ボード設定とピン定義が異なります。
