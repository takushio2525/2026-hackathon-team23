// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/production/node_01
//   pio run -d firmware/production/node_01 -t upload
//   pio device monitor -d firmware/production/node_01
//
// 指揮者ノード node_01 のエントリポイント
// EMA の 3 フェーズループ (入力 -> ロジック -> 出力) を loop() で回す
#include <Arduino.h>
#include <Wire.h>

#include "ProjectConfig.h"
#include "SystemData.h"

#include "ImuModule.h"
#include "OrcNetModule.h"
#include "OrcSenderModule.h"
#include "StatusLedModule.h"
#include "SerialDebug.h"
#include "MopTest.h"

void applyPattern(SystemData& data);

namespace {

SystemData       gData;
ImuModule        gImu(IMU_CONFIG);
OrcNetModule     gNet(ORC_NET_CONFIG);
OrcSenderModule  gSender(ORC_SENDER_CONFIG);
StatusLedModule  gLed(STATUS_LED_CONFIG);

// 入力フェーズ: WiFi 受信 -> IMU 読取
IModule* gInputs[]  = { &gNet, &gImu };
// 出力フェーズ: ロジック結果をパケット化 -> LED 反映 -> UDP 送信
IModule* gOutputs[] = { &gSender, &gLed, &gNet };

constexpr size_t MAX_RETRY = 3;

void initWithRetry(IModule* m, const char* name) {
    bool ok = false;
    for (size_t i = 0; i < MAX_RETRY && !ok; ++i) {
        ok = m->init();
        if (!ok) delay(50);
    }
    m->enabled = ok;
    DBG_PRINTF("[N1 INIT] %s = %s\n", name, ok ? "OK" : "NG");
}

#if SERIAL_DEBUG
const char* stateName(ConductorState s) {
    switch (s) {
        case ConductorState::Idle:        return "Idle";
        case ConductorState::Calibrating: return "Calibrating";
        case ConductorState::Conducting:  return "Conducting";
        case ConductorState::Fallback:    return "Fallback";
        case ConductorState::Menu:        return "Menu";
        case ConductorState::Result:      return "Result";
    }
    return "?";
}

constexpr uint32_t DUMP_INTERVAL_MS = 200;
uint32_t       gLastDumpMs = 0;
ConductorState gPrevState  = ConductorState::Idle;
bool           gPrevWifi   = false;
uint16_t       gPrevBeatNo = 0;
// 区間内ピーク (200ms ごとにリセット)。dump はスポット値だと動きの瞬間を取り逃がすため、
// IMU が ready になる毎フレーム (5ms 周期) にこの 2 つを更新して可視化する。
float          gPeakNraw   = 0.0f;  // 生加速度ノルム (重力込み)
float          gPeakNdyn   = 0.0f;  // 動加速度ノルム (重力補正後 = 拍判定対象)

void trackPeak(const SystemData& d) {
    if (!d.imu.ready) return;
    const float nraw = sqrtf(d.imu.acc[0] * d.imu.acc[0] +
                             d.imu.acc[1] * d.imu.acc[1] +
                             d.imu.acc[2] * d.imu.acc[2]);
    if (nraw > gPeakNraw) gPeakNraw = nraw;
    if (d.imu.dynNorm > gPeakNdyn) gPeakNdyn = d.imu.dynNorm;
}

void dumpPeriodic(const SystemData& d) {
    const uint32_t now = millis();
    if (now - gLastDumpMs < DUMP_INTERVAL_MS) return;
    gLastDumpMs = now;
    DBG_PRINTF(
        "[N1 t=%lu st=%s wifi=%d imu=%d acc=(%6.2f,%6.2f,%6.2f) n=%4.2f dyn=%4.2f peakRaw=%4.2f peakDyn=%4.2f gate=%c armedPk=%4.2f path=%5.3f bpm=%5.1f beatNo=%u ctrlSeq=%lu beatSeq=%lu]\n",
        (unsigned long)now,
        stateName(d.conductor.state),
        d.orcNet.wifiConnected ? 1 : 0,
        d.imu.ready ? 1 : 0,
        d.imu.accLpf[0], d.imu.accLpf[1], d.imu.accLpf[2],
        d.imu.accNorm,
        d.imu.dynNorm,
        gPeakNraw,
        gPeakNdyn,
        d.beat.gateState ? 'A' : 'I',
        d.beat.armedPeakDyn,
        d.beat.pathLenM,
        d.tempo.bpm,
        (unsigned)d.beat.beatNo,
        (unsigned long)d.sender.ctrlSeq,
        (unsigned long)d.sender.beatSeq);
    gPeakNraw = 0.0f;
    gPeakNdyn = 0.0f;
}

void dumpEdges(const SystemData& d) {
    if (d.conductor.state != gPrevState) {
        DBG_PRINTF("[N1 EVT STATE] %s -> %s (gravityMag=%6.3f done=%d)\n",
                   stateName(gPrevState), stateName(d.conductor.state),
                   d.calibration.gravityMag,
                   d.calibration.done ? 1 : 0);
        gPrevState = d.conductor.state;
    }
    if (d.orcNet.wifiConnected != gPrevWifi) {
        DBG_PRINTF("[N1 EVT WIFI] connected=%d\n",
                   d.orcNet.wifiConnected ? 1 : 0);
        gPrevWifi = d.orcNet.wifiConnected;
    }
    if (d.beat.beatNo != gPrevBeatNo) {
        DBG_PRINTF("[N1 EVT BEAT] no=%u t=%lu playAt=%lu bpm=%5.1f\n",
                   (unsigned)d.beat.beatNo,
                   (unsigned long)d.beat.lastBeatMs,
                   (unsigned long)d.beat.playAtMasterMs,
                   d.tempo.bpm);
        gPrevBeatNo = d.beat.beatNo;
    }
}
#endif  // SERIAL_DEBUG

}  // namespace

