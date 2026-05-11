// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v1/node_02
//   pio run -d firmware/test_v1/node_02 -t upload
//   pio device monitor -d firmware/test_v1/node_02
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
    // 消音は Processing 側が NotePacket.durationMs から自動で行うため、node_02 では
    // 鳴りっぱなしの追跡をしない (旧 noteIsSounding / noteOffAtMs は削除)。
    // ── 細分音符 (8 分音符など) の予約発火スロット ──
    // BEAT 受信時に fireScoreEvent から積まれ、applyPattern の先頭で時刻到達を判定する。
    // 後続の BEAT で新しい予約が来たら上書きされる (1 BEAT につき高々 1 個の subdivision)。
    bool     pendingSub = false;
    uint32_t pendingSubAtMs = 0;
    uint8_t  pendingSubNote = 0;
    uint8_t  pendingSubVelocity = 0;
    uint16_t pendingSubDurationMs = 0;
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
