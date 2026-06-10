// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v3/node_02
//
// 楽器ノード → PC への UI 状態中継モジュール (test_v3 ゲームモード)。
// data.ctrl (受信した CTRL の state/mode/navCursor/targetBpm/score/bpmQ8) を、
// UI フレーム (PKT_UI, 20B) として USB シリアルへ書き出す。NOTE バイナリ (PKT_NOTE) とは
// 別フレームとして同じ Serial に流す (PC 側は magic で再同期するので混在しても解釈できる)。
//
// 送出頻度: 「内容が変化したとき + minIntervalMs の上限」+「heartbeatMs ごとの保険送出」。
// Menu/Result 中の変化はユーザー操作ペース、Conducting 中は bpmQ8 の変化時のみで
// いずれも低頻度。USB 115200bps 上の演奏 NOTE のバーストを阻害しない。
// SERIAL_DEBUG=1 のときはバイナリを流さない (人間可読モニタを汚さない)。
#pragma once
#include <Arduino.h>
#include "IModule.h"

struct UiRelayConfig {
    uint8_t  partId;          // 中継元ノード ID (PC の役割判定用。node_02=0x02)
    uint16_t minIntervalMs;   // 変化送出の最小間隔 [ms] (200 = 5Hz 上限)
    uint16_t heartbeatMs;     // 無変化でも送る保険間隔 [ms] (PC が途中接続しても状態を拾える)
};

class UiRelayModule : public IModule {
public:
    explicit UiRelayModule(const UiRelayConfig& cfg) : cfg_(cfg) {}
    bool init() override { return true; }   // Serial は NoteSenderModule / main が begin 済み
    void updateOutput(SystemData& data) override;

private:
    UiRelayConfig cfg_;
    uint32_t uiSeq_      = 0;
    uint32_t lastSentMs_ = 0;
    bool     hasSent_    = false;
    // 直近に送った値 (変化検出用)。初期値は実値と必ず異なるダミー。
    uint8_t  lastState_  = 0xFE;
    uint8_t  lastMode_   = 0xFE;
    uint8_t  lastCursor_ = 0xFE;
    uint8_t  lastTarget_ = 0xFE;
    uint8_t  lastScore_  = 0xFE;
    uint16_t lastBpmQ8_  = 0xFFFF;
};
