// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/production/node_05
//   pio run -d firmware/production/node_05 -t upload
//   pio device monitor -d firmware/production/node_05
//
// 楽器ノード node_05 (輪唱の 1 声部) の全モジュール共有データ
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
    float    bpm = 100.0f;   // CTRL 未受信時の既定。指揮者の初期テンポも 100 BPM
    uint8_t  velocity = 64;
    uint8_t  state = 0;
    // ── production ゲームモード: CTRL 予約バイトから展開した UI 状態 ──
    // UiRelayModule がこれらを PC へ中継する (演奏ロジックには使わない)。
    uint8_t  mode = 0;          // 0=自由演奏 / 1=ゲーム
    uint8_t  navCursor = 0;     // メニューカーソル位置
    uint8_t  targetBpm = 0;     // ゲーム目標テンポ (生 BPM)
    uint8_t  score = 0xFF;      // 得点 0-100 / 0xFF=未確定
    uint16_t bpmQ8 = 800;       // 実振り BPM ×8 (受信値をそのまま中継・演奏画面のテンポ表示用)
    uint32_t lastReceivedMs = 0;
};

struct PerformerStateData {
    PerformerState state = PerformerState::Idle;
};

struct ScoreProgressData {
    uint16_t currentEventIndex = 0;   // 直近に発火した kScore のインデックス (診断ログ用)
    // 消音は Processing 側が NotePacket.durationMs から自動で行うため、ここでは
    // 鳴りっぱなしの追跡をしない。
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
