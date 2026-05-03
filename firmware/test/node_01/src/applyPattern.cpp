// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test/node_01
//   pio run -d firmware/test/node_01 -t upload
//   pio device monitor -d firmware/test/node_01
//
// 指揮者ノードの判断ロジック
// 仕様 §2.4.2.4 の処理フロー:
//   1. IIR LPF + ノルム計算
//   2. 拍検出 (Conducting 時のみ)
//   3. テンポ推定 (EMA)
//   4. 状態遷移 (Idle -> Calibrating -> Conducting <-> Fallback)
#include <math.h>
#include <Arduino.h>

#include "SystemData.h"
#include "ProjectConfig.h"
#include "SerialDebug.h"

namespace {

float    sLpfAcc[3] = {0, 0, 0};
bool     sLpfInit = false;
uint32_t sLastBeatMs = 0;
float    sBpmEma = 120.0f;
bool     sBpmInit = false;

// 拍検出のゲートステート。
//   Idle  : 動加速度が小さい状態。積分しない (ノイズ蓄積なし)。
//   Armed : dynNorm > BEAT_DYN_THRESHOLD_G で突入。Armed 中だけ
//           dynAcc を積分して経路長 sPathLen を計算する。
// 拍は Armed -> Idle のリリースエッジで判定する (= 振り終わりタイミング)。
enum class BeatGate : uint8_t { Idle, Armed };

BeatGate sGate         = BeatGate::Idle;
float    sVel[3]       = {0, 0, 0};   // 動加速度の時間積分 (m/s) — Armed 中のみ更新
float    sPathLen      = 0.0f;        // |sVel| の時間積分 (m)   — Armed 中のみ更新
float    sArmedPeakDyn = 0.0f;        // Armed 中の dynNorm 最大値 (デバッグ用)
uint32_t sArmedAtMs    = 0;           // Armed に入った時刻
uint32_t sLastImuMs    = 0;           // 直前に積分した IMU サンプル時刻
// 直前に終了した Armed セッションの最終結果。dump で「振りごとに何が起きたか」
// を可視化するため、新しい Armed が始まるまで保持する。
float    sLastArmedPath  = 0.0f;
float    sLastArmedPeak  = 0.0f;
uint16_t sLastArmedDurMs = 0;
bool     sLastArmedAdopt = false;

void gateToIdle() {
    sGate         = BeatGate::Idle;
    sVel[0] = sVel[1] = sVel[2] = 0.0f;
    sPathLen      = 0.0f;
    sArmedPeakDyn = 0.0f;
    sArmedAtMs    = 0;
    sLastImuMs    = 0;
}

void updateLed(SystemData& data) {
    using namespace logic_params;
    switch (data.conductor.state) {
        case ConductorState::Idle:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_IDLE_MS;
            break;
        case ConductorState::Calibrating:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_CALIBRATING_MS;
            break;
        case ConductorState::Conducting:
            data.led.solidOn = true;
            break;
        case ConductorState::Fallback:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_FALLBACK_MS;
            break;
    }
}

}  // namespace

