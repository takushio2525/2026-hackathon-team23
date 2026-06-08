// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v2/node_01
//   pio run -d firmware/test_v2/node_01 -t upload
//   pio device monitor -d firmware/test_v2/node_01

#include "OrcSenderModule.h"
#include "SystemData.h"
#include "OrcProtocol.h"

void OrcSenderModule::updateOutput(SystemData& data) {
    const uint32_t masterNow = millis();

    // BEAT 送信予約 (イベント駆動)
    if (data.beat.event) {
        orc::BeatPacket pkt{};
        pkt.header.magic       = orc::MAGIC;
        pkt.header.version     = orc::PROTOCOL_VERSION;
        pkt.header.type        = orc::PKT_BEAT;
        pkt.header.seq         = ++data.sender.beatSeq;
        pkt.header.timestampMs = masterNow;
        pkt.payload.beatNo         = data.beat.beatNo;
        pkt.payload.reserved[0]    = 0;
        pkt.payload.reserved[1]    = 0;
        pkt.payload.playAtMasterMs = masterNow + cfg_.beatLookaheadMs;

        data.beat.playAtMasterMs = pkt.payload.playAtMasterMs;
        data.orcNet.pendingBeat  = pkt;
        data.orcNet.pendingBeatRedundancy = cfg_.beatRedundancy;
        data.orcNet.hasPendingBeat = true;

        // event は読み取り後にクリア
        data.beat.event = false;
    }

    // CTRL 送信予約 (周期駆動)
    if (ctrlTimer_.getNowTime() >= cfg_.ctrlIntervalMs) {
        ctrlTimer_.setTime();
        orc::CtrlPacket pkt{};
        pkt.header.magic       = orc::MAGIC;
        pkt.header.version     = orc::PROTOCOL_VERSION;
        pkt.header.type        = orc::PKT_CTRL;
        pkt.header.seq         = ++data.sender.ctrlSeq;
        pkt.header.timestampMs = masterNow;

        float bpm = data.tempo.bpm;
        if (bpm < 0)    bpm = 0;
        if (bpm > 8000) bpm = 8000;
        pkt.payload.bpmQ8     = (uint16_t)(bpm * 8.0f + 0.5f);
        pkt.payload.velocity  = data.tempo.velocity;
        pkt.payload.state     = (uint8_t)data.conductor.state;
        // test_v3 ゲームモード: 旧 reserved[4] に mode/navCursor/targetBpm/score を載せる
        pkt.payload.mode      = data.game.mode;
        pkt.payload.targetBpm = data.game.targetBpm;
        // Conducting 時: navCursor/score バイトにジャイロスコープ 2 軸 (int8, ±127) を載せる。
        // gyro[]/8: ±2000dps → ±250。典型的な指揮振り 100-500dps が ±12〜±62 に収まる。
        // 重力の影響がない角速度なので、傾けても静的オフセットが出ない。
        if (data.conductor.state == ConductorState::Conducting) {
            int gx = (int)(data.imu.gyro[0] / 8.0f);
            int gy = (int)(data.imu.gyro[1] / 8.0f);
            if (gx < -127) gx = -127; if (gx > 127) gx = 127;
            if (gy < -127) gy = -127; if (gy > 127) gy = 127;
            pkt.payload.navCursor = (uint8_t)(int8_t)gx;
            pkt.payload.score     = (uint8_t)(int8_t)gy;
        } else {
            pkt.payload.navCursor = data.game.navCursor;
            pkt.payload.score     = data.game.score;
        }

        data.orcNet.pendingCtrl    = pkt;
        data.orcNet.hasPendingCtrl = true;
        data.sender.lastCtrlSentMs = masterNow;
    }
}
