---
title: OrcProtocol — パケット定義の中身
description: CTRL / BEAT / NOTE 3 種類のパケットを 20 B 固定長で揃える型定義と、パース関数の安全網
sidebar:
  label: 共通 — OrcProtocol
  order: 2
---

:::note[この章で分かること]
- `CtrlPacket` / `BeatPacket` / `NotePacket` が **すべて 20 B ぴったり** に揃えられている理由
- `#pragma pack(push, 1)` と `static_assert` がどう型サイズを保証しているか
- `parseHeader()` のチェック順とフォールバック方針
:::

## 実体

| ファイル | 行数 | 内容 |
|---|---|---|
| `firmware/test_v2/common/lib/OrcProtocol/OrcProtocol.h` | 86 | パケット構造体 + 定数 + パース関数の宣言 |
| `firmware/test_v2/common/lib/OrcProtocol/OrcProtocol.cpp` | 20 | `parseHeader()` 実装 |

このモジュールは「定義の集約点」であって、`IModule` を継承していない。
**全ノードがリンクし、CTRL / BEAT / NOTE を共通の構造体として扱える** ことだけが目的。

## 全体構造

```
PacketHeader  (12 B 共通)
├─ magic       2 B   0x4F52 ('OR')
├─ version     1 B   0x01
├─ type        1 B   CTRL=1 / BEAT=2 / NOTE=3
├─ seq         4 B   送信側で単調増加
└─ timestampMs 4 B   送信時の millis()

CtrlPayload (8 B) | BeatPayload (8 B) | NotePayload (8 B)
└─ どれか 1 つがヘッダの後ろに続く

合計 = 12 + 8 = 20 B (常に)
```

## 定数と enum

```cpp
namespace orc {

constexpr uint16_t MAGIC = 0x4F52;          // ASCII "OR"
constexpr uint8_t  PROTOCOL_VERSION = 0x01;

enum PacketType : uint8_t {
    PKT_CTRL = 1,
    PKT_BEAT = 2,
    PKT_NOTE = 3,
};

constexpr size_t HEADER_SIZE = 12;
constexpr size_t PACKET_SIZE = 20;

}  // namespace orc
```

### MAGIC の値選定

`0x4F52` は ASCII 文字 `'O' 'R'` の **リトルエンディアン配置**（つまりバイト列で `0x52 0x4F`）。

ホストエンディアン依存を避けるため、`MAGIC` は `uint16_t` で持って `memcpy` で読み書きする。
パケットの先頭 2 バイトが `0x52 0x4F` でないものは、たとえ UDP マルチキャストに紛れ込んでも
即破棄される（IGMP 設定ミスや他アプリの汚染対策）。

### PROTOCOL_VERSION の使い方

現在は `0x01` 固定。将来「ヘッダに 1 B 増やす」「ペイロードを 12 B に拡張する」などの変更を
する場合、ここをインクリメントし、`parseHeader()` でバージョンに応じてサイズチェックを
切り替える設計。当面は単一バージョン運用。

## ヘッダ構造体

```cpp
#pragma pack(push, 1)
struct PacketHeader {
    uint16_t magic;        // 0x4F52
    uint8_t  version;      // 0x01
    uint8_t  type;         // PacketType
    uint32_t seq;          // 単調増加
    uint32_t timestampMs;  // 送信時のマスタ時刻 (送信ノードの millis())
};
#pragma pack(pop)
```

### `#pragma pack(push, 1)` の意味

C++ コンパイラはデフォルトで構造体のメンバを 4 B または 8 B 境界に揃える（パディング挿入）。
`#pragma pack(push, 1)` はこのアライメントを **1 B に強制** し、メンバを詰めて配置する。

これをやらないと、`PacketHeader` が 12 B のつもりが 16 B になってしまい、ネットワーク越しに
**バイト位置がずれる** 致命的バグになる。`#pragma pack(pop)` で元に戻す。

### サイズ保証 `static_assert`

```cpp
static_assert(sizeof(PacketHeader) == HEADER_SIZE, "header must be 12 B");
static_assert(sizeof(CtrlPacket) == PACKET_SIZE, "ctrl packet must be 20 B");
static_assert(sizeof(BeatPacket) == PACKET_SIZE, "beat packet must be 20 B");
static_assert(sizeof(NotePacket) == PACKET_SIZE, "note packet must be 20 B");
```

`#pragma pack` がコンパイラに無視された場合、**コンパイル時に検出してビルドを止める** 保険。
ESP32 (Xtensa) / Arduino UNO R4 (Renesas RA4M1) / macOS (Clang) すべてで通っていることを
CI で確認している。

## 3 種類のペイロード

### CtrlPayload — テンポと状態（20 Hz 連続配信）

