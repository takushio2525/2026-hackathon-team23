// Build (run from project root) — shared by node_01〜node_05 of production:
//   pio run -d firmware/production/node_01     # 指揮者ノード
//   pio run -d firmware/production/node_02     # 輪唱 声部 1
//
// CTRL / BEAT / NOTE / UI 共通の 20 バイト固定パケット定義
// 仕様: 共通ヘッダ 12 B + ペイロード 8 B、リトルエンディアン
//
// test_v2 の変更点: NotePayload の旧 reserved[0] を instrumentId に充てた。
// 楽器ノードは「輪唱の声部 = 楽器番号」を固定で持ち、PC 側 (orchestra_resynth) は
// この番号で読み込み済みの楽器定義 (sound_lab の JSON) を選んで加算合成する。
//
// production の変更点 (ゲームモード):
//   1. CtrlPayload の旧 reserved[4] を mode/navCursor/targetBpm/score にフィールド化。
//      自由演奏/ゲームのモード・メニューカーソル・目標テンポ・得点を指揮者→楽器へ載せる。
//      「画面」は (state, mode) から PC が導出するのでバイトは消費しない。
//   2. PKT_UI (type=4) を追加。楽器ノード→PC の USB シリアル専用で UI 状態を中継する。
//      UDP マルチキャストには一切流さない (同期経路 CTRL/BEAT/NOTE に無影響)。
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
    PKT_UI   = 4,   // production: 楽器→PC の UI 状態中継 (USB シリアル専用)
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
    uint16_t bpmQ8;        // BPM x 8 (例: 120.5 → 964)。実振り BPM (自由演奏/ゲーム共通)
    uint8_t  velocity;     // 0-127
    uint8_t  state;        // 0=Idle 1=Calibrating 2=Conducting 3=Fallback 4=Menu 5=Result
    // ── production ゲームモード: 旧 reserved[4] をフィールド化 ──
    // 画面は (state, mode) から PC が導出するのでここには持たない。カーソルだけ別バイト。
    uint8_t  mode;         // 0=自由演奏 / 1=ゲーム
    uint8_t  navCursor;    // メニューカーソル位置 0..N (Menu/Result で有効)
    uint8_t  targetBpm;    // ゲーム目標テンポ (生 BPM 40-240, 0=未設定/自由演奏では無視)
    uint8_t  score;        // ゲーム得点 0-100, 0xFF=未確定 (Menu/Result で有効)
};

struct BeatPayload {
    uint16_t beatNo;
    uint8_t  reserved[2];
    uint32_t playAtMasterMs;  // マスタ時刻でこの ms に発音せよ
};

struct NotePayload {
    uint8_t  partId;       // test_v2 は 0x02-0x04 / production は 0x02-0x05 / production 想定は 0x02-0x06 (ADR-0004 改訂版で楽器 5 台 = 金管 4 + ドラム 1)
    uint8_t  noteNumber;   // MIDI 0-127, 60=C4 (高さ)
    uint8_t  velocity;     // 0-127
    uint8_t  gate;         // 1=NoteOn, 0=NoteOff
    uint16_t durationMs;   // 発音予定長 (長さ)
    uint8_t  instrumentId; // 0..N-1: PC 側で読み込んだ楽器定義のインデックス (楽器番号)
    uint8_t  reserved;     // 0 埋め
};

// production: 楽器ノード → PC への UI 状態中継ペイロード (USB シリアル専用)。
// node_02 が受信 CTRL の中身を低頻度 (変化時 + 最大 5Hz) で PC へ転送し、Processing が
// (state, mode) から画面を自動判定する。UDP には流れない。
struct UiPayload {
    uint8_t  state;        // 0..5 (CtrlPayload.state と同義: Idle/Calibrating/Conducting/Fallback/Menu/Result)
    uint8_t  mode;         // 0=自由演奏 / 1=ゲーム
    uint8_t  navCursor;    // メニューカーソル位置 (Menu/Result で有効)
    uint8_t  targetBpm;    // ゲーム目標テンポ (生 BPM)
    uint8_t  score;        // ゲーム得点 0-100 / 0xFF=未確定 (Menu/Result で有効)
    uint8_t  partId;       // 中継元の楽器ノード ID (PC の役割判定用: 0x02=メイン操作 UI)
    uint16_t bpmQ8;        // 実振り BPM x8 (演奏画面のテンポ表示用)
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

struct UiPacket {
    PacketHeader header;
    UiPayload    payload;
};
#pragma pack(pop)

static_assert(sizeof(PacketHeader) == HEADER_SIZE, "header must be 12 B");
static_assert(sizeof(CtrlPacket) == PACKET_SIZE, "ctrl packet must be 20 B");
static_assert(sizeof(BeatPacket) == PACKET_SIZE, "beat packet must be 20 B");
static_assert(sizeof(NotePacket) == PACKET_SIZE, "note packet must be 20 B");
static_assert(sizeof(UiPacket) == PACKET_SIZE, "ui packet must be 20 B");

// magic / version の妥当性を確認しヘッダを取り出す
bool parseHeader(const uint8_t* buf, size_t len, PacketHeader& out);

}  // namespace orc
