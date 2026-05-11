// Build (run from project root) — shared by node_01 and node_02:
//   pio run -d firmware/test_v1/node_01     # 指揮者ノード
//   pio run -d firmware/test_v1/node_02     # 楽器 1

#include "StatusLedModule.h"
#include "SystemData.h"

bool StatusLedModule::init() {
    pinMode(cfg_.pin, OUTPUT);
    // activeLow=true なら HIGH が消灯、活性化レベルは下記 onLevel_ で扱う
    digitalWrite(cfg_.pin, cfg_.activeLow ? HIGH : LOW);
    ledOn_ = false;
    lastToggleMs_ = millis();
    return true;
}

void StatusLedModule::updateOutput(SystemData& data) {
    const uint8_t onLevel  = cfg_.activeLow ? LOW  : HIGH;
    const uint8_t offLevel = cfg_.activeLow ? HIGH : LOW;
    uint32_t now = millis();
    if (data.led.solidOn) {
        if (!ledOn_) {
            digitalWrite(cfg_.pin, onLevel);
            ledOn_ = true;
        }
        return;
    }
    uint16_t period = data.led.blinkIntervalMs ? data.led.blinkIntervalMs
                                               : cfg_.blinkIntervalMs;
    if (now - lastToggleMs_ >= period) {
        lastToggleMs_ = now;
        ledOn_ = !ledOn_;
        digitalWrite(cfg_.pin, ledOn_ ? onLevel : offLevel);
    }
}
