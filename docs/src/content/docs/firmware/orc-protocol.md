---
title: OrcProtocol — パケット定義の中身
description: productionのCTRL／BEAT／NOTE／UIを20 B固定にする型、配置、検証処理
sidebar:
  label: 共通 — OrcProtocol
  order: 2
---

## 実体と責務

| ファイル | 行数 | 内容 |
|---|---:|---|
| `firmware/production/common/lib/OrcProtocol/OrcProtocol.h` | 118 | 定数、4種パケット、サイズ保証 |
| `firmware/production/common/lib/OrcProtocol/OrcProtocol.cpp` | 19 | `parseHeader()` |
| `pc_app/common/OrcProtocol.pde` | — | PC側の対称な定数とパーサ |

このライブラリは`IModule`ではありません。全ノードが共有する**ワイヤ形式の唯一の定義**です。

## 20 Bの全体構造

```text
offset  size  field
0       2     magic = 0x4F52（送信バイトは52 4F）
2       1     version = 0x01
3       1     type = 1..4
4       4     seq
8       4     timestampMs
12      8     payload
```

ヘッダー12 Bとペイロード8 Bを揃え、UDPでもUSB Serialでも同じフレームを使います。

## 定数とtype

```cpp
constexpr uint16_t MAGIC = 0x4F52;
constexpr uint8_t PROTOCOL_VERSION = 0x01;
enum PacketType : uint8_t {
  PKT_CTRL = 1,
  PKT_BEAT = 2,
  PKT_NOTE = 3,
  PKT_UI   = 4,
};
constexpr size_t HEADER_SIZE = 12;
constexpr size_t PACKET_SIZE = 20;
```

`MAGIC`はリトルエンディアンのため、実際の先頭バイトは`0x52 0x4F`です。
Processingの`SerialCore`も同じ順でフレーム開始を探索します。

## `PacketHeader`

```cpp
struct PacketHeader {
  uint16_t magic;
  uint8_t version;
  uint8_t type;
  uint32_t seq;
  uint32_t timestampMs;
};
```

- `seq`：送信系列の単調増加番号。診断と欠損確認に使う
- `timestampMs`：指揮者基準の送信時刻。NOTE/UIも受信CTRL/BEAT由来のマスタ時刻を維持する
- `type`：ペイロードを解釈する前に必ず確認する

## CTRLペイロード

```cpp
struct CtrlPayload {
  uint16_t bpmQ8;
  uint8_t velocity;
  uint8_t state;
  uint8_t mode;
  uint8_t navCursor;
  uint8_t targetBpm;
  uint8_t score;
};
```

| offset | field | 範囲・意味 |
|---:|---|---|
| 12 | `bpmQ8` | BPM×8。0.125 BPM刻み |
| 14 | `velocity` | 0〜127 |
| 15 | `state` | 0 Idle、1 Calibrating、2 Conducting、3 Fallback、4 Menu、5 Result |
| 16 | `mode` | 0自由演奏、1ゲーム |
| 17 | `navCursor` | メニュー位置 |
| 18 | `targetBpm` | ゲーム目標。現在100 |
| 19 | `score` | 0〜100、`0xFF`は未確定 |

`bpmQ8`は一般的なQ8.8ではなく「8倍整数」というプロジェクト固有名です。

```cpp
uint16_t wire = (uint16_t)(bpm * 8.0f + 0.5f);
float bpm = wire / 8.0f;
```

## BEATペイロード

```cpp
struct BeatPayload {
  uint16_t beatNo;
  uint8_t reserved[2];
  uint32_t playAtMasterMs;
};
```

- `beatNo`は1始まりで進み、`uint16_t`のラップは符号付き差分で扱う
- `playAtMasterMs`は現在時刻ではなく、**220 ms先の発音予約時刻**
- 同じペイロードを4回送るが、楽器は同じ`beatNo`を1発音にまとめる

## NOTEペイロード

```cpp
struct NotePayload {
  uint8_t partId;
  uint8_t noteNumber;
  uint8_t velocity;
  uint8_t gate;
  uint16_t durationMs;
  uint8_t instrumentId;
  uint8_t reserved;
};
```

| field | 意味 |
|---|---|
| `partId` | node_02〜06 = `0x02〜0x06` |
| `noteNumber` | MIDI。ドラムではGM打楽器番号 |
| `velocity` | 0〜127 |
| `gate` | 1=NoteOn、0=NoteOff。通常は1と`durationMs`を使う |
| `durationMs` | PCが自動リリースする予定時間 |
| `instrumentId` | 0〜3金管、4以上ドラム経路 |

通常のファームはNoteOffを送らず、Processingが`durationMs`後にリリースします。
`gate=0`の受信処理は互換性と将来拡張のため残しています。

## UIペイロード

```cpp
struct UiPayload {
  uint8_t state;
  uint8_t mode;
  uint8_t navCursor;
  uint8_t targetBpm;
  uint8_t score;
  uint8_t partId;
  uint16_t bpmQ8;
};
```

UIはUDPには流しません。node_02が受け取ったCTRLをUSB Serialへ中継し、PCが画面を決めます。
`partId=0x02`によりProcessingはメインUI役を自動判定します。

## packingとサイズ保証

```cpp
#pragma pack(push, 1)
// structs...
#pragma pack(pop)

static_assert(sizeof(PacketHeader) == 12, "header must be 12 B");
static_assert(sizeof(CtrlPacket) == 20, "ctrl packet must be 20 B");
static_assert(sizeof(BeatPacket) == 20, "beat packet must be 20 B");
static_assert(sizeof(NotePacket) == 20, "note packet must be 20 B");
static_assert(sizeof(UiPacket) == 20, "ui packet must be 20 B");
```

`pack(1)`がなければパディングでoffsetが変わります。`static_assert`はその事故をコンパイル時に止めます。

## `parseHeader()`

```cpp
bool parseHeader(const uint8_t* buf, size_t len, PacketHeader& out) {
  if (len < HEADER_SIZE) return false;
  memcpy(&out, buf, HEADER_SIZE);
  if (out.magic != MAGIC) return false;
  if (out.version != PROTOCOL_VERSION) return false;
  return true;
}
```

ペイロードを読む前に長さ、magic、versionを確認します。typeが未知なら呼び出し側で捨てます。
アライメントされていない受信バッファへ構造体ポインタを直接キャストせず、`memcpy`を使います。

## Processing側の読み方

```java
int u16le(byte lo, byte hi) {
  return (lo & 0xFF) | ((hi & 0xFF) << 8);
}
```

SerialCoreは`52 4F`を探し、20 B揃ってからtype別クラスへ渡します。
C++側のフィールドを変更したら、`pc_app/common/OrcProtocol.pde`も同じコミットで直します。

## 拡張チェックリスト

1. ペイロード8 B以内に収めるか、protocol versionを上げる
2. C++構造体とProcessing offsetを同時更新
3. `static_assert`を追加・維持
4. CTRL/BEAT/NOTE/UIの全typeを実機またはテストデータで確認
5. magic、version、未知type、不足長の拒否を確認

関連：[バイナリパケット](/deep-dive/binary-packet/) / [UiRelayModule](/firmware/ui-relay/)
