// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test/node_01
//   pio run -d firmware/test/node_01 -t upload
//   pio device monitor -d firmware/test/node_01
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

void applyPattern(SystemData& data);

namespace {

SystemData       gData;
ImuModule        gImu(IMU_CONFIG);
OrcNetModule     gNet(ORC_NET_CONFIG);
OrcSenderModule  gSender(ORC_SENDER_CONFIG);
StatusLedModule  gLed(STATUS_LED_CONFIG);

// init を一意モジュール集合に対して呼ぶ
IModule* gAll[]     = { &gNet, &gImu, &gSender, &gLed };
// 入力フェーズ: WiFi 受信 -> IMU 読取
IModule* gInputs[]  = { &gNet, &gImu };
// 出力フェーズ: ロジック結果をパケット化 -> LED 反映 -> UDP 送信
IModule* gOutputs[] = { &gSender, &gLed, &gNet };

constexpr size_t MAX_RETRY = 3;

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
    Serial.begin(115200);
    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    Wire.setClock(400000);

    for (auto* m : gAll) initWithRetry(m);
}

void loop() {
    for (auto* m : gInputs) {
        if (m->enabled) m->updateInput(gData);
    }
    applyPattern(gData);
    for (auto* m : gOutputs) {
        if (m->enabled) m->updateOutput(gData);
    }
}
