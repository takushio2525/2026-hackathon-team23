// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v3/node_03
//   pio run -d firmware/test_v3/node_03 -t upload
//   pio device monitor -d firmware/test_v3/node_03
//
// 楽器ノード node_03 (輪唱の 1 声部) のエントリポイント (Arduino UNO R4 WiFi)
// partId / instrumentId / headRestBeats は ProjectConfig.h で決める。
// 3 フェーズループを loopIntervalMs (5 ms) 間隔で回す
#include <Arduino.h>

#include "ProjectConfig.h"
#include "SystemData.h"

#include "OrcNetModule.h"
#include "OrcReceiverModule.h"
#include "NoteSenderModule.h"
#include "StatusLedModule.h"
#include "SerialDebug.h"

void applyPattern(SystemData& data);

namespace {

SystemData         gData;
OrcNetModule       gNet(ORC_NET_CONFIG);
OrcReceiverModule  gRecv(ORC_RECEIVER_CONFIG);
NoteSenderModule   gNote(NOTE_SENDER_CONFIG);
StatusLedModule    gLed(STATUS_LED_CONFIG);

IModule* gInputs[]  = { &gNet, &gRecv };
IModule* gOutputs[] = { &gNote, &gLed, &gNet };

constexpr size_t MAX_RETRY = 3;
uint32_t gLastLoopMs = 0;

void initWithRetry(IModule* m, const char* name) {
    bool ok = false;
    for (size_t i = 0; i < MAX_RETRY && !ok; ++i) {
        ok = m->init();
        if (!ok) delay(50);
    }
    m->enabled = ok;
    DBG_PRINTF("[N3 INIT] %s = %s\n", name, ok ? "OK" : "NG");
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

void dumpEdges(const SystemData& d) {
    if (d.performer.state != gPrevState) {
        DBG_PRINTF("[N3 EVT STATE] %s -> %s\n",
                   perfStateName(gPrevState),
                   perfStateName(d.performer.state));
        gPrevState = d.performer.state;
    }
    if (d.orcNet.wifiConnected != gPrevWifi) {
        DBG_PRINTF("[N3 EVT WIFI] connected=%d\n",
                   d.orcNet.wifiConnected ? 1 : 0);
        gPrevWifi = d.orcNet.wifiConnected;
    }
    if (d.sync.converged && !gPrevConverged) {
        DBG_PRINTF("[N3 EVT SYNC_CONVERGED] off=%ld n=%u\n",
                   (long)d.sync.offsetMs, (unsigned)d.sync.sampleCount);
        gPrevConverged = true;
    }
    if (d.orcNet.hasNewCtrl && d.ctrl.lastReceivedMs != gPrevCtrlMs) {
        DBG_PRINTF("[N3 EVT CTRL] bpm=%5.1f vel=%u st=%u seq=%lu off=%ld n=%u\n",
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
        DBG_PRINTF("[N3 EVT BEAT] no=%u playAt=%lu ahead=%ld seq=%lu\n",
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
        "[N3 t=%lu st=%s wifi=%d sync=%s(off=%ld n=%u) ctrl=(bpm=%5.1f v=%u s=%u) "
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
#endif  // SERIAL_DEBUG

}  // namespace

void setup() {
    // SERIAL_DEBUG=1 のときは NoteSenderModule.init() の Serial.begin() より先に
    // ホスト接続を待ちたいので、ここで明示的に Serial.begin() してから待つ。
    // SERIAL_DEBUG=0 のときは DBG_BEGIN/WAIT_HOST が空展開され、
    // 従来どおり NoteSenderModule.init() が Serial.begin() する。
    DBG_BEGIN(115200);
    DBG_WAIT_HOST(1500);
    DBG_PRINTLN("");
    DBG_PRINTF("=== node_03 (round voice partId=0x%02X instr=%u headRest=%u) boot ===\n",
               (unsigned)ORC_RECEIVER_CONFIG.partId,
               (unsigned)NOTE_SENDER_CONFIG.instrumentId,
               (unsigned)ORC_RECEIVER_CONFIG.headRestBeats);

    initWithRetry(&gNet,  "OrcNetModule");
    initWithRetry(&gRecv, "OrcReceiverModule");
    initWithRetry(&gNote, "NoteSenderModule");
    initWithRetry(&gLed,  "StatusLedModule");

    DBG_PRINTLN("[N3 INIT] done");
}

void loop() {
    const uint32_t now = millis();
    if (now - gLastLoopMs < ORC_RECEIVER_CONFIG.loopIntervalMs) {
        return;  // ループ周期 5 ms を維持
    }
    gLastLoopMs = now;

    for (auto* m : gInputs) {
        if (m->enabled) m->updateInput(gData);
    }
    applyPattern(gData);
    for (auto* m : gOutputs) {
        if (m->enabled) m->updateOutput(gData);
    }
#if SERIAL_DEBUG
    dumpEdges(gData);
    dumpPeriodic(gData);
#endif
}
