---
title: NoteSenderModule — NOTEをUSBシリアルで送る
description: 楽器の発音予約を20 B NotePacketへ変換し、通常音と細分音符をPCへ送る出力モジュール
sidebar:
  label: 楽器 — NoteSenderModule
  order: 9
---

## 実体

| ファイル | 行数 |
|---|---:|
| `firmware/production/common/lib/NoteSenderModule/NoteSenderModule.h` | 41 |
| `firmware/production/common/lib/NoteSenderModule/NoteSenderModule.cpp` | 93 |

## 責務

- `noteOut`と`noteOutSub`の発音予約を読む
- NOTEヘッダーと8 Bペイロードを作る
- USB Serialへ20 Bを書き出す
- 送信統計を更新し、pendingをclearする

音価計算、楽譜選択、音色合成は担当しません。

## Config

```cpp
struct NoteSenderConfig {
  uint32_t baudRate;
  uint8_t partId;
  uint8_t instrumentId;
};
```

baudRateは115200。partId/instrumentIdは02/0、03/1、04/2、05/3、06/4です。

## 2つの予約スロット

- `noteOut`：拍頭の主音符
- `noteOutSub`：拍途中の8分音符など

同じ2 msループで両方が発火可能でも上書きしないため、モジュールは両スロットを独立に送ります。

## NOTEの組み立て

```text
PacketHeader {
  magic, version, PKT_NOTE, seq++, timestampMs
}
NotePayload {
  partId, noteNumber, velocity, gate=1,
  durationMs, instrumentId, reserved=0
}
```

実装は値初期化した`NotePacket pkt{}`を使い、予約バイトを確実に0にします。

## `SERIAL_DEBUG`との排他

- `SERIAL_DEBUG=0`：20 Bバイナリを送る通常運用
- `SERIAL_DEBUG=1`：人間向けNOTEログを出し、バイナリは送らない

テキストとバイナリが同じストリームへ混ざるとProcessingのmagic探索が誤同期するため、同時出力しません。

## NoteOffを送らない理由

`durationMs`をPCへ渡し、Processing側が予定時刻にreleaseします。楽器側で発音中ボイスを追跡せずに済み、
Serialパケット数も減らせます。gateフィールド自体は互換用に残っています。

## ドラム

node_06は`instrumentId=4`を送り、PCのドラム経路へ入ります。キック・スネア・クラッシュの選択は
`noteNumber`（36/38/49）で行います。

## 異常時

Serialが開かれていなくても書き込み自体は進みます。PCの途中起動後は次のNOTEから受信します。
楽譜位置はbeatNo駆動なので、PCが不在だった期間を再送せず現在位置へ合流します。

## 注意点

- `Serial.flush()`を拍ごとに濫用すると待ち時間が増える
- partIdとOrcReceiverConfigのpartIdを一致させる
- JSON順序を変えたらinstrumentIdも更新する
- pendingを送信後に必ずclearする

関連：[音色JSON](/implementation/instrument-json/) / [NOTEから発音まで](/pc-audio/signal-flow/)
