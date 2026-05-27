// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v2/node_01_devkitc
//   pio run -d firmware/test_v2/node_01_devkitc -t upload
//   pio device monitor -d firmware/test_v2/node_01_devkitc
//
// 指揮者ノード node_01_devkitc (ESP32-S3-DevKitC-1 版) のピン/定数/閾値を一元管理。
// アンテナ切り分け用に node_01 (XIAO ESP32-S3 Sense / 外付け IPEX) と全く同じロジックを
// 別ボードで動かす。ピン GPIO 番号は XIAO 版と同一なので、配線図だけ差し替えれば
// 共通モジュールを修正せず流用できる。
#pragma once
#include <Arduino.h>
#include <IPAddress.h>

#include "OrcNetModule.h"
#include "StatusLedModule.h"
#include "ImuModule.h"
#include "OrcSenderModule.h"

// ESP32-S3-DevKitC-1 左列ピンヘッダから I2C を取り出す配置。
// 左列上から 3V3/3V3/RST/GPIO4/GPIO5/GPIO6/GPIO7/... の順なので、SDA=GPIO5/SCL=GPIO6
// は左列 5・6 番目で物理的に連続している。ブレッドボード上で GY-521 を横に並べて
// 配線できる。GPIO5/6 はストラッピングピンではないので I2C 用途で安全に使える。
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
    /*beatGapMs=*/           0,    // 0 = タイトループ連送 (旧挙動)。一時的に切り分け用
};

inline const OrcSenderConfig ORC_SENDER_CONFIG = {
    /*ctrlIntervalMs=*/  50,   // 20 Hz
    /*beatRedundancy=*/  4,    // 同一 BEAT を 4 連送 (旧 2 だが ESP32-S3 SoftAP の radio ロス対策。連送間隔は OrcNetModule の beatGapMs で設定)
    /*beatLookaheadMs=*/ 50,   // playAtMasterMs = masterNow + 50 ms
};

inline const StatusLedConfig STATUS_LED_CONFIG = {
    // DevKitC-1 の User LED は GPIO48 の WS2812 (ネオピクセル) なので digitalWrite では
    // 光らない。LED_BUILTIN マクロが 48 を指すのでそのまま書き込んでも害はない (光らない
    // だけ)。状態確認は SERIAL_DEBUG=1 の Serial ログで行う。
    // 外部 LED で状態表示したい場合は、左列で空いている GPIO7 等に LED+抵抗を付けて
    // pin を 7、activeLow を false に変更する。
    /*pin=*/             LED_BUILTIN,   // = 48 (DevKitC では実 LED として点灯しない)
    /*blinkIntervalMs=*/ 500,
    /*activeLow=*/       false,         // WS2812 は無関係。外部 LED 追加時のデフォルトに合わせる
};

// applyPattern() のロジック係数
namespace logic_params {
    constexpr float    LPF_ALPHA               = 0.10f;
    // 拍検出閾値 (Armed 突入トリガ): 動加速度ノルム dynNorm (= LPF 後の加速度
    // ノルム − キャリブ済み静止ノルム ≒1g) がこれを超えたら拍候補とみなす。
    // 姿勢非依存のスカラー量で、重力相当は引かれているので純粋な振りの加速度
    // 強度で判定する。振り下ろし加速のピーク値を狙う。
    // 経緯: 仕様書の 1.8g は重力込み前提で届かず、0.8g では小さい揺れで誤検出
    // (= 勝手に進む) したため中間の 1.2g に調整。
    // 注意: ノルム差なので重力に直交する向きの振りは過小評価される
    // (|g + a| − |g| = sqrt(1 + a²) − 1 < a)。実機で取りこぼし/誤検出が出たら
    // 1.0〜1.4 の範囲で再調整する。
    constexpr float    BEAT_DYN_THRESHOLD_G    = 1.20f;
    // 不応期: 1 振りの中で「振り下ろし -> 振り戻し」の両方を 2 拍として
    // 拾わないために必要。350 ms = 約 170 BPM 上限。普通の指揮なら十分。
    constexpr uint32_t BEAT_REFRACTORY_MS      = 350;
    // 振り終わり (リリース) 判定: 以下の OR でリリースと見なす。
    //   (a) 動加速度が BEAT_RELEASE_G 未満 (= 完全停止)
    //   (b) 動加速度が Armed 中ピークの BEAT_RELEASE_RATIO 未満
    //       (= ピークアウト後、相対的に十分減衰)
    // 連続スイングだと dynNorm が 0 まで落ちきらないので、(b) で拾う。
    constexpr float    BEAT_RELEASE_G          = 0.20f;
    constexpr float    BEAT_RELEASE_RATIO      = 0.40f;
    // Armed 突入直後の単発ノイズで誤リリースしないための最低保持時間。
    constexpr uint32_t BEAT_ARMED_MIN_HOLD_MS  = 50;
    // リリース判定デバウンス: (releaseAbs || releaseRatio) が連続して
    // この時間以上成立したら真のリリースと見なす。振り途中の一瞬の dynNorm
    // dip で Armed を抜けて再 Armed→再発火するのを防ぐ。
    // 5ms 周期 IMU で 8 サンプル分。短すぎると効かず、長すぎるとリリースが
    // 遅れて連続スイングのテンポが乱れる。
    constexpr uint32_t BEAT_RELEASE_HOLD_MS    = 40;
    // Armed が長引いたら強制終了。普通の振り下ろしは 200〜500 ms 程度。
    // タイムアウトでも path/refractory を満たせば拍として採用する (取りこぼし防止)。
    constexpr uint32_t BEAT_ARMED_TIMEOUT_MS   = 800;
    // 早期発火の閾値 (= "swing intensity" の最低ライン)。
    // Armed セッション中、擬似経路長 sPathLen がこの値に達した瞬間に拍を発火
    // する。本振りなら Armed 突入から ~150 ms 程度で到達するため、振りと
    // 音がほぼ同時に感じられる。
    // 0.10 では軽い振れ (peak 1.3 g 程度) でも 100 ms で蓄積して誤発火した
    // ため 0.20 に引き上げ。
    // 1 Armed セッションに 1 回しか発火しない & 発火後も Armed を維持して
    // リリース/timeout を待つため、同じ振り中に二重発火しない。連続スイング
    // で「発火→即 Idle→再 Arm→refractory 境界で再発火」という連続発火
    // ループも構造的に発生しない。
    constexpr float    BEAT_FIRE_PATH_M        = 0.20f;
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
