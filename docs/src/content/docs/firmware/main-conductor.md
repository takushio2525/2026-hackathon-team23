---
title: main フロー（指揮者）
description: XIAO ESP32-S3 の setup() / loop() / applyPattern() の処理フローを 5 ms 周期で追いかける
sidebar:
  label: 統合 — 指揮者 main
  order: 10
---

:::note[この章で分かること]
- `setup()` で各モジュールがどんな順番で初期化されるか
- `loop()` 1 周回（5 ms）の中で起きる「入力 → ロジック → 出力 → デバッグ」の流れ
- `applyPattern()` がモジュール群と `SystemData` を橋渡しする様子
- なぜ `gInputs / gOutputs` の配列順がこの順になっているか
:::

## 実体

| ファイル | 行数 | 内容 |
|---|---|---|
| `firmware/test_v2/node_01/src/main.cpp` | 159 | `setup() / loop()` と起動シーケンス、デバッグ出力 |
| `firmware/test_v2/node_01/src/applyPattern.cpp` | 330 | 状態機械 + 拍検出 + テンポ EMA + LED 反映 |

このページは 2 つを行ったり来たりしながら、1 ループの中で何が起きているかを追う。

## main.cpp の構造

### グローバルインスタンス

```cpp
namespace {

SystemData       gData;
ImuModule        gImu(IMU_CONFIG);
OrcNetModule     gNet(ORC_NET_CONFIG);
OrcSenderModule  gSender(ORC_SENDER_CONFIG);
StatusLedModule  gLed(STATUS_LED_CONFIG);

IModule* gInputs[]  = { &gNet, &gImu };
IModule* gOutputs[] = { &gSender, &gLed, &gNet };

}  // namespace
```

### `gData` と 4 つのモジュール

| 変数 | 役割 |
|---|---|
| `gData` | ノード内の全モジュールが読み書きする共有データ |
| `gImu` | 入力: MPU6050 から加速度・角速度 |
| `gNet` | 入出力: WiFi + UDP マルチキャスト送受信 |
| `gSender` | 出力: CTRL / BEAT パケット組み立て |
| `gLed` | 出力: LED 点滅 |

それぞれが対応する `〜Config` を受け取って構築される（コンパイル時定数）。

### `gInputs` / `gOutputs` の **順序が重要**

```cpp
IModule* gInputs[]  = { &gNet, &gImu };           // 入力フェーズ: ネット → IMU
IModule* gOutputs[] = { &gSender, &gLed, &gNet }; // 出力フェーズ: 送信予約 → LED → 実送信
```

#### 入力フェーズの順序

1. **gNet** (受信): UDP バッファから新着パケットを処理し `data.orcNet` を更新
2. **gImu** (センサー): MPU6050 から 6 軸データを読んで `data.imu` を更新

順序は重要ではないが、ネットワーク受信は遅延の影響を受けるので先に処理して
「最新の WiFi 状態 + 最新の IMU」というセットで `applyPattern()` に渡す。

#### 出力フェーズの順序

1. **gSender** (パケット組み立て): `data.beat.event` や周期判定を見て `data.orcNet.pendingXxx` を更新
2. **gLed** (LED 反映): `data.led.solidOn / blinkIntervalMs` を物理 LED に反映
3. **gNet** (UDP 送信): `pendingXxx` の中身を実際に UDP マルチキャストで送信

**`gSender` → `gNet`** の順は決定的に重要：
- `gSender` が「予約」して、`gNet` が「実行」する
- 順序を逆にすると、1 周遅れて送信される（拍と音が 5 ms ずれる）

`gLed` は途中に挟んでいるが、LED は誰にも影響しないのでどこに置いても OK。

## `setup()` — 起動シーケンス

```cpp
void setup() {
    DBG_BEGIN(115200);
    DBG_WAIT_HOST(1500);
    DBG_PRINTLN("");
    DBG_PRINTLN("=== node_01 (conductor) boot ===");

    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    Wire.setClock(400000);

    initWithRetry(&gNet,    "OrcNetModule");
    initWithRetry(&gImu,    "ImuModule");
    initWithRetry(&gSender, "OrcSenderModule");
    initWithRetry(&gLed,    "StatusLedModule");

    DBG_PRINTLN("[N1 INIT] done");
}
```

