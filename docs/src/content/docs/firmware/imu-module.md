---
title: ImuModule — MPU6050 を I2C で読む
description: 6 軸 IMU GY-521 から加速度・角速度を 200 Hz で取得する入力モジュールの内部実装。レジスタ叩きから 14 B バーストリードまで
sidebar:
  label: 指揮者 — ImuModule
  order: 6
---

:::note[この章で分かること]
- MPU6050 (GY-521) のレジスタアドレスと初期化シーケンス
- 加速度フルスケール ±4g と角速度フルスケール ±2000 dps を選ぶ理由
- `readRegs()` 1 回で 14 バイト連続読み出し（バーストリード）する仕掛け
- `sampleIntervalMs` で 200 Hz サンプルレートをどう実現するか
:::

## 実体

| ファイル | 行数 | 内容 |
|---|---|---|
| `firmware/production/node_01/lib/ImuModule/ImuModule.h` | 49 | Config / Data / クラス宣言 |
| `firmware/production/node_01/lib/ImuModule/ImuModule.cpp` | 106 | レジスタアクセス + バーストリード実装 |

指揮者ノード（XIAO ESP32-S3 Sense）専用。楽器ノードでは使わない。

## 役割と責務

| 観点 | 内容 |
|---|---|
| **入力責務** | 5 ms ごとに MPU6050 から加速度 3 軸 + 角速度 3 軸を読み、`data.imu` に書き込む |
| **書くフィールド** | `data.imu.acc[3]`, `data.imu.gyro[3]`, `data.imu.ready`, `data.imu.sampleAtMs` |
| **書かないフィールド** | `data.imu.accLpf[]`, `data.imu.accNorm`, `data.imu.dynNorm`（これらは `applyPattern()` の責務） |

このモジュールは **「生データを取ってくる」だけ**。LPF やノルム計算は `applyPattern.cpp` の
ロジック層の仕事。責務境界がきれい。

## ハードウェア

### MPU6050 / GY-521 概要

- センサーチップ: InvenSense MPU6050（後継 MPU6500 互換）
- 通信: I2C（最大 400 kHz）
- 機能: 3 軸加速度 + 3 軸ジャイロ（合計 6 軸）+ 温度
- スレーブアドレス: 0x68（AD0=GND）/ 0x69（AD0=VCC）
- 内部 ADC: 16 bit × 6 軸 + 16 bit 温度 = 計 14 B / サンプル

### 配線（XIAO ESP32-S3 Sense）

| MPU6050 | XIAO ESP32-S3 | 補足 |
|---|---|---|
| VCC | 3V3 | 3.3 V 駆動 |
| GND | GND | |
| SDA | D4 (GPIO5) | I2C データ |
| SCL | D5 (GPIO6) | I2C クロック |
| AD0 | GND | アドレスを 0x68 に固定 |

XIAO ESP32-S3 の I2C 既定ピンは D4 / D5。`Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN)` で
明示指定するため、配線変更時はここを変える。

## ImuConfig

```cpp
struct ImuConfig {
    uint8_t  address;            // 0x68 (AD0=GND) or 0x69
    uint32_t sampleIntervalMs;   // 5 ms = 200 Hz
    uint8_t  accelRangeG;        // 2 / 4 / 8 / 16
    uint16_t gyroRangeDps;       // 250 / 500 / 1000 / 2000
};
```

### 設定値（`ProjectConfig.h`）

```cpp
inline const ImuConfig IMU_CONFIG = {
    /*address=*/          0x68,
    /*sampleIntervalMs=*/ 5,
    /*accelRangeG=*/      4,
    /*gyroRangeDps=*/     2000,
};
```

### `sampleIntervalMs = 5` の根拠

200 Hz サンプルレート。これは：
- 拍検出に **十分な時間分解能**: 5 ms = 1 BPM 差で 4 ms ずれる解像度
- I2C 帯域に余裕: 14 B × 200 Hz = 2.8 kB/s（400 kHz の 1% 以下）
- CPU 負荷が無視できる: 1 ループ 5 ms 内に余裕で完結

MPU6050 自体は最大 1 kHz サンプル可能だが、それ以上はノイズが増えるだけで拍検出に寄与しない。

### `accelRangeG = 4` の根拠

加速度のフルスケールを ±4g に設定。

| フルスケール | LSB → g | 解像度 |
|---|---|---|
| ±2g | 1/16384 g | 細かい（重力 = 16384 LSB） |
| **±4g** | **1/8192 g** | **中程度（重力 = 8192 LSB）** |
| ±8g | 1/4096 g | 粗い |
| ±16g | 1/2048 g | とても粗い |

