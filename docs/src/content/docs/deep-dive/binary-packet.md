---
title: バイナリパケット
description: production の20 B固定 CTRL・BEAT・NOTE・UIを、構造体配置、エンディアン、Serialフレーミングまで分解する
sidebar:
  order: 4
---

:::note[この章で分かること]
- 4種類のパケットが同じ20 Bに収まる仕組み
- `#pragma pack`、リトルエンディアン、`static_assert` が必要な理由
- UDPとUSB Serialでフレーミング方法が違う理由
- C++とProcessingで同じオフセットを読む方法
:::

実装本体:

- マイコン: `firmware/production/common/lib/OrcProtocol/OrcProtocol.h`
- PC: `pc_app/common/OrcProtocol.pde`
- Serialフレーミング: `pc_app/common/SerialCore.pde`

## 全体構造

production のプロトコルは、すべて次の20 B固定です。

```text
0                         11 12                       19
+---------------------------+---------------------------+
| PacketHeader 12 B         | type別 payload 8 B       |
+---------------------------+---------------------------+
```

パケット型は4種類あります。

| type | 名前 | 主な経路 | 用途 |
|---:|---|---|---|
| 1 | CTRL | node_01 → UDP → node_02〜06 | BPM、状態、ゲーム設定 |
| 2 | BEAT | node_01 → UDP → node_02〜06 | 拍番号と発音予定時刻 |
| 3 | NOTE | node_02〜06 → USB Serial → PC | 音高、音量、長さ、音色 |
| 4 | UI | node_02 → USB Serial → PC | 画面状態の中継 |

UIはUDPには流しません。node_02が受けたCTRLを低頻度でPCへ中継するための専用型です。

固定長にすると、受信側は型ごとにバッファを確保する必要がありません。UDPでは
「20 Bでなければ破棄」、Serialでは「magicを見つけてから20 B読む」と単純化できます。

## 共通ヘッダ12 B

```cpp
#pragma pack(push, 1)
struct PacketHeader {
    uint16_t magic;        // offset 0, 2 B
    uint8_t  version;      // offset 2, 1 B
    uint8_t  type;         // offset 3, 1 B
    uint32_t seq;          // offset 4, 4 B
    uint32_t timestampMs;  // offset 8, 4 B
};
#pragma pack(pop)
```

| offset | フィールド | 意味 |
|---:|---|---|
| 0〜1 | `magic` | `0x4F52`。送信バイト列は `52 4F` |
| 2 | `version` | 現行は `0x01` |
| 3 | `type` | 1=CTRL、2=BEAT、3=NOTE、4=UI |
| 4〜7 | `seq` | 単調増加するシーケンス番号 |
| 8〜11 | `timestampMs` | 送信側の `millis()` |

`magic` はASCIIの「OR」を16 bit値として表したものです。little endianでは下位バイトから
送るので、Serial上では `0x52, 0x4F`、つまり「RO」の順に見えます。

### seqの役割

`seq` はペイロードの意味を持たず、欠落や重複の観測に使います。BEATの4連送は
同じパケットを繰り返すため同じ `seq` と `beatNo` を持ちます。受信側は
`beatNo` が同じ再送を二重発音させません。

### timestampMsの役割

CTRLとBEATではマスター時計を伝え、楽器側の時計オフセット推定に使います。
NOTEとUIではPCログ上の送信時刻として残ります。32 bit `millis()` は約49.7日で
ラップするため、差分は符号付き32 bitとして扱います。

## 1バイト境界で詰める理由

C++コンパイラは通常、CPUが読みやすい境界へメンバを揃えるためパディングを挿入します。

```cpp
struct Example {
    uint8_t  a;
    uint32_t b;
};
```

この構造体は見かけ上5 Bでも、`b` の手前に3 B入り、8 Bになることがあります。
通信形式ではコンパイラやボードごとにサイズが変わると壊れるため、
`#pragma pack(push, 1)` でパディングを禁止します。

さらにコンパイル時検査を置いています。

```cpp
static_assert(sizeof(PacketHeader) == 12, "header must be 12 B");
static_assert(sizeof(CtrlPacket) == 20, "ctrl packet must be 20 B");
static_assert(sizeof(BeatPacket) == 20, "beat packet must be 20 B");
static_assert(sizeof(NotePacket) == 20, "note packet must be 20 B");
static_assert(sizeof(UiPacket) == 20, "ui packet must be 20 B");
```

フィールド追加で8 Bを超えると、実行前にビルドが止まります。

## CTRLペイロード

