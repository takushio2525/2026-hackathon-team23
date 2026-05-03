// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test/node_04
//   pio run -d firmware/test/node_04 -t upload
//   pio device monitor -d firmware/test/node_04
//
// 楽器ノード出力モジュール
// data.noteOut.pendingOn を見て NotePacket (20 B, NoteOn のみ) を組み立て、
// USB Serial で 1 対 1 接続の Mac へ書き出す。
// 消音は Processing 側が NotePacket.durationMs から自動で行うため、NoteOff
// パケットは送らない (旧 pendingOff は削除)。
#pragma once
#include <Arduino.h>
#include "IModule.h"

struct NoteSenderConfig {
    uint32_t baudRate;  // 115200 (UNO R4 WiFi の Serial は USB CDC)
    uint8_t  partId;    // 0x04
};

struct NoteOutData {
    bool     pendingOn = false;
    uint8_t  noteNumber = 0;   // MIDI ノート番号
    uint8_t  velocity = 0;     // 0-127
    uint16_t durationMs = 0;   // Processing 側で自動消音するための長さ
};

struct NoteSenderData {
    uint32_t noteSeq = 0;
    uint32_t lastSentMs = 0;
};

class NoteSenderModule : public IModule {
public:
    explicit NoteSenderModule(const NoteSenderConfig& cfg) : cfg_(cfg) {}
    bool init() override;
    void updateOutput(SystemData& data) override;

private:
    NoteSenderConfig cfg_;
};
