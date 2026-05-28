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
| 12 | 2 B | `bpmQ8` | BPM × 8（分解能 0.125 BPM の整数表現。例: 100.0 BPM → 800、120.5 BPM → 964）。フィールド名に `Q8` を含むが、一般的な Q8 固定小数（×256）ではなく ×8 整数である点に注意 |
| 14 | 1 B | `velocity` | 0–127（強弱。ストレッチ未実装時は固定 64） |
| 15 | 1 B | `state` | `0=Idle`, `1=Calibrating`, `2=Conducting`, `3=Fallback` |
| 16 | 4 B | `reserved` | 0 埋め（将来拡張） |

### BEAT（type=0x02）— 指揮者 → 楽器（拍ごと、2 連送）

| オフセット | サイズ | フィールド | 内容 |
|---|---|---|---|
| 12 | 2 B | `beatNo` | 拍番号（**1 オリジン**、巻き戻しなしの単調増加）。指揮者は内部の `beatNo` をインクリメントしてから送信するため、最初に飛ぶ BEAT は `beatNo=1`。楽器側は `beatNo - 1 - headRestBeats` を楽譜 index として扱う |
| 14 | 2 B | `reserved` | 0 埋め |
| 16 | 4 B | `playAtMasterMs` | 楽器が発音する目標時刻（指揮者時計） |

### NOTE（type=0x03）— 楽器 → PC（USB シリアル経由）

| オフセット | サイズ | フィールド | 内容 |
|---|---|---|---|
| 12 | 1 B | `partId` | ノード ID。test_v2 は `0x02`〜`0x04`（楽器 3 台）、production 想定は `0x02`〜`0x06`（楽器 5 台＝金管 4 + ドラム）。輪唱のどの声部か |
| 13 | 1 B | `noteNumber` | MIDI ノート番号（0–127、60=C4） |
| 14 | 1 B | `velocity` | 0–127 |
| 15 | 1 B | `gate` | `1=NoteOn`、`0=NoteOff`（test_v2 は常に `1`、消音は PC が `durationMs` から自動） |
| 16 | 2 B | `durationMs` | 発音時間（ミリ秒） |
| 18 | 1 B | **`instrumentId`** | 音色 ID。PC 側 `pc_app/test_v2/orchestra_resynth/data/` 内の JSON をファイル名昇順で配列化し、その index として参照。test_v2 で追加（旧 `reserved` 領域） |
| 19 | 1 B | `reserved` | 0 埋め |

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

楽器ノード（node_02〜04）の `SystemData` は構造が異なる。実体（`firmware/test_v2/node_02/include/SystemData.h`）は次のフィールドを持つ:

```cpp
struct SystemData {
    OrcNetData          orcNet;       // WiFi 接続状態・受信バッファ
    StatusLedData       led;          // 現在の点滅周期
    ReceiverLogicData   receiver;     // CTRL/BEAT 受信ロジック内部状態
    NoteOutData         noteOut;      // 直近に出した NOTE（診断用）
    NoteSenderData      noteSender;   // NOTE 送信統計
    SyncLogicData       sync;         // 時刻同期: offsetMs（= master − local）、sampleCount、converged
    CtrlData            ctrl;         // 受信中の bpm / velocity / state / lastReceivedMs
    PerformerStateData  performer;    // Idle / WaitStart / Playing
    ScoreProgressData   score;        // currentEventIndex と細分音符予約スロット
};
```

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
    /*beatGapMs=*/           0,     // BEAT 連送間に挿む delay [ms]。0=旧挙動 (タイトループ連送)。2026-05-25 暫定追加
};