### 起動ステップを追う

#### 1. シリアル初期化 (`SERIAL_DEBUG=1` 時のみ)

```cpp
DBG_BEGIN(115200);
DBG_WAIT_HOST(1500);
```

- `Serial.begin(115200)` でシリアルポートを開く
- USB CDC のホストが `pio device monitor` を開くのを最大 1.5 秒待つ

`SERIAL_DEBUG=0` のときはどちらも `(void)0` に消えて、即座に次のステップへ。

#### 2. I2C バスの初期化

```cpp
Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
Wire.setClock(400000);
```

- SDA=GPIO5, SCL=GPIO6 を指定して I2C を起動
- クロックを 400 kHz に設定（デフォルト 100 kHz では IMU の 14 B 読みが 1.4 ms かかる）

**ここで `Wire.begin()` を呼ぶのが重要**。`ImuModule::init()` 側で `Wire.begin()` を呼ぶ設計
にすると、複数モジュールが I2C を使うときに上書きされる事故が起きる。
[ImuModule の解説 — Wire.begin() を init() で呼ばない理由](/firmware/imu-module/#wirebegin-を-init-で呼ばない理由) を参照。

#### 3. モジュール初期化（4 つ順番に）

```cpp
initWithRetry(&gNet,    "OrcNetModule");
initWithRetry(&gImu,    "ImuModule");
initWithRetry(&gSender, "OrcSenderModule");
initWithRetry(&gLed,    "StatusLedModule");
```

順序は **OrcNet → IMU → Sender → LED**。意図：
1. **OrcNet を最初** に: WiFi SoftAP を起動して、後続モジュールの初期化中に AP が安定する
2. **IMU を 2 番目**: I2C 初期化済みなのでセンサーチップを叩ける
3. **Sender を 3 番目**: 純粋な状態初期化なので、ハードウェア依存なし
4. **LED を最後**: I/O は `pinMode` だけなのでいつでも OK

### `initWithRetry()` の中身

```cpp
void initWithRetry(IModule* m, const char* name) {
    bool ok = false;
    for (size_t i = 0; i < MAX_RETRY && !ok; ++i) {
        ok = m->init();
        if (!ok) delay(50);
    }
    m->enabled = ok;
    DBG_PRINTF("[N1 INIT] %s = %s\n", name, ok ? "OK" : "NG");
}
```

最大 3 回まで `init()` を試行：
- 成功すれば `enabled = true` でループに参加
- 3 回失敗したら `enabled = false` で **そのモジュールだけ停止**
- 他のモジュールは独立に動き続ける

`delay(50)` を挟むのは「短時間で再試行しても同じエラーが返るだけ」だから。50 ms 待つと
ハードウェアの一時的不調が解消することがある（特に WiFi の AP 起動直後）。

## `loop()` — 3 フェーズループ

```cpp
void loop() {
    for (auto* m : gInputs) {
        if (m->enabled) m->updateInput(gData);
    }
    applyPattern(gData);
    for (auto* m : gOutputs) {
        if (m->enabled) m->updateOutput(gData);
    }
#if SERIAL_DEBUG
    trackPeak(gData);
    dumpEdges(gData);
    dumpPeriodic(gData);
#endif
}
```

### **EMA の 3 フェーズ厳守**

| フェーズ | 呼ばれるもの | 役割 |
|---|---|---|
| 入力 | `m->updateInput(gData)` × 2 | ハードウェア → `gData` |
| ロジック | `applyPattern(gData)` | `gData` → `gData`（純粋な状態遷移） |
| 出力 | `m->updateOutput(gData)` × 3 | `gData` → ハードウェア |

ロジックフェーズは **ハードウェアに触らない**。`millis()` だけ参照する。
これにより：
- 入力フェーズの後にロジックが走るので、`applyPattern` は最新のセンサー値を見られる
- 出力フェーズの前にロジックが終わるので、出力モジュールは確定した `gData` を反映できる
- ロジックの単体テストが（理論上）可能（ハードウェア呼び出しがない）

### ループの周期制御がないことの意味

指揮者ノードの `loop()` には **周期制御の `delay()` がない**。これは：
- ESP32-S3 は十分速い（loop が 1 ms 程度で 1 周）
- 入力モジュール（IMU）が `sampleIntervalMs = 5` で内部周期制御している
- WiFi 受信は `parsePacket()` のポーリングが必要なので、loop が速く回るほど反応が良い
- 出力モジュールも「予約があれば処理、なければスキップ」の設計で空回りが軽い

つまり「loop は全力で回す、必要な周期制御は各モジュール内」の設計。CPU 100% 使用だが、
ESP32 は十分余裕がある（音処理は PC 側）。

楽器ノードの UNO R4 WiFi は CPU が遅いので、`main.cpp` で loop 周期 5 ms を強制する。
[main フロー（楽器）](/firmware/main-instrument/) を参照。

## `applyPattern.cpp` の構造

`applyPattern(gData)` は **指揮者ノードの判断ロジック全体** を 1 関数に集約する。
330 行あるが、責務は 4 つに分かれる：

```
applyPattern(data)
├── 1. IIR LPF + 動加速度ノルム計算 + 経路長積分
├── 4. 状態遷移 (Idle / Calibrating / Conducting / Fallback)
├── 2-3. 拍検出ステートマシン + テンポ EMA
└── 5. LED 状態反映 (updateLed)
```

### 静的変数群

```cpp
namespace {
float    sLpfAcc[3] = {0, 0, 0};
bool     sLpfInit = false;
uint32_t sLastBeatMs = 0;
float    sBpmEma = 100.0f;
bool     sBpmInit = false;

enum class BeatGate : uint8_t { Idle, Armed };
BeatGate sGate              = BeatGate::Idle;
float    sVel[3]            = {0, 0, 0};
float    sPathLen           = 0.0f;
float    sArmedPeakDyn      = 0.0f;
uint32_t sArmedAtMs         = 0;
uint32_t sLastImuMs         = 0;
bool     sBeatFiredInArmed  = false;
uint32_t sReleaseStartMs    = 0;
}
```

これらが拍検出の内部状態。`SystemData` に置かないのは：
- 他モジュールから参照されない（純粋に `applyPattern` のローカル）
- 同名衝突を避ける（モジュールがあるかどうかに依存しない）
- `static` で外部リンケージを断つので名前衝突防止

`SystemData` に置くべきものと、ロジック内部の静的変数で持つべきものを **区別する** のが
EMA の運用上のコツ。

### Phase 1 — IIR LPF と動加速度ノルム

```cpp
if (data.imu.ready) {
    if (!sLpfInit) {
        for (int i = 0; i < 3; ++i) sLpfAcc[i] = data.imu.acc[i];
        sLpfInit = true;
    } else {
        for (int i = 0; i < 3; ++i) {
            sLpfAcc[i] = (1.0f - LPF_ALPHA) * sLpfAcc[i] +
                         LPF_ALPHA * data.imu.acc[i];
        }
    }
    for (int i = 0; i < 3; ++i) data.imu.accLpf[i] = sLpfAcc[i];
    data.imu.accNorm = sqrtf(sLpfAcc[0]*sLpfAcc[0] + sLpfAcc[1]*sLpfAcc[1] + sLpfAcc[2]*sLpfAcc[2]);
    // 動加速度ノルム = LPF 後の加速度ノルム − キャリブ済み静止ノルム
    float dynN = data.imu.accNorm - data.calibration.gravityMag;
    if (dynN < 0.0f) dynN = 0.0f;
    data.imu.dynNorm = dynN;
}
```

ポイント：
- **`data.imu.ready` で分岐**: IMU が新サンプルを返したときのみ処理
- LPF 係数 α=0.10 で IIR ローパス（ジャーク的なノイズを除去）
- ノルム計算後、キャリブ済み静止ノルム（≒重力 1g）を **スカラー減算**
- 軸ごとに重力ベクトルを引かないので **姿勢非依存**

詳しい数学は [拍検出アルゴリズム](/deep-dive/beat-detection/) を参照。

### Phase 4 — 状態遷移

```cpp
switch (data.conductor.state) {
    case ConductorState::Idle:
        if (data.orcNet.wifiConnected) {
            data.conductor.state = ConductorState::Calibrating;
            data.calibration.startMs = now;
            data.calibration.sampleCount = 0;
            data.calibration.accumNorm = 0.0f;
            data.calibration.done = false;
        }
        break;

    case ConductorState::Calibrating: {
        // 2 秒間 加速度ノルムの平均を取って gravityMag を確定
        if (data.imu.ready) {
            const float n = sqrtf(data.imu.acc[0]*data.imu.acc[0] +
                                  data.imu.acc[1]*data.imu.acc[1] +
                                  data.imu.acc[2]*data.imu.acc[2]);
            data.calibration.accumNorm += n;
            data.calibration.sampleCount++;
        }
        if (now - data.calibration.startMs >= CALIBRATION_MS) {
            if (data.calibration.sampleCount > 0) {
                data.calibration.gravityMag =
                    data.calibration.accumNorm / (float)data.calibration.sampleCount;
            }
            data.calibration.done = true;
            data.conductor.state = ConductorState::Conducting;
        }
        break;
    }

    case ConductorState::Conducting: {
        const bool imuOk = data.imu.ready || (now - data.imu.sampleAtMs < IMU_TIMEOUT_MS);
        if (!imuOk || !data.orcNet.wifiConnected) {
            data.conductor.state = ConductorState::Fallback;
        }
        break;
    }

    case ConductorState::Fallback: {
        const bool imuOk = data.imu.ready || (now - data.imu.sampleAtMs < IMU_TIMEOUT_MS);
        if (imuOk && data.orcNet.wifiConnected) {
            data.conductor.state = ConductorState::Conducting;
        }
        break;
    }
}
```

```
[起動]
   ↓ (WiFi 接続完了)
Idle ─────────────► Calibrating ──── (2秒経過) ──► Conducting ◄─┐
                                                       │ ▲       │
                                          IMU タイムアウト or WiFi 切断
                                                       ▼ │       │
                                                  Fallback ──────┘
                                                  (復帰条件成立で戻る)
```

### Phase 2-3 — 拍検出 + テンポ推定

```cpp
if (data.conductor.state == ConductorState::Conducting && data.imu.ready) {
    switch (sGate) {
        case BeatGate::Idle:
            if (data.imu.dynNorm > BEAT_DYN_THRESHOLD_G) {
                sGate         = BeatGate::Armed;
                sArmedAtMs    = now;
                sArmedPeakDyn = data.imu.dynNorm;
                sVel[0] = sVel[1] = sVel[2] = 0.0f;
                sPathLen      = 0.0f;
                sLastImuMs    = 0;
                sBeatFiredInArmed = false;
            }
            break;

        case BeatGate::Armed: {
            const uint32_t armedFor = now - sArmedAtMs;
            const bool pathOk      = sPathLen >= BEAT_FIRE_PATH_M;
            const bool minHoldOk   = armedFor >= BEAT_ARMED_MIN_HOLD_MS;

            // ── 早期発火 ──
            if (!sBeatFiredInArmed && pathOk &&
                (now - sLastBeatMs) >= BEAT_REFRACTORY_MS) {
                data.beat.event      = true;
                data.beat.beatNo    += 1;
                data.beat.lastBeatMs = now;
                // テンポ EMA 更新
                if (sLastBeatMs != 0) {
                    const uint32_t intervalMs = now - sLastBeatMs;
                    const float instBpm = 60000.0f / (float)intervalMs;
                    sBpmEma = (1.0f - BPM_EMA_ALPHA) * sBpmEma + BPM_EMA_ALPHA * instBpm;
                    data.tempo.bpm = sBpmEma;
                }
                sLastBeatMs       = now;
                sBeatFiredInArmed = true;
            }

            // ── リリース判定 ──
            // (省略：完全停止 or ピーク × 40% 以下 が 40ms 連続したら Idle に戻る)
            break;
        }
    }
}
```

このロジックの核心は：

| ゲート | 条件 | 動作 |
|---|---|---|
| Idle | `dynNorm > 1.20g` | Armed に遷移 |
| Armed | `pathLen >= 0.20m` かつ `now - lastBeatMs >= 350ms` | 拍発火 + テンポ EMA |
| Armed | 完全停止 or ピーク × 40% 以下 が 40ms 連続 | Idle に戻る |
| Armed | `armedFor >= 800ms` | タイムアウトで Idle に戻る |

詳細は [拍検出アルゴリズム](/deep-dive/beat-detection/)。

### Phase 5 — LED 反映

```cpp
void updateLed(SystemData& data) {
    switch (data.conductor.state) {
        case ConductorState::Idle:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_IDLE_MS;        // 1 Hz
            break;
        case ConductorState::Calibrating:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_CALIBRATING_MS; // 2 Hz
            break;
        case ConductorState::Conducting:
            data.led.solidOn = true;                        // 点灯固定
            break;
        case ConductorState::Fallback:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_FALLBACK_MS;    // 5 Hz
            break;
    }
}
```

`applyPattern` の最後で呼ぶ。状態に応じた点滅周期を `data.led` に書く。
実際の `digitalWrite` は `StatusLedModule::updateOutput()` が行う（出力フェーズ）。

## 1 ループの全体タイムライン

5 ms 周期で「IMU が新サンプルを返す」周期に合わせて、典型的な 1 ループの中身：

```
T=0ms     [入力] gNet.updateInput()      UDP 受信ループ (通常 0 件)
                gImu.updateInput()       MPU6050 14 B バーストリード → data.imu に書く
                                                                          ↑ ready=true

T=0.5ms   [ロジック] applyPattern(gData)
                ├─ LPF + 動加速度計算
                ├─ 状態遷移チェック (Conducting なら何もしない)
                ├─ 拍検出 (Armed なら経路長更新 / 閾値超えで発火)
                └─ LED 状態反映

T=1ms     [出力] gSender.updateOutput()  data.beat.event なら BEAT 組み立て
                                          50ms 周期なら CTRL 組み立て
                gLed.updateOutput()      pin に digitalWrite
                gNet.updateOutput()      pendingCtrl/pendingBeat を UDP 送信

T=1.5ms   [デバッグ] trackPeak / dumpEdges / dumpPeriodic
                                          200ms ごとに 1 行 dump
                                          状態変化などは即時 dump

T=1.5〜5ms 待ち (次の IMU 周期まで)
                                          ループ自体は止まらず回り続ける
                                          ただし IMU は ready=false を返すので
                                          applyPattern は LPF 等をスキップ
T=5ms     次の IMU サンプル → 同じ流れを繰り返す
```

## デバッグ出力（`SERIAL_DEBUG=1`）

main.cpp は `SERIAL_DEBUG=1` のとき、3 種類のデバッグ出力を持つ：

### `trackPeak()` — IMU 5ms 周期のピーク追跡

```cpp
void trackPeak(const SystemData& d) {
    if (!d.imu.ready) return;
    const float nraw = sqrtf(d.imu.acc[0]*d.imu.acc[0] + d.imu.acc[1]*d.imu.acc[1] + d.imu.acc[2]*d.imu.acc[2]);
    if (nraw > gPeakNraw) gPeakNraw = nraw;
    if (d.imu.dynNorm > gPeakNdyn) gPeakNdyn = d.imu.dynNorm;
}
```

`dumpPeriodic` が 200 ms ごとにしか出ないので、その間の **最大値を蓄積** する。
振りのピーク値が dump タイミングと一致しなくても観測できる。

### `dumpEdges()` — エッジ通知

```cpp
if (d.conductor.state != gPrevState) {
    DBG_PRINTF("[N1 EVT STATE] %s -> %s\n", ...);
    gPrevState = d.conductor.state;
}
```

状態が変わった瞬間に 1 行出す：

- 状態遷移（Idle → Calibrating など）
- WiFi 接続状態の変化
- 拍検出 (`beatNo` が増えた瞬間)

エッジだけ出力するので、ログが長大にならない。

### `dumpPeriodic()` — 200ms 周期 dump

```cpp
DBG_PRINTF("[N1 t=%lu st=%s wifi=%d imu=%d acc=(...) n=%4.2f dyn=%4.2f peakRaw=%4.2f peakDyn=%4.2f gate=%c ...]\n", ...);
```

200 ms ごとに「現在の全状態を 1 行で」出す。例：

```
[N1 t=12345 st=Conducting wifi=1 imu=1 acc=( 0.01, 0.02, 1.00) n=1.00 dyn=0.00 peakRaw=2.34 peakDyn=1.34 gate=I armedPk=0.00 path=0.000 bpm=120.0 beatNo=42 ctrlSeq=246 beatSeq=42]
```

これを見れば、いつでも「指揮者の状態スナップショット」が取れる。

## ループ全体のシーケンス図

```
┌──────────────┐  loop entry
│              │
│  入力フェーズ │  ┌── gNet (UDP 受信) ──┐
│              │  │   data.orcNet 更新   │
│              │  └─────────────────────┘
│              │  ┌── gImu (I2C 読み) ──┐
│              │  │   data.imu 更新     │
│              │  └─────────────────────┘
├──────────────┤
│  ロジック    │  applyPattern(gData):
│  フェーズ    │     ├─ LPF + dynNorm 計算
│              │     ├─ 状態遷移
│              │     ├─ 拍検出 (event=true)
│              │     ├─ BPM EMA
│              │     └─ LED 状態反映
├──────────────┤
│  出力フェーズ │  ┌── gSender ──────────┐
│              │  │ event → BEAT pkt    │
│              │  │ 50ms → CTRL pkt     │
│              │  └─────────────────────┘
│              │  ┌── gLed ──────────────┐
│              │  │   digitalWrite       │
│              │  └─────────────────────┘
│              │  ┌── gNet (UDP 送信) ──┐
│              │  │   pending を flush   │
│              │  └─────────────────────┘
├──────────────┤
│  デバッグ    │  trackPeak / dumpEdges / dumpPeriodic
└──────────────┘
   loop exit → 即 loop() が再呼び出し (continuous)
```

## なぜこの構造が良いのか

EMA の 3 フェーズ厳守には次の利点がある：

1. **責務境界が明確**: モジュール 1 つを見れば、入力か出力か（or 両方）が一目で分かる
2. **テストしやすい**: 入力モジュールをモックして `SystemData` を作れば、`applyPattern()` を
   単体で動かせる
3. **拡張しやすい**: 新しい入力源（例：マイク）を足したいなら、`IModule` を継承して
   `updateInput()` を実装し `gInputs[]` に追加するだけ
4. **デバッグしやすい**: `dumpPeriodic` で `SystemData` のスナップショットを取れば、
   どの瞬間も完全に状態が分かる

## 落とし穴

- **`Wire.begin()` を `main` で呼ぶのを忘れない**: モジュール側で呼ばない設計なので、
  忘れると IMU 初期化が失敗する。
- **`gInputs / gOutputs` の順序は変えない**: 特に `gOutputs` の Sender → Net の順は
  決定的に重要。逆にすると拍と音が 1 周期ずれる。
- **`gNet` を入出力両方に入れる**: 入力では受信、出力では送信。1 つの配列だけに入れると
  受信か送信どちらかが死ぬ。
- **`applyPattern.cpp` の静的変数を `SystemData` に移動しない**: ロジック内部の状態は
  そのモジュールに閉じておくべき。
- **`SERIAL_DEBUG=1` でビルドすると CTRL/BEAT 送信は通常通り動く**: 指揮者ノードは
  デバッグログとパケット送信が衝突しないため、`SERIAL_DEBUG` の値で挙動が変わらない
  （楽器ノードは衝突するので別扱い）。

## 関連ページ

- 入力モジュール → [ImuModule](/firmware/imu-module/) / [OrcNetModule](/firmware/orc-net/)
- 出力モジュール → [OrcSenderModule](/firmware/orc-sender/) / [StatusLedModule](/firmware/status-led/)
- 楽器ノード側 → [main フロー（楽器）](/firmware/main-instrument/)
- 拍検出アルゴリズム → [拍検出アルゴリズム](/deep-dive/beat-detection/)
- 拡張ガイド → [モジュール拡張ガイド](/deep-dive/module-extension/)
