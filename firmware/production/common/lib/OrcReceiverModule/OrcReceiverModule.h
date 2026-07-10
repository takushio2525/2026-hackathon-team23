// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/production/node_XX
//   pio run -d firmware/production/node_XX -t upload
//   pio device monitor -d firmware/production/node_XX
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
    uint16_t clockSyncWindowMs;       // 時計同期 min フィルタの窓長 [ms]。窓内の最大 offset
                                      // サンプル (= 最小配送遅延のサンプル) だけを採用する。
                                      // 旧 EMA (α=0.20) は SoftAP のバースト配送 (204.8ms 周期)
                                      // 下で平均遅延を吸い込み、推定マスタ時計が真値より
                                      // 40〜55ms 遅れていた。窓長はバースト ~10 回ぶん (2000ms)
                                      // を推奨: 窓内に鮮度の高い CTRL がほぼ確実に含まれ、
                                      // UNO R4 の millis() スキュー (最大 ±0.3%) への下方向
                                      // 追従も窓長ぶん (≈6ms) に抑えられる。
    uint8_t  clockSyncMinSamples;     // 5 (デバッグ表示用. Playing 遷移条件には使わない)
    uint16_t clockSyncSnapThresholdMs; // offset サンプルが現推定値からこれ以上飛んだらフィルタを
                                      // やめて即時採用 (スナップ)。指揮者リセットでマスタ時計が
                                      // 巻き戻った直後でも 1 パケットで追従できる。SoftAP 直結
                                      // LAN の正常遅延 (バースト待ち含め ~205ms) では届かない
                                      // 1000 を推奨。
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
    // 時計同期の min フィルタ本体 (実装と設計意図は .cpp のコメント参照)。
    // 返り値: スナップ (指揮者リセット等の大ジャンプへの即時追従) が起きたか。
    bool updateClockOffset(SystemData& data, uint32_t timestampMs);

    OrcReceiverConfig cfg_;
    // min フィルタの窓状態 (data.sync には推定結果 offsetMs だけを公開する)
    bool     winValid_     = false;  // 現在の窓が開いているか
    int32_t  winMaxSample_ = 0;      // 窓内の最大 offset サンプル
    uint32_t winStartMs_   = 0;      // 窓の開始時刻 (millis)
};
