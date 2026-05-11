// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v2/node_01
//   pio run -d firmware/test_v2/node_01 -t upload
//   pio device monitor -d firmware/test_v2/node_01
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
    // 前回拍からの経路長 (= |v| の時間積分, m 単位)。拍検出の AND ゲート用。
    // 拍確定 / 状態遷移などでゼロリセットされる。
    float    pathLenM = 0.0f;
    // デバッグ可視化用: 拍検出ゲートの状態と Armed 中の dynNorm 最大値。
    uint8_t  gateState = 0;        // 0 = Idle, 1 = Armed
    float    armedPeakDyn = 0.0f;
};

struct TempoLogicData {
    // 初期テンポは 100 BPM。最初の 1 拍 (= 1 音目) はまだ拍間隔が取れないので
    // この値で CTRL を送る。2 拍目で「1 拍目→2 拍目」の間隔からそのまま簡易テンポ
    // を確定し、以降は拍ごとに EMA で随時補正していく (applyPattern.cpp 参照)。
    float    bpm = 100.0f;
    uint32_t nextBeatPredictedMs = 0;
    uint8_t  velocity = 64;        // ストレッチ未実装時は固定 64
};

struct CalibrationData {
    bool     done = false;
    uint32_t startMs = 0;
    uint32_t sampleCount = 0;
    // 停止時の加速度ノルムの累積。軸ごとの重力ベクトルではなくスカラー 1 個だけ持つ。
    // 平均すると姿勢に依らない「静止ノルム ≒ 重力 1g」になる。
    float    accumNorm = 0.0f;
    float    gravityMag = 0.0f;   // 確定値 = accumNorm / sampleCount (≒ 1g)
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
