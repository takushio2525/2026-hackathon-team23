// Build (run from project root) — shared by node_01 and node_02:
//   pio run -d firmware/test/node_01     # 指揮者ノード
//   pio run -d firmware/test/node_02     # 楽器 1

#include "StatusLedModule.h"
#include "SystemData.h"

bool StatusLedModule::init() {
    pinMode(cfg_.pin, OUTPUT);
    digitalWrite(cfg_.pin, LOW);
    ledOn_ = false;
    lastToggleMs_ = millis();
    return true;
}

void StatusLedModule::updateOutput(SystemData& data) {
    uint32_t now = millis();
    if (data.led.solidOn) {
        if (!ledOn_) {
            digitalWrite(cfg_.pin, HIGH);
            ledOn_ = true;
        }
        return;
    }
    uint16_t period = data.led.blinkIntervalMs ? data.led.blinkIntervalMs
                                               : cfg_.blinkIntervalMs;
    if (now - lastToggleMs_ >= period) {
        lastToggleMs_ = now;
        ledOn_ = !ledOn_;
        digitalWrite(cfg_.pin, ledOn_ ? HIGH : LOW);
    }
}
