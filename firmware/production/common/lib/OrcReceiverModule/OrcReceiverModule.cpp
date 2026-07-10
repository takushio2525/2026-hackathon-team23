// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/production/node_XX
//   pio run -d firmware/production/node_XX -t upload
//   pio device monitor -d firmware/production/node_XX

#include "OrcReceiverModule.h"
#include "SystemData.h"
#include "MopTest.h"

namespace {

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

// 時計同期: min フィルタ (窓内最大 offset サンプル追従、NTP 系の定石)。
// 返り値: スナップ (大ジャンプの即時追従) が起きたか。
//
// 設計意図 (tools/verification/results/MOP5_systematic_shift_analysis_20260710.md §4/§8 案4):
//   SoftAP のマルチキャストは DTIM バッファリングで 204.8ms 周期のバースト配送になり、
//   サンプル (= timestampMs − millis() = 真のオフセット θ − 配送遅延 D) は
//   「θ から 0〜205ms 下に散らばる」。旧 EMA (α=0.20) は新鮮な CTRL と ~102ms 古い
//   BEAT の平均的な位置に落ち着き、推定マスタ時計が真値より 40〜55ms 遅れていた。
//   min フィルタは配送遅延が最小のサンプル (= 最大 sample) だけを信じるため、
//   推定時計が最小遅延線に張り付き、この系統遅れがほぼ消える。
//
// 実装:
//   - sample > 現 offset なら即採用 (より遅延の小さいサンプル。UNO R4 の millis() が
//     指揮者比で遅い個体 = sample が上昇トレンドの場合の追従もこの経路で即時)。
//   - 同時に窓 (clockSyncWindowMs) 内の最大 sample を記録し、窓満了で offset を
//     窓内最大値へ引き直す。offset が上振れノイズや下降トレンド (楽器側時計が
//     速い個体) で古くなっても、窓長ぶんの遅れで必ず追従し直せる。
//   - スナップ: 指揮者リセットでマスタ時計 millis() が 0 付近へ巻き戻ると sample が
//     数十秒〜数分ぶん飛ぶ。|sample − 現 offset| が snapThresholdMs を超えたら
//     フィルタをやめて即時採用し、収束カウントと窓をやり直す (旧 EMA 実装と同じ
//     1 パケット追従を維持)。SoftAP 直結 LAN の正常遅延 (バースト待ち含め ~205ms)
//     では閾値 1000ms に届かない。
bool OrcReceiverModule::updateClockOffset(SystemData& data, uint32_t timestampMs) {
    const int32_t sample = (int32_t)(timestampMs - millis());
    bool snapped = false;
    if (data.sync.sampleCount == 0) {
        data.sync.offsetMs = sample;
        winValid_ = false;
    } else {
        const int32_t jump = sample - data.sync.offsetMs;
        if (jump > (int32_t)cfg_.clockSyncSnapThresholdMs ||
            jump < -(int32_t)cfg_.clockSyncSnapThresholdMs) {
            // スナップ: 巻き戻った (または大きく飛んだ) マスタ時計に即追従し、
            // 収束カウントもやり直す。
            data.sync.offsetMs    = sample;
            data.sync.sampleCount = 0;
            data.sync.converged   = false;
            winValid_ = false;
            snapped = true;
        } else {
            if (sample > data.sync.offsetMs) {
                data.sync.offsetMs = sample;
            }
            const uint32_t nowMs = millis();
            if (!winValid_) {
                winValid_     = true;
                winStartMs_   = nowMs;
                winMaxSample_ = sample;
            } else {
                if (sample > winMaxSample_) winMaxSample_ = sample;
                if (nowMs - winStartMs_ >= cfg_.clockSyncWindowMs) {
                    // 窓満了: 窓内最大サンプルへ引き直し (下方向の再追従)、次の窓を開く
                    data.sync.offsetMs = winMaxSample_;
                    winValid_ = false;
                }
            }
        }
    }
    if (data.sync.sampleCount < 0xFFFF) data.sync.sampleCount++;
    if (data.sync.sampleCount >= cfg_.clockSyncMinSamples) data.sync.converged = true;
    return snapped;
}

void OrcReceiverModule::updateInput(SystemData& data) {
    // 1. CTRL を受信していれば時計同期 + 状態取り込み
    if (data.orcNet.hasNewCtrl) {
        if (updateClockOffset(data, data.orcNet.lastCtrl.header.timestampMs)) {
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
    //   - clock sync は連送 4 個ぶん全部サンプルとして使う。min フィルタでは重複は
    //     自然に無害: 同一 timestampMs で millis() が経過ぶん進むため sample は
    //     初回以下になり、窓内最大値を押し上げない (旧 EMA の重複用 α は不要になった)。
    if (data.orcNet.hasNewBeat) {
        const uint16_t bn = data.orcNet.lastBeat.payload.beatNo;
        bool isDuplicate = data.receiver.hasFirstBeat &&
                           (bn == data.receiver.lastBeatNo);

        if (updateClockOffset(data, data.orcNet.lastBeat.header.timestampMs)) {
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

#if MOP_TEST == 4 || MOP_TEST == 5
            // MOP4/MOP5 共通の BEAT 受信記録 (受理した初回のみ = 1 beat 1 record)。
            // 旧実装は main.cpp 側にも M5I 出力があり同一拍が二重記録されていたため、
            // 計測出力はこの 1 箇所に統一した (発火時の M45F は applyPattern.cpp)。
            // localMasterMs = 受信処理時点の推定マスタ時刻。集計側が
            // lateMs = max(0, localMasterMs - playAtMasterMs) を計算し、
            // beatLookahead の発音予約が受信時点で間に合っているかを判定する。
            {
                const uint32_t tLocal = millis();
                const uint32_t localMasterMs = tLocal + (uint32_t)data.sync.offsetMs;
                mop_test::mprintf("M45R,%u,%u,%lu,%lu,%ld,%lu\n",
                                  (unsigned)cfg_.partId, (unsigned)bn,
                                  (unsigned long)data.orcNet.lastBeat.payload.playAtMasterMs,
                                  (unsigned long)tLocal,
                                  (long)data.sync.offsetMs,
                                  (unsigned long)localMasterMs);
            }
#endif
#if MOP_TEST == 9
            mop_test::mprintf("M9,%u,%u,%lu,%lu\n",
                              (unsigned)cfg_.partId, (unsigned)bn,
                              (unsigned long)data.orcNet.lastBeat.header.seq,
                              (unsigned long)millis());
#endif
        }
        // 重複でも lastBeatMs は更新する (受信タイムアウト監視・診断ログ用)
        data.receiver.lastBeatMs = millis();
    }
}
