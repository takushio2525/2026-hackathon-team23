// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v3/node_04
//   pio run -d firmware/test_v3/node_04 -t upload
//   pio device monitor -d firmware/test_v3/node_04
//
// 楽器ノード出力モジュール (輪唱の 1 声部)
// data.noteOut.pendingOn を見て NotePacket (20 B, NoteOn のみ) を組み立て、
// USB Serial で Mac へ書き出す。1 パケットに「楽器番号(instrumentId)・高さ(noteNumber)
// ・長さ(durationMs)・声部(partId)・velocity」が乗る。
// 消音は Processing 側が NotePacket.durationMs から自動で行うため、NoteOff は送らない。
#pragma once
#include <Arduino.h>
#include "IModule.h"

struct NoteSenderConfig {
    uint32_t baudRate;     // 115200 (UNO R4 WiFi の Serial は USB CDC)
    uint8_t  partId;       // 0x02-0x04: 輪唱のどの声部か
    uint8_t  instrumentId; // 0..N-1: PC 側 (orchestra_resynth) で読み込んだ楽器定義のインデックス
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
