---
title: UiRelayModule — 指揮者状態をPCへ中継する
description: node_02が受信CTRLを20 B UIパケットへ変換し、変化時とheartbeatでUSB送信する
sidebar:
  label: 楽器 — UiRelayModule
  order: 10
---

## 実体

| ファイル | 行数 |
|---|---:|
| `firmware/production/node_02/lib/UiRelayModule/UiRelayModule.h` | 41 |
| `firmware/production/node_02/lib/UiRelayModule/UiRelayModule.cpp` | 57 |

productionで追加されたnode_02専用の出力モジュールです。音のNOTEとは別に、指揮者の状態をPCの画面へ渡します。

## なぜnode_02だけか

すべての楽器がUIを中継すると、同じ指揮者状態が複数のUSBポートから到着し、メイン画面の役割判定が曖昧になります。
node_02をメイン操作UIの接続点と決め、node_03〜06はアナライザ役にします。

## Config

```cpp
struct UiRelayConfig {
  uint8_t partId;
  uint16_t minIntervalMs;
  uint16_t heartbeatMs;
};
```

production値：

| field | 値 | 意味 |
|---|---:|---|
| `partId` | `0x02` | PCのメインUI判定 |
| `minIntervalMs` | 33 | 変化送信の最大頻度を約30 Hzへ制限 |
| `heartbeatMs` | 1000 | 無変化でも現在状態を再通知 |

## 入力データ

OrcReceiverModuleが`data.ctrl`へ書いた次の値を読みます。

- `state`
- `mode`
- `navCursor`
- `targetBpm`
- `score`
- `bpmQ8`

モジュールはUDPを直接読みません。受信とUI変換の境界を分けています。

## 送信条件

```text
changed = いずれかのUIフィールドが前回値と異なる
intervalReady = now - lastSent >= 33 ms
heartbeatDue = now - lastSent >= 1000 ms

send = (changed && intervalReady) || heartbeatDue
```

BPMは拍ごとに変わる可能性がありますが、33 ms未満の連続送信を抑えてSerial帯域と描画更新を安定させます。
一方、状態が変わらなくてもheartbeatを出すため、PCを途中接続して最大1秒で画面を復元できます。

## UIパケット

```cpp
UiPacket pkt{};
pkt.header.type = orc::PKT_UI;
pkt.payload.state = data.ctrl.state;
pkt.payload.mode = data.ctrl.mode;
pkt.payload.navCursor = data.ctrl.navCursor;
pkt.payload.targetBpm = data.ctrl.targetBpm;
pkt.payload.score = data.ctrl.score;
pkt.payload.partId = 0x02;
pkt.payload.bpmQ8 = data.ctrl.bpmQ8;
```

20 Bを`Serial.write()`し、前回値と送信時刻を更新します。

## NOTEとの共存

NOTEとUIは同じUSBストリームですが、共通ヘッダーのtypeが異なります。
ProcessingのSerialCoreは20 B単位に復元し、NOTEは発音、UIは画面更新へ振り分けます。

`SERIAL_DEBUG=1`時は人間向けログへ切り替わるため、UiRelayとNoteSenderのバイナリは通常運用と同じように停止します。

## PC側タイムアウト

Processingは最後のUI受信から2000 ms経過するとマスター再起動または経路停止と判断します。

1. 表示状態をIdleへ戻す
2. 得点を未確定へ戻す
3. メトロノームを停止
4. 全ボイスを停止
5. 待機画面へ遷移

heartbeatが1000 msなので、正常時にはタイムアウトの半分以内に必ず更新されます。

## 変更時の注意

- node_03〜06へ無条件に複製しない
- CTRLとUIのstate/mode定義を同時更新する
- 20 BのUiPayloadを変更したらProcessingの`UiEvent`も更新する
- minIntervalを短くしすぎるとBPM微変動でSerialが埋まる
- heartbeatを2000 ms以上にすると正常でもPCがタイムアウトする

関連：[PCのシリアル受信とUI](/implementation/pc-serial-ui/) / [OrcProtocol](/firmware/orc-protocol/)
