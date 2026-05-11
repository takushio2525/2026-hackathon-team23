// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v2/node_02
//   pio run -d firmware/test_v2/node_02 -t upload
//   pio device monitor -d firmware/test_v2/node_02
//
// 楽器ノード入力モジュール (輪唱の 1 声部)
// data.orcNet (生の受信ペイロード) を読み、時計同期 / 受理 BEAT キュー / CTRL 状態を整形して
// data.sync / data.receiver / data.ctrl に書き出す
#pragma once
#include <Arduino.h>
#include "IModule.h"

struct OrcReceiverConfig {
    uint8_t  partId;              // 0x02-0x04: 輪唱のどの声部か
    uint16_t headRestBeats;       // 輪唱: 先頭に入れる休符の拍数 (0=先頭から入る)。
                                  // applyPattern が firedBeatNo からこのぶん引いて楽譜を引く
    float    clockSyncEmaAlpha;   // 0.10
    uint8_t  clockSyncMinSamples; // 5 (デバッグ表示用. Playing 遷移条件には使わない)
    uint16_t loopIntervalMs;      // 5 ms (ループ周期)
};

struct PendingBeat {
    bool     valid = false;
    uint16_t beatNo = 0;
    uint32_t playAtMasterMs = 0;
    uint32_t enqueuedAtMs = 0;
};

struct ReceiverLogicData {
    bool        hasFirstBeat = false;
    uint16_t    lastBeatNo = 0;
    uint32_t    lastBeatMs = 0;
    PendingBeat pending;
};

class OrcReceiverModule : public IModule {
public:
    explicit OrcReceiverModule(const OrcReceiverConfig& cfg) : cfg_(cfg) {}
    bool init() override { return true; }
    void updateInput(SystemData& data) override;

private:
    OrcReceiverConfig cfg_;
};
