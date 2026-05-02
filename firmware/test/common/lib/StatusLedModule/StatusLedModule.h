// 状態に応じた LED 点滅を担当する IModule 実装
// applyPattern() が data.led.blinkIntervalMs / solidOn を更新する
#pragma once
#include <Arduino.h>
#include "IModule.h"

struct StatusLedConfig {
    uint8_t  pin;
    uint16_t blinkIntervalMs;  // 既定の点滅周期
};

struct StatusLedData {
    uint16_t blinkIntervalMs = 500;
    bool     solidOn = false;  // true なら点灯固定 (Conducting / Playing)
};

class StatusLedModule : public IModule {
public:
    explicit StatusLedModule(const StatusLedConfig& cfg) : cfg_(cfg) {}
    bool init() override;
    void updateOutput(SystemData& data) override;

private:
    StatusLedConfig cfg_;
    uint32_t lastToggleMs_ = 0;
    bool     ledOn_ = false;
};
