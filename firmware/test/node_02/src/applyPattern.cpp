// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test/node_02
//   pio run -d firmware/test/node_02 -t upload
//   pio device monitor -d firmware/test/node_02
//
// 楽器ノードの判断ロジック
// 設計方針: BPM はあくまで補助 (8 分音符の細分化や durationMs 計算で使用)。
// score の進行は「実 BEAT 受信ごとに 1 拍進める」純粋イベント駆動とし、
// BPM 起点の自走 (旧 SelfRun) は行わない。
//
// 仕様 §2.4.3.5 の処理フロー:
//   1. 時計オフセット更新 (受信側で済 — Receiver が data.sync を更新)
//   2. 演奏状態遷移 (Idle -> WaitStart -> Playing)
//   3. 保留 BEAT のキューイング (受信側で済 — data.receiver.pending)
//   4. マスタ時刻判定 (発音粒度)
//   5. 楽譜進行 (BEAT 受信ごとに発火)
//   6. velocity 合成
//   7. NoteOff 判定
#include <Arduino.h>

#include "SystemData.h"
#include "ProjectConfig.h"
#include "score_data.h"

namespace {

// durationQ8 を ms に変換 (Q8: 256 = 1 拍)
// BPM は CTRL から受け取った参考値。NoteOff の予定時刻計算に使う補助。
uint16_t durationQ8ToMs(uint16_t durationQ8, float bpm) {
    const float beats = (float)durationQ8 / 256.0f;
    return (uint16_t)(beats * 60000.0f / (bpm < 1.0f ? logic_params::DEFAULT_BPM : bpm));
}

// 楽譜の 1 イベントを発火 (NoteOn 予約のみ)。
// 消音は Processing 側が NotePacket.durationMs から自動で行うため、ここでは
// noteIsSounding 等の追跡は不要。
// 細分音符 (subNote != 0) があれば、現在 BPM から ms を計算して予約スロットに積む。
void fireScoreEvent(SystemData& data, const ScoreEvent& ev, uint32_t now) {
    const bool isRest = (ev.flags & 0x04) != 0 || ev.noteNumber == 0;
    if (!isRest) {
        // velocity 合成: score × ctrl / 127
        uint16_t v = ((uint16_t)ev.velocity * (uint16_t)data.ctrl.velocity) / 127;
        if (v > 127) v = 127;

        const uint16_t durMs = durationQ8ToMs(ev.durationQ8, data.ctrl.bpm);
        data.noteOut.noteNumber = ev.noteNumber;
        data.noteOut.velocity   = (uint8_t)v;
        data.noteOut.durationMs = durMs;
        data.noteOut.pendingOn  = true;
    }

    // 細分音符の予約 (拍頭から subOffsetQ8/256 拍ぶん遅らせて発火)
    if (ev.subNote != 0) {
        const float bpm = (data.ctrl.bpm >= 1.0f) ? data.ctrl.bpm
                                                  : logic_params::DEFAULT_BPM;
        const float beats = (float)ev.subOffsetQ8 / 256.0f;
        const uint32_t subDelayMs = (uint32_t)(beats * 60000.0f / bpm);
        data.score.pendingSub          = true;
        data.score.pendingSubAtMs      = now + subDelayMs;
        data.score.pendingSubNote      = ev.subNote;
        data.score.pendingSubVelocity  = ev.subVelocity;
        data.score.pendingSubDurationMs = durationQ8ToMs(ev.subDurationQ8, bpm);
    }
}

// 予約された細分音符の時刻が来ていれば NoteOn を出す。
// applyPattern の先頭で呼び、楽譜進行 (4 分 BEAT 受信) と同一ループに重ならないようにする。
void firePendingSub(SystemData& data, uint32_t now) {
    if (!data.score.pendingSub) return;
    if ((int32_t)(now - data.score.pendingSubAtMs) < 0) return;

    uint16_t v = ((uint16_t)data.score.pendingSubVelocity *
                  (uint16_t)data.ctrl.velocity) / 127;
    if (v > 127) v = 127;
    data.noteOut.noteNumber = data.score.pendingSubNote;
    data.noteOut.velocity   = (uint8_t)v;
    data.noteOut.durationMs = data.score.pendingSubDurationMs;
    data.noteOut.pendingOn  = true;
    data.score.pendingSub = false;
}

void updatePerformerLed(SystemData& data) {
    using namespace logic_params;
    switch (data.performer.state) {
        case PerformerState::Idle:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_IDLE_MS;
            break;
        case PerformerState::WaitStart:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_WAIT_START_MS;
            break;
        case PerformerState::Playing:
            data.led.solidOn = true;
            break;
    }
}

}  // namespace

