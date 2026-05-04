// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test/node_02
//   pio run -d firmware/test/node_02 -t upload
//   pio device monitor -d firmware/test/node_02

#include "OrcReceiverModule.h"
#include "SystemData.h"

namespace {

void updateClockOffset(SystemData& data, uint32_t timestampMs, float alpha,
                       uint8_t minSamples) {
    const int32_t sample = (int32_t)(timestampMs - millis());
    if (data.sync.sampleCount == 0) {
        data.sync.offsetMs = sample;
    } else {
        // EMA (浮動小数で計算してから整数に丸める)
        const float prev = (float)data.sync.offsetMs;
        const float next = (1.0f - alpha) * prev + alpha * (float)sample;
        data.sync.offsetMs = (int32_t)next;
    }
    if (data.sync.sampleCount < 0xFFFF) data.sync.sampleCount++;
    if (data.sync.sampleCount >= minSamples) data.sync.converged = true;
}

}  // namespace

void OrcReceiverModule::updateInput(SystemData& data) {
    // 1. CTRL を受信していれば時計同期 + 状態取り込み
    if (data.orcNet.hasNewCtrl) {
        updateClockOffset(data,
                          data.orcNet.lastCtrl.header.timestampMs,
                          cfg_.clockSyncEmaAlpha,
                          cfg_.clockSyncMinSamples);

        data.ctrl.bpm = data.orcNet.lastCtrl.payload.bpmQ8 / 8.0f;
        data.ctrl.velocity = data.orcNet.lastCtrl.payload.velocity;
        data.ctrl.state = data.orcNet.lastCtrl.payload.state;
        data.ctrl.lastReceivedMs = millis();
    }

    // 2. BEAT を受信していれば時計同期 + 重複排除のうえ保留キューに積む
    if (data.orcNet.hasNewBeat) {
        updateClockOffset(data,
                          data.orcNet.lastBeat.header.timestampMs,
                          cfg_.clockSyncEmaAlpha,
                          cfg_.clockSyncMinSamples);

        const uint16_t bn = data.orcNet.lastBeat.payload.beatNo;
        const bool isDuplicate = data.receiver.hasFirstBeat &&
                                 (bn == data.receiver.lastBeatNo);
        if (!isDuplicate) {
            data.receiver.pending.valid = true;
            data.receiver.pending.beatNo = bn;
            data.receiver.pending.playAtMasterMs =
                data.orcNet.lastBeat.payload.playAtMasterMs;
            data.receiver.pending.enqueuedAtMs = millis();
            data.receiver.lastBeatNo = bn;
            data.receiver.hasFirstBeat = true;
        }
        // 重複でも lastBeatMs は更新する (受信タイムアウト監視・診断ログ用)
        data.receiver.lastBeatMs = millis();
    }
}
