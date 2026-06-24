// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/production/node_02
//
// UiRelayModule の実装。詳細は UiRelayModule.h と .agent/production-game-design.md を参照。

#include "UiRelayModule.h"
#include "SystemData.h"
#include "OrcProtocol.h"

void UiRelayModule::updateOutput(SystemData& data) {
#if SERIAL_DEBUG
    // 人間可読モニタ用ビルドではバイナリ UI フレームを流さない。
    (void)data;
#else
    const uint32_t now   = millis();
    const uint16_t bpmQ8 = data.ctrl.bpmQ8;

    const bool changed =
        data.ctrl.state     != lastState_  ||
        data.ctrl.mode      != lastMode_   ||
        data.ctrl.navCursor != lastCursor_ ||
        data.ctrl.targetBpm != lastTarget_ ||
        data.ctrl.score     != lastScore_  ||
        bpmQ8               != lastBpmQ8_;
    const bool heartbeat = !hasSent_ || (now - lastSentMs_) >= cfg_.heartbeatMs;
    const bool rateOk    = !hasSent_ || (now - lastSentMs_) >= cfg_.minIntervalMs;

    // 変化があれば 5Hz 上限で送る。無変化でも heartbeat 間隔で 1 発送る。
    if (!((changed && rateOk) || heartbeat)) return;

    orc::UiPacket pkt{};
    pkt.header.magic       = orc::MAGIC;
    pkt.header.version     = orc::PROTOCOL_VERSION;
    pkt.header.type        = orc::PKT_UI;
    pkt.header.seq         = ++uiSeq_;
    pkt.header.timestampMs = now;
    pkt.payload.state      = data.ctrl.state;
    pkt.payload.mode       = data.ctrl.mode;
    pkt.payload.navCursor  = data.ctrl.navCursor;
    pkt.payload.targetBpm  = data.ctrl.targetBpm;
    pkt.payload.score      = data.ctrl.score;
    pkt.payload.partId     = cfg_.partId;
    pkt.payload.bpmQ8      = bpmQ8;
    Serial.write(reinterpret_cast<const uint8_t*>(&pkt), sizeof(pkt));
    // NoteSenderModule と同じく、USB CDC のまとめ送りを避けて即座にホストへ送り出す。
    Serial.flush();

    lastSentMs_ = now;
    hasSent_    = true;
    lastState_  = data.ctrl.state;
    lastMode_   = data.ctrl.mode;
    lastCursor_ = data.ctrl.navCursor;
    lastTarget_ = data.ctrl.targetBpm;
    lastScore_  = data.ctrl.score;
    lastBpmQ8_  = bpmQ8;
#endif
}