```cpp
struct CtrlPayload {
    uint16_t bpmQ8;      // offset 12
    uint8_t  velocity;   // 14
    uint8_t  state;      // 15
    uint8_t  mode;       // 16
    uint8_t  navCursor;  // 17
    uint8_t  targetBpm;  // 18
    uint8_t  score;      // 19
};
```

| offset | フィールド | 値 |
|---:|---|---|
| 12〜13 | `bpmQ8` | BPM × 8 |
| 14 | `velocity` | 0〜127 |
| 15 | `state` | 0=Idle、1=Calibrating、2=Conducting、3=Fallback、4=Menu、5=Result |
| 16 | `mode` | 0=自由演奏、1=ゲーム |
| 17 | `navCursor` | メニューカーソル |
| 18 | `targetBpm` | ゲーム目標40〜240、0=未設定 |
| 19 | `score` | 0〜100、`0xFF`=未確定 |

### Q8固定小数

BPMは小数1桁程度を保ちたい一方、`float` をネットワーク形式に含めたくありません。
そこで8倍して `uint16_t` にします。

```text
encode: bpmQ8 = round(BPM × 8)
decode: BPM   = bpmQ8 ÷ 8
```

たとえば120.5 BPMは964、解像度は0.125 BPMです。名前はQ8ですが、一般的な
Q8.8形式ではなく「倍率8」というプロジェクト内の呼び方です。

## BEATペイロード

```cpp
struct BeatPayload {
    uint16_t beatNo;          // offset 12
    uint8_t  reserved[2];     // 14
    uint32_t playAtMasterMs;  // 16
};
```

`beatNo` は曲進行の基準です。各楽器は自分のローカルカウンタではなく、
`(beatNo + headOffset) % 32` から読む譜面位置を決めます。

`playAtMasterMs` は受信時刻ではなく発音予定時刻です。現行設定は送信時刻の45 ms先です。
BEATは2 ms間隔で4連送されても、すべて同じ予定時刻を持ちます。

## NOTEペイロード

```cpp
struct NotePayload {
    uint8_t  partId;       // offset 12
    uint8_t  noteNumber;   // 13
    uint8_t  velocity;     // 14
    uint8_t  gate;         // 15
    uint16_t durationMs;   // 16
    uint8_t  instrumentId; // 18
    uint8_t  reserved;     // 19
};
```

| フィールド | 意味 |
|---|---|
| `partId` | 送信ノード。productionでは `0x02〜0x06` |
| `noteNumber` | MIDI音番号。60=C4 |
| `velocity` | 0〜127 |
| `gate` | 1=NoteOn、0=NoteOff |
| `durationMs` | 予定発音長 |
| `instrumentId` | 0=trumpet、1=horn、2=trombone、3=tuba、4=drum |
| `reserved` | 0で埋める |

PCは金管のNOTEに楽器別オクターブ移調を適用します。ドラムでは
`noteNumber` 36/38/42/49をkick/snare/closed hi-hat/crashとして解釈します。

## UIペイロード

```cpp
struct UiPayload {
    uint8_t  state;      // offset 12
    uint8_t  mode;       // 13
    uint8_t  navCursor;  // 14
    uint8_t  targetBpm;  // 15
    uint8_t  score;      // 16
    uint8_t  partId;     // 17
    uint16_t bpmQ8;      // 18
};
```

UIはCTRLと内容が似ていますが、経路と受信者が違います。node_02の
`UiRelayModule` がCTRLの値を取り出し、変化時は最短33 ms（最大約30 Hz）、
無変化時は1秒heartbeatでUSB Serialへ送ります。
PCは `partId = 0x02` とUI受信からメイン操作画面の役割を判定します。

画面番号そのものは送りません。PCは `(state, mode)` から
Menu、Free Play、Game Play、Resultなどを導出します。これによりマイコンとPCの
画面列挙を二重管理しません。

## little endian

productionで使うESP32-S3、UNO R4 WiFi、PC側Javaの手動パースは、
複数バイト値を下位バイトから並べる前提です。

16 bit値 `0x03C4` は次の順です。

```text
offset n     : C4
offset n + 1 : 03
```

Processing側の復元関数は次のとおりです。

```java
int u8(byte v){
  return v & 0xFF;
}

int u16le(byte lo, byte hi){
  return u8(lo) | (u8(hi) << 8);
}
```

Javaの`byte`は -128〜127の符号付きなので、`& 0xFF` で0〜255へ戻してから
シフトします。32 bit値をPCで読む実装を追加するときも同じ順序で4バイトを合成します。

## C++での送受信

送信側は値を詰めた構造体を、そのまま20 Bのバイト列として渡します。

