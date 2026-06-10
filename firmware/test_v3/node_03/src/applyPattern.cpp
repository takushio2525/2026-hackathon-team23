// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v3/node_03
//   pio run -d firmware/test_v3/node_03 -t upload
//   pio device monitor -d firmware/test_v3/node_03
//
// 楽器ノード (輪唱の 1 声部) の判断ロジック
// 設計方針: BPM はあくまで補助 (durationMs 計算で使用)。score の進行は
// 「指揮者の拍番号 firedBeatNo」で決める。輪唱は headRestBeats だけ頭の拍を
// 読み飛ばしてから kScore[0] を鳴らし始める (声部ごとにずれて入る)。
// 拍番号駆動なので、Processing をいつ起動しても「曲の現在位置」から自然に鳴る。
//
// 処理フロー:
//   1. 時計オフセット更新 (受信側で済 — Receiver が data.sync を更新)
//   2. 演奏状態遷移 (Idle -> WaitStart -> Playing)
//   3. 保留 BEAT のキューイング (受信側で済 — data.receiver.pending)
//   4. マスタ時刻判定 (発音粒度)
//   5. 楽譜進行: firedBeatNo と headRestBeats から kScore のインデックスを算出して発火
//   6. velocity 合成 (fireScoreEvent 内)
#include <Arduino.h>

#include "SystemData.h"
#include "ProjectConfig.h"
#include "SerialDebug.h"
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
    DBG_PRINTF("[SUB] note=%u vel=%u dur=%u delay=%lu now=%lu\n",
               (unsigned)data.score.pendingSubNote,
               (unsigned)v,
               (unsigned)data.score.pendingSubDurationMs,
               (unsigned long)(now - data.score.pendingSubAtMs),
               (unsigned long)now);
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

    // 2. 演奏状態遷移 (Idle -> WaitStart -> Playing)
    // Playing への遷移条件は「最初の BEAT を受信した」だけ (sync.converged 待ちで
    // 鳴らない症状を避ける)。輪唱の「頭の休符」は Playing には入ってから headRestBeats
    // ぶん拍を消費する形で表すので、ここでは入り拍を待たない。
    switch (data.performer.state) {
        case PerformerState::Idle:
            if (data.orcNet.wifiConnected) {
                data.performer.state = PerformerState::WaitStart;
            }
            break;
        case PerformerState::WaitStart:
            if (data.receiver.hasFirstBeat) {
                data.performer.state = PerformerState::Playing;
            }
            break;
        case PerformerState::Playing:
            // BEAT が長く来なくても Playing に留まる。次の BEAT で自然に再開する。
            break;
    }

    // 4. 発音判定: マスタ時刻 playAtMasterMs に揃えて発火する (本来の同期設計)。
    //   targetLocalMs = playAtMasterMs - sync.offsetMs (マスタ時刻 → 自分のローカル ms)
    //   - waitMs <= 0 (既に到来 or 受信遅延): 即発火 (期限切れでも捨てない。捨てると鳴らなくなる)
    //   - waitMs >  0: この周期は何もしない。次ループで再評価し時刻到来したら発火する
    // 各スレーブが同じ playAtMasterMs に対してそれぞれの sync.offsetMs を引いて
    // 待つため、複数スレーブの発音はマスタ時刻基準で自然に揃う。
    // 旧即発火版は受信遅延ぶんスレーブ間でズレていたが、本実装ではそのズレが消える。
    bool     fired       = false;
    uint16_t firedBeatNo = 0;   // 発火した拍の指揮者拍番号 (1 始まり)
    if (data.performer.state == PerformerState::Playing &&
        data.receiver.pending.valid) {
        const int32_t targetLocalMs =
            (int32_t)data.receiver.pending.playAtMasterMs - data.sync.offsetMs;
        const int32_t waitMs = targetLocalMs - (int32_t)now;
        if (waitMs <= 0) {
            fired       = true;
            firedBeatNo = data.receiver.pending.beatNo;
            data.receiver.pending.valid = false;
        }
        // waitMs > 0: 次ループで再評価 (pending は valid のまま残す)
    }

    // 5. 楽譜進行: 指揮者拍番号 firedBeatNo から自分の楽譜インデックスを算出する。
    //   effective = firedBeatNo - 1 - headRestBeats
    //     effective < 0          : まだ「頭の休符」期間 → 何も鳴らさない (拍を消費するだけ)
    //     effective >= 0         : scoreIndex = effective % kScoreLength で kScore を引いて発火
    // 拍番号で引くので、Processing をいつ起動しても曲の現在位置から鳴り始める。
    // 拍が一つ飛んでも firedBeatNo に追随するだけでズレが残らない (自己補正)。
    if (fired && kScoreLength > 0) {
        const int32_t effective =
            (int32_t)firedBeatNo - 1 - (int32_t)ORC_RECEIVER_CONFIG.headRestBeats;
        if (effective >= 0) {
            const uint32_t scoreIndex = (uint32_t)effective % (uint32_t)kScoreLength;
            fireScoreEvent(data, kScore[scoreIndex], now);
            data.score.currentEventIndex = (uint16_t)scoreIndex;   // 診断ログ用
        }
    }

    // (NoteOff 判定はない: 消音は Processing 側が NotePacket.durationMs から自動で行う。)

    // LED
    updatePerformerLed(data);
}