```cpp
struct CtrlPayload {
    uint16_t bpmQ8;        // BPM × 8 (例: 120.5 → 964)
    uint8_t  velocity;     // 0-127
    uint8_t  state;        // 0=Idle 1=Calibrating 2=Conducting 3=Fallback
    uint8_t  reserved[4];
};
```

**`bpmQ8` の Q8 固定小数表記**

なぜ float ではなく `uint16_t` × 8 にしたのか：

| 観点 | float (4 B) | uint16_t × 8 (2 B) |
|---|---|---|
| サイズ | 4 B | 2 B (半分) |
| 精度 | 7 桁有効精度 | 0.125 BPM 刻み |
| エンディアン | プラットフォーム依存（IEEE754 だが順序が揺れる） | リトル固定で安全 |

楽器側のテンポ追従は 0.125 BPM 刻みで十分（人間が認識できる差ではない）し、
2 B 削った分を将来拡張に回せる。

エンコード（指揮者側）:
```cpp
pkt.payload.bpmQ8 = (uint16_t)(bpm * 8.0f + 0.5f);   // + 0.5 で四捨五入
```

デコード（楽器側）:
```cpp
data.ctrl.bpm = data.orcNet.lastCtrl.payload.bpmQ8 / 8.0f;
```

**`velocity` フィールド**

0–127 の MIDI 互換レンジ。`uint8_t` ぴったり。テンポと一緒に「強弱」のグローバル指示を
配信する設計（現状はストレッチ未実装で固定値 64）。

**`state` フィールド**

指揮者の状態機械をそのまま `uint8_t` にキャスト：

| 値 | 意味 | LED 周期 |
|---|---|---|
| 0 | Idle | 1 Hz 点滅 |
| 1 | Calibrating | 2 Hz 点滅 |
| 2 | Conducting | 点灯固定 |
| 3 | Fallback | 5 Hz 点滅 |

楽器側は受信した state を `data.ctrl.state` に格納するだけ（演奏判断には使わない）。
将来「指揮者が Fallback に入ったら楽器も停止する」などの拡張ポイントとして残してある。

### BeatPayload — 拍イベント（イベント駆動）

```cpp
struct BeatPayload {
    uint16_t beatNo;
    uint8_t  reserved[2];
    uint32_t playAtMasterMs;  // マスタ時刻でこの ms に発音せよ
};
```

**`beatNo`**

拍番号（0 オリジン、巻き戻しなしの単調増加）。`uint16_t` なので 65535 拍まで
（120 BPM で約 9 時間）。1 ステージ内では十分。

楽器側はこれを使って **重複排除**（同じ `beatNo` の BEAT を 2 回受け取っても発音は 1 回）と、
**取りこぼし検知**（`beatNo` の不連続）を行う。

**`playAtMasterMs` の役割**

「指揮者時計でこの時刻に発音せよ」という未来時刻。指揮者は拍検出した瞬間に：

```cpp
pkt.payload.playAtMasterMs = masterNow + cfg_.beatLookaheadMs;
// = masterNow + 50 ms
```

として **50 ms 先の時刻** を載せる。楽器側は時計同期で換算した自時計の時刻と比較して、
その時刻に揃えて NoteOn を吐く。これがネットワーク遅延の吸収 = 全楽器の発音タイミング統一の鍵。

詳しい同期理論は [時刻同期メカニズム](/deep-dive/time-sync/) を参照。

### NotePayload — 発音指示（楽器 → PC、シリアル経由）

```cpp
struct NotePayload {
    uint8_t  partId;       // 楽器ノードの ID（test_v2 は 0x02-0x04、production 想定は 0x02-0x05）
    uint8_t  noteNumber;   // MIDI 0-127, 60=C4
    uint8_t  velocity;     // 0-127
    uint8_t  gate;         // 1=NoteOn, 0=NoteOff
    uint16_t durationMs;   // 発音予定長
    uint8_t  instrumentId; // 0..N-1: PC 側で読み込んだ楽器定義のインデックス
    uint8_t  reserved;     // 0 埋め
};
```

**フィールドの順序が重要**

`partId / noteNumber / velocity / gate` を 1 B ずつ並べて 4 B、次に `durationMs` (2 B)、
最後に `instrumentId / reserved` で 2 B。`#pragma pack(1)` のおかげで詰めて 8 B。

**`gate` フィールドの省略**

test_v2 では NoteOff を送らない設計：

```cpp
data.noteOut.pendingOn = true;   // NoteOn のみ
// NoteOff は Processing 側が durationMs から自動消音
```

これにより：
- シリアル帯域が半分に減る
- 楽器側で「鳴っている音」を追跡する状態が要らなくなる
- Processing 側のボイスプールが durationMs + ADSR Release で勝手に終わる

