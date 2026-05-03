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
    /*pin=*/             LED_BUILTIN,   // XIAO ESP32-S3 では GPIO21 (User LED)
    /*blinkIntervalMs=*/ 500,
    /*activeLow=*/       true,          // XIAO ESP32-S3 の User LED は LOW で点灯
};

// applyPattern() のロジック係数
namespace logic_params {
    constexpr float    LPF_ALPHA               = 0.10f;
    // 拍検出閾値: 動加速度 (= LPF 後 - キャリブ重力) のノルムがこれを超えたら拍。
    // 重力 1g は引かれているので、純粋な振り下ろし加速度の大きさで判定する。
    // 経緯: 仕様書の 1.8g は重力込み前提で、そのままだと届かなかった。0.8g に
    // 下げたら小さい揺れで誤検出する (= 勝手に進む) ため、中間の 1.2g に調整。
    // 重力込み 1.8g は姿勢により動加速度 0.9〜1.5g 相当、その中央付近を狙う。
    // 拍検出の本体閾値 (Armed 突入トリガ)。振り下ろし加速のピーク値を狙う。
    constexpr float    BEAT_DYN_THRESHOLD_G    = 1.20f;
    constexpr uint32_t BEAT_REFRACTORY_MS      = 250;
    // 振り終わり (リリース) 判定。Armed 中に動加速度がこの値を下回ったら、
    // そのタイミング (= 振り下ろし切って減速し終わる瞬間) で拍を確定する。
    // BEAT_DYN_THRESHOLD_G より十分小さく取る (ヒステリシス)。
    constexpr float    BEAT_RELEASE_G          = 0.20f;
    // Armed が長引いて何かおかしいときの保険。これを超えたら強制的に Idle に
    // 戻して暴走を止める。普通の振り下ろしは 200〜400 ms なので 800 ms で十分。
    constexpr uint32_t BEAT_ARMED_TIMEOUT_MS   = 800;
    // 拍検出の追加ゲート: Armed に入ってから振り終わるまでに動かした
    // 「経路長」 (= 速度ノルムの時間積分) がこの距離以上であること。
    // 瞬間ピークだけが立つ細かい揺れを除外する AND 条件。10 cm = 0.10 m。
    // ※積分は Armed の間だけ走るので、起動からのノイズ蓄積は混じらない。
    constexpr float    BEAT_PATH_THRESHOLD_M   = 0.10f;
    // g -> m/s^2 変換係数 (ISO 標準重力)
    constexpr float    GRAVITY_MS2             = 9.80665f;
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
