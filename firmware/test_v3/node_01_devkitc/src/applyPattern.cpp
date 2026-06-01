// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v2/node_01
//   pio run -d firmware/test_v2/node_01 -t upload
//   pio device monitor -d firmware/test_v2/node_01
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
// 初期テンポ 100 BPM。1 音目 (= 最初の拍) はこの値で CTRL を流す。
// 2 拍目で sBpmInit が false なので「1→2 拍目の間隔」をそのまま簡易テンポとして採用し、
// 3 拍目以降は BPM_EMA_ALPHA で随時補正する。
float    sBpmEma = 100.0f;
bool     sBpmInit = false;

// 拍検出のゲートステート。
//   Idle  : 動加速度が小さい状態。積分しない (ノイズ蓄積なし)。
//   Armed : dynNorm > BEAT_DYN_THRESHOLD_G で突入。Armed 中だけ
//           dynAcc を積分して経路長 sPathLen を計算する。
// 拍は Armed -> Idle のリリースエッジで判定する (= 振り終わりタイミング)。
enum class BeatGate : uint8_t { Idle, Armed };

BeatGate sGate              = BeatGate::Idle;
float    sVel[3]            = {0, 0, 0};   // 動加速度の時間積分 (m/s) — Armed 中のみ更新
float    sPathLen           = 0.0f;        // |sVel| の時間積分 (m)   — Armed 中のみ更新
float    sArmedPeakDyn      = 0.0f;        // Armed 中の dynNorm 最大値 (デバッグ用)
uint32_t sArmedAtMs         = 0;           // Armed に入った時刻
uint32_t sLastImuMs         = 0;           // 直前に積分した IMU サンプル時刻
bool     sBeatFiredInArmed  = false;       // 現 Armed セッション中に既に発火したか
uint32_t sReleaseStartMs    = 0;           // リリース条件が連続成立し始めた時刻 (0=未成立)

