// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v3/node_06
//   pio run -d firmware/test_v3/node_06 -t upload
//   pio device monitor -d firmware/test_v3/node_06
//
// 楽器ノード node_06 — ドラム (headRestBeats=0 / 楽器番号 4 = kick)
// ドラムは 56 拍分のサイクル全体を担当し、金管4声と同じサイクル窓を共有する。
// instrumentId=4 は PC 側の data/4_kick のインデックスに対応するが、ドラムの
// 各打楽器音色は noteNumber (GM ドラムマップ) で Processing 側が判別する。
//   node_02: partId=0x02  headRestBeats=0   instrumentId=0 (トランペット)
//   node_03: partId=0x03  headRestBeats=8   instrumentId=1 (ホルン)
//   node_04: partId=0x04  headRestBeats=16  instrumentId=2 (トロンボーン)
//   node_05: partId=0x05  headRestBeats=24  instrumentId=3 (チューバ)
//   node_06: partId=0x06  headRestBeats=0   instrumentId=4 (ドラム)
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
    /*partId=*/                0x06,    // ドラム
    /*headRestBeats=*/         0,       // 先頭から入る (サイクル全体を担当)
    /*clockSyncEmaAlpha=*/     0.20f,
    /*clockSyncEmaAlphaDup=*/  0.05f,
    /*clockSyncMinSamples=*/   5,
    /*clockSyncSnapThresholdMs=*/ 1000,
    /*loopIntervalMs=*/        2,
};

inline const NoteSenderConfig NOTE_SENDER_CONFIG = {
    /*baudRate=*/     115200,
    /*partId=*/       0x06,
    /*instrumentId=*/ 4,             // PC 側の楽器定義インデックス (4=kick がベースだが、noteNumber で打楽器を区別)
};

inline const StatusLedConfig STATUS_LED_CONFIG = {
    /*pin=*/             LED_BUILTIN,
    /*blinkIntervalMs=*/ 500,
    /*activeLow=*/       false,    // UNO R4 WiFi の LED_BUILTIN は HIGH で点灯
};

namespace logic_params {
    constexpr uint16_t LED_IDLE_MS       = 1000;
    constexpr uint16_t LED_WAIT_START_MS = 500;
    constexpr float    DEFAULT_BPM = 100.0f;
    // ドラムは headRestBeats=0 でサイクル全体 56 拍を担当する。
    // 金管4声と同じサイクル窓を共有し、全声部が 1 周を終えるまで次の周回を始めない。
    constexpr uint16_t CANON_CYCLE_BEATS = 56;
}
