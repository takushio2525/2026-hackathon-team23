// 指揮者ノード専用の出力モジュール
// applyPattern() が決めた拍/テンポ/状態を CTRL/BEAT パケットに組み立て、
// data.orcNet.pendingCtrl / pendingBeat に積む。実送信は OrcNetModule が行う。
#pragma once
#include <Arduino.h>
#include "IModule.h"
#include "ModuleTimer.h"

struct OrcSenderConfig {
    uint32_t ctrlIntervalMs;   // 50 ms = 20 Hz
    uint8_t  beatRedundancy;   // 同一 BEAT を何発まで連送するか (1-3)
    uint16_t beatLookaheadMs;  // playAtMasterMs = masterNow + lookahead
};

struct OrcSenderData {
    uint32_t ctrlSeq = 0;
    uint32_t beatSeq = 0;
    uint32_t lastCtrlSentMs = 0;
};

class OrcSenderModule : public IModule {
public:
    explicit OrcSenderModule(const OrcSenderConfig& cfg) : cfg_(cfg) {}
    bool init() override { ctrlTimer_.setTime(); return true; }
    void updateOutput(SystemData& data) override;

private:
    OrcSenderConfig cfg_;
    ModuleTimer     ctrlTimer_;
};