void gateToIdle() {
    sGate              = BeatGate::Idle;
    sVel[0] = sVel[1] = sVel[2] = 0.0f;
    sPathLen           = 0.0f;
    sArmedPeakDyn      = 0.0f;
    sArmedAtMs         = 0;
    sLastImuMs         = 0;
    sBeatFiredInArmed  = false;
    sReleaseStartMs    = 0;
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

    // 1. IIR LPF + ノルム計算 + 動加速度ノルム (静止ノルム補正後) の計算
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
        // 動加速度ノルム = LPF 後の加速度ノルム − キャリブ済み静止ノルム (≒重力 1g)。
        // 軸ごとではなくスカラーで引くので姿勢に依存しない。水平で校正してから
        // 90 度傾けて振っても残留重力で誤検出しない (旧方式の不具合)。
        // Calibrating 中は gravityMag=0 なので dynNorm=accNorm。負側は 0 クランプ。
        float dynN = data.imu.accNorm - data.calibration.gravityMag;
        if (dynN < 0.0f) dynN = 0.0f;
        data.imu.dynNorm = dynN;
        // dynAcc は accLpf の向きを保ったまま大きさを dynNorm にスケール
        // (= 重力を「現在の加速度方向の成分」として差し引いた近似ベクトル)。
        // 経路長の二重積分はこのベクトルを使う。Armed 中は accNorm が十分大きく
        // 向きは振りに支配されるので近似として十分。
        if (data.imu.accNorm > 1e-3f) {
            const float k = dynN / data.imu.accNorm;
            for (int i = 0; i < 3; ++i) data.imu.dynAcc[i] = sLpfAcc[i] * k;
        } else {
            for (int i = 0; i < 3; ++i) data.imu.dynAcc[i] = 0.0f;
        }

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
                data.calibration.accumNorm = 0.0f;
                data.calibration.done = false;
            }
            break;

        case ConductorState::Calibrating: {
            if (data.imu.ready) {
                // 軸ごとではなく生加速度のノルムを累積する。停止していれば姿勢に
                // 関係なく ≒1g になり、その平均を「静止ノルム」として保持する。
                const float n = sqrtf(data.imu.acc[0] * data.imu.acc[0] +
                                      data.imu.acc[1] * data.imu.acc[1] +
                                      data.imu.acc[2] * data.imu.acc[2]);
                data.calibration.accumNorm += n;
                data.calibration.sampleCount++;
            }
            if (now - data.calibration.startMs >= CALIBRATION_MS) {
                if (data.calibration.sampleCount > 0) {
                    data.calibration.gravityMag =
                        data.calibration.accumNorm /
                        (float)data.calibration.sampleCount;
                } else {
                    data.calibration.gravityMag = 1.0f;   // フォールバック: 1g
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

    // 2-3. 拍検出 (ゲート式ステートマシン + 早期発火)
    //   Idle:  dynNorm > BEAT_DYN_THRESHOLD_G で Armed に遷移し積分を開始
    //   Armed:
    //     [発火] sPathLen が BEAT_FIRE_PATH_M に達した瞬間に拍を発火
    //            (Armed セッション中 1 回のみ、refractory も AND)。
    //            振り始めから ~100ms で発火するので体感的に振りと同期する。
    //            ※発火しても Armed は維持する。これが 1 振り=1 拍の鍵で、
    //              「発火→即 Idle→次サンプルで dyn 高いまま再 Arm→refractory
    //              境界で再発火」という連続発火ループを防ぐ。
    //     [リリース] 以下のいずれかで Idle に戻して次の振りに備える
    //       (a) dynNorm < BEAT_RELEASE_G   (絶対値: 完全停止)
    //       (b) dynNorm < peak * BEAT_RELEASE_RATIO (相対値: ピークアウト)
    //       (c) Armed 開始から BEAT_ARMED_TIMEOUT_MS 経過 (保険)
    //       未発火セッションでは pathOk も AND して弱い振りの早期リリースを防ぐ
    //       (発火済セッションは pathOk が自明なので無条件)。
    //       minHoldOk で突入直後の単発ノイズによる即リリースも防ぐ。
    if (data.conductor.state == ConductorState::Conducting && data.imu.ready) {
        switch (sGate) {
            case BeatGate::Idle:
                if (data.imu.dynNorm > BEAT_DYN_THRESHOLD_G) {
                    sGate              = BeatGate::Armed;
                    sArmedAtMs         = now;
                    sArmedPeakDyn      = data.imu.dynNorm;
                    sVel[0] = sVel[1] = sVel[2] = 0.0f;
                    sPathLen           = 0.0f;
                    sLastImuMs         = 0;
                    sBeatFiredInArmed  = false;
                }
                break;

            case BeatGate::Armed: {
                const uint32_t armedFor = now - sArmedAtMs;
                const bool pathOk       = sPathLen >= BEAT_FIRE_PATH_M;
                const bool minHoldOk    = armedFor >= BEAT_ARMED_MIN_HOLD_MS;

                // ── 早期発火: 1 Armed セッションに 1 回まで ──
                // path 閾値 + refractory 経過で発火する。Idle には戻さず Armed を
                // 維持し、リリース or timeout が来るのを待つ。これにより 1 振り
                // 中の二重発火を構造的に防ぐ。
                if (!sBeatFiredInArmed && pathOk &&
                    (now - sLastBeatMs) >= BEAT_REFRACTORY_MS) {
                    data.beat.event      = true;
                    data.beat.beatNo    += 1;
                    data.beat.lastBeatMs = now;

                    // テンポ推定の段取り:
                    //   1 拍目: sLastBeatMs == 0 なので何もしない (= 1 音目は初期値 100 BPM)
                    //   2 拍目: sBpmInit == false なので「1→2 拍目の間隔」をそのまま採用 (簡易テンポ)
                    //   3 拍目以降: BPM_EMA_ALPHA で随時補正
                    if (sLastBeatMs != 0) {
                        const uint32_t intervalMs = now - sLastBeatMs;
                        if (intervalMs > 0) {
                            const float instBpm = 60000.0f / (float)intervalMs;
                            if (!sBpmInit) {
                                sBpmEma  = instBpm;   // 簡易テンポ確定 (1→2 拍目)
                                sBpmInit = true;
                            } else {
                                sBpmEma = (1.0f - BPM_EMA_ALPHA) * sBpmEma +
                                          BPM_EMA_ALPHA * instBpm;   // 随時補正
                            }
                            if (sBpmEma < BPM_MIN) sBpmEma = BPM_MIN;
                            if (sBpmEma > BPM_MAX) sBpmEma = BPM_MAX;
                            data.tempo.bpm = sBpmEma;
                            const uint32_t periodMs = (uint32_t)(60000.0f / sBpmEma);
                            data.tempo.nextBeatPredictedMs = now + periodMs;
                        }
                    }
                    sLastBeatMs       = now;
                    sBeatFiredInArmed = true;
                }

                // ── リリース判定 (デバウンス付き) ──
                // 発火/未発火どちらでも評価する。
                // 発火済なら pathOk は自明なので無条件で release/timeout で抜ける。
                // 未発火なら pathOk を AND して弱い振りでの早期リリースを防止。
                // releaseInst を即時には採用せず、BEAT_RELEASE_HOLD_MS の間
                // 連続して成立したらリリース確定とする。これにより、振りの
                // 最中に dynNorm が一瞬 peak*RATIO を割るだけで Armed を抜けて
                // しまい、再 Armed→再発火が起きるチャタリングを防ぐ。
                const bool releaseAbs   = data.imu.dynNorm < BEAT_RELEASE_G;
                const bool releaseRatio = (sArmedPeakDyn > 0.0f) &&
                                          (data.imu.dynNorm <
                                           sArmedPeakDyn * BEAT_RELEASE_RATIO);
                const bool releaseInst  = releaseAbs || releaseRatio;
                if (releaseInst) {
                    if (sReleaseStartMs == 0) sReleaseStartMs = now;
                } else {
                    sReleaseStartMs = 0;
                }
                const bool releaseHeld = (sReleaseStartMs != 0) &&
                                         (now - sReleaseStartMs >= BEAT_RELEASE_HOLD_MS);
                const bool released = minHoldOk && releaseHeld &&
                                      (sBeatFiredInArmed || pathOk);
                const bool timeout  = armedFor >= BEAT_ARMED_TIMEOUT_MS;
                if (released || timeout) {
                    const char* exitReason = timeout ? "timeout"
                                            : releaseAbs ? "abs"
                                            : "ratio";
                    DBG_PRINTF("[N1 ARM_END dur=%lu peak=%4.2f path=%5.3f reason=%s fired=%s]\n",
                               (unsigned long)armedFor,
                               sArmedPeakDyn,
                               sPathLen,
                               exitReason,
                               sBeatFiredInArmed ? "YES" : "NO");
                    gateToIdle();
                    data.beat.pathLenM = 0.0f;
                }
                break;
            }
        }
    } else if (data.conductor.state != ConductorState::Conducting) {
        // Conducting でない状態 (Idle / Calibrating / Fallback) に入ったら
        // ゲートを必ず Idle に戻す。
        // ※「Conducting だが imu.ready=false」のループではここに来ない。
        //   ImuModule は 5ms 周期でサンプルするので loop の大半は ready=false で
        //   通過するため、ここで gateToIdle すると Armed が次ループで毎回潰され、
        //   積分が走らず ARM_END も出ない致命的バグになる。
        if (sGate != BeatGate::Idle) gateToIdle();
    }

    // デバッグ可視化用にゲート状態を SystemData にミラー
    data.beat.gateState    = (sGate == BeatGate::Armed) ? 1 : 0;
    data.beat.armedPeakDyn = sArmedPeakDyn;

    // LED 状態
    updateLed(data);
}