指揮の振りでピーク 2〜3g 程度になるので、±4g なら飽和せず、解像度も十分。
±2g だと飽和して頭打ちになり、振りのピークが取れない。

### `gyroRangeDps = 2000` の根拠

角速度のフルスケールを ±2000 dps（degrees per second）に設定。

指揮の振り下ろしで瞬間角速度が 1000 dps 程度になる。±1000 dps だと飽和する可能性があるので
余裕を持って ±2000。現状ジャイロは拍検出に使っていないが、将来「振りの種類分類」のために
取得だけ続けている。

## ImuData

```cpp
struct ImuData {
    bool     ready = false;          // この周期で読めたか
    float    acc[3]   = {0, 0, 0};   // 生加速度 (g, 重力込み)
    float    gyro[3]  = {0, 0, 0};   // 生角速度 (dps)
    float    accLpf[3] = {0, 0, 0};  // LPF 後の加速度 (g, 重力込み)
    float    accNorm = 0;            // LPF 後ノルム (g, 重力込み)
    float    dynAcc[3] = {0, 0, 0};  // 重力差し引いた近似ベクトル
    float    dynNorm = 0;            // 動加速度ノルム (= accNorm - gravityMag)
    uint32_t sampleAtMs = 0;
};
```

### 各フィールドの意味

| フィールド | 単位 | 書く側 | 読む側 |
|---|---|---|---|
| `ready` | - | ImuModule | applyPattern (毎周期判定) |
| `acc[3]` | g | ImuModule | applyPattern (LPF / キャリブ) |
| `gyro[3]` | dps | ImuModule | （現状未使用、将来拡張用） |
| `accLpf[3]` | g | applyPattern (LPF 結果) | applyPattern / dump |
| `accNorm` | g | applyPattern | applyPattern (dynNorm 計算) |
| `dynAcc[3]` | g | applyPattern | applyPattern (経路長積分) |
| `dynNorm` | g | applyPattern | applyPattern (拍検出) |
| `sampleAtMs` | ms | ImuModule | applyPattern (dt 計算) |

ImuModule が書くのは **太字の 4 つだけ**（`ready`, `acc`, `gyro`, `sampleAtMs`）。
他は `applyPattern` の責務。

## init() — MPU6050 の起動シーケンス

```cpp
bool ImuModule::init() {
    uint8_t who = 0;
    if (!readRegs(cfg_.address, REG_WHO_AM_I, &who, 1)) return false;
    if (who != 0x68 && who != 0x70 && who != 0x71 && who != 0x72) return false;

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
```

### 4 段階の初期化

#### 1. WHO_AM_I で接続確認

```cpp
if (!readRegs(cfg_.address, REG_WHO_AM_I, &who, 1)) return false;
if (who != 0x68 && who != 0x70 && who != 0x71 && who != 0x72) return false;
```

`REG_WHO_AM_I = 0x75` から 1 バイト読み、MPU6050 系のチップ ID であることを確認：

| ID | チップ |
|---|---|
| 0x68 | MPU6050（純正） |
| 0x70 | MPU6500（後継・互換） |
| 0x71 | MPU9250（9 軸版） |
| 0x72 | MPU9255 |

I2C 通信そのもの（バーストリードでバスを掴めるか）と、デバイスの正体（互換品種か）の
両方を 1 回でチェックできる。失敗時は false で `enabled = false` に倒れる。

#### 2. SLEEP 解除 + クロック源切替

```cpp
if (!writeReg(cfg_.address, REG_PWR_MGMT_1, 0x01)) return false;
delay(10);
```

`REG_PWR_MGMT_1 = 0x6B` に `0x01` を書く：
- bit 6 (`SLEEP`) = 0: スリープ解除（デフォルトは SLEEP=1 で停止している）
- bit 2-0 (`CLKSEL`) = 1: クロック源を **X 軸ジャイロ PLL** に切替（内部発振より精度が高い）

書き込み後 10 ms 待つのはチップマニュアル指定の安定化時間。

#### 3. 加速度フルスケール設定

```cpp
if (!writeReg(cfg_.address, REG_ACCEL_CONFIG, (uint8_t)(accelFs << 3))) return false;
```

`REG_ACCEL_CONFIG = 0x1C` の bit 4-3 が `AFS_SEL`：

