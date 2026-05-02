// 楽器ノード出力モジュール
// data.noteOut.pendingOn / pendingOff を見て NotePacket (20 B) を組み立て、
// USB Serial で 1 対 1 接続の Mac へ書き出す
#pragma once
#include <Arduino.h>
#include "IModule.h"

struct NoteSenderConfig {
    uint32_t baudRate;  // 115200 (UNO R4 WiFi の Serial は USB CDC)
    uint8_t  partId;    // 0x02
};

struct NoteOutData {
    bool     pendingOn = false;
    bool     pendingOff = false;
    uint8_t  noteNumber = 0;   // MIDI ノート番号
    uint8_t  velocity = 0;     // 0-127
    uint16_t durationMs = 0;
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
