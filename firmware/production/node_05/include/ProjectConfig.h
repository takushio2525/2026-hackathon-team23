// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/production/node_05
//   pio run -d firmware/production/node_05 -t upload
//   pio device monitor -d firmware/production/node_05
//
// 楽器ノード node_05 — 輪唱「かえるのうた」の声部 4 (24 拍遅れて入る / 楽器番号 3)
// node_02〜05 で差分はこのファイルだけ (楽譜 score_data.* は 4 台とも同一)。
//   node_02: partId=0x02  headRestBeats=0   instrumentId=0 (トランペット)
//   node_03: partId=0x03  headRestBeats=8   instrumentId=1 (ホルン)
//   node_04: partId=0x04  headRestBeats=16  instrumentId=2 (トロンボーン)
//   node_05: partId=0x05  headRestBeats=24  instrumentId=3 (チューバ)
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
    /*partId=*/                0x05,    // 輪唱 声部 4
    /*headRestBeats=*/         24,      // 24 拍ぶん頭に休符を入れてから入る (最終声部)
    /*clockSyncWindowMs=*/     2000,    // min フィルタ窓長: バースト配送 (204.8ms 周期) ~10 回ぶん。
                                        // 旧 EMA は推定時計が真値より 40〜55ms 遅れていた
                                        // (MOP5_systematic_shift_analysis_20260710.md §4/§8 案4)
    /*clockSyncMinSamples=*/   5,
    /*clockSyncSnapThresholdMs=*/ 1000,  // 指揮者リセット (マスタ時計巻き戻り) を 1 パケットで追従。正常遅延 (数十 ms) では届かない
    /*loopIntervalMs=*/        2,       // 旧 5 ms → 2 ms (発音判定ジッタ最大 5 ms → 2 ms)
};

inline const NoteSenderConfig NOTE_SENDER_CONFIG = {
    /*baudRate=*/     115200,
    /*partId=*/       0x05,
    /*instrumentId=*/ 3,             // PC 側で読み込んだ楽器定義 (data/*.json) の何番目を使うか (3=チューバ)
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
    // 輪唱サイクル長 [拍] = 曲長 32 拍 + 最終声部 (node_05) の入り遅れ 24 拍。
    // 全声部がこの周期を共有することで「最終声部が 1 周を終えるまで先頭声部が
    // 次の周回を始めない」という輪唱の終端が成立する。score_data.cpp の曲長や
    // 各ノードの headRestBeats (0/8/16/24) を変えるときは、必ず 4 ノードすべてで
    // この値を揃えて再計算すること (ずれると声部間の周回がぶつかる)。
    constexpr uint16_t CANON_CYCLE_BEATS = 56;
}
