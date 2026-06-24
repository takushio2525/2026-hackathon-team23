// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/production/node_01
//   pio run -d firmware/production/node_01 -t upload
//   pio device monitor -d firmware/production/node_01
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

// テンポ推定のリセット (Menu からの演奏セッション開始時に呼ぶ)。
// sLastBeatMs=0 で次の拍を「1 拍目」(間隔計算なし) に戻す。これをしないと
// Menu 滞在時間が拍間隔として EMA に混入し、BPM_MIN クランプ値 (40) に
// 引っ張られた BPM を新セッションの頭で数拍引きずる。
void resetTempoTracking(SystemData& data) {
    sLastBeatMs = 0;
    sBpmEma     = 100.0f;
    sBpmInit    = false;
    data.tempo.bpm = 100.0f;
    data.tempo.nextBeatPredictedMs = 0;
}

// Fallback に落ちる直前の状態 (= 復帰先)。Menu/Result で IMU が止まっても
// 復帰後に元の画面へ戻る。既定 Menu は「Calibrating 完了前に Fallback は
// 起きない」ため実際には使われない保険値。
ConductorState sStateBeforeFallback = ConductorState::Menu;

// ── production: メニューナビのゲート (拍検出ゲートとは独立) ──
// 重力基準の縦/横判定。加速度の遅い LPF で重力ベクトルを推定し、振り加速度
// (accLpf − 推定重力) を「重力軸成分」と「水平面成分」に分解する。センサに
// 取り付け角度がついていても「地面に対して垂直=縦 (決定) / 水平=横 (カーソル)」
// になる (旧方式のセンサ軸直読みは取り付け角度で破綻した)。
// 瞬時値は振り始めの向きが暴れるので、Armed 中の判定窓で両成分を積算し、
// 窓終了かリリースの早い方で 1 回だけ判定・発火する。Menu / Result 状態でのみ動かす。
enum class NavGate : uint8_t { Idle, Armed };
NavGate  sNavGate        = NavGate::Idle;
uint32_t sLastNavMs      = 0;            // 最後に発火した時刻 (不応期の基準)
uint32_t sNavArmedAtMs   = 0;            // Armed 突入時刻 (判定窓の基準)
bool     sNavFired       = false;        // 現 Armed セッションで発火済みか
float    sNavVertAccum   = 0.0f;         // |重力軸成分| の積算
float    sNavHorizAccum  = 0.0f;         // |水平面成分| の積算
float    sNavHorizVec[3] = {0, 0, 0};    // 水平面成分ベクトルの積算 (カーソル移動方向用)

// ナビ用の重力ベクトル推定 (accLpf をさらに遅い LPF に通したもの)。
// 拍検出のキャリブ値 gravityMag はスカラーなので方向の分解には使えない。
float    sNavGrav[3] = {0, 0, 0};
bool     sNavGravInit = false;