| AFS_SEL | レンジ | LSB → g |
|---|---|---|
| 0 (= `accelFs=0 << 3 = 0x00`) | ±2g | 1/16384 |
| 1 (= `accelFs=1 << 3 = 0x08`) | ±4g | 1/8192 |
| 2 (= `accelFs=2 << 3 = 0x10`) | ±8g | 1/4096 |
| 3 (= `accelFs=3 << 3 = 0x18`) | ±16g | 1/2048 |

ビット位置 bit 4-3 にセットするため `<< 3` でシフト。

同時に `accelLsbToG_` を計算しておく（後で `readBurst()` で生値に掛け算する係数）。

#### 4. 角速度フルスケール設定

```cpp
if (!writeReg(cfg_.address, REG_GYRO_CONFIG, (uint8_t)(gyroFs << 3))) return false;
```

`REG_GYRO_CONFIG = 0x1B` の bit 4-3 が `FS_SEL`、同じパターン：

| FS_SEL | レンジ | LSB → dps |
|---|---|---|
| 0 | ±250 dps | 1/131.0 |
| 1 | ±500 dps | 1/65.5 |
| 2 | ±1000 dps | 1/32.8 |
| 3 | ±2000 dps | 1/16.4 |

### `Wire.begin()` を init() で呼ばない理由

`init()` は `Wire.begin()` を呼ばない。`main.cpp` の `setup()` 内で **1 回だけ** 呼ぶ：

```cpp
// main.cpp::setup()
Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
Wire.setClock(400000);
```

これは I2C バスが「1 つの物理リソースで複数モジュールが共有する」性質を持つから。
モジュール側で `Wire.begin()` を呼ぶと：
- 別モジュールが既に初期化していたバスを上書きする
- 別ピン指定で初期化されると一方のモジュールが死ぬ
- ピン指定なしで呼ぶとデフォルトピンに戻ってしまう

I2C / SPI / Serial のような **共有リソースの初期化は `main` の責任**。これは EMA の暗黙ルール。

## updateInput() — 5 ms 周期のサンプリング

```cpp
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
```

### 周期判定

```cpp
if (now - lastSampleMs_ < cfg_.sampleIntervalMs) {
    data.imu.ready = false;
    return;
}
```

`now - lastSampleMs_ >= 5 ms` でない限り、`ready = false` にして即 return。
**メインループ自体は ImuModule より速く回っているかもしれない**（指揮者ノードの loop は
周期制御なしで全力で回す）が、IMU は 5 ms ごとにしか読まない。

`ready = false` は「この周期は新しいサンプルがないよ」というシグナル。`applyPattern()` は
`if (data.imu.ready)` で分岐して LPF 計算をスキップする。

### `data.imu.ready` のセマンティクス

| 値 | 意味 |
|---|---|
| true | この `updateInput()` 呼び出しで新しいサンプルを取得した |
| false | サンプル間隔が来ていない or 読み取り失敗 |

`applyPattern()` はこのフラグを毎周期見て、true のときだけ加速度処理（LPF / ノルム / 拍検出）を
走らせる。**「IMU の周期と loop の周期は別」** という設計の鍵。

## readBurst() — 14 バイト連続読み出し

```cpp
bool ImuModule::readBurst(ImuData& imu) {
    uint8_t buf[14];
    if (!readRegs(cfg_.address, REG_ACCEL_XOUT_H, buf, 14)) {
        return false;
    }
    int16_t ax = (int16_t)((buf[0]  << 8) | buf[1]);
    int16_t ay = (int16_t)((buf[2]  << 8) | buf[3]);
    int16_t az = (int16_t)((buf[4]  << 8) | buf[5]);
    // buf[6..7] は温度 (未使用)
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
```

### バーストリードの仕組み

MPU6050 のレジスタは `0x3B` から連続して：

| アドレス | 内容 |
|---|---|
| 0x3B-0x3C | ACCEL_XOUT (16 bit) |
| 0x3D-0x3E | ACCEL_YOUT (16 bit) |
| 0x3F-0x40 | ACCEL_ZOUT (16 bit) |
| 0x41-0x42 | TEMP (16 bit) |
| 0x43-0x44 | GYRO_XOUT (16 bit) |
| 0x45-0x46 | GYRO_YOUT (16 bit) |
| 0x47-0x48 | GYRO_ZOUT (16 bit) |

**合計 14 B** がメモリ的に連続している。1 回の I2C トランザクションで 14 B 連続読みすれば、
6 軸全てを **同一サンプル時点の値** で取得できる。