void applyPattern(SystemData& data) {
    using namespace logic_params;
    const uint32_t now = millis();

    // 0. 予約された細分音符 (8 分音符等) の発火判定。
    //    前ループまでに fireScoreEvent から積まれた予約が、現時刻に達していれば発音する。
    firePendingSub(data, now);

    // 2. 演奏状態遷移 (Idle -> WaitStart -> Playing のみ。BPM 起点の自走は持たない)
    switch (data.performer.state) {
        case PerformerState::Idle:
            if (data.orcNet.wifiConnected) {
                data.performer.state = PerformerState::WaitStart;
            }
            break;
        case PerformerState::WaitStart:
            if (data.sync.converged && data.receiver.hasFirstBeat &&
                data.receiver.lastBeatNo >= ORC_RECEIVER_CONFIG.startBeatNo) {
                data.performer.state = PerformerState::Playing;
            }
            break;
        case PerformerState::Playing:
            // BEAT が長く来なくても Playing に留まる。次の BEAT で自然に再開する。
            break;
    }

    // 4. 発音判定 (Playing 中に保留 BEAT があるときだけ発火)
    bool     fired = false;
    uint16_t firedBeatNo = 0;

    if (data.performer.state == PerformerState::Playing &&
        data.receiver.pending.valid) {
        // マスタ時刻 = 自時計 + offsetMs
        const uint32_t masterNow = now + (uint32_t)data.sync.offsetMs;
        const uint32_t playAt = data.receiver.pending.playAtMasterMs;
        const int32_t  diff   = (int32_t)(masterNow - playAt);

        if (diff >= 0) {
            // grace 内なら発火、超過なら破棄
            if (diff <= (int32_t)ORC_RECEIVER_CONFIG.expiredGraceMs) {
                fired = true;
                firedBeatNo = data.receiver.pending.beatNo;
            }
            data.receiver.pending.valid = false;
        }
        // 未来時刻 (diff < 0) は次ループまで待機
    }

    // 6. 楽譜進行: BEAT 1 個 = currentEventIndex を 1 個進める純粋 index 駆動。
    // ScoreEvent.beatAt はソートとログ読みやすさのための参考値で、進行判定には
    // 使わない。末尾まで来たら先頭に戻ってループ再生する。
    if (fired) {
        const int32_t effective =
            (int32_t)firedBeatNo - (int32_t)ORC_RECEIVER_CONFIG.startBeatNo;
        if (effective >= 1) {
            // 同 effective で再発火しないよう lastFiredEffectiveBeat を見る (保険)
            const bool alreadyFired =
                (data.score.lastFiredEffectiveBeat != 0xFFFF) &&
                ((uint16_t)effective <= data.score.lastFiredEffectiveBeat);
            if (!alreadyFired) {
                if (data.score.currentEventIndex < kScoreLength) {
                    fireScoreEvent(data,
                                   kScore[data.score.currentEventIndex], now);
                    data.score.currentEventIndex++;
                    if (data.score.currentEventIndex >= kScoreLength) {
                        data.score.currentEventIndex = 0;  // 末尾まで来たらループ
                    }
                }
                data.score.lastFiredEffectiveBeat = (uint16_t)effective;
            }
        }
    }

    // (旧 NoteOff 判定はここにあったが、消音は Processing 側で durationMs から
    // 自動で行うため、node_02 では NoteOff パケットを送らない。)

    // LED
    updatePerformerLed(data);
}