// 1 振りを 1 操作として処理する。横振り→カーソル移動 (data.game.navCursor を更新・false)、
// 縦振り→決定 (true を返す)。多重発火は Armed ゲート + 発火済みフラグ + 不応期で防ぐ。
bool updateNav(SystemData& data, uint32_t now, uint8_t itemCount) {
    using namespace logic_params;
    if (!data.imu.ready) return false;

    if (sNavGate == NavGate::Idle) {
        // しきい値超え + 不応期経過で Armed へ (積算を開始)
        if (data.imu.dynNorm <= NAV_SWING_THRESHOLD_G) return false;
        if ((now - sLastNavMs) < NAV_REFRACTORY_MS) return false;
        sNavGate        = NavGate::Armed;
        sNavArmedAtMs   = now;
        sNavFired       = false;
        sNavVertAccum   = 0.0f;
        sNavHorizAccum  = 0.0f;
        sNavHorizVec[0] = sNavHorizVec[1] = sNavHorizVec[2] = 0.0f;
    } else if (sNavFired &&
               data.imu.dynNorm > NAV_SWING_THRESHOLD_G &&
               (now - sLastNavMs) >= NAV_REFRACTORY_MS) {
        // 発火済み Armed セッション中に新しい振りを検出 → セッションをリセット。
        // LPF の尾引きで release (dynNorm < 0.30) が遅れると、2 回目以降の
        // 振りが発火済みセッションに吸い込まれて無視される問題を修正。
        sNavArmedAtMs   = now;
        sNavFired       = false;
        sNavVertAccum   = 0.0f;
        sNavHorizAccum  = 0.0f;
        sNavHorizVec[0] = sNavHorizVec[1] = sNavHorizVec[2] = 0.0f;
    }

    // Armed 中: 振り加速度を重力軸成分と水平面成分に分解して積算する
    const float gravNorm = sqrtf(sNavGrav[0] * sNavGrav[0] +
                                 sNavGrav[1] * sNavGrav[1] +
                                 sNavGrav[2] * sNavGrav[2]);
    if (gravNorm > 1e-3f) {
        const float invG = 1.0f / gravNorm;
        float swing[3];   // 振り加速度ベクトル (g 単位、重力差し引き済み)
        for (int i = 0; i < 3; ++i) swing[i] = data.imu.accLpf[i] - sNavGrav[i];
        const float vert = (swing[0] * sNavGrav[0] +
                            swing[1] * sNavGrav[1] +
                            swing[2] * sNavGrav[2]) * invG;   // 符号付き重力軸成分
        sNavVertAccum += fabsf(vert);
        float horizSq = 0.0f;
        for (int i = 0; i < 3; ++i) {
            const float h = swing[i] - vert * sNavGrav[i] * invG;   // 水平面成分
            sNavHorizVec[i] += h;
            horizSq         += h * h;
        }
        sNavHorizAccum += sqrtf(horizSq);
    }

    // 判定: 窓終了かリリースの早い方で 1 回だけ発火
    const bool windowDone = (now - sNavArmedAtMs) >= NAV_DECISION_WINDOW_MS;
    const bool release    = data.imu.dynNorm < NAV_RELEASE_G;
    bool decide = false;
    if (!sNavFired && (windowDone || release)) {
        sNavFired  = true;
        sLastNavMs = now;
        int     dom    = 0;
        float   dir    = 0.0f;
        uint8_t curBefore = data.game.navCursor;
        if (sNavVertAccum >= sNavHorizAccum * NAV_VERT_DOMINANCE) {
            decide = true;   // 縦振りが支配的 → 決定
        } else {
            // 横振りが支配的 → カーソル移動。向きは水平積算ベクトルの支配軸の符号で決める
            // (どの軸が水平に対応するかは取り付けに依存するが、支配軸選択で自動追従する。
            //  左右の向きが実機で逆なら NAV_LR_SIGN を反転する)。
            for (int i = 1; i < 3; ++i) {
                if (fabsf(sNavHorizVec[i]) > fabsf(sNavHorizVec[dom])) dom = i;
            }
            dir = sNavHorizVec[dom] * NAV_LR_SIGN;
            if (dir < 0.0f) { if (data.game.navCursor > 0)             data.game.navCursor--; }
            else            { if (data.game.navCursor + 1 < itemCount) data.game.navCursor++; }
        }
        DBG_PRINTF("[N1 NAV vert=%5.2f horiz=%5.2f grav=(%5.2f,%5.2f,%5.2f) hvec=(%5.1f,%5.1f,%5.1f) dom=%d dir=%+5.1f cur=%u->%u -> %s]\n",
                   sNavVertAccum, sNavHorizAccum,
                   sNavGrav[0], sNavGrav[1], sNavGrav[2],
                   sNavHorizVec[0], sNavHorizVec[1], sNavHorizVec[2],
                   dom, dir, curBefore, data.game.navCursor,
                   decide ? "DECIDE" : "CURSOR");
    }
    // 振りが収まったら (release) 次操作に備える。
    // 発火済みで不応期を越えた場合は release を待たず強制的に Idle へ戻す。
    // dynNorm が NAV_RELEASE_G と NAV_SWING_THRESHOLD_G の間に留まって Armed から
    // 抜けられなくなり、2 回目以降の振りを検知できなくなる問題を修正。
    if (release) {
        sNavGate = NavGate::Idle;
    } else if (sNavFired && (now - sLastNavMs) >= NAV_REFRACTORY_MS) {
        sNavGate = NavGate::Idle;
    }
    return decide;
}

// ── production: 状態遷移直後のデッドタイム (ジェスチャ/拍検出の不感時間) ──
// 遷移を起こした振りの残り (惰性・戻し) を次状態の入力として拾わないため、
// 遷移から STATE_TRANSITION_DEADTIME_MS の間は拍検出とナビを無視する。
ConductorState sPrevState      = ConductorState::Idle;
uint32_t       sStateEnteredMs = 0;

