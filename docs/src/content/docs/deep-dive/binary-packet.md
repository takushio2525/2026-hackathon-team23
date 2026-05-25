---
title: バイナリパケット
description: 20 B 固定の CTRL/BEAT/NOTE がメモリ上でどう並ぶか — pragma pack、エンディアン、memcpy 復元、static_assert
sidebar:
  order: 4
---

:::note[この章で分かること]
- 「20 バイト固定」を C++ の構造体で表現する方法
- `#pragma pack` の意味と、サボると何が壊れるか
- リトルエンディアン環境で `memcpy` が動く前提
- Processing 側で同じバイナリを読むときのオフセット計算
- 拡張時のチェックリスト（互換性を壊さない作法）
:::

:::tip[読了目安]
**約 10 分**。前提: C/C++ の構造体・ポインタ・型サイズ（`uint8_t` / `uint16_t` / `uint32_t`）。
:::

実装本体: `firmware/test_v2/common/lib/OrcProtocol/OrcProtocol.h`

## 20 B 固定にした狙い

CTRL / BEAT / NOTE のすべてを 20 B に統一している。これにより：

- 受信側は **「20 B 来たら 1 パケット」** とだけ思えば良い（フレーミングが単純）
- マイコンのバッファサイズを 20 B で固定できる（メモリ予測が容易）
- パケット長で型を推定する必要がない（`type` フィールドで判別）

ヘッダ 12 B + ペイロード 8 B の構成は、メモリレイアウトを揃えるための制約から来ている。

## 共通ヘッダ（12 B）の構造

```cpp
#pragma pack(push, 1)
struct PacketHeader {
    uint16_t magic;        //  2 B (オフセット 0)
    uint8_t  version;      //  1 B (オフセット 2)
    uint8_t  type;         //  1 B (オフセット 3)
    uint32_t seq;          //  4 B (オフセット 4)
    uint32_t timestampMs;  //  4 B (オフセット 8)
};
#pragma pack(pop)
```

合計 12 B。各フィールドの意味：

| フィールド | 意味 |
|---|---|
| `magic = 0x4F52` | バイト列で `0x52 0x4F` =「RO」をリトルエンディアンで読むと「OR」 |
| `version` | プロトコルバージョン。`0x01` 以外は捨てる |
| `type` | `1=CTRL` / `2=BEAT` / `3=NOTE` |
| `seq` | 型ごとに独立な単調増加カウンタ。受信側でロス / 重複検知に使う |
| `timestampMs` | 送信側 `millis()`。楽器側はこれで時刻オフセットを推定 |

## `#pragma pack(push, 1)` の意味

C/C++ のデフォルトでは、コンパイラが速度のために **構造体メンバの間にパディングバイト** を
挿入することがある。たとえば：

```cpp
struct Foo {
    uint8_t  a;   // 1 B
    uint32_t b;   // 4 B
};
// sizeof(Foo) = 8 になりがち (a の後ろに 3 B のパディング)
```

これだと「ヘッダ 12 B」のはずが、コンパイラ次第で 16 B や 20 B に膨らんでしまう。
それを防ぐのが `#pragma pack(push, 1)`：

- `push`: 現在のパッキング設定をスタックに保存
- `1`: 「1 バイト境界で詰める」= パディングを入れない
- 対応する `#pragma pack(pop)` で元の設定に戻る

これにより、`sizeof(PacketHeader) == 12` が保証される（後述の `static_assert`）。

### パディングを入れたままだと何が起きるか

ヘッダが 16 B になると、送信側と受信側でフィールドのオフセットがずれて、
**全部のデータが意味不明になる**。Magic だけ偶然合うこともあるが、`seq` や
`timestampMs` がでたらめになる。

特にマイコン側と PC 側でアラインメント仕様が違うと、こっそり壊れる。
`#pragma pack` を入れる、もしくは Processing 側のように手動オフセット指定にする、
のどちらかで揃える必要がある。

## ペイロード（8 B）の構造

### CtrlPayload

```cpp
struct CtrlPayload {
    uint16_t bpmQ8;        // 2 B (オフセット 12 from start)
    uint8_t  velocity;     // 1 B (14)
    uint8_t  state;        // 1 B (15)
    uint8_t  reserved[4];  // 4 B (16)
};
```

`bpmQ8` は BPM を 8 倍した固定小数（Q8）。
- 例: 100.0 BPM → `800`、120.5 BPM → `964`
- 送信: `bpmQ8 = (uint16_t)(bpm * 8.0f + 0.5f)`
- 受信: `bpm = bpmQ8 / 8.0f`
- 解像度 0.125 BPM、範囲 40〜240 BPM は `320`〜`1920` に収まる（`uint16_t` の `0`〜`65535` 内）

### BeatPayload

```cpp
struct BeatPayload {
    uint16_t beatNo;          // 2 B (12)
    uint8_t  reserved[2];     // 2 B (14)
    uint32_t playAtMasterMs;  // 4 B (16)
};
```

