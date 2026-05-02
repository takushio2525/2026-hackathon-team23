// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test/node_02
//   pio run -d firmware/test/node_02 -t upload
//   pio device monitor -d firmware/test/node_02
//
// 楽器ノード node_02 の全モジュール共有データ
// 仕様 §2.4.3.3 SystemData (抜粋) に準拠
#pragma once
#include <Arduino.h>

#include "OrcNetModule.h"          // OrcNetData
#include "StatusLedModule.h"       // StatusLedData
#include "OrcReceiverModule.h"     // ReceiverLogicData
#include "NoteSenderModule.h"      // NoteOutData / NoteSenderData

enum class PerformerState : uint8_t {
    Idle      = 0,
    WaitStart = 1,
    Playing   = 2,
};

struct SyncLogicData {
    int32_t  offsetMs = 0;
    uint16_t sampleCount = 0;
    bool     converged = false;
};

struct CtrlData {
    float    bpm = 120.0f;
    uint8_t  velocity = 64;
    uint8_t  state = 0;
    uint32_t lastReceivedMs = 0;
};

struct PerformerStateData {
    PerformerState state = PerformerState::Idle;
};

struct ScoreProgressData {
    uint16_t currentEventIndex = 0;
    bool     noteIsSounding = false;
    uint32_t noteOffAtMs = 0;
    uint16_t lastFiredEffectiveBeat = 0xFFFF;  // 同 BEAT で再発火しないため
};

struct SystemData {
    OrcNetData          orcNet;
    StatusLedData       led;
    ReceiverLogicData   receiver;
    NoteOutData         noteOut;
    NoteSenderData      noteSender;
    SyncLogicData       sync;
    CtrlData            ctrl;
    PerformerStateData  performer;
    ScoreProgressData   score;
};
