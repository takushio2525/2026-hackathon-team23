// Build (run from project root) — shared by node_01 and node_02:
//   pio run -d firmware/production/node_01     # 指揮者ノード
//   pio run -d firmware/production/node_02     # 楽器 1
//
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