// 状態遷移を検知したら不感時間を開始し、拍/ナビ両ゲートの撃ちかけを破棄する。
// 遷移は状態遷移 switch 内と拍検出ブロック内 (Conducting→Result) の複数箇所で
// 起きるため、switch の前後 2 箇所から呼ぶ (state 不変なら何もしない冪等処理)。
void noteStateTransition(SystemData& data, uint32_t now) {
    if (data.conductor.state == sPrevState) return;
    sPrevState      = data.conductor.state;
    sStateEnteredMs = now;
    gateToIdle();
    sNavGate = NavGate::Idle;
    data.beat.pathLenM = 0.0f;
}

bool inTransitionDeadtime(uint32_t now) {
    return (now - sStateEnteredMs) < logic_params::STATE_TRANSITION_DEADTIME_MS;
}

// メトロノームガイド強度 (経過拍ベースの固定スケジュール・通信不要)。1.0=はっきり / 0.0=なし。
// 採点重みは 1 - この値 (ガイドが薄い/無い区間ほど重く配点する)。
float gameGuideIntensity(uint16_t beatCount) {
    using namespace logic_params;
    if (beatCount <  GAME_GUIDE_FULL_BEATS) return 1.0f;
    if (beatCount >= GAME_GUIDE_ZERO_BEATS) return 0.0f;
    const float span = (float)(GAME_GUIDE_ZERO_BEATS - GAME_GUIDE_FULL_BEATS);
    return 1.0f - (float)(beatCount - GAME_GUIDE_FULL_BEATS) / span;
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
            // ゲーム中でガイドが残っている区間は目標テンポで点滅 (LED メトロノームガイド)。
            // ガイドが切れたら点灯のまま (自由演奏も常時点灯)。
            if (data.game.mode == 1 && data.game.targetBpm > 0 &&
                gameGuideIntensity(data.game.gameBeatCount) > 0.5f) {
                data.led.solidOn = false;
                data.led.blinkIntervalMs = (uint16_t)(30000u / data.game.targetBpm);
            } else {
                data.led.solidOn = true;
            }
            break;
        case ConductorState::Fallback:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_FALLBACK_MS;
            break;
        case ConductorState::Menu:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_MENU_MS;
            break;
        case ConductorState::Result:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_RESULT_MS;
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

        // ナビ用の重力ベクトル推定: accLpf をさらに遅い LPF に通す。
        // dynNorm が大きい間 (振り中) は更新を凍結し、振り加速度の漏れ込みを防ぐ。
        // 状態によらず常時回しておくことで、Menu 突入時には収束済みになっている
        // (Calibrating の静止 2 秒で十分収束する)。
        if (!sNavGravInit) {
            for (int i = 0; i < 3; ++i) sNavGrav[i] = data.imu.accLpf[i];
            sNavGravInit = true;
        } else if (data.imu.dynNorm < NAV_GRAV_FREEZE_G) {
            for (int i = 0; i < 3; ++i) {
                sNavGrav[i] += NAV_GRAV_LPF_ALPHA * (data.imu.accLpf[i] - sNavGrav[i]);
            }
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
    // 前ループの拍検出ブロック内で起きた遷移 (Conducting→Result) をここで拾い、
    // Result のナビが動き出す前にデッドタイムを開始する。
    noteStateTransition(data, now);
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
                // production: キャリブ完了後はまず Menu へ (モード選択)。
                data.conductor.state = ConductorState::Menu;
                data.game.mode = 0;          // 既定カーソル = 自由演奏
                data.game.navCursor = 0;
                data.game.targetBpm = 0;
                data.game.score = 0xFF;
                sNavGate = NavGate::Idle;
            }
            break;
        }

        case ConductorState::Conducting:
            // Fallback 遷移は無効化: 実機テストで IMU 瞬断により演奏が遮られるため。
            break;

        case ConductorState::Fallback:
            // Fallback への遷移経路を全て無効化したので到達しないが、
            // 万一入った場合は直前の状態に即復帰する。
            data.conductor.state = sStateBeforeFallback;
            sNavGate = NavGate::Idle;
            break;

        // ── production: メニュー (IMU ナビでモード選択。拍検出は止まる) ──
        case ConductorState::Menu: {
            // Fallback 遷移は無効化済み (修正3)
            if (!inTransitionDeadtime(now) && updateNav(data, now, MENU_ITEM_COUNT)) {
                if (data.game.navCursor == 1) {
                    // ゲーム開始: 目標テンポ提示・採点カウンタをリセット
                    data.game.mode = 1;
                    data.game.targetBpm = GAME_TARGET_BPM;
                    data.game.gameBeatCount = 0;
                    data.game.scoreErrAccum = 0.0f;
                    data.game.scoreWeightAccum = 0.0f;
                    data.game.score = 0xFF;
                } else {
                    // 自由演奏
                    data.game.mode = 0;
                    data.game.targetBpm = 0;
                    data.game.score = 0xFF;
                }
                // 演奏セッション開始: テンポ推定と拍番号を初期化する。
                // beatNo=0 に戻すと楽器側は effective = beatNo-1-headRestBeats < 0 の
                // 頭休符からやり直す = 毎セッション曲頭から演奏が始まる
                // (ゲームの「32 拍 = かえるのうた 1 周を採点」の前提と一致させる)。
                // 楽器側の重複排除は「bn == lastBeatNo」だけなので巻き戻しも受理される。
                // ※前セッションが 1 拍だけで終わった直後に限り、新セッションの bn=1 が
                //   重複と誤判定され 1 拍飲まれるが、bn=2 から自己回復するため許容。
                resetTempoTracking(data);
                data.beat.beatNo = 0;
                gateToIdle();
                data.conductor.state = ConductorState::Conducting;
            }
            break;
        }

        // ── production: 結果表示 (縦振り=決定で Menu へ戻る。拍検出は止まる) ──
        case ConductorState::Result: {
            // Fallback 遷移は無効化済み (修正3)
            if (!inTransitionDeadtime(now) && updateNav(data, now, 1)) {
                data.conductor.state = ConductorState::Menu;
                data.game.mode = 0;
                data.game.navCursor = 0;
                data.game.targetBpm = 0;
                data.game.score = 0xFF;
                data.game.gameBeatCount = 0;
                data.game.scoreErrAccum = 0.0f;
                data.game.scoreWeightAccum = 0.0f;
            }
            break;
        }
    }

    // 今ループの switch 内で起きた遷移 (Menu→Conducting 等) を即時反映し、
    // 直後の拍検出ブロックがメニュー決定の振りを 1 拍目として拾わないようにする。
    noteStateTransition(data, now);

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
    // 遷移直後のデッドタイム中は拍検出を走らせない (ゲートは遷移検知時に Idle 化済み)。
    if (data.conductor.state == ConductorState::Conducting && data.imu.ready &&
        !inTransitionDeadtime(now)) {
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

                            // ── production ゲーム採点 ──
                            // 実振り間隔 intervalMs と目標拍間隔の誤差を、ガイド強度で重み付け
                            // して累積する (ガイドが薄い区間ほど重い)。1 拍目は基準が無いので除外。
                            if (data.game.mode == 1 && data.game.targetBpm > 0 &&
                                data.game.gameBeatCount >= 1) {
                                const float targetInterval = 60000.0f / (float)data.game.targetBpm;
                                const float err = fabsf((float)intervalMs - targetInterval);
                                const float w   = 1.0f - gameGuideIntensity(data.game.gameBeatCount);
                                data.game.scoreErrAccum    += w * err;
                                data.game.scoreWeightAccum += w;
                            }
                        }
                    }
                    sLastBeatMs       = now;
                    sBeatFiredInArmed = true;

                    // ── production ゲーム進行: 経過拍を数え、規定拍に達したら結果へ ──
                    if (data.game.mode == 1) {
                        data.game.gameBeatCount += 1;
                        if (data.game.gameBeatCount >= GAME_LENGTH_BEATS) {
                            // 得点確定: 平均誤差を 0-100 へ写像 (誤差小=高得点)
                            float s = 100.0f;
                            if (data.game.scoreWeightAccum > 0.0f && data.game.targetBpm > 0) {
                                const float avgErr =
                                    data.game.scoreErrAccum / data.game.scoreWeightAccum;
                                const float targetInterval = 60000.0f / (float)data.game.targetBpm;
                                const float tol = targetInterval * GAME_SCORE_TOLERANCE_RATIO;
                                s = 100.0f * (1.0f - avgErr / tol);
                            }
                            if (s <   0.0f) s =   0.0f;
                            if (s > 100.0f) s = 100.0f;
                            data.game.score = (uint8_t)(s + 0.5f);
                            data.conductor.state = ConductorState::Result;
                        }
                    }
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
