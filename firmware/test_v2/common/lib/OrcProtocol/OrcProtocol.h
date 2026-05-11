// Build (run from project root) — shared by node_01〜node_04 of test_v2:
//   pio run -d firmware/test_v2/node_01     # 指揮者ノード
//   pio run -d firmware/test_v2/node_02     # 輪唱 声部 1
//
// CTRL / BEAT / NOTE 共通の 20 バイト固定パケット定義
// 仕様: 共通ヘッダ 12 B + ペイロード 8 B、リトルエンディアン
//
// test_v2 の変更点: NotePayload の旧 reserved[0] を instrumentId に充てた。
// 楽器ノードは「輪唱の声部 = 楽器番号」を固定で持ち、PC 側 (orchestra_resynth) は
// この番号で読み込み済みの楽器定義 (sound_lab の JSON) を選んで加算合成する。
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace orc {

// ASCII "OR" (リトルエンディアンで 0x52 0x4F)
constexpr uint16_t MAGIC = 0x4F52;
constexpr uint8_t  PROTOCOL_VERSION = 0x01;

enum PacketType : uint8_t {
    PKT_CTRL = 1,
    PKT_BEAT = 2,
    PKT_NOTE = 3,
};

constexpr size_t HEADER_SIZE = 12;
constexpr size_t PACKET_SIZE = 20;

#pragma pack(push, 1)
struct PacketHeader {
    uint16_t magic;        // 0x4F52
    uint8_t  version;      // 0x01
    uint8_t  type;         // PacketType
    uint32_t seq;          // 単調増加
    uint32_t timestampMs;  // 送信時のマスタ時刻
};

struct CtrlPayload {
    uint16_t bpmQ8;        // BPM × 8 (例: 120.5 → 964)
    uint8_t  velocity;     // 0-127
    uint8_t  state;        // 0=Idle 1=Calibrating 2=Conducting 3=Fallback
    uint8_t  reserved[4];
};

struct BeatPayload {
    uint16_t beatNo;
    uint8_t  reserved[2];
    uint32_t playAtMasterMs;  // マスタ時刻でこの ms に発音せよ
};

struct NotePayload {
    uint8_t  partId;       // 0x02-0x05 (輪唱のどの声部か)
    uint8_t  noteNumber;   // MIDI 0-127, 60=C4 (高さ)
    uint8_t  velocity;     // 0-127
    uint8_t  gate;         // 1=NoteOn, 0=NoteOff
    uint16_t durationMs;   // 発音予定長 (長さ)
    uint8_t  instrumentId; // 0..N-1: PC 側で読み込んだ楽器定義のインデックス (楽器番号)
    uint8_t  reserved;     // 0 埋め
};

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
#pragma pack(pop)

static_assert(sizeof(PacketHeader) == HEADER_SIZE, "header must be 12 B");
static_assert(sizeof(CtrlPacket) == PACKET_SIZE, "ctrl packet must be 20 B");
static_assert(sizeof(BeatPacket) == PACKET_SIZE, "beat packet must be 20 B");
static_assert(sizeof(NotePacket) == PACKET_SIZE, "note packet must be 20 B");

// magic / version の妥当性を確認しヘッダを取り出す
bool parseHeader(const uint8_t* buf, size_t len, PacketHeader& out);

}  // namespace orc