void applyPattern(SystemData& data) {
    using namespace logic_params;
    const uint32_t now = millis();

    // 1. IIR LPF + ノルム計算 + 動加速度 (重力補正後) の計算
    if (data.imu.ready) {
        if (!sLpfInit) {
            for (int i = 0; i < 3; ++i) sLpfAcc[i] = data.imu.acc[i];
            sLpfInit = true;
        } else {
            for (int i = 0; i < 3; ++i) {
                sLpfAcc[i] = (1.0f - LPF_ALPHA) * sLpfAcc[i] +
                             LPF_ALPHA * data.imu.acc[i];
            }
        }
        for (int i = 0; i < 3; ++i) data.imu.accLpf[i] = sLpfAcc[i];
        data.imu.accNorm = sqrtf(sLpfAcc[0] * sLpfAcc[0] +
                                 sLpfAcc[1] * sLpfAcc[1] +
                                 sLpfAcc[2] * sLpfAcc[2]);
        // 動加速度 = LPF 後 - キャリブ重力。Calibrating 中は gravityOffset=0 なので
        // dyn=accLpf となり、Conducting 遷移直後はほぼ 0 から始まる。
        for (int i = 0; i < 3; ++i) {
            data.imu.dynAcc[i] = sLpfAcc[i] - data.calibration.gravityOffset[i];
        }
        data.imu.dynNorm = sqrtf(data.imu.dynAcc[0] * data.imu.dynAcc[0] +
                                 data.imu.dynAcc[1] * data.imu.dynAcc[1] +
                                 data.imu.dynAcc[2] * data.imu.dynAcc[2]);

        // Armed 中のみ dynAcc を二重積分して経路長 sPathLen を更新する。
        // Idle 中は積分しないので、起動からのノイズが蓄積することはない。
        if (data.conductor.state == ConductorState::Conducting &&
            data.calibration.done && sGate == BeatGate::Armed) {
            const uint32_t sampleMs = data.imu.sampleAtMs ? data.imu.sampleAtMs : now;
            if (sLastImuMs == 0) {
                sLastImuMs = sampleMs;
            } else {
                const uint32_t dtMs = sampleMs - sLastImuMs;
                sLastImuMs = sampleMs;
                // 5ms 周期想定。loop 遅延で dt が飛んだサンプルは捨てる。
                if (dtMs > 0 && dtMs <= 50) {
                    const float dt = dtMs * 0.001f;
                    for (int i = 0; i < 3; ++i) {
                        sVel[i] += data.imu.dynAcc[i] * GRAVITY_MS2 * dt;
                    }
                    const float vNorm = sqrtf(sVel[0] * sVel[0] +
                                              sVel[1] * sVel[1] +
                                              sVel[2] * sVel[2]);
                    sPathLen += vNorm * dt;
                }
            }
            if (data.imu.dynNorm > sArmedPeakDyn) sArmedPeakDyn = data.imu.dynNorm;
            data.beat.pathLenM = sPathLen;
        } else {
            // Conducting でない or Idle ゲート時: 積分は走らせない。
            // pathLen は前回確定値を 0 にしてデバッグの見え方を揃える。
            data.beat.pathLenM = sPathLen;
        }
    }

    // 4. 状態遷移
    switch (data.conductor.state) {
        case ConductorState::Idle:
            // SoftAP 起動完了で Calibrating へ
            if (data.orcNet.wifiConnected) {
                data.conductor.state = ConductorState::Calibrating;
                data.calibration.startMs = now;
                data.calibration.sampleCount = 0;
                data.calibration.accumAccel[0] = 0;
                data.calibration.accumAccel[1] = 0;
                data.calibration.accumAccel[2] = 0;
                data.calibration.done = false;
            }
            break;

        case ConductorState::Calibrating: {
            if (data.imu.ready) {
                for (int i = 0; i < 3; ++i) {
                    data.calibration.accumAccel[i] += data.imu.acc[i];
                }
                data.calibration.sampleCount++;
            }
            if (now - data.calibration.startMs >= CALIBRATION_MS) {
                if (data.calibration.sampleCount > 0) {
                    for (int i = 0; i < 3; ++i) {
                        data.calibration.gravityOffset[i] =
                            data.calibration.accumAccel[i] /
                            (float)data.calibration.sampleCount;
                    }
                } else {
                    data.calibration.gravityOffset[0] = 0;
                    data.calibration.gravityOffset[1] = 0;
                    data.calibration.gravityOffset[2] = 1.0f;
                }
                data.calibration.done = true;
                data.conductor.state = ConductorState::Conducting;
            }
            break;
        }

        case ConductorState::Conducting: {
            const bool imuOk = data.imu.ready ||
                               (now - data.imu.sampleAtMs < IMU_TIMEOUT_MS);
            if (!imuOk || !data.orcNet.wifiConnected) {
                data.conductor.state = ConductorState::Fallback;
            }
            break;
        }

        case ConductorState::Fallback: {
            const bool imuOk = data.imu.ready ||
                               (now - data.imu.sampleAtMs < IMU_TIMEOUT_MS);
            if (imuOk && data.orcNet.wifiConnected) {
                data.conductor.state = ConductorState::Conducting;
            }
            break;
        }
    }

    // 2-3. 拍検出 (ゲート式ステートマシン)
    //   Idle:  dynNorm > BEAT_DYN_THRESHOLD_G で Armed に遷移し積分を開始
    //   Armed: 以下のいずれかでリリース判定に入る
    //          (a) dynNorm < BEAT_RELEASE_G        (絶対値: 完全停止)
    //          (b) dynNorm < peak * BEAT_RELEASE_RATIO (相対値: ピークアウト後減衰)
    //          (c) Armed 開始から BEAT_ARMED_TIMEOUT_MS 経過 (保険)
    //          リリース時点で sPathLen >= 閾値 かつ refractory 経過なら拍確定。
    //          (a)(b)(c) いずれの経路でも採用条件は同じ (取りこぼし防止)。
    //   突入直後 BEAT_ARMED_MIN_HOLD_MS は (a)(b) を抑制し、突入直後の単発
    //   ノイズで即リリースしてしまうのを防ぐ。
    if (data.conductor.state == ConductorState::Conducting && data.imu.ready) {
        switch (sGate) {
            case BeatGate::Idle:
                if (data.imu.dynNorm > BEAT_DYN_THRESHOLD_G) {
                    sGate         = BeatGate::Armed;
                    sArmedAtMs    = now;
                    sArmedPeakDyn = data.imu.dynNorm;
                    sVel[0] = sVel[1] = sVel[2] = 0.0f;
                    sPathLen      = 0.0f;
                    sLastImuMs    = 0;
                }
                break;

            case BeatGate::Armed: {
                const uint32_t armedFor    = now - sArmedAtMs;
                const bool pathOk          = sPathLen >= BEAT_PATH_THRESHOLD_M;
                const bool minHoldOk       = armedFor >= BEAT_ARMED_MIN_HOLD_MS;
                const bool releaseAbs      = data.imu.dynNorm < BEAT_RELEASE_G;
                const bool releaseRatio    = (sArmedPeakDyn > 0.0f) &&
                                             (data.imu.dynNorm <
                                              sArmedPeakDyn * BEAT_RELEASE_RATIO);
                // path がまだ届いていないならリリースを抑制 (= もっと振らせる)。
                // 振り下ろし加速ピーク直後の dynNorm 落下で 100ms 以内に Armed
                // が終わってしまい、積分量が 1〜2cm しか積めない問題を回避する。
                const bool released        = minHoldOk && pathOk &&
                                             (releaseAbs || releaseRatio);
                const bool timeout         = armedFor >= BEAT_ARMED_TIMEOUT_MS;
                if (released || timeout) {
                    const bool refractoryOk = (now - sLastBeatMs) >= BEAT_REFRACTORY_MS;
                    const bool adopted      = pathOk && refractoryOk;
                    if (adopted) {
                        data.beat.event = true;
                        data.beat.beatNo += 1;
                        data.beat.lastBeatMs = now;

                        if (sLastBeatMs != 0) {
                            const uint32_t intervalMs = now - sLastBeatMs;
                            if (intervalMs > 0) {
                                const float instBpm = 60000.0f / (float)intervalMs;
                                if (!sBpmInit) {
                                    sBpmEma  = instBpm;
                                    sBpmInit = true;
                                } else {
                                    sBpmEma = (1.0f - BPM_EMA_ALPHA) * sBpmEma +
                                              BPM_EMA_ALPHA * instBpm;
                                }
                                if (sBpmEma < BPM_MIN) sBpmEma = BPM_MIN;
                                if (sBpmEma > BPM_MAX) sBpmEma = BPM_MAX;
                                data.tempo.bpm = sBpmEma;
                                const uint32_t periodMs = (uint32_t)(60000.0f / sBpmEma);
                                data.tempo.nextBeatPredictedMs = now + periodMs;
                            }
                        }
                        sLastBeatMs = now;
                    }
                    // 振りごとのサマリを 1 行で出力 (拍検出のチューニング用)
                    const char* reason = timeout ? "timeout"
                                       : releaseAbs ? "abs"
                                       : "ratio";
                    DBG_PRINTF("[N1 ARM_END dur=%lu peak=%4.2f path=%5.3f reason=%s adopt=%s]\n",
                               (unsigned long)armedFor,
                               sArmedPeakDyn,
                               sPathLen,
                               reason,
                               adopted ? "YES" : "NO");
                    // 直前セッションを保存してから Idle へ
                    sLastArmedPath  = sPathLen;
                    sLastArmedPeak  = sArmedPeakDyn;
                    sLastArmedDurMs = (armedFor > 65535u) ? 65535u : (uint16_t)armedFor;
                    sLastArmedAdopt = adopted;
                    gateToIdle();
                    data.beat.pathLenM = 0.0f;
                }
                break;
            }
        }
    } else {
        // Conducting 以外ではゲートを必ず Idle に戻しておく
        if (sGate != BeatGate::Idle) gateToIdle();
    }

    // デバッグ可視化用にゲート状態を SystemData にミラー
    data.beat.gateState    = (sGate == BeatGate::Armed) ? 1 : 0;
    data.beat.armedPeakDyn = sArmedPeakDyn;

    // LED 状態
    updateLed(data);
}
