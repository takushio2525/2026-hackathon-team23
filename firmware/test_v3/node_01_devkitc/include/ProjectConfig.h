// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v2/node_01
//   pio run -d firmware/test_v2/node_01 -t upload
//   pio device monitor -d firmware/test_v2/node_01
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
    /*beatGapMs=*/           2,    // 連送 4 発を 2ms 間隔で時間分散し radio のまとめ落ちを軽減
};

inline const OrcSenderConfig ORC_SENDER_CONFIG = {
    /*ctrlIntervalMs=*/  50,   // 20 Hz
    /*beatRedundancy=*/  4,    // 同一 BEAT を 4 連送 (旧 2 だが ESP32-S3 SoftAP の radio ロス対策。連送間隔は OrcNetModule の beatGapMs で設定)
    /*beatLookaheadMs=*/ 30,   // playAtMasterMs = masterNow + 30 ms (連送受信完了 ~23ms にマージン約7ms)
};

inline const StatusLedConfig STATUS_LED_CONFIG = {
    /*pin=*/             LED_BUILTIN,   // XIAO ESP32-S3 では GPIO21 (User LED)
    /*blinkIntervalMs=*/ 500,
    /*activeLow=*/       true,          // XIAO ESP32-S3 の User LED は LOW で点灯
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
    constexpr uint16_t LED_MENU_MS             = 300;   // メニュー中 (約 1.7 Hz)
    constexpr uint16_t LED_RESULT_MS           = 120;   // 結果表示中 (速い点滅で完了を示す)

    // ── test_v3 ゲームモード: IMU メニューナビ (単純閾値判定) ──
    // dynAcc[NAV_LR_AXIS] (左右) / dynAcc[NAV_UD_AXIS] (上下) の符号と大きさだけで判定する。
    // 複雑なジェスチャ認識はしない。軸番号と符号は IMU の物理取付に依存するので実機で確定する
    // (右に振る→カーソル右、下に振る→決定、になる軸/符号へ要調整)。暫定: X=左右 / Y=上下。
    constexpr uint8_t  NAV_LR_AXIS             = 0;     // 左右 = X 軸 (要実機確認)
    constexpr uint8_t  NAV_UD_AXIS             = 1;     // 上下 = Y 軸 (要実機確認)
    constexpr float    NAV_SWING_THRESHOLD_G   = 1.00f; // ナビ振り検出しきい値 (拍検出 1.20g より低め)
    constexpr float    NAV_RELEASE_G           = 0.30f; // ナビゲート解放 (1 振り=1 操作にするため)
    constexpr uint32_t NAV_REFRACTORY_MS       = 400;   // ナビ不応期 (誤連打防止)
    constexpr uint8_t  MENU_ITEM_COUNT         = 2;     // メニュー項目数 (0=自由演奏 / 1=ゲーム)

    // ── test_v3 ゲームモード: ゲーム進行・採点・ガイドフェード ──
    constexpr uint16_t GAME_LENGTH_BEATS       = 32;    // ゲーム 1 セッションの拍数 (かえるのうた 1 周 = 32 拍)
    constexpr uint8_t  GAME_TARGET_BPM         = 100;   // 目標テンポ (固定・設定値)
    // メトロノームガイド強度の固定スケジュール (経過拍ベース):
    //   beat <  FULL          : 強度 1.0 (はっきり刻む)
    //   FULL <= beat <  ZERO  : 1.0→0 へ線形フェード
    //   beat >= ZERO          : 強度 0   (ガイドなし・記憶で維持)
    // 採点重み = 1 - 強度 (ガイドが薄い/無い区間ほど重く配点)。
    constexpr uint16_t GAME_GUIDE_FULL_BEATS   = 8;
    constexpr uint16_t GAME_GUIDE_ZERO_BEATS   = 16;
    // 採点の許容誤差比: 拍間隔誤差が目標拍間隔のこの割合に達したら 0 点。0.5 = 半拍ずれで 0 点。
    constexpr float    GAME_SCORE_TOLERANCE_RATIO = 0.5f;
}