```cpp
orc::BeatPacket packet{};
packet.header.magic = orc::MAGIC;
packet.header.version = orc::PROTOCOL_VERSION;
packet.header.type = orc::PKT_BEAT;
packet.payload.beatNo = data.beat.beatNo;
packet.payload.playAtMasterMs = masterNow + cfg_.beatLookaheadMs;

udp.write(
    reinterpret_cast<const uint8_t*>(&packet),
    sizeof(packet)
);
```

受信側は先にヘッダを検査し、型が合う構造体へコピーします。

```cpp
orc::PacketHeader header;
if (!orc::parseHeader(buf, len, header)) return;

if (header.type == orc::PKT_CTRL) {
    memcpy(&data.orcNet.lastCtrl, buf, sizeof(orc::CtrlPacket));
}
```

`parseHeader()` が検査するのは長さ、magic、versionです。その後の型や値域は
呼び出し側で確認します。

## USB Serialのフレーミング

UDPにはデータグラム境界がありますが、Serialは単なるバイト列です。途中から接続したり
1 B欠けたりすると、20 Bごとに区切るだけでは永続的にずれます。

`SerialCore.pde` は次の状態機械で先頭を探します。

```text
SearchMagicLo
  └─ 0x52 → SearchMagicHi
               ├─ 0x4F → 残り18 Bを収集
               ├─ 0x52 → SearchMagicHiを継続
               └─ その他 → SearchMagicLo
```

20 B揃うと配列をコピーして `ConcurrentLinkedQueue<byte[]>` へ積みます。
Serialコールバックは音声やUIを直接触らず、`draw()` がキューを消費します。

現行PC実装の `packetType()` は長さとversionを確認します。magicはフレーマが確認済みです。
別経路から直接 `handlePacket()` を呼ぶ場合はmagic検査も追加する必要があります。

## ProcessingでのNOTEとUIパース

```java
class NoteEvent {
  NoteEvent(byte[] b){
    partId       = u8(b[12]);
    noteNumber   = u8(b[13]);
    velocity     = u8(b[14]);
    gate         = u8(b[15]);
    durationMs   = u16le(b[16], b[17]);
    instrumentId = u8(b[18]);
  }
}

class UiEvent {
  UiEvent(byte[] b){
    state     = u8(b[12]);
    mode      = u8(b[13]);
    navCursor = u8(b[14]);
    targetBpm = u8(b[15]);
    score     = u8(b[16]);
    partId    = u8(b[17]);
    bpmQ8     = u16le(b[18], b[19]);
  }
}
```

C++構造体の順序を変更したら、PCの各インデックスも同じ変更に含めます。

## 互換性を保つ変更手順

### reservedを使う変更

既存ペイロードの意味を保ち、`reserved` を新しいフィールドへ割り当てるなら、
パケットサイズと既存offsetは維持できます。旧受信者はそのバイトを無視できます。

### 既存offsetを変える変更

フィールドの並べ替え、サイズ変更、20 B超過は非互換です。

1. `PROTOCOL_VERSION` を上げる
2. 新旧の構造体とパーサを併存させるか、一斉更新する
3. マイコンとPCを同時に更新する
4. `static_assert` とパケットfixtureを更新する
5. [プロトコル仕様](/system/protocol/) とこのページを更新する

### 新しいパケット型を足す変更

8 Bの新ペイロードと20 Bのパケット構造体を追加し、未使用type番号を割り当てます。
既存受信者が未知typeを無視できることを確認します。UI追加はこの方法です。

## デバッグ

| 症状 | 確認箇所 |
|---|---|
| PCが一切受信しない | Serialが115200 bpsか、デバッグ文字列を同じポートへ混ぜていないか |
| 途中から値が崩れる | magic再同期、20 B固定、1 B欠落 |
| typeが不正 | offset 3、version offset 2 |
| BPMだけ8倍/8分の1 | `bpmQ8` のencode/decode |
| NOTEの長さが異常 | offset 16〜17のlittle endian |
| 画面だけ更新されない | node_02のUI type=4、2秒タイムアウト、`partId=0x02` |
| 拍が二重に鳴る | 4連送を `beatNo` で重複排除しているか |

## 次に読む

- 通信路: [UDPマルチキャスト](/deep-dive/udp-multicast/)
- 時刻と4連送: [時刻同期メカニズム](/deep-dive/time-sync/)
- 譜面: [楽譜進行ロジック](/deep-dive/score-progression/)
- PCの同じ実装: [PC側プロトコル](/pc-audio/orc-protocol/)
