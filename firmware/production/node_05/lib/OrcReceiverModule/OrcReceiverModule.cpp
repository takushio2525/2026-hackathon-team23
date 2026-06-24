// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/production/node_05
//   pio run -d firmware/production/node_05 -t upload
//   pio device monitor -d firmware/production/node_05

#include "OrcReceiverModule.h"
#include "SystemData.h"

namespace {

// 返り値: スナップ (大ジャンプの即時追従) が起きたか。
// 指揮者がリセットされるとマスタ時計 millis() が 0 付近へ巻き戻り、offset サンプルが
// 一気に数十秒〜数分ぶん飛ぶ。EMA (α=0.20) だけだと新 offset への収束に約 1 秒かかり、
// その間は playAtMasterMs の発火判定が壊れる (過去扱いの即発火 or 遠未来扱いの無音)。
// |sample − 現 offset| が snapThresholdMs を超えたら EMA をやめて即時採用する。
// SoftAP 直結 LAN の正常遅延は数十 ms 以下なので、閾値 1000ms に正常系は届かない。
bool updateClockOffset(SystemData& data, uint32_t timestampMs, float alpha,
                       uint8_t minSamples, uint16_t snapThresholdMs) {
    const int32_t sample = (int32_t)(timestampMs - millis());
    bool snapped = false;
    if (data.sync.sampleCount == 0) {
        data.sync.offsetMs = sample;
    } else {
        const int32_t jump = sample - data.sync.offsetMs;
        if (jump > (int32_t)snapThresholdMs || jump < -(int32_t)snapThresholdMs) {
            // スナップ: 巻き戻った (または大きく飛んだ) マスタ時計に即追従し、
            // 収束カウントもやり直す。
            data.sync.offsetMs    = sample;
            data.sync.sampleCount = 0;
            data.sync.converged   = false;
            snapped = true;
        } else {
            // EMA (浮動小数で計算してから整数に丸める)
            const float prev = (float)data.sync.offsetMs;
            const float next = (1.0f - alpha) * prev + alpha * (float)sample;
            data.sync.offsetMs = (int32_t)next;
        }
    }
    if (data.sync.sampleCount < 0xFFFF) data.sync.sampleCount++;
    if (data.sync.sampleCount >= minSamples) data.sync.converged = true;
    return snapped;
}

// マスターリセット (offset スナップ) 検知時の後始末。
// pending.playAtMasterMs は旧マスタ時計の値で、新 offset では発火判定が壊れるため破棄。
// lastBeatNo は新しい連番 (1 から再開) と偶然一致して初拍を重複扱いで飲む事故を
// 防ぐためリセットする。performer.state を WaitStart に戻すことで、新マスタの
// 最初の BEAT を受信してから演奏を再開する（リセット直後の不安定な期間を飛ばす）。
void resetAfterMasterReset(SystemData& data) {
    data.receiver.pending.valid = false;
    data.receiver.hasFirstBeat  = false;
    data.receiver.lastBeatNo    = 0;
    data.performer.state        = PerformerState::WaitStart;
}

}  // namespace

void OrcReceiverModule::updateInput(SystemData& data) {
    // 1. CTRL を受信していれば時計同期 + 状態取り込み
    if (data.orcNet.hasNewCtrl) {
        if (updateClockOffset(data,
                              data.orcNet.lastCtrl.header.timestampMs,
                              cfg_.clockSyncEmaAlpha,
                              cfg_.clockSyncMinSamples,
                              cfg_.clockSyncSnapThresholdMs)) {
            resetAfterMasterReset(data);
        }

        data.ctrl.bpm = data.orcNet.lastCtrl.payload.bpmQ8 / 8.0f;
        data.ctrl.velocity = data.orcNet.lastCtrl.payload.velocity;
        data.ctrl.state = data.orcNet.lastCtrl.payload.state;
        // production ゲームモード: 予約バイトから UI 状態を展開 (UiRelayModule が PC へ中継)
        data.ctrl.bpmQ8     = data.orcNet.lastCtrl.payload.bpmQ8;
        data.ctrl.mode      = data.orcNet.lastCtrl.payload.mode;
        data.ctrl.navCursor = data.orcNet.lastCtrl.payload.navCursor;
        data.ctrl.targetBpm = data.orcNet.lastCtrl.payload.targetBpm;
        data.ctrl.score     = data.orcNet.lastCtrl.payload.score;
        data.ctrl.lastReceivedMs = millis();
    }

    // 2. BEAT 受信:
    //   - 連送 (beatRedundancy 回) で同一 beatNo が複数届くが、payload は完全同一。
    //     違うのは header.timestampMs (各送信時刻) と header.seq。
    //   - pending (発音予約) は初到着の 1 個だけ採用。同 beatNo の発火後に
    //     後着が再キューされて「同じ拍を二度発音」する事故を避ける。
    //   - clock sync は連送 4 個ぶん全部サンプルとして使う。ただし重複は数 ms
    //     以内の強相関なので α を小さくし、初回サンプルが過剰反映されないようにする
    //     (旧実装は全 4 個を α=0.10 で吸って同じサンプルに 4 回追従していた)。
    if (data.orcNet.hasNewBeat) {
        const uint16_t bn = data.orcNet.lastBeat.payload.beatNo;
        bool isDuplicate = data.receiver.hasFirstBeat &&
                           (bn == data.receiver.lastBeatNo);

        if (updateClockOffset(data,
                              data.orcNet.lastBeat.header.timestampMs,
                              isDuplicate ? cfg_.clockSyncEmaAlphaDup
                                          : cfg_.clockSyncEmaAlpha,
                              cfg_.clockSyncMinSamples,
                              cfg_.clockSyncSnapThresholdMs)) {
            // この BEAT 自体は新マスタ時計の正しい playAtMasterMs を持つので、
            // 重複扱いを解いて「新時計の最初の BEAT」として受理し直す。
            resetAfterMasterReset(data);
            isDuplicate = false;
        }

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
