// 「ある基準時刻からの経過 ms」を返す軽量タイマ
// 周期判定やタイムアウト判定に使う
#pragma once
#include <Arduino.h>

class ModuleTimer {
public:
    // 基準時刻を「現在 - offsetMs」にセット
    void setTime(uint32_t offsetMs = 0) {
        referenceMs_ = millis() - offsetMs;
    }

    // 基準時刻からの経過 ms を返す
    uint32_t getNowTime() const {
        return millis() - referenceMs_;
    }

private:
    uint32_t referenceMs_ = 0;
};
