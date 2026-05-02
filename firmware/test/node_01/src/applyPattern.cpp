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

    // 1. IIR LPF + ノルム計算
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

    // 2-3. 拍検出 + テンポ推定 (Conducting 時のみ実行)
    if (data.conductor.state == ConductorState::Conducting && data.imu.ready) {
        if (data.imu.accNorm > BEAT_ACCEL_THRESHOLD_G &&
            now - sLastBeatMs >= BEAT_REFRACTORY_MS) {
            data.beat.event = true;
            data.beat.beatNo += 1;
            data.beat.lastBeatMs = now;

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
