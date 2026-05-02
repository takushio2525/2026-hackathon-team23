// 楽器ノード node_02 (金管 1) の設定一元化
// 4 台共通コードのうち、ここと score_data.* だけが差分
#pragma once
#include <Arduino.h>
#include <IPAddress.h>

#include "OrcNetModule.h"
#include "OrcReceiverModule.h"
#include "NoteSenderModule.h"
#include "StatusLedModule.h"

inline const OrcNetConfig ORC_NET_CONFIG = {
    /*mode=*/                WifiMode::Sta,
    /*ssid=*/                "OrchestraAP",
    /*pass=*/                "orchestra2026",
    /*multicastIp=*/         IPAddress(239, 0, 0, 1),
    /*udpPort=*/             5001,
    /*channel=*/             6,
    /*reconnectIntervalMs=*/ 2000,
};

inline const OrcReceiverConfig ORC_RECEIVER_CONFIG = {
    /*partId=*/              0x02,    // 金管 1
    /*startBeatNo=*/         0,       // 輪唱の入り拍 (このパートは先頭から)
    /*beatTimeoutMs=*/       1500,
    /*clockSyncEmaAlpha=*/   0.10f,
    /*clockSyncMinSamples=*/ 5,
    /*expiredGraceMs=*/      100,
    /*loopIntervalMs=*/      5,
};

inline const NoteSenderConfig NOTE_SENDER_CONFIG = {
    /*baudRate=*/ 115200,
    /*partId=*/   0x02,
};

inline const StatusLedConfig STATUS_LED_CONFIG = {
    /*pin=*/             LED_BUILTIN,
    /*blinkIntervalMs=*/ 500,
};

namespace logic_params {
    constexpr uint16_t LED_IDLE_MS       = 1000;
    constexpr uint16_t LED_WAIT_START_MS = 500;
    constexpr uint16_t LED_SELF_RUN_MS   = 200;
    constexpr uint32_t SELF_RUN_RECOVER_MS = 200;  // 実 BEAT 復帰の閾値
    constexpr float    DEFAULT_BPM = 120.0f;
}
