# API — UDP プロトコル・SystemData・ProjectConfig

実装変更時の SSOT（Single Source of Truth）。プロトコル / 構造体 / 設定値を
変更した際は本ファイルと該当ヘッダを同期更新する。

## UDP パケット（`OrcProtocol`）

### 共通仕様

| 項目 | 値 |
|---|---|
| トランスポート | UDP マルチキャスト |
| グループアドレス | `239.0.0.1` |
| ポート | `5001` |
| パケット長 | **20 B 固定** |
| ヘッダ | 12 B（共通） |
| ペイロード | 8 B（型ごと） |

### 共通ヘッダ（12 B）

| オフセット | サイズ | フィールド | 内容 |
|---|---|---|---|
| 0 | 2 B | `magic` | `0x4F52`（'OR' = "ORchestra"） |
| 2 | 1 B | `version` | プロトコルバージョン（現行 `0x01`） |
| 3 | 1 B | `type` | `0x01=CTRL`, `0x02=BEAT`, `0x03=NOTE` |
| 4 | 4 B | `seq` | 送信側で単調増加するシーケンス番号（型ごとに独立） |
| 8 | 4 B | `timestampMs` | 送信側の `millis()`（指揮者時計） |

### CTRL（type=0x01）— 指揮者 → 楽器（20 Hz 連続配信）

| オフセット | サイズ | フィールド | 内容 |
|---|---|---|---|
| 12 | 2 B | `bpmFixed` | BPM × 256（固定小数。例: 100.0 BPM → 25600） |
| 14 | 1 B | `velocity` | 0–127（強弱。ストレッチ未実装時は固定 64） |
| 15 | 1 B | `state` | `0=Idle`, `1=Calibrating`, `2=Conducting`, `3=Fallback` |
| 16 | 4 B | `reserved` | 0 埋め（将来拡張） |

### BEAT（type=0x02）— 指揮者 → 楽器（拍ごと、2 連送）

| オフセット | サイズ | フィールド | 内容 |
|---|---|---|---|
| 12 | 2 B | `beatNo` | 拍番号（0 オリジン、巻き戻しなしの単調増加） |
| 14 | 2 B | `reserved` | 0 埋め |
| 16 | 4 B | `playAtMasterMs` | 楽器が発音する目標時刻（指揮者時計） |

### NOTE（type=0x03）— 楽器 → PC（USB シリアル経由）

| オフセット | サイズ | フィールド | 内容 |
|---|---|---|---|
| 12 | 1 B | `midiNote` | MIDI ノート番号（0–127、60=C4） |
| 13 | 1 B | `velocity` | 0–127 |
| 14 | 2 B | `durationMs` | 発音時間（ミリ秒） |
| 16 | 1 B | `partId` | ノード ID（`0x02`〜`0x05`） |
| 17 | 1 B | **`instrumentId`** | 音色 ID（`sound_lab/data/<id>.json` を参照）。test_v2 で追加（旧 `reserved[0]`） |
| 18 | 2 B | `reserved` | 0 埋め |

NOTE は UDP ではなく **USB シリアル（115200 bps）** で楽器ノード → PC に流す。
20 B のバイナリパケットをそのまま流すため、楽器ノードはデフォルト `SERIAL_DEBUG=0`。

## SystemData（指揮者ノード）

`firmware/test_v2/node_01/include/SystemData.h` の構造体。
モジュール間通信はこれを通じてのみ行う。

```cpp
struct SystemData {
    ImuData             imu;          // IMU 加速度/角速度/dynNorm/ready
    OrcNetData          orcNet;       // WiFi 接続状態・受信バッファ
    OrcSenderData       sender;       // CTRL/BEAT 送信統計（ctrlSeq, beatSeq）
    StatusLedData       led;          // 現在の点滅周期
    BeatLogicData       beat;         // 拍検出結果（event, beatNo, playAtMasterMs, pathLenM, gateState）
    TempoLogicData      tempo;        // bpm, nextBeatPredictedMs, velocity
    CalibrationData     calibration;  // 起動時 2 秒のキャリブ結果（gravityMag）
    ConductorStateData  conductor;    // Idle / Calibrating / Conducting / Fallback
};
```

楽器ノード（node_02〜04）の `SystemData` は構造が異なる
（`ScoreData` / `OrcReceiverData` / `NoteEmitterData` 等を持つ）。
詳細は各ノードの `include/SystemData.h` を直接参照。

## ProjectConfig（ノード固有設定）

ピン配置・閾値・WiFi 設定などはすべて各 node の `include/ProjectConfig.h` に集約。
モジュール本体（`src/*.cpp`）にハードコードしない。

### 指揮者ノード（node_01）の主な設定