`gate` は将来「NoteOff を明示的に送りたくなった」場合の拡張ポイント。

**`instrumentId` の意味（test_v2 で追加）**

旧 `reserved[0]` を `instrumentId` に充てた。PC 側は
`pc_app/test_v2/orchestra_resynth/data/` 配下の JSON を **ファイル名昇順** で配列化し、
`instrumentId` を **その配列の index** として参照して倍音定義から音色合成する。
3 ノードが instrumentId = 0 / 1 / 2 を持って、**輪唱の声部ごとに異なる音色** で鳴る仕掛け。

## 「フルパケット」構造体

```cpp
struct CtrlPacket {
    PacketHeader header;
    CtrlPayload  payload;
};
struct BeatPacket {
    PacketHeader header;
    BeatPayload  payload;
};
struct NotePacket {
    PacketHeader header;
    NotePayload  payload;
};
```

ヘッダ + ペイロードを連結しただけ。これらが「ネットワーク上に流す 20 B のバイト列」と
**完全に同じビット配置** になる。`reinterpret_cast<const uint8_t*>(&pkt)` で
そのままワイヤフォーマットになる。

## `parseHeader()` の実装

```cpp
bool parseHeader(const uint8_t* buf, size_t len, PacketHeader& out) {
    if (len < HEADER_SIZE) return false;
    memcpy(&out, buf, HEADER_SIZE);
    if (out.magic != MAGIC) return false;
    if (out.version != PROTOCOL_VERSION) return false;
    return true;
}
```

3 段階のチェック：

1. **サイズチェック**: バッファ長が 12 B 未満なら即 false（ヘッダすら読めない）
2. **MAGIC チェック**: `0x4F52` でなければ別アプリのパケット → 破棄
3. **バージョンチェック**: 既知バージョンでなければ → 破棄

このチェック順は **コストが安い順** に並べてある。`len` の比較は CPU 1 命令、`memcpy` は 12 B コピー、
MAGIC 比較は 16 bit 比較。明らかにダメなものを早期 reject する。

### 呼び出し側の使い方

```cpp
// OrcNetModule.cpp::pollReceive() から抜粋
orc::PacketHeader hdr;
if (!orc::parseHeader(buf, orc::PACKET_SIZE, hdr)) continue;   // パース失敗 → 次のパケットへ
if (hdr.type == orc::PKT_CTRL) {
    memcpy(&net.lastCtrl, buf, sizeof(net.lastCtrl));
    net.hasNewCtrl = true;
}
```

`parseHeader()` は **ヘッダだけ** を取り出す。ペイロードは type を判別してから対応する
構造体に `memcpy` する。これにより：

- 不正なタイプ値 (`type=99` など) は MAGIC/version が合っていてもどこにも書き込まれない
- 各ハンドラがそれぞれ独立して書き込み先を選べる

## エンディアン仮定

このプロトコルは **リトルエンディアン固定** で運用している。
理由：

- 関与ハードウェアは全部リトル
  - XIAO ESP32-S3 (Xtensa): リトル
  - Arduino UNO R4 WiFi (Renesas RA4M1, ARM Cortex-M4): リトル
  - macOS (x86_64 / arm64): リトル
- リトルからリトルへの転送なので `htons` / `ntohs` は不要
- バイトオーダー変換コストがゼロ

将来ビッグエンディアンのプラットフォームが混ざる場合は、`parseHeader()` 内で
`__builtin_bswap16` 等を入れる拡張ポイント。

## 落とし穴

- **`#pragma pack` を忘れると即死**。新しいペイロード構造体を足したら、必ず
  `static_assert(sizeof(...) == PACKET_SIZE, "...")` で守ること。
- **`memcpy` 経由でしか読まない**。`reinterpret_cast<NotePayload*>(buf)` のような
  ポインタキャストはアライメント未満のアクセスで UB になる場合がある（特に Renesas）。
- **`reserved` フィールドを未初期化のまま送らない**。`NotePacket pkt{};` のように値初期化
  すれば `reserved = 0` になる。
- **PC 側 Processing のパースもこの構造体定義と一致させる**。`pc_app/test_v2/orchestra_resynth/`
  でリトルエンディアンで読む（`ByteBuffer.order(ByteOrder.LITTLE_ENDIAN)`）。

## 関連ページ

- パケットがネットワークを流れる側 → [OrcNetModule](/firmware/orc-net/)
- パケットを組み立てる側 → [OrcSenderModule](/firmware/orc-sender/) / [NoteSenderModule](/firmware/note-sender/)
- バイト列レベルの解説 → [バイナリパケット](/deep-dive/binary-packet/)
- 公開 API 仕様 → `.agent/api.md`
