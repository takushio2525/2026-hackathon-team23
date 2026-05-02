// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test/node_01
//   pio run -d firmware/test/node_01 -t upload
//   pio device monitor -d firmware/test/node_01
//
// 指揮者ノードの全モジュール共有データを集約
// EMA 規約: モジュール間は SystemData のフィールド経由でのみ通信する
#pragma once
#include <Arduino.h>

#include "OrcNetModule.h"      // OrcNetData
#include "StatusLedModule.h"   // StatusLedData
#include "ImuModule.h"         // ImuData
#include "OrcSenderModule.h"   // OrcSenderData

enum class ConductorState : uint8_t {
    Idle        = 0,
    Calibrating = 1,
    Conducting  = 2,
    Fallback    = 3,
};

struct BeatLogicData {
    bool     event = false;        // 今周期で拍を検出したか (送信側がクリア)
    uint16_t beatNo = 0;
    uint32_t lastBeatMs = 0;
    uint32_t playAtMasterMs = 0;
    bool     armed = true;         // ヒステリシス: 次の HI 超えで BEAT を撃てる状態か
};

struct TempoLogicData {
    float    bpm = 120.0f;
    uint32_t nextBeatPredictedMs = 0;
    uint8_t  velocity = 64;        // ストレッチ未実装時は固定 64
};

struct CalibrationData {
    bool     done = false;
    uint32_t startMs = 0;
    uint32_t sampleCount = 0;
    float    accumAccel[3] = {0, 0, 0};
    float    gravityOffset[3] = {0, 0, 0};
};

struct ConductorStateData {
    ConductorState state = ConductorState::Idle;
};

struct SystemData {
    ImuData             imu;
    OrcNetData          orcNet;
    OrcSenderData       sender;
    StatusLedData       led;
    BeatLogicData       beat;
    TempoLogicData      tempo;
    CalibrationData     calibration;
    ConductorStateData  conductor;
};