`beatNo` は 0 オリジンで単調増加、`playAtMasterMs` は指揮者時計でのこの拍の発音目標時刻。
詳しくは [時刻同期メカニズム](/deep-dive/time-sync/) 参照。

### NotePayload

```cpp
struct NotePayload {
    uint8_t  partId;        // 1 B (12)
    uint8_t  noteNumber;    // 1 B (13)
    uint8_t  velocity;      // 1 B (14)
    uint8_t  gate;          // 1 B (15)
    uint16_t durationMs;    // 2 B (16)
    uint8_t  instrumentId;  // 1 B (18)
    uint8_t  reserved;      // 1 B (19)
};
```

`instrumentId` は test_v2 で追加された。旧 `reserved[0]` を充てている。
PC 側 Processing が `data/<n>_*.json` の n 番目の楽器定義を選ぶキーになる。

> ⚠️ test_v1 のドキュメントでは「先頭が `midiNote`」と書かれていた箇所があるが、test_v2
> 実装は **ヘッダ直後を `partId` から始める順序**。受信側はオフセット 12 から
> `partId, noteNumber, velocity, gate, durationMs, instrumentId, reserved` の順で読む。

## `static_assert` でサイズを固定する

仕様変更でうっかりサイズが変わってないか、**コンパイル時** にチェックする：

```cpp
static_assert(sizeof(PacketHeader) == HEADER_SIZE, "header must be 12 B");
static_assert(sizeof(CtrlPacket) == PACKET_SIZE,  "ctrl packet must be 20 B");
static_assert(sizeof(BeatPacket) == PACKET_SIZE,  "beat packet must be 20 B");
static_assert(sizeof(NotePacket) == PACKET_SIZE,  "note packet must be 20 B");
```

`#pragma pack` を入れ忘れたり、フィールドを誤って追加したりすると、
ここでビルドが落ちる。仕様の **嘘** を実装に持ち込ませない安全装置。

## リトルエンディアンの前提

ESP32 / Arduino UNO R4 / x86 PC は **リトルエンディアン**（多バイト整数の下位バイトが
先に並ぶ）。`uint16_t bpmQ8 = 800` をメモリに置くと：

```
オフセット: 12   13
バイト値:   0x20 0x03   (0x0320 = 800)
```

楽器側は同じくリトルエンディアン環境なので、`memcpy` で生バイトを構造体に書き戻すと
正しい値になる：

```cpp
orc::CtrlPacket pkt;
memcpy(&pkt, buf, sizeof(pkt));
// pkt.payload.bpmQ8 は 800 になっている
```

### ビッグエンディアン環境では

ARM Cortex-M も含めて現代の組み込みは大半がリトルエンディアン。理論的には
ビッグエンディアン環境（一部のミップス、ネットワーク機器）で動かすと壊れるが、
本プロジェクトの対象ハードウェアでは想定不要。

### `magic = 0x4F52` の表示

リトルエンディアンで書き込まれるので、メモリ上のバイト列は：

```
オフセット 0:  0x52  0x4F   (= 'R' 'O')
```

WireShark で見ると "RO" の順に並んでいるように見えるが、`uint16_t` として読み戻すと
`0x4F52` = "OR" になる。

## シリアライズ / デシリアライズ

### シリアライズ（送信時）

「シリアライズ」と呼んでいるが、本プロジェクトでは **構造体をそのままバイト列として送る**。
変換コードは不要：

```cpp
orc::BeatPacket pkt{};
pkt.header.magic       = orc::MAGIC;
pkt.header.version     = orc::PROTOCOL_VERSION;
pkt.header.type        = orc::PKT_BEAT;
pkt.header.seq         = ++data.sender.beatSeq;
pkt.header.timestampMs = masterNow;
pkt.payload.beatNo         = data.beat.beatNo;
pkt.payload.playAtMasterMs = masterNow + cfg_.beatLookaheadMs;

udp_.write(reinterpret_cast<const uint8_t*>(&pkt), sizeof(pkt));
```

`reinterpret_cast<const uint8_t*>` で構造体の先頭ポインタを `uint8_t*` として扱い、
`sizeof(pkt)` = 20 バイトをそのまま UDP に流す。

### デシリアライズ（受信時）

受信側も同じく `memcpy`：

```cpp
uint8_t buf[orc::PACKET_SIZE];
udp_.read(buf, orc::PACKET_SIZE);
orc::PacketHeader hdr;
if (!orc::parseHeader(buf, orc::PACKET_SIZE, hdr)) continue;
if (hdr.type == orc::PKT_CTRL) {
    memcpy(&net.lastCtrl, buf, sizeof(net.lastCtrl));
    net.hasNewCtrl = true;
}
```

`parseHeader()` は magic / version の検証だけ：

```cpp
bool parseHeader(const uint8_t* buf, size_t len, PacketHeader& out) {
    if (len < HEADER_SIZE) return false;
    memcpy(&out, buf, HEADER_SIZE);
    if (out.magic != MAGIC) return false;
    if (out.version != PROTOCOL_VERSION) return false;
    return true;
}
```