軸ごとに別トランザクションで読むと：
- 加速度 X を読む時刻 ≠ 加速度 Y を読む時刻 となり、振り検出で位相がずれる
- I2C オーバーヘッド（毎回スタートコンディション + アドレス送信）が 6 倍に増える

バーストリード方式により、`readBurst()` 1 回で 6 軸スナップショットが得られる。

### ビッグエンディアン → ホストエンディアン変換

MPU6050 は **ビッグエンディアン** で値を返す（上位バイトが先）。

```cpp
int16_t ax = (int16_t)((buf[0] << 8) | buf[1]);
```

- `buf[0]`: 上位 8 bit
- `buf[1]`: 下位 8 bit
- `buf[0] << 8`: 上位を 16 bit のうち上半分にずらす
- `| buf[1]`: 下位 8 bit を OR で合体

`(int16_t)` キャストで符号付き解釈にすることで、負の加速度値（重力下向きの 1g など）が
正しく扱われる。

### 物理量への変換

```cpp
imu.acc[0]  = ax * accelLsbToG_;     // LSB → g
imu.gyro[0] = gx * gyroLsbToDps_;    // LSB → dps
```

`init()` で計算した係数を掛けるだけ。`accelLsbToG_ = 1/8192` なら、生 LSB 値 8192 が 1g に相当。

例：静止して水平に置いた状態だと `acc = (0, 0, 1.0)`（Z 軸下向きに 1g）。
完全停止時の `|acc| = sqrt(0² + 0² + 1²) = 1.0 g`。

### 温度を読み捨てる理由

`buf[6..7]` の温度は配列バッファに入るが、`ImuData` に書かない。
本プロジェクトでは IMU 温度補正をしていない（短時間使用のためドリフトが許容範囲）。
将来「温度補正を入れたい」拡張時のために 14 B 一括読みは維持してある。

## 内部レジスタアクセス（namespace 無名）

```cpp
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
```

### `writeReg()` — 単発書き込み

```
START → ADDR+W → REG → VAL → STOP
```

`Wire.endTransmission()` の戻り値が 0 なら成功。それ以外は I2C エラー（NACK、アービトレーション
失敗など）。

### `readRegs()` — 連続読み出し

```
[STAGE 1] START → ADDR+W → REG → repeated START
                                  ↑ STOP を打たない
[STAGE 2] ADDR+R → DATA × len → STOP
```

ポイントは `Wire.endTransmission(false)`：
- 引数 `false` は **STOP コンディションを打たない** という指示
- これにより「次に repeated START を打って読み取りに移行する」I2C パターンが実現できる
- STOP を打ってしまうと、デバイスは「読み取り開始アドレス」を覚えていないかもしれない

`Wire.requestFrom(addr, len)` で `len` バイトを連続要求し、内部バッファに溜める。
`Wire.read()` を `len` 回呼んで取り出す。

## 落とし穴

- **`Wire.begin()` をモジュール側で呼ぶと、別モジュールの初期化を上書きしうる**。
  `main.cpp` で 1 回だけ呼ぶこと。
- **`(int16_t) ((buf[0] << 8) | buf[1])` の `(int16_t)` キャストを忘れない**: 符号付きの
  負の値（重力下向きの加速度など）が正しく解釈されない。
- **I2C クロック 400 kHz 必須**: `Wire.setClock(400000)` を `main.cpp` で呼ぶ。デフォルト 100 kHz
  だと 14 B 読みが 1.4 ms 程度かかり、5 ms 周期に圧迫を与える。400 kHz なら 350 μs 程度。
- **GY-521 モジュールの 5V 入力許容範囲は要確認**: 純正品は 3.3V 駆動推奨。VCC を 5V に
  繋ぐと SDA / SCL のロジックレベルが 5V になり、ESP32 の 3.3V GPIO に過電圧をかける危険あり。
- **AD0 のフローティング厳禁**: GND か VCC に必ず引く。フローティングだとアドレスが不安定で
  通信ができない。
- **温度補正をしていない**: 長時間動作させると ±0.1g 程度のドリフトが乗る可能性。
  ハッカソンスケール（数十分）では問題ないが、本番運用するなら対策が要る。

## 関連ページ

- 加速度から拍を検出するロジック → [拍検出アルゴリズム](/deep-dive/beat-detection/)
- I2C / Wire の使い方 → [Arduino を書き換える](/guide/firmware/)
- ProjectConfig の全体 → [main フロー（指揮者）](/firmware/main-conductor/)