```cpp
// I2C ピン（XIAO ESP32-S3 Sense）
constexpr uint8_t I2C_SDA_PIN = 5;   // D4
constexpr uint8_t I2C_SCL_PIN = 6;   // D5

// IMU 設定
inline const ImuConfig IMU_CONFIG = {
    /*address=*/          0x68,
    /*sampleIntervalMs=*/ 5,
    /*accelRangeG=*/      4,
    /*gyroRangeDps=*/     2000,
};

// WiFi / UDP
inline const OrcNetConfig ORC_NET_CONFIG = {
    /*mode=*/                WifiMode::SoftAp,
    /*ssid=*/                "OrchestraAP",
    /*pass=*/                "orchestra2026",
    /*multicastIp=*/         IPAddress(239, 0, 0, 1),
    /*udpPort=*/             5001,
    /*channel=*/             6,
    /*reconnectIntervalMs=*/ 2000,
};

// 送信周期
inline const OrcSenderConfig ORC_SENDER_CONFIG = {
    /*ctrlIntervalMs=*/  50,   // 20 Hz
    /*beatRedundancy=*/  2,    // BEAT を 2 連送
    /*beatLookaheadMs=*/ 50,   // playAtMasterMs = masterNow + 50 ms
};
```

### 拍検出の閾値（`logic_params` 名前空間）

| 定数 | 値 | 意味 |
|---|---|---|
| `LPF_ALPHA` | 0.10 | 加速度 LPF 係数 |
| `BEAT_DYN_THRESHOLD_G` | 1.20 g | Armed 突入トリガ（動加速度ノルム） |
| `BEAT_REFRACTORY_MS` | 350 | 不応期（≒ 170 BPM 上限） |
| `BEAT_RELEASE_G` | 0.20 g | 完全停止判定 |
| `BEAT_RELEASE_RATIO` | 0.40 | Armed ピーク比でのリリース判定 |
| `BEAT_ARMED_MIN_HOLD_MS` | 50 | Armed 最低保持時間 |
| `BEAT_RELEASE_HOLD_MS` | 40 | リリースのデバウンス |
| `BEAT_ARMED_TIMEOUT_MS` | 800 | Armed 強制終了 |
| `BEAT_FIRE_PATH_M` | 0.20 m | 経路長による早期発火閾値 |
| `BPM_EMA_ALPHA` | 0.30 | BPM 平滑化 |
| `BPM_MIN` / `BPM_MAX` | 40 / 240 | 受け付け範囲 |
| `CALIBRATION_MS` | 2000 | 起動時静止時間 |
| `IMU_TIMEOUT_MS` | 200 | IMU 通信タイムアウト |

詳細な経緯（なぜ 1.20 g なのか、なぜ 350 ms なのか）はヘッダ内のコメントに残してある。
変更時はそのコメントも更新する。

### 楽器ノードの主な設定

```cpp
// 輪唱の頭ずらし
constexpr uint16_t HEAD_REST_BEATS = 0;   // node_02=0, node_03=8, node_04=16

// 楽器番号（NOTE の instrumentId）
constexpr uint8_t INSTRUMENT_ID = 0;       // node_02=0, node_03=1, node_04=2

// パート ID（NOTE の partId）
constexpr uint8_t PART_ID = 0x02;          // node_02=0x02, node_03=0x03, node_04=0x04
```

## score_data フォーマット（楽譜データ）

`firmware/test_v2/node_0{2,3,4}/include/score_data.h` で定義され、
`src/score_data.cpp` に実体を持つ。**3 台同一内容**（＝輪唱だから）。

```cpp
struct ScoreEvent {
    uint16_t beatOffset;       // 曲頭からの拍オフセット
    uint8_t  midiNote;         // MIDI ノート番号（0=休符）
    uint16_t durationBeats;    // 拍数（1 拍 = 1.0、半拍 = 0.5 を 256 倍で保持する場合あり）
    uint8_t  velocity;         // 0–127
};

extern const ScoreEvent SCORE_DATA[];
extern const size_t     SCORE_LENGTH;
extern const uint16_t   SCORE_TOTAL_BEATS;
```

実装は配列リテラルで直書き。曲を変える際は 3 ノード分を同時に書き換える
（または共通ヘッダに切り出して `#include` させる）。

## 音色定義（`sound_lab/data/*.json`）

NOTE の `instrumentId` から PC 側で参照する。

```json
{
  "name": "金管 1",
  "harmonics": [
    { "ratio": 1.0, "amp": 1.0 },
    { "ratio": 2.0, "amp": 0.6 },
    { "ratio": 3.0, "amp": 0.3 }
  ],
  "adsr": { "attack": 0.02, "decay": 0.1, "sustain": 0.7, "release": 0.2 }
}
```

`pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde` が `data/<instrumentId>.json` を
ロードして加算合成する。追加楽器は `sound_lab/data/` に JSON を増やすだけで増設可能。