これ以外のフィールド検証はしていない（速度優先）。妥当性チェックは
各受信モジュール（`OrcReceiverModule` 等）が行う。

## Processing 側のパース

Java 側では構造体を直接 `memcpy` できないので、**バイト列を手動で読み解く**：

```java
int u8(byte v){ return v & 0xFF; }
int u16le(byte lo, byte hi){ return u8(lo) | (u8(hi) << 8); }

void handlePacket(byte[] buf){
    if (u8(buf[2]) != 0x01) return;                   // version
    int type = u8(buf[3]);
    if (type != TYPE_NOTE) return;                    // NOTE 以外無視
    int partId       = u8(buf[12]);
    int noteNumber   = u8(buf[13]);
    int velocity     = u8(buf[14]);
    int gate         = u8(buf[15]);
    int durationMs   = u16le(buf[16], buf[17]);
    int instrumentId = u8(buf[18]);
    // ...
}
```

`u16le()` で 2 バイトをリトルエンディアン解釈。`& 0xFF` は Java の `byte` が
符号付きなので、上位ビットを 0 にクリアして 0〜255 に正規化するため。

オフセット 12〜19 はマイコン側の `NotePayload` と完全に一致する。
構造体定義を変えるときは、必ず両方を同じコミットで更新する。

## フレーミング（バイト列をパケットに切り出す）

UDP は 1 パケット 1 メッセージ単位で届くので、UDP 経由なら長さチェックだけで OK
（`packetSize != 20` を捨てる）。だが USB Serial はバイトストリームなので、
**どこからどこまでが 1 パケットか** を自前で見つける必要がある。

Processing 側は `magic` 2 バイト = "RO" を見つけたところで頭出しする：

```java
void serialEvent(Serial p){
    while (p.available() > 0){
        int b = p.read();
        if (!pc.inFrame){
            if (pc.rxIdx == 0){
                if ((byte)b == MAGIC_LO){ rxBuf[0] = (byte)b; rxIdx = 1; }
            } else {
                if ((byte)b == MAGIC_HI){ rxBuf[1] = (byte)b; rxIdx = 2; inFrame = true; }
                else { /* 再同期 */ }
            }
        } else {
            rxBuf[rxIdx++] = (byte)b;
            if (rxIdx >= PACKET_SIZE){
                // 1 パケット確定。キューに積む
                packetQueue.offer(copyOf(rxBuf));
                rxIdx = 0; inFrame = false;
            }
        }
    }
}
```

「`0x52` を見たら次が `0x4F` か確認 → 違ったら再同期、合ったら 20 B 読む」。
これにより、起動直後や 1 バイトロスからも自動回復する。

## 拡張時のチェックリスト

新しいフィールドや新しいパケット型を足すときの作法：

### 既存フィールドを変えない場合（後方互換）

- `reserved` 領域を使って新フィールドを追加
- `version` は上げない（既存ノードも捨てずに動かしたい場合）
- 例: test_v2 で `instrumentId` を `NotePayload::reserved[0]` に充てた

### 既存フィールドを変える場合（後方非互換）

- `PROTOCOL_VERSION` を `0x02` に上げる
- 受信側は `version != 0x01` を見たら **古いパケットを捨てるか変換** する
- 旧バージョンと並行運用したいなら、両方の構造体を残しておく

### 共通の作法

- `static_assert(sizeof(...) == 20, ...)` を必ず追加
- `#pragma pack(push, 1)` で囲む
- `.agent/api.md` と `architecture/protocol.md` を **同じコミットで** 更新
- Processing 側のオフセット計算も同期更新

## なぜ `union` で型を切り替えないか

別の設計として、`Packet { Header h; union { Ctrl c; Beat b; Note n; }; }` を
1 つの型で表す案もある。本プロジェクトでは採用していない：

- `union` は型タグ（`type`）の手動管理が必要で、誤用しやすい
- 別々の構造体（`CtrlPacket` / `BeatPacket` / `NotePacket`）の方が、受信時の
  `memcpy` 先が明確
- メモリオーバーヘッドはどちらも同じ（20 B）

明示的な型分離の方が読みやすく、ミスが少ない。

## デバッグの観点

- パケットがおかしい → WireShark で 20 B 並んでいるか確認、`magic = 0x4F52` か
- パケット型が違うと言われる → `type` バイト（オフセット 3）を確認
- 値が変 → `bpmQ8` を `bpmFixed × 256` で計算していないか（古い文書の罠）
- Processing が読めない → USB Serial がデバッグログとパケットを混ぜていないか
  （`SERIAL_DEBUG=0` を確認）

## 次に読むべきページ

- 受信したパケットの先 → [楽譜進行ロジック](/deep-dive/score-progression/)
- 楽器→PC の発音側 → [加算合成エンジン](/deep-dive/additive-synthesis/)
- 通信路の選定理由 → [UDP マルチキャスト](/deep-dive/udp-multicast/)
