---
title: PC側OrcProtocol
description: OrcProtocol.pdeの定数、NOTE・UIパーサ、状態値、画面IDをoffset単位で解説する
sidebar:
  order: 4
---

実体: `pc_app/common/OrcProtocol.pde`（99行）。

## 責務

この共有タブは次の3種類を定義します。

1. firmwareと一致させるwire protocol定数
2. NOTEとUIの20 Bを読むdata class
3. PC内だけで使うroleとscreen ID

packetをSerialから切り出す処理は [SerialCore](/pc-audio/serial-handling/)、
packetの意味に応じた処理はmainの`handlePacket()`です。

## wire protocol定数

```java
final int  SERIAL_BAUD = 115200;
final int  PACKET_SIZE = 20;
final byte MAGIC_LO    = (byte)0x52;
final byte MAGIC_HI    = (byte)0x4F;

final int TYPE_CTRL = 1;
final int TYPE_BEAT = 2;
final int TYPE_NOTE = 3;
final int TYPE_UI   = 4;
```

PCが直接処理するのはNOTEとUIですが、型番号の一覧はfirmwareと同じにしてあります。
CTRLとBEATを今後PCへ流したときに番号を再定義しないためです。

## 状態値

| 値 | 定数 | 意味 |
|---:|---|---|
| 0 | `ST_IDLE` | 起動・停止 |
| 1 | `ST_CALIBRATING` | IMU校正 |
| 2 | `ST_CONDUCTING` | 自由演奏またはゲーム中 |
| 3 | `ST_FALLBACK` | 異常時の退避 |
| 4 | `ST_MENU` | モード選択 |
| 5 | `ST_RESULT` | ゲーム結果 |

これは `firmware/.../OrcProtocol.h` の `CtrlPayload.state` と一致させます。
`stateName()` はログ表示用で、未知値も `Unknown(n)` として残します。

## roleとscreen

roleは「このPCがどの画面を出すか」の大分類です。

```text
ROLE_UNKNOWN  = 0
ROLE_MAIN_UI  = 1
ROLE_ANALYZER = 2
```

screenはPC内部だけの表示IDです。

| ID | 画面 |
|---:|---|
| 0 | Port Select |
| 1 | Waiting |
| 2 | Menu |
| 3 | Free Play |
| 4 | Game Play |
| 5 | Result |
| 6 | Analyzer |
| 7 | Dashboard（test_multi用） |

firmwareはscreen IDを送りません。mainがrole、state、modeからscreenを導出します。

## ゲーム定数

```java
final int GAME_LENGTH_BEATS     = 56;
final int GAME_GUIDE_FULL_BEATS = 16;
final int GAME_GUIDE_ZERO_BEATS = 32;
final int UI_TIMEOUT_MS         = 2000;
```

この4値はproductionの挙動に直結します。最初の16拍はガイド100%、次の16拍で
0%まで減衰し、56拍でゲームが終わります。UI packetが2秒来なければマスター再起動と
判定します。

## byte変換

Javaの`byte`は符号付きなので、packet値を直接`int`へ代入すると128以上が負になります。

```java
int u8(byte v){
  return v & 0xFF;
}

int u16le(byte lo, byte hi){
  return u8(lo) | (u8(hi) << 8);
}
```

`u16le()`はlittle endianの16 bit値を0〜65535へ復元します。

## NoteEvent

```java
class NoteEvent {
  int partId;
  int noteNumber;
  int velocity;
  int gate;
  int durationMs;
  int instrumentId;
}
```

| offset | 値 |
|---:|---|
| 12 | partId |
| 13 | MIDI note |
| 14 | velocity |
| 15 | gate |
| 16〜17 | duration ms、little endian |
| 18 | instrumentId |
| 19 | reserved、PCでは読まない |

constructorは長さやtypeを検査しません。呼び出し前に`packetType()`で確認する契約です。

## UiEvent

| offset | 値 |
|---:|---|
| 12 | state |
| 13 | mode |
| 14 | navCursor |
| 15 | targetBpm |
| 16 | score |
| 17 | partId |
| 18〜19 | bpmQ8 |

`bpmQ8 / 8.0f` が表示BPMです。`score=0xFF`は未確定です。

## packetType

```java
int packetType(byte[] buf){
  if (buf.length < PACKET_SIZE) return -1;
  if (u8(buf[2]) != 0x01) return -1;
  return u8(buf[3]);
}
```

ここではversionと長さを見ます。magicはSerialCoreが先頭を見つける過程で確認済みです。
ただし厳密なvalidatorではありません。

- 20 Bより長くても受理する
- typeの範囲を確認しない
- magicを再確認しない
- payload値域を確認しない

現在はSerialCoreが常に20 B配列だけをqueueへ入れるので成立します。テストや別transportから
直接呼び出す場合は、`buf.length == 20` とmagicも検査してください。

## firmwareとの整合チェック

変更時に対で見る項目:

| PC | firmware |
|---|---|
| `TYPE_*` | `enum PacketType` |
| `ST_*` | `CtrlPayload.state`の定義 |
| NoteEvent offset | `NotePayload` |
| UiEvent offset | `UiPayload` |
| ゲーム定数 | node_01 `ProjectConfig.h` |
| `UI_TIMEOUT_MS` | UI中継周期と運用要件 |

より低レベルの配置は [バイナリパケット](/deep-dive/binary-packet/) を参照してください。
