// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test/node_01
//   pio run -d firmware/test/node_01 -t upload
//   pio device monitor -d firmware/test/node_01
//
// 指揮者ノード node_01 のピン/定数/閾値を一元管理
// 具体値はこの 1 ファイルでだけ管理し、モジュール本体にはハードコードしない
#pragma once
#include <Arduino.h>
#include <IPAddress.h>

#include "OrcNetModule.h"
#include "StatusLedModule.h"
#include "ImuModule.h"
#include "OrcSenderModule.h"

// XIAO ESP32-S3 Sense の I2C 既定ピン (D4=GPIO5, D5=GPIO6)
constexpr uint8_t I2C_SDA_PIN = 5;
constexpr uint8_t I2C_SCL_PIN = 6;

inline const ImuConfig IMU_CONFIG = {
    /*address=*/          0x68,
    /*sampleIntervalMs=*/ 5,
    /*accelRangeG=*/      4,
    /*gyroRangeDps=*/     2000,
};

inline const OrcNetConfig ORC_NET_CONFIG = {
    /*mode=*/                WifiMode::SoftAp,
    /*ssid=*/                "OrchestraAP",
    /*pass=*/                "orchestra2026",
    /*multicastIp=*/         IPAddress(239, 0, 0, 1),
    /*udpPort=*/             5001,
    /*channel=*/             6,
    /*reconnectIntervalMs=*/ 2000,
};

inline const OrcSenderConfig ORC_SENDER_CONFIG = {
    /*ctrlIntervalMs=*/  50,   // 20 Hz
    /*beatRedundancy=*/  2,    // 同一 BEAT を 2 連送
    /*beatLookaheadMs=*/ 50,   // playAtMasterMs = masterNow + 50 ms
};

inline const StatusLedConfig STATUS_LED_CONFIG = {
    /*pin=*/             LED_BUILTIN,
    /*blinkIntervalMs=*/ 500,
};

// applyPattern() のロジック係数
namespace logic_params {
    constexpr float    LPF_ALPHA               = 0.10f;
    // 拍検出はヒステリシス付きの立ち上がりエッジ検出にしている。
    // 「dynNorm が LO 以下に一旦戻ってから HI を超えた瞬間」だけ 1 BEAT 発火。
    // これで 1 振りの中の過渡振動や、静止時の微小ドリフトによる連発を防ぐ。
    // 経緯: 単純な閾値超えだと振り下ろし1回で複数 BEAT が出て、Processing 側で
    // 「ずっと音が流れる」状態になっていたため、エッジ検出に置き換えた。
    constexpr float    BEAT_DYN_HI_G           = 1.20f;  // 発火しきい (振り下ろしのピーク)
    constexpr float    BEAT_DYN_LO_G           = 0.40f;  // 解除しきい (これ未満に戻ったら次を許可)
    constexpr uint32_t BEAT_REFRACTORY_MS      = 250;    // 保険: 連続発火の最小間隔
    constexpr float    BPM_EMA_ALPHA           = 0.30f;
    constexpr float    BPM_MIN                 = 40.0f;
    constexpr float    BPM_MAX                 = 240.0f;
    constexpr uint32_t CALIBRATION_MS          = 2000;
    constexpr uint32_t IMU_TIMEOUT_MS          = 200;
    // LED 点滅周期
    constexpr uint16_t LED_IDLE_MS             = 1000;  // 1 Hz
    constexpr uint16_t LED_CALIBRATING_MS      = 500;   // 2 Hz
    constexpr uint16_t LED_FALLBACK_MS         = 200;   // 5 Hz
}