// 送信周期
inline const OrcSenderConfig ORC_SENDER_CONFIG = {
    /*ctrlIntervalMs=*/  50,   // 20 Hz
    /*beatRedundancy=*/  4,    // BEAT を 4 連送 (2026-05-25 に旧 2 -> 4。ESP32-S3 SoftAP の radio ロス対策・暫定値)
    /*beatLookaheadMs=*/ 50,   // playAtMasterMs = masterNow + 50 ms
};
```

> ⚠️ **2026-05-25 暫定設定**: `beatRedundancy=4` と `beatGapMs=0` は ESP32-S3 SoftAP の
> パケットロス切り分け中の値。実機計測で確定値（旧 2 連送に戻すか、4 連送＋beatGapMs=1〜5 ms
> で確定）を入れ、本節を書き直す予定。

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

ノード固有値は **すべて構造体リテラル経由** で `ProjectConfig.h` に集約されている。
`HEAD_REST_BEATS` / `INSTRUMENT_ID` / `PART_ID` といった単独の `UPPER_SNAKE_CASE` 定数は
**存在しない** ので、grep する場合はフィールド名（`partId`, `headRestBeats`, `instrumentId`）で
探す。`firmware/test_v2/node_02/include/ProjectConfig.h` の実体は次のとおり:

```cpp
// 輪唱受信ロジック（partId と頭ずらしを含む）
inline const OrcReceiverConfig ORC_RECEIVER_CONFIG = {
    /*partId=*/              0x02,    // node_02=0x02, node_03=0x03, node_04=0x04
    /*headRestBeats=*/       0,       // node_02=0, node_03=8, node_04=16
    /*clockSyncEmaAlpha=*/   0.10f,
    /*clockSyncMinSamples=*/ 5,
    /*loopIntervalMs=*/      5,
};

// NOTE 送信（instrumentId を含む）
inline const NoteSenderConfig NOTE_SENDER_CONFIG = {
    /*baudRate=*/     115200,
    /*partId=*/       0x02,           // partId は OrcReceiverConfig と同値を入れる
    /*instrumentId=*/ 0,              // node_02=0, node_03=1, node_04=2
};
```

`clockSyncEmaAlpha`（時刻同期 offset の EMA 平滑化係数）は **0.10**。指揮者側の
BPM EMA `BPM_EMA_ALPHA = 0.30` とは別の係数なので混同しないこと。

## score_data フォーマット（楽譜データ）

`firmware/test_v2/node_0{2,3,4}/include/score_data.h` で定義され、
`src/score_data.cpp` に実体を持つ。**3 台同一内容**（＝輪唱だから）。

```cpp
struct ScoreEvent {
    uint16_t beatAt;          // 参考値: 1 始まりの拍番号（ログ可読性のため。進行は index 駆動）
    uint8_t  noteNumber;      // MIDI ノート番号（0 = 休符）
    uint8_t  velocity;        // 0-127
    uint16_t durationQ8;      // 1/256 拍単位（256 = 1 拍）
    uint8_t  flags;           // bit0=NoteOn / bit2=休符（タイの続き）
    uint8_t  subNote;         // 細分音符の MIDI（0 = 予約なし）
    uint8_t  subVelocity;
    uint16_t subOffsetQ8;     // 拍頭からのオフセット（128 = 半拍 = 8 分音符）
    uint16_t subDurationQ8;
};

extern const ScoreEvent kScore[];
extern const size_t     kScoreLength;
```

**1 拍 = 1 ScoreEvent** で巡回参照。曲長は `kScoreLength` 自体（`SCORE_TOTAL_BEATS` などの
別変数は存在しない）。実装は配列リテラルで直書き。曲を変える際は 3 ノード分を同時に書き換える。

## 音色定義（`pc_app/test_v2/orchestra_resynth/data/*.json`）

NOTE の `instrumentId` から PC 側で参照する。Processing スケッチは
`pc_app/test_v2/orchestra_resynth/data/` を **ファイル名昇順** にソートしてロードし、
`instrumentId` を **その配列の index** として扱う。
ファイル名先頭の数字（`0_`, `1_`, …）は人間が並び順を把握しやすくするための慣例で、
ファイル名そのものは `<id>.json` 形式ではない。実体は `0_organ.json` / `1_flute.json` /
`2_bell.json` / `3_flute_tweaked.json` の 4 つ（2026-05 時点）。

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

`pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde` がディレクトリ内の `*.json` を
**ファイル名昇順** にソートして配列化し、`instrumentId` を index として参照する。
追加楽器は `pc_app/test_v2/orchestra_resynth/data/` に JSON を増やすだけで増設可能。
`sound_lab/` 配下は音色を分析・試作する実験場であり、完成した JSON を
`pc_app/test_v2/orchestra_resynth/data/` に **コピーして** 使う運用にする。
