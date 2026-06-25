// MOP8 検証用: 指揮者 node_01 の main.cpp に 3 フェーズ計測を追加したもの。
// production/node_01/src/main.cpp のドロップイン置き換え。
//
// 使い方:
//   cp firmware/production/node_01/src/main.cpp firmware/production/node_01/src/main.cpp.bak
//   cp tools/verification/firmware/main_conductor_perf.cpp firmware/production/node_01/src/main.cpp
//   pio run -d firmware/production/node_01 -t upload
//   (計測後)
//   mv firmware/production/node_01/src/main.cpp.bak firmware/production/node_01/src/main.cpp
//
// 追加出力: [N1 PERF] in=<us> logic=<us> out=<us> total=<us>  (200ms 間隔)
#include <Arduino.h>
#include <Wire.h>

#include "ProjectConfig.h"
#include "SystemData.h"

#include "ImuModule.h"
#include "OrcNetModule.h"
#include "OrcSenderModule.h"
#include "StatusLedModule.h"
#include "SerialDebug.h"

void applyPattern(SystemData& data);

namespace {

SystemData       gData;
ImuModule        gImu(IMU_CONFIG);
OrcNetModule     gNet(ORC_NET_CONFIG);
OrcSenderModule  gSender(ORC_SENDER_CONFIG);
StatusLedModule  gLed(STATUS_LED_CONFIG);

IModule* gInputs[]  = { &gNet, &gImu };
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
float          gPeakNraw   = 0.0f;
float          gPeakNdyn   = 0.0f;

// ── PERF 計測用 (追加部分) ──
uint32_t gLastPerfDumpUs = 0;
uint32_t gMaxInputUs  = 0;
uint32_t gMaxLogicUs  = 0;
uint32_t gMaxOutputUs = 0;
uint32_t gMaxTotalUs  = 0;

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

void dumpPerf() {
    const uint32_t now = micros();
    if (now - gLastPerfDumpUs < 200000) return;
    gLastPerfDumpUs = now;
    DBG_PRINTF("[N1 PERF] in=%lu logic=%lu out=%lu total=%lu\n",
               (unsigned long)gMaxInputUs,
               (unsigned long)gMaxLogicUs,
               (unsigned long)gMaxOutputUs,
               (unsigned long)gMaxTotalUs);
    gMaxInputUs = gMaxLogicUs = gMaxOutputUs = gMaxTotalUs = 0;
}
#endif  // SERIAL_DEBUG

}  // namespace

void setup() {
    DBG_BEGIN(115200);
    DBG_WAIT_HOST(1500);
    DBG_PRINTLN("");
    DBG_PRINTLN("=== node_01 (conductor) boot [PERF] ===");

    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    Wire.setClock(400000);

    initWithRetry(&gNet,    "OrcNetModule");
    initWithRetry(&gImu,    "ImuModule");
    initWithRetry(&gSender, "OrcSenderModule");
    initWithRetry(&gLed,    "StatusLedModule");

    DBG_PRINTLN("[N1 INIT] done");
}

void loop() {
    const uint32_t t0 = micros();
    for (auto* m : gInputs) {
        if (m->enabled) m->updateInput(gData);
    }
    const uint32_t t1 = micros();
    applyPattern(gData);
    const uint32_t t2 = micros();
    for (auto* m : gOutputs) {
        if (m->enabled) m->updateOutput(gData);
    }
    const uint32_t t3 = micros();

#if SERIAL_DEBUG
    uint32_t di = t1 - t0, dl = t2 - t1, do_ = t3 - t2, dt = t3 - t0;
    if (di > gMaxInputUs)  gMaxInputUs  = di;
    if (dl > gMaxLogicUs)  gMaxLogicUs  = dl;
    if (do_ > gMaxOutputUs) gMaxOutputUs = do_;
    if (dt > gMaxTotalUs)  gMaxTotalUs  = dt;

    trackPeak(gData);
    dumpEdges(gData);
    dumpPeriodic(gData);
    dumpPerf();
#endif
}
