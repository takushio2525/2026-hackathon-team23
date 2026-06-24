// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/production/node_06
//   pio run -d firmware/production/node_06 -t upload
//   pio device monitor -d firmware/production/node_06
//
// 楽器ノード入力モジュール (輪唱の 1 声部)
// data.orcNet (生の受信ペイロード) を読み、時計同期 / 受理 BEAT キュー / CTRL 状態を整形して
// data.sync / data.receiver / data.ctrl に書き出す
#pragma once
#include <Arduino.h>
#include "IModule.h"

struct OrcReceiverConfig {
    uint8_t  partId;                  // 0x02-0x05: 輪唱のどの声部か
    uint16_t headRestBeats;           // 輪唱: 先頭に入れる休符の拍数 (0=先頭から入る)。
                                      // applyPattern が firedBeatNo からこのぶん引いて楽譜を引く
    float    clockSyncEmaAlpha;       // 初回サンプル (新規 CTRL / 初到着 BEAT) の EMA 係数
    float    clockSyncEmaAlphaDup;    // 重複サンプル (同一 beatNo の連送 2 個目以降) の EMA 係数。
                                      // 連送は数 ms 以内の強相関サンプルなので、初回より小さく
                                      // して過剰反映を防ぐ。初回 0.20 × 重複 0.05 で、4 連送
                                      // 合計の影響は ≈ 0.32 (初回 α 単独に近い吸い方)。
    uint8_t  clockSyncMinSamples;     // 5 (デバッグ表示用. Playing 遷移条件には使わない)
    uint16_t clockSyncSnapThresholdMs; // offset サンプルが現 EMA からこれ以上飛んだら EMA を
                                      // やめて即時採用 (スナップ)。指揮者リセットでマスタ時計が
                                      // 巻き戻った直後でも 1 パケットで追従できる。SoftAP 直結
                                      // LAN の正常遅延 (数十 ms) では届かない 1000 を推奨。
    uint16_t loopIntervalMs;          // 2 ms (発火判定粒度。短いほど発音ジッタが減る)
};

struct PendingBeat {
    bool     valid = false;
    uint16_t beatNo = 0;
    uint32_t playAtMasterMs = 0;
    uint32_t enqueuedAtMs = 0;
};

struct ReceiverLogicData {
    bool        hasFirstBeat = false;
    uint16_t    lastBeatNo = 0;
    uint32_t    lastBeatMs = 0;
    PendingBeat pending;
};

class OrcReceiverModule : public IModule {
public:
    explicit OrcReceiverModule(const OrcReceiverConfig& cfg) : cfg_(cfg) {}
    bool init() override { return true; }
    void updateInput(SystemData& data) override;

private:
    OrcReceiverConfig cfg_;
};
