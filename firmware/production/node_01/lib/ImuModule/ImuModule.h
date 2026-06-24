// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/production/node_01
//   pio run -d firmware/production/node_01 -t upload
//   pio device monitor -d firmware/production/node_01
//
// MPU6050 (GY-521) 6 軸を I2C で読むモジュール
// applyPattern() が data.imu の値を IIR LPF / ノルム計算 / 拍検出に使う
#pragma once
#include <Arduino.h>
#include "IModule.h"

struct ImuConfig {
    uint8_t  address;            // 0x68 (AD0=GND) or 0x69
    uint32_t sampleIntervalMs;   // 5 ms = 200 Hz
    uint8_t  accelRangeG;        // 2 / 4 / 8 / 16
    uint16_t gyroRangeDps;       // 250 / 500 / 1000 / 2000
};

struct ImuData {
    bool     ready = false;          // この周期で読めたか
    float    acc[3]   = {0, 0, 0};   // 生加速度 (g, 重力込み)
    float    gyro[3]  = {0, 0, 0};   // 生角速度 (dps)
    float    accLpf[3] = {0, 0, 0};  // LPF 後の加速度 (g, 重力込み)
    float    accNorm = 0;            // LPF 後ノルム (g, 重力込み)
    // 動加速度ノルム dynNorm = accNorm - キャリブ済み静止ノルム (gravityMag ≒ 1g)。
    // 姿勢非依存のスカラー量で、拍検出はこの dynNorm で判定する。0 でクランプ済み。
    // dynAcc は accLpf の向きを保ったまま大きさを dynNorm にスケールしたベクトル
    // (= 重力を「現在の加速度方向の成分」として差し引いた近似)。経路長の二重積分用。
    // Calibrating 完了前は gravityMag=0 のため dynNorm=accNorm。
    float    dynAcc[3] = {0, 0, 0};
    float    dynNorm = 0;
    uint32_t sampleAtMs = 0;
};

class ImuModule : public IModule {
public:
    explicit ImuModule(const ImuConfig& cfg) : cfg_(cfg) {}
    bool init() override;
    void updateInput(SystemData& data) override;

private:
    bool readBurst(ImuData& imu);

    ImuConfig cfg_;
    uint32_t  lastSampleMs_ = 0;
    float     accelLsbToG_  = 1.0f / 8192.0f;   // ±4g 既定
    float     gyroLsbToDps_ = 1.0f / 16.4f;     // ±2000 dps 既定
};