// MOP_TEST=8: ループごとの各フェーズ処理時間を計測するための変数
#if MOP_TEST == 8
uint32_t gMopInputUs = 0;
uint32_t gMopLogicUs = 0;
uint32_t gMopOutputUs = 0;
#endif

void setup() {
    mop_test::ensureSerial();
    DBG_BEGIN(115200);
    DBG_WAIT_HOST(1500);
    DBG_PRINTLN("");
    DBG_PRINTLN("=== node_01 (conductor) boot ===");
#if MOP_TEST == 7
    mop_test::mprintf("M7,1,BOOT,%lu\n", (unsigned long)millis());
#endif

    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    Wire.setClock(400000);

    initWithRetry(&gNet,    "OrcNetModule");
    initWithRetry(&gImu,    "ImuModule");
    initWithRetry(&gSender, "OrcSenderModule");
    initWithRetry(&gLed,    "StatusLedModule");

    DBG_PRINTLN("[N1 INIT] done");
#if MOP_TEST == 7
    mop_test::mprintf("M7,1,INIT,%lu\n", (unsigned long)millis());
#endif
}

void loop() {
#if MOP_TEST == 8
    const uint32_t t0 = micros();
#endif
    for (auto* m : gInputs) {
        if (m->enabled) m->updateInput(gData);
    }
#if MOP_TEST == 8
    const uint32_t t1 = micros();
#endif
    applyPattern(gData);
#if MOP_TEST == 8
    const uint32_t t2 = micros();
#endif
    for (auto* m : gOutputs) {
        if (m->enabled) m->updateOutput(gData);
    }
#if MOP_TEST == 8
    const uint32_t t3 = micros();
    mop_test::mprintf("M8,%lu,%lu,%lu\n",
                      (unsigned long)(t1 - t0),
                      (unsigned long)(t2 - t1),
                      (unsigned long)(t3 - t2));
#endif

#if MOP_TEST == 1
    // MOP1: 拍検出イベントを出力
    static uint16_t sPrevBeatNo_m1 = 0;
    if (gData.beat.beatNo != sPrevBeatNo_m1) {
        const uint16_t bpmQ8 = (uint16_t)(gData.tempo.bpm * 8.0f + 0.5f);
        mop_test::mprintf("M1,%u,%lu,%u\n",
                          (unsigned)gData.beat.beatNo,
                          (unsigned long)gData.beat.lastBeatMs,
                          (unsigned)bpmQ8);
        sPrevBeatNo_m1 = gData.beat.beatNo;
    }
#endif

#if MOP_TEST == 5
    // MOP5: 指揮者側 BEAT 送信時刻を出力
    static uint16_t sPrevBeatNo_m5 = 0;
    if (gData.beat.beatNo != sPrevBeatNo_m5) {
        mop_test::mprintf("M5C,%u,%lu\n",
                          (unsigned)gData.beat.beatNo,
                          (unsigned long)gData.beat.lastBeatMs);
        sPrevBeatNo_m5 = gData.beat.beatNo;
    }
#endif

#if MOP_TEST == 7
    // MOP7: Calibrating 完了 → Conducting/Menu 遷移 = 「演奏可能」
    static bool sMop7Ready = false;
    if (!sMop7Ready &&
        gData.conductor.state != ConductorState::Idle &&
        gData.conductor.state != ConductorState::Calibrating) {
        mop_test::mprintf("M7,1,READY,%lu\n", (unsigned long)millis());
        sMop7Ready = true;
    }
#endif

#if SERIAL_DEBUG && MOP_TEST == 0
    trackPeak(gData);   // 5ms 周期でピーク追跡 (dump はスポット値を補完)
    dumpEdges(gData);
    dumpPeriodic(gData);
#endif
}
