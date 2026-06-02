// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v2/node_01
//   pio run -d firmware/test_v2/node_01 -t upload
//   pio device monitor -d firmware/test_v2/node_01

#include "ImuModule.h"
#include "SystemData.h"
#include <Wire.h>

namespace {

constexpr uint8_t REG_PWR_MGMT_1   = 0x6B;
constexpr uint8_t REG_ACCEL_CONFIG = 0x1C;
constexpr uint8_t REG_GYRO_CONFIG  = 0x1B;
constexpr uint8_t REG_ACCEL_XOUT_H = 0x3B;
constexpr uint8_t REG_WHO_AM_I     = 0x75;

bool writeReg(uint8_t addr, uint8_t reg, uint8_t val) {
    Wire.beginTransmission(addr);
    Wire.write(reg);
    Wire.write(val);
    return Wire.endTransmission() == 0;
}

bool readRegs(uint8_t addr, uint8_t reg, uint8_t* out, uint8_t len) {
    Wire.beginTransmission(addr);
    Wire.write(reg);
    if (Wire.endTransmission(false) != 0) return false;
    uint8_t got = Wire.requestFrom((int)addr, (int)len);
    if (got != len) return false;
    for (uint8_t i = 0; i < len; ++i) out[i] = Wire.read();
    return true;
}

}  // namespace

bool ImuModule::init() {
    // Wire.begin() は main 側で SDA/SCL 指定込みで呼ばれている前提
    uint8_t who = 0;
    if (!readRegs(cfg_.address, REG_WHO_AM_I, &who, 1)) return false;
    // MPU6050 は 0x68、互換 MPU6500 は 0x70
    if (who != 0x68 && who != 0x70 && who != 0x71 && who != 0x72) return false;

    // SLEEP 解除 + クロック源 PLL
    if (!writeReg(cfg_.address, REG_PWR_MGMT_1, 0x01)) return false;
    delay(10);

    uint8_t accelFs;
    switch (cfg_.accelRangeG) {
        case 2:  accelFs = 0; accelLsbToG_ = 1.0f / 16384.0f; break;
        case 4:  accelFs = 1; accelLsbToG_ = 1.0f / 8192.0f;  break;
        case 8:  accelFs = 2; accelLsbToG_ = 1.0f / 4096.0f;  break;
        case 16: accelFs = 3; accelLsbToG_ = 1.0f / 2048.0f;  break;
        default: accelFs = 1; accelLsbToG_ = 1.0f / 8192.0f;  break;
    }
    if (!writeReg(cfg_.address, REG_ACCEL_CONFIG, (uint8_t)(accelFs << 3))) return false;

    uint8_t gyroFs;
    switch (cfg_.gyroRangeDps) {
        case 250:  gyroFs = 0; gyroLsbToDps_ = 1.0f / 131.0f; break;
        case 500:  gyroFs = 1; gyroLsbToDps_ = 1.0f / 65.5f;  break;
        case 1000: gyroFs = 2; gyroLsbToDps_ = 1.0f / 32.8f;  break;
        case 2000: gyroFs = 3; gyroLsbToDps_ = 1.0f / 16.4f;  break;
        default:   gyroFs = 3; gyroLsbToDps_ = 1.0f / 16.4f;  break;
    }
    if (!writeReg(cfg_.address, REG_GYRO_CONFIG, (uint8_t)(gyroFs << 3))) return false;

    return true;
}

void ImuModule::updateInput(SystemData& data) {
    uint32_t now = millis();
    if (now - lastSampleMs_ < cfg_.sampleIntervalMs) {
        data.imu.ready = false;
        return;
    }
    lastSampleMs_ = now;
    if (!readBurst(data.imu)) {
        data.imu.ready = false;
    }
}

bool ImuModule::readBurst(ImuData& imu) {
    uint8_t buf[14];
    if (!readRegs(cfg_.address, REG_ACCEL_XOUT_H, buf, 14)) {
        return false;
    }
    int16_t ax = (int16_t)((buf[0]  << 8) | buf[1]);
    int16_t ay = (int16_t)((buf[2]  << 8) | buf[3]);
    int16_t az = (int16_t)((buf[4]  << 8) | buf[5]);
    // buf[6..7] は温度。本案件未使用。
    int16_t gx = (int16_t)((buf[8]  << 8) | buf[9]);
    int16_t gy = (int16_t)((buf[10] << 8) | buf[11]);
    int16_t gz = (int16_t)((buf[12] << 8) | buf[13]);

    imu.acc[0]  = ax * accelLsbToG_;
    imu.acc[1]  = ay * accelLsbToG_;
    imu.acc[2]  = az * accelLsbToG_;
    imu.gyro[0] = gx * gyroLsbToDps_;
    imu.gyro[1] = gy * gyroLsbToDps_;
    imu.gyro[2] = gz * gyroLsbToDps_;
    imu.sampleAtMs = lastSampleMs_;
    imu.ready = true;
    return true;
}
