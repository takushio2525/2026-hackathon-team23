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

namespace {

float    sLpfAcc[3] = {0, 0, 0};
bool     sLpfInit = false;
uint32_t sLastBeatMs = 0;
float    sBpmEma = 120.0f;
bool     sBpmInit = false;
// 拍検出ヒステリシスの「次の BEAT を撃てる状態か」フラグ。
// true: 振り下ろしの加速度が HI を超えれば BEAT 発火可
// false: 既に発火済み。|dynAlongG| が LO 未満に戻るまで再発火を抑止
bool     sBeatArmed = true;
// 重力方向の単位ベクトル。Calibrating 完了時に算出して固定する。
// dynAlongG = dynAcc・gravityUnit が「振り下ろし方向 (重力と同方向の動き)」で
// 負になる (= センサが下方向に投げ出される = 反力としての加速度が抜ける)。
float    sGravityUnit[3] = {0.0f, 0.0f, 1.0f};
bool     sGravityUnitReady = false;

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
                // 重力方向の単位ベクトルを保存 (拍検出で使う射影方向)
                const float gn = sqrtf(
                    data.calibration.gravityOffset[0] * data.calibration.gravityOffset[0] +
                    data.calibration.gravityOffset[1] * data.calibration.gravityOffset[1] +
                    data.calibration.gravityOffset[2] * data.calibration.gravityOffset[2]);
                if (gn > 0.1f) {
                    for (int i = 0; i < 3; ++i) {
                        sGravityUnit[i] = data.calibration.gravityOffset[i] / gn;
                    }
                    sGravityUnitReady = true;
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

    // 2-3. 拍検出 + テンポ推定 (Conducting 時のみ実行)
    // 判定は動加速度を「重力方向に射影した成分」dynAlongG で行う。
    // dynAlongG が大きく負 = 振り下ろし (重力と逆向きの加速度ピーク) を 1 BEAT として捉える。
    // 振り戻し (正方向の加速度) では発火しないので、1 振り = 1 BEAT が構造的に保証される。
    if (data.conductor.state == ConductorState::Conducting && data.imu.ready) {
        const float dynAlongG = data.imu.dynAcc[0] * sGravityUnit[0] +
                                data.imu.dynAcc[1] * sGravityUnit[1] +
                                data.imu.dynAcc[2] * sGravityUnit[2];
        // 解除: 重力方向の動加速度がほぼ 0 に戻ったら次の振りを受け付ける
        if (!sBeatArmed && fabsf(dynAlongG) < BEAT_DOWN_LO_G) {
            sBeatArmed = true;
        }
        data.beat.armed = sBeatArmed;
        data.beat.dynAlongG = dynAlongG;
        // 振り下ろし発火: アームド + 負方向に HI 超え + refractory 経過
        if (sBeatArmed && dynAlongG < -BEAT_DOWN_HI_G &&
            now - sLastBeatMs >= BEAT_REFRACTORY_MS) {
            data.beat.event = true;
            data.beat.beatNo += 1;
            data.beat.lastBeatMs = now;
            sBeatArmed = false;  // 次の解除まで発火停止

            if (sLastBeatMs != 0) {
                const uint32_t intervalMs = now - sLastBeatMs;
                if (intervalMs > 0) {
                    const float instBpm = 60000.0f / (float)intervalMs;
                    if (!sBpmInit) {
                        sBpmEma = instBpm;
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
    }

    // LED 状態
    updateLed(data);
}
