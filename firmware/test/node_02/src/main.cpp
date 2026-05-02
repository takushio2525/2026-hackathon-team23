// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test/node_02
//   pio run -d firmware/test/node_02 -t upload
//   pio device monitor -d firmware/test/node_02
//
// 楽器ノード node_02 のエントリポイント (Arduino UNO R4 WiFi)
// 3 フェーズループを loopIntervalMs (5 ms) 間隔で回す
#include <Arduino.h>

#include "ProjectConfig.h"
#include "SystemData.h"

#include "OrcNetModule.h"
#include "OrcReceiverModule.h"
#include "NoteSenderModule.h"
#include "StatusLedModule.h"

void applyPattern(SystemData& data);

namespace {

SystemData         gData;
OrcNetModule       gNet(ORC_NET_CONFIG);
OrcReceiverModule  gRecv(ORC_RECEIVER_CONFIG);
NoteSenderModule   gNote(NOTE_SENDER_CONFIG);
StatusLedModule    gLed(STATUS_LED_CONFIG);

IModule* gAll[]     = { &gNet, &gRecv, &gNote, &gLed };
IModule* gInputs[]  = { &gNet, &gRecv };
IModule* gOutputs[] = { &gNote, &gLed, &gNet };

constexpr size_t MAX_RETRY = 3;
uint32_t gLastLoopMs = 0;

void initWithRetry(IModule* m) {
    bool ok = false;
    for (size_t i = 0; i < MAX_RETRY && !ok; ++i) {
        ok = m->init();
        if (!ok) delay(50);
    }
    m->enabled = ok;
}

}  // namespace

void setup() {
    // NoteSenderModule.init() で Serial.begin() するので、ここでは呼ばない
    for (auto* m : gAll) initWithRetry(m);
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
}
