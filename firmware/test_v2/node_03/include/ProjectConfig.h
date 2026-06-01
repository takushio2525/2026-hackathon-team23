// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v2/node_03
//   pio run -d firmware/test_v2/node_03 -t upload
//   pio device monitor -d firmware/test_v2/node_03
//
// 楽器ノード node_03 — 輪唱「きらきら星」の声部 2 (8 拍遅れて入る / 楽器番号 1)
// node_02/03/04 で差分はこのファイルだけ (楽譜 score_data.* は 3 台とも同一)。
//   node_02: partId=0x02  headRestBeats=0   instrumentId=0
//   node_03: partId=0x03  headRestBeats=8   instrumentId=1
//   node_04: partId=0x04  headRestBeats=16  instrumentId=2
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
    /*beatGapMs=*/           0,    // Sta 側は送信しないので未使用
};

inline const OrcReceiverConfig ORC_RECEIVER_CONFIG = {
    /*partId=*/                0x03,    // 輪唱 声部 2
    /*headRestBeats=*/         8,       // 8 拍ぶん頭に休符を入れてから入る
    /*clockSyncEmaAlpha=*/     0.20f,   // 初回サンプル: 旧 0.10 → 0.20 で応答性向上 (時定数 ≈0.25 s)
    /*clockSyncEmaAlphaDup=*/  0.05f,   // 連送 2 個目以降: 過剰反映を避けて軽く補正
    /*clockSyncMinSamples=*/   5,
    /*loopIntervalMs=*/        2,       // 旧 5 ms → 2 ms (発音判定ジッタ最大 5 ms → 2 ms)
};

inline const NoteSenderConfig NOTE_SENDER_CONFIG = {
    /*baudRate=*/     115200,
    /*partId=*/       0x03,
    /*instrumentId=*/ 1,             // PC 側で読み込んだ楽器定義 (data/*.json) の何番目を使うか
};

inline const StatusLedConfig STATUS_LED_CONFIG = {
    /*pin=*/             LED_BUILTIN,
    /*blinkIntervalMs=*/ 500,
    /*activeLow=*/       false,    // UNO R4 WiFi の LED_BUILTIN は HIGH で点灯
};

namespace logic_params {
    constexpr uint16_t LED_IDLE_MS       = 1000;
    constexpr uint16_t LED_WAIT_START_MS = 500;
    constexpr float    DEFAULT_BPM = 100.0f;   // CTRL 未受信時の発音長計算に使う既定テンポ
}
