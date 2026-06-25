// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/production/node_01
//   pio run -d firmware/production/node_01 -t upload
//   pio device monitor -d firmware/production/node_01
//
// 指揮者ノード専用の出力モジュール
// applyPattern() が決めた拍/テンポ/状態を CTRL/BEAT パケットに組み立て、
// data.orcNet.pendingCtrl / pendingBeat に積む。実送信は OrcNetModule が行う。
#pragma once
#include <Arduino.h>
#include "IModule.h"
#include "ModuleTimer.h"

struct OrcSenderConfig {
    uint32_t ctrlIntervalMs;   // 50 ms = 20 Hz
    uint8_t  beatRedundancy;   // 同一 BEAT を何発まで連送するか (1-8 想定。2026-05-25 に ESP32-S3 SoftAP の radio ロス対策で旧 2 -> 4 に増量。連送間隔は OrcNetConfig.beatGapMs を参照)
    uint16_t beatLookaheadMs;  // playAtMasterMs = masterNow + lookahead
};

struct OrcSenderData {
    uint32_t ctrlSeq = 0;
    uint32_t beatSeq = 0;
    uint32_t lastCtrlSentMs = 0;
    bool     forceCtrlSend = false;   // 状態遷移・カーソル変更時にタイマーを待たず即送信
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
