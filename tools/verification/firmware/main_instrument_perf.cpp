// MOP8 検証用: 楽器ノード node_02 の main.cpp に 3 フェーズ計測を追加したもの。
// production/node_02/src/main.cpp のドロップイン置き換え。node_03〜06 にも使える。
//
// 使い方:
//   cp firmware/production/node_02/src/main.cpp firmware/production/node_02/src/main.cpp.bak
//   cp tools/verification/firmware/main_instrument_perf.cpp firmware/production/node_02/src/main.cpp
//   pio run -d firmware/production/node_02 -t upload
//   (計測後)
//   mv firmware/production/node_02/src/main.cpp.bak firmware/production/node_02/src/main.cpp
//
// 追加出力: [N2 PERF] in=<us> logic=<us> out=<us> total=<us>  (200ms 間隔)
// platformio.ini の build_flags に -DSERIAL_DEBUG=1 を設定すること。
#include <Arduino.h>

#include "ProjectConfig.h"
#include "SystemData.h"

#include "OrcNetModule.h"
#include "OrcReceiverModule.h"
#include "NoteSenderModule.h"
#include "UiRelayModule.h"
#include "StatusLedModule.h"
#include "SerialDebug.h"

void applyPattern(SystemData& data);

namespace {

SystemData         gData;
OrcNetModule       gNet(ORC_NET_CONFIG);
OrcReceiverModule  gRecv(ORC_RECEIVER_CONFIG);
NoteSenderModule   gNote(NOTE_SENDER_CONFIG);
UiRelayModule      gUi(UI_RELAY_CONFIG);
StatusLedModule    gLed(STATUS_LED_CONFIG);

IModule* gInputs[]  = { &gNet, &gRecv };
IModule* gOutputs[] = { &gNote, &gUi, &gLed, &gNet };

constexpr size_t MAX_RETRY = 3;
uint32_t gLastLoopMs = 0;

void initWithRetry(IModule* m, const char* name) {
    bool ok = false;
    for (size_t i = 0; i < MAX_RETRY && !ok; ++i) {
        ok = m->init();
        if (!ok) delay(50);
    }
    m->enabled = ok;
    DBG_PRINTF("[N2 INIT] %s = %s\n", name, ok ? "OK" : "NG");
}

#if SERIAL_DEBUG
const char* perfStateName(PerformerState s) {
    switch (s) {
        case PerformerState::Idle:      return "Idle";
        case PerformerState::WaitStart: return "WaitStart";
        case PerformerState::Playing:   return "Playing";
    }
    return "?";
}

constexpr uint32_t DUMP_INTERVAL_MS = 200;
uint32_t       gLastDumpMs   = 0;
PerformerState gPrevState    = PerformerState::Idle;
bool           gPrevWifi     = false;
bool           gPrevConverged = false;
uint16_t       gPrevLastBeatNo = 0;
uint32_t       gPrevCtrlMs   = 0;

// ── PERF 計測用 (追加部分) ──
uint32_t gLastPerfDumpUs = 0;
uint32_t gMaxInputUs  = 0;
uint32_t gMaxLogicUs  = 0;
uint32_t gMaxOutputUs = 0;
uint32_t gMaxTotalUs  = 0;

void dumpEdges(const SystemData& d) {
    if (d.performer.state != gPrevState) {
        DBG_PRINTF("[N2 EVT STATE] %s -> %s\n",
                   perfStateName(gPrevState),
                   perfStateName(d.performer.state));
        gPrevState = d.performer.state;
    }
    if (d.orcNet.wifiConnected != gPrevWifi) {
        DBG_PRINTF("[N2 EVT WIFI] connected=%d\n",
                   d.orcNet.wifiConnected ? 1 : 0);
        gPrevWifi = d.orcNet.wifiConnected;
    }
    if (d.sync.converged && !gPrevConverged) {
        DBG_PRINTF("[N2 EVT SYNC_CONVERGED] off=%ld n=%u\n",
                   (long)d.sync.offsetMs, (unsigned)d.sync.sampleCount);
        gPrevConverged = true;
    }
    if (d.orcNet.hasNewCtrl && d.ctrl.lastReceivedMs != gPrevCtrlMs) {
        DBG_PRINTF("[N2 EVT CTRL] bpm=%5.1f vel=%u st=%u seq=%lu off=%ld n=%u\n",
                   d.ctrl.bpm, (unsigned)d.ctrl.velocity,
                   (unsigned)d.ctrl.state,
                   (unsigned long)d.orcNet.lastCtrl.header.seq,
                   (long)d.sync.offsetMs,
                   (unsigned)d.sync.sampleCount);
        gPrevCtrlMs = d.ctrl.lastReceivedMs;
    }
    if (d.orcNet.hasNewBeat && d.receiver.lastBeatNo != gPrevLastBeatNo) {
        const int32_t ahead =
            (int32_t)d.orcNet.lastBeat.payload.playAtMasterMs -
            (int32_t)(millis() + (uint32_t)d.sync.offsetMs);
        DBG_PRINTF("[N2 EVT BEAT] no=%u playAt=%lu ahead=%ld seq=%lu\n",
                   (unsigned)d.receiver.lastBeatNo,
                   (unsigned long)d.orcNet.lastBeat.payload.playAtMasterMs,
                   (long)ahead,
                   (unsigned long)d.orcNet.lastBeat.header.seq);
        gPrevLastBeatNo = d.receiver.lastBeatNo;
    }
}

void dumpPeriodic(const SystemData& d) {
    const uint32_t now = millis();
    if (now - gLastDumpMs < DUMP_INTERVAL_MS) return;
    gLastDumpMs = now;
    const uint32_t ago = (d.receiver.lastBeatMs == 0)
                          ? 0 : (now - d.receiver.lastBeatMs);
    DBG_PRINTF(
        "[N2 t=%lu st=%s wifi=%d sync=%s(off=%ld n=%u) ctrl=(bpm=%5.1f v=%u s=%u) "
        "recv=(no=%u ago=%lu) pend=%d score=(idx=%u)]\n",
        (unsigned long)now,
        perfStateName(d.performer.state),
        d.orcNet.wifiConnected ? 1 : 0,
        d.sync.converged ? "ok" : "..",
        (long)d.sync.offsetMs,
        (unsigned)d.sync.sampleCount,
        d.ctrl.bpm, (unsigned)d.ctrl.velocity, (unsigned)d.ctrl.state,
        (unsigned)d.receiver.lastBeatNo,
        (unsigned long)ago,
        d.receiver.pending.valid ? 1 : 0,
        (unsigned)d.score.currentEventIndex);
}

void dumpPerf() {
    const uint32_t now = micros();
    if (now - gLastPerfDumpUs < 200000) return;
    gLastPerfDumpUs = now;
    DBG_PRINTF("[N2 PERF] in=%lu logic=%lu out=%lu total=%lu\n",
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
    DBG_PRINTF("=== node_02 (round voice partId=0x%02X instr=%u headRest=%u) boot [PERF] ===\n",
               (unsigned)ORC_RECEIVER_CONFIG.partId,
               (unsigned)NOTE_SENDER_CONFIG.instrumentId,
               (unsigned)ORC_RECEIVER_CONFIG.headRestBeats);

    initWithRetry(&gNet,  "OrcNetModule");
    initWithRetry(&gRecv, "OrcReceiverModule");
    initWithRetry(&gNote, "NoteSenderModule");
    initWithRetry(&gUi,   "UiRelayModule");
    initWithRetry(&gLed,  "StatusLedModule");

    DBG_PRINTLN("[N2 INIT] done");
}

void loop() {
    const uint32_t now = millis();
    if (now - gLastLoopMs < ORC_RECEIVER_CONFIG.loopIntervalMs) {
        return;
    }
    gLastLoopMs = now;

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

    dumpEdges(gData);
    dumpPeriodic(gData);
    dumpPerf();
#endif
}
