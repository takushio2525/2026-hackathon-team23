---
title: main フロー（楽器）
description: Arduino UNO R4 WiFi 上の setup() / loop() / applyPattern() の処理フローと、5 ms 周期制御の実装
sidebar:
  label: 統合 — 楽器 main
  order: 11
---

:::note[この章で分かること]
- なぜ楽器ノードの `loop()` には明示的な周期制御がいるのか
- 演奏状態機械（Idle → WaitStart → Playing）の遷移条件
- `firedBeatNo` から `kScore` のインデックスを引き出す式
- 細分音符（8 分音符など）の予約発火スロットの仕組み
:::

## 実体

| ファイル | 行数 | 内容 |
|---|---|---|
| `firmware/test_v2/node_02/src/main.cpp` | 167 | `setup() / loop()` + 周期制御 + デバッグ出力 |
| `firmware/test_v2/node_02/src/applyPattern.cpp` | 171 | 演奏状態機械 + 楽譜進行 + 細分音符発火 + LED 反映 |

このページは 2 ファイルを行き来する。node_02 / node_03 / node_04 で内容はほぼ同一
（`ProjectConfig.h` の `partId / headRestBeats / instrumentId` だけ違う）。

## main.cpp の構造

### グローバルインスタンス

```cpp
namespace {

SystemData         gData;
OrcNetModule       gNet(ORC_NET_CONFIG);
OrcReceiverModule  gRecv(ORC_RECEIVER_CONFIG);
NoteSenderModule   gNote(NOTE_SENDER_CONFIG);
StatusLedModule    gLed(STATUS_LED_CONFIG);

IModule* gInputs[]  = { &gNet, &gRecv };
IModule* gOutputs[] = { &gNote, &gLed, &gNet };

constexpr size_t MAX_RETRY = 3;
uint32_t gLastLoopMs = 0;

}  // namespace
```

### 指揮者との対比

| 観点 | 指揮者 (node_01) | 楽器 (node_02-04) |
|---|---|---|
| ハード | XIAO ESP32-S3 Sense | Arduino UNO R4 WiFi |
| 入力モジュール | gNet + gImu | gNet + gRecv |
| 出力モジュール | gSender + gLed + gNet | gNote + gLed + gNet |
| ループ周期 | 制御なし（全力で回す） | **5 ms 周期で制御** |
| WiFi モード | SoftAP | Station |
| パケット出力 | UDP マルチキャスト | USB シリアル |

### `gInputs` / `gOutputs` の順序

```cpp
IModule* gInputs[]  = { &gNet, &gRecv };           // 入力: ネット受信 → 整形
IModule* gOutputs[] = { &gNote, &gLed, &gNet };    // 出力: NOTE 送信 → LED → (なし)
```

#### 入力フェーズ

1. **gNet**: UDP バッファから新着パケットを読み `data.orcNet.lastCtrl / lastBeat` に書く
2. **gRecv**: `data.orcNet` を解釈して `data.sync / ctrl / receiver` に整形

**この順序は重要**: gRecv が gNet の出力を入力として使うので、gNet が先に走らなければならない。

#### 出力フェーズ

1. **gNote**: `data.noteOut.pendingOn` を見て NotePacket を Serial に書く
2. **gLed**: `data.led.solidOn` を物理 LED に反映
3. **gNet**: 楽器ノードは UDP **送信** しない（受信のみ）。配列に入っているのは
   `OrcNetModule` の出力フェーズが「将来送信したくなったとき」のためのプレースホルダ

楽器側の `gNet.updateOutput()` は `hasPendingCtrl / hasPendingBeat` が立たないので
実質何もしない。配列から外しても良いが、共通モジュールの構造を保つために残してある。

## `setup()` — 起動シーケンス

```cpp
void setup() {
    DBG_BEGIN(115200);
    DBG_WAIT_HOST(1500);
    DBG_PRINTLN("");
    DBG_PRINTF("=== node_02 (round voice partId=0x%02X instr=%u headRest=%u) boot ===\n",
               (unsigned)ORC_RECEIVER_CONFIG.partId,
               (unsigned)NOTE_SENDER_CONFIG.instrumentId,
               (unsigned)ORC_RECEIVER_CONFIG.headRestBeats);

    initWithRetry(&gNet,  "OrcNetModule");
    initWithRetry(&gRecv, "OrcReceiverModule");
    initWithRetry(&gNote, "NoteSenderModule");
    initWithRetry(&gLed,  "StatusLedModule");

    DBG_PRINTLN("[N2 INIT] done");
}
```

### 起動時のログ出力

```cpp
DBG_PRINTF("=== node_02 (round voice partId=0x%02X instr=%u headRest=%u) boot ===\n",
           (unsigned)ORC_RECEIVER_CONFIG.partId,
           (unsigned)NOTE_SENDER_CONFIG.instrumentId,
           (unsigned)ORC_RECEIVER_CONFIG.headRestBeats);
```

ノードを 3 台繋ぐと **どれが node_02 / 03 / 04 か** が見分けにくい。起動時に
`partId / instrumentId / headRestBeats` を出力することで、シリアル出力を見れば
「これは声部 1 だ」と分かる。

### モジュール初期化の順序

1. **gNet** (WiFi Station): SoftAP に接続。最大 8 秒待機
2. **gRecv** (受信整形): ハード初期化なしで即 true
3. **gNote** (シリアル): `Serial.begin()` を呼ぶ（`SERIAL_DEBUG=0` のとき）
4. **gLed** (pinMode): I/O 設定

順序の意図は指揮者と同じ：通信モジュールを最初、I/O モジュールを最後。

### I2C を使わない

楽器ノードは IMU を持たないので `Wire.begin()` を呼ばない。指揮者と main.cpp の構造は
似ているが、I2C 関連の初期化は省略されている。

## `loop()` — 周期制御付き 3 フェーズループ

```cpp
void loop() {
    const uint32_t now = millis();
    if (now - gLastLoopMs < ORC_RECEIVER_CONFIG.loopIntervalMs) {
        return;  // ループ周期 5 ms を維持
    }
    gLastLoopMs = now;

    for (auto* m : gInputs) {
        if (m->enabled) m->updateInput(gData);
    }
    applyPattern(gData);
    for (auto* m : gOutputs) {
        if (m->enabled) m->updateOutput(gData);
    }
#if SERIAL_DEBUG
    dumpEdges(gData);
    dumpPeriodic(gData);
#endif
}
```

### なぜ周期制御が必要か

UNO R4 WiFi（Renesas RA4M1 / ARM Cortex-M4 / 48 MHz）は ESP32 と比べて遅い：

| ハード | クロック | 1 ループ典型時間 |
|---|---|---|
| XIAO ESP32-S3 | 240 MHz | ~0.5 ms |
| Arduino UNO R4 WiFi | 48 MHz | ~3 ms |

UNO R4 で全力ループを回すと：
- WiFi スタックの CPU 割り当てが足りなくなる（パケットロスが増える）
- シリアル CDC バッファが追いつかず、NotePacket が遅延する
- 電力消費が大きい

**5 ms 周期に制限** することで：
- 1 ループあたり ~3 ms を処理、~2 ms を WiFi / シリアルに譲る
- パケット受信が安定する
- CPU が休めて発熱が下がる

### 周期制御の実装

```cpp
const uint32_t now = millis();
if (now - gLastLoopMs < ORC_RECEIVER_CONFIG.loopIntervalMs) {
    return;
}
gLastLoopMs = now;
```

`5 ms` 経過していなければ即 return。Arduino の `loop()` は次のフレームでまた呼ばれるので、
return しても CPU 使用率は 100% ではない（裏で WiFi タスクが走る）。

**`delay(5 - elapsed)` を使わない理由**:
- `delay()` は CPU を完全に止めるので WiFi スタックも止まる
- `return` ならフレームワーク側のスケジューラに制御を渡せる

### 3 フェーズの中身

指揮者と完全に同じ構造：

```cpp
for (auto* m : gInputs)  if (m->enabled) m->updateInput(gData);
applyPattern(gData);
for (auto* m : gOutputs) if (m->enabled) m->updateOutput(gData);
```

EMA の 3 フェーズ厳守。**入力 → ロジック → 出力** の順番でだけ走る。

## `applyPattern.cpp` の構造

楽器ノードの判断ロジック。171 行を 6 つの責務に分解：

```
applyPattern(data)
├── 0. 細分音符予約の発火判定 (firePendingSub)
├── 2. 演奏状態遷移 (Idle → WaitStart → Playing)
├── 4. 発音判定 (playAtMasterMs と sync.offsetMs から発火時刻を決める)
├── 5. 楽譜進行 (firedBeatNo → kScore インデックス → fireScoreEvent)
├── 6. velocity 合成 (fireScoreEvent 内)
└── LED 反映 (updatePerformerLed)
```

`SystemData` を読みつつ書き換える。ハードウェアは触らない（純粋ロジック）。

### Phase 0 — 細分音符の予約発火

```cpp
void firePendingSub(SystemData& data, uint32_t now) {
    if (!data.score.pendingSub) return;
    if ((int32_t)(now - data.score.pendingSubAtMs) < 0) return;

    uint16_t v = ((uint16_t)data.score.pendingSubVelocity *
                  (uint16_t)data.ctrl.velocity) / 127;
    if (v > 127) v = 127;
    data.noteOut.noteNumber = data.score.pendingSubNote;
    data.noteOut.velocity   = (uint8_t)v;
    data.noteOut.durationMs = data.score.pendingSubDurationMs;
    data.noteOut.pendingOn  = true;
    data.score.pendingSub = false;
}
```

**「細分音符の予約」とは？**

`kScore[]` の各 `ScoreEvent` は 1 拍に対応するが、`subNote` フィールドで「拍の中盤に追加で
鳴らす音」を表現できる：

```cpp
struct ScoreEvent {
    uint16_t beatAt;
    uint8_t  noteNumber;   // 拍頭の音
    uint8_t  velocity;
    uint16_t durationQ8;
    uint8_t  flags;
    uint8_t  subNote;      // 細分音符（0 なら未使用）
    uint8_t  subVelocity;
    uint16_t subOffsetQ8;  // 拍頭からのオフセット（256 = 1 拍）
    uint16_t subDurationQ8;
};
```

例：8 分音符を含む拍

| `noteNumber=60` (C4) | `subNote=64` (E4) |
|---|---|
| 拍頭で鳴る | 拍頭から半拍後に鳴る |

8 分音符は `subOffsetQ8 = 128` (= 半拍) で表す。

**予約発火スロット**

BEAT が来た瞬間に拍頭の音は即発火する（`fireScoreEvent` 内）。subNote は **その後 X ms 後** に
発火するので、`data.score.pendingSub` に予約として積んでおき、`applyPattern` の頭で時刻判定する：

```cpp
if ((int32_t)(now - data.score.pendingSubAtMs) < 0) return;   // まだ時刻でない
// → 時刻が来たら NoteOn を吐く
```

`(int32_t)` キャストで符号付き比較。`uint32_t` のラップアラウンドを跨いでも正しく扱える。

### Phase 2 — 演奏状態機械

```cpp
switch (data.performer.state) {
    case PerformerState::Idle:
        if (data.orcNet.wifiConnected) {
            data.performer.state = PerformerState::WaitStart;
        }
        break;
    case PerformerState::WaitStart:
        if (data.receiver.hasFirstBeat) {
            data.performer.state = PerformerState::Playing;
        }
        break;
    case PerformerState::Playing:
        break;
}
```

シンプルな 3 状態：

```
[起動]
   ↓ (WiFi 接続完了)
Idle ─────────────► WaitStart ──── (最初の BEAT 受信) ──► Playing
                                                              │
                            (BEAT が長く来なくても Playing に留まる)
```

#### `WaitStart → Playing` の条件

```cpp
if (data.receiver.hasFirstBeat) {
    data.performer.state = PerformerState::Playing;
}
```

「最初の BEAT を受信した」 → Playing。`sync.converged` は条件に **入れていない**：

> Playing への遷移条件は「最初の BEAT を受信した」だけ（sync.converged 待ちで鳴らない症状を避ける）。

最初の数拍は時計同期がまだ収束していないが、それでも演奏は始める。同期は走りながら EMA で
改善する。詳しくは [OrcReceiverModule の解説](/firmware/orc-receiver/#clocksyncminsamples-が-playing-遷移に使われない理由)。

#### Playing からの抜け道がない

```cpp
case PerformerState::Playing:
    break;
```

Playing からの遷移は明示的にはない。WiFi が切れても、BEAT が長く来なくても Playing に留まる。
理由：
- 演奏が止まる体験は最悪
- BEAT が来ない間は単に何も鳴らないだけ（pending が valid にならない）
- BEAT が復活すれば自然に音が出る（拍番号駆動の自己補正）

### Phase 4 — 発音時刻判定

```cpp
bool     fired       = false;
uint16_t firedBeatNo = 0;
if (data.performer.state == PerformerState::Playing &&
    data.receiver.pending.valid) {
    const int32_t targetLocalMs =
        (int32_t)data.receiver.pending.playAtMasterMs - data.sync.offsetMs;
    const int32_t waitMs = targetLocalMs - (int32_t)now;
    if (waitMs <= 0) {
        fired       = true;
        firedBeatNo = data.receiver.pending.beatNo;
        data.receiver.pending.valid = false;
    }
}
```

#### `playAtMasterMs → targetLocalMs` の変換

```cpp
const int32_t targetLocalMs =
    (int32_t)data.receiver.pending.playAtMasterMs - data.sync.offsetMs;
```

- `playAtMasterMs`: 指揮者時計での発音目標時刻（例：12345 ms）
- `data.sync.offsetMs`: 「指揮者時計 − 自時計」(例：+50 ms)
- `targetLocalMs = 12345 - 50 = 12295`: **自時計** での発音目標時刻

これが時刻同期の核。`OrcReceiverModule` が EMA で追跡した `offsetMs` を使って、
**マスタ時刻指示を自時計に翻訳** する。

#### 待ち時間判定

```cpp
const int32_t waitMs = targetLocalMs - (int32_t)now;
if (waitMs <= 0) {
    fired = true;
    // ...
}
```

- `waitMs > 0`: まだ目標時刻に達していない → 次ループで再判定
- `waitMs <= 0`: 既に到達 or 受信遅延 → **即発火**

`waitMs > 0` のとき pending は `valid = true` のまま残す。次の 5 ms ループで再評価。

`waitMs <= 0` で **マイナスでも捨てない** のがポイント：
- 受信遅延で目標時刻を過ぎて届いた場合、即発火する
- 捨ててしまうと音が出ないので、遅れても鳴らす方を選ぶ

#### マスタ時刻同期の効果

各楽器が同じ `playAtMasterMs` に対してそれぞれの `sync.offsetMs` を引いて待つので、
**マスタ時刻基準で複数楽器の発音が自然に揃う**。

```
指揮者:                          時刻 T で BEAT 発射, playAtMasterMs = T + 50
node_02 (offsetMs=+5ms):        受信時刻 T+3, targetLocalMs = T+50-5 = T+45, 待ち時間 T+42 ms
node_03 (offsetMs=+50ms):       受信時刻 T+5, targetLocalMs = T+50-50 = T, 待ち時間 -5 ms (即発火)
node_04 (offsetMs=-20ms):       受信時刻 T+8, targetLocalMs = T+50+20 = T+70, 待ち時間 T+62 ms

→ 全楽器がマスタ時刻 T+50 ぴったりに合わせて発音 (実際は各自時計でその時刻に発音)
```

詳細は [時刻同期メカニズム](/deep-dive/time-sync/) を参照。

### Phase 5 — 楽譜進行

```cpp
if (fired && kScoreLength > 0) {
    const int32_t effective =
        (int32_t)firedBeatNo - 1 - (int32_t)ORC_RECEIVER_CONFIG.headRestBeats;
    if (effective >= 0) {
        const uint32_t scoreIndex = (uint32_t)effective % (uint32_t)kScoreLength;
        fireScoreEvent(data, kScore[scoreIndex], now);
        data.score.currentEventIndex = (uint16_t)scoreIndex;
    }
}
```

#### `firedBeatNo` から `scoreIndex` への変換

```
effective = firedBeatNo - 1 - headRestBeats
```

| ノード | firedBeatNo | headRestBeats | effective | scoreIndex |
|---|---|---|---|---|
| node_02 | 1 | 0 | 0 | 0 (kScore[0] 発火) |
| node_02 | 2 | 0 | 1 | 1 (kScore[1] 発火) |
| node_03 | 1 | 8 | -7 | (発火しない、頭の休符中) |
| node_03 | 9 | 8 | 0 | 0 (kScore[0] 発火、声部 2 が入る) |
| node_04 | 17 | 16 | 0 | 0 (kScore[0] 発火、声部 3 が入る) |

`-1` は 1 始まりの拍番号を 0 始まりに変換するため。

#### `effective < 0` の場合

`-7` などの負数 → まだ「頭の休符期間」なので何も鳴らさない。拍だけ消費する。

#### `% kScoreLength` の意味

```cpp
const uint32_t scoreIndex = (uint32_t)effective % (uint32_t)kScoreLength;
```

`kScoreLength = 24` なら、effective が 25 になったら scoreIndex = 1 に戻る。
つまり **曲が無限ループする**。指揮者がいつまで振り続けても演奏が続く設計。

### fireScoreEvent — 1 イベントを発音

```cpp
void fireScoreEvent(SystemData& data, const ScoreEvent& ev, uint32_t now) {
    const bool isRest = (ev.flags & 0x04) != 0 || ev.noteNumber == 0;
    if (!isRest) {
        // velocity 合成: score × ctrl / 127
        uint16_t v = ((uint16_t)ev.velocity * (uint16_t)data.ctrl.velocity) / 127;
        if (v > 127) v = 127;

        const uint16_t durMs = durationQ8ToMs(ev.durationQ8, data.ctrl.bpm);
        data.noteOut.noteNumber = ev.noteNumber;
        data.noteOut.velocity   = (uint8_t)v;
        data.noteOut.durationMs = durMs;
        data.noteOut.pendingOn  = true;
    }

    // 細分音符の予約
    if (ev.subNote != 0) {
        const float bpm = (data.ctrl.bpm >= 1.0f) ? data.ctrl.bpm
                                                  : logic_params::DEFAULT_BPM;
        const float beats = (float)ev.subOffsetQ8 / 256.0f;
        const uint32_t subDelayMs = (uint32_t)(beats * 60000.0f / bpm);
        data.score.pendingSub          = true;
        data.score.pendingSubAtMs      = now + subDelayMs;
        data.score.pendingSubNote      = ev.subNote;
        data.score.pendingSubVelocity  = ev.subVelocity;
        data.score.pendingSubDurationMs = durationQ8ToMs(ev.subDurationQ8, bpm);
    }
}
```

#### velocity 合成

```cpp
uint16_t v = ((uint16_t)ev.velocity * (uint16_t)data.ctrl.velocity) / 127;
```

`score velocity × ctrl velocity / 127`：
- 楽譜上の velocity（楽譜が指定する強弱）と
- 指揮者からの velocity（全体強弱）の積を 127 で割る
- 両方とも 127 なら最終 127、片方が 64 なら 32

`uint16_t` でオーバーフロー防止。

#### durationMs の計算

```cpp
const uint16_t durMs = durationQ8ToMs(ev.durationQ8, data.ctrl.bpm);
```

```cpp
uint16_t durationQ8ToMs(uint16_t durationQ8, float bpm) {
    const float beats = (float)durationQ8 / 256.0f;
    return (uint16_t)(beats * 60000.0f / (bpm < 1.0f ? logic_params::DEFAULT_BPM : bpm));
}
```

`durationQ8` は 256 = 1 拍 の Q8 固定小数。BPM から ms に変換：

- 1 拍の時間 = 60000 / BPM ms
- durationQ8 = 256 → 1 拍 = 500 ms (BPM 120)
- durationQ8 = 128 → 半拍 = 250 ms (BPM 120)

BPM が未受信（< 1.0）なら `DEFAULT_BPM = 100` を使う。

#### 細分音符の予約

```cpp
data.score.pendingSub          = true;
data.score.pendingSubAtMs      = now + subDelayMs;
```

`subOffsetQ8` から ms 遅延を計算して、`pendingSubAtMs` を「現在時刻 + 遅延」にセット。
次回以降の `applyPattern` の頭で `firePendingSub` が時刻判定して発火する。

### Phase 6 — LED 反映

```cpp
void updatePerformerLed(SystemData& data) {
    switch (data.performer.state) {
        case PerformerState::Idle:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_IDLE_MS;        // 1 Hz
            break;
        case PerformerState::WaitStart:
            data.led.solidOn = false;
            data.led.blinkIntervalMs = LED_WAIT_START_MS;  // 2 Hz
            break;
        case PerformerState::Playing:
            data.led.solidOn = true;                        // 点灯固定
            break;
    }
}
```

指揮者と同じパターン。`data.led` に書き、実際の `digitalWrite` は出力フェーズの
`StatusLedModule` が担当。

## 1 ループの全体タイムライン

```
T=0ms     loop entry
           gLastLoopMs から 5 ms 経過チェック → 経過していれば続行

T=0.1ms   [入力] gNet.updateInput()
                 UDP バッファ poll → lastCtrl / lastBeat 更新
                gRecv.updateInput()
                 lastCtrl / lastBeat → sync / ctrl / receiver に整形

T=0.5ms   [ロジック] applyPattern(gData)
                 ├─ Phase 0: 細分音符の予約発火 (時刻到達なら NoteOn)
                 ├─ Phase 2: 演奏状態遷移
                 ├─ Phase 4: BEAT 発火時刻判定 (playAtMasterMs - offsetMs)
                 ├─ Phase 5: 楽譜進行 (kScore[scoreIndex] を引いて fireScoreEvent)
                 │   └─ NoteOut.pendingOn = true (+ 細分音符予約)
                 └─ LED 状態反映

T=2ms     [出力] gNote.updateOutput()
                 pendingOn なら NotePacket (20 B) を Serial に書き flush
                gLed.updateOutput()
                 digitalWrite
                gNet.updateOutput()
                 楽器側は送信予約がないので何もしない

T=2.5ms   [デバッグ] dumpEdges / dumpPeriodic
                 状態変化と 200 ms 周期 dump

T=2.5-5ms 待ち (フレームワーク側に制御を返す)
                 ↓ Arduino フレームワークが内部タスク (WiFi / USB) を処理
T=5ms     次のループ
```

## デバッグ出力（`SERIAL_DEBUG=1`）

指揮者と同じく、`dumpEdges` と `dumpPeriodic` の 2 種類。

### `dumpEdges`

```cpp
if (d.performer.state != gPrevState) {
    DBG_PRINTF("[N2 EVT STATE] %s -> %s\n",
               perfStateName(gPrevState), perfStateName(d.performer.state));
    gPrevState = d.performer.state;
}
```

状態遷移、WiFi 変化、SYNC 収束、CTRL 受信、BEAT 受信などをエッジで通知。例：

```
[N2 EVT STATE] Idle -> WaitStart
[N2 EVT WIFI] connected=1
[N2 EVT CTRL] bpm=120.0 vel=64 st=2 seq=10 off=15 n=10
[N2 EVT SYNC_CONVERGED] off=15 n=10
[N2 EVT BEAT] no=1 playAt=12345 ahead=42 seq=1
[N2 EVT STATE] WaitStart -> Playing
```

### `dumpPeriodic`

```cpp
DBG_PRINTF(
    "[N2 t=%lu st=%s wifi=%d sync=%s(off=%ld n=%u) ctrl=(bpm=%5.1f v=%u s=%u) "
    "recv=(no=%u ago=%lu) pend=%d score=(idx=%u)]\n", ...);
```

200 ms ごとに 1 行のスナップショット。例：

```
[N2 t=12345 st=Playing wifi=1 sync=ok(off=15 n=42) ctrl=(bpm=120.0 v=64 s=2) recv=(no=24 ago=120) pend=0 score=(idx=23)]
```

### 重要な注意点: `SERIAL_DEBUG=1` で発音できない

楽器ノードでは **Serial が NotePacket バイナリ出力と人間可読ログを共有** している。
両方を同時に流すと Processing 側がヘッダ MAGIC を見失う。

そのため `NoteSenderModule.cpp` は：

```cpp
#if SERIAL_DEBUG
    DBG_PRINTF("[N2 NOTE_ON ] ...\n");   // 人間可読ログのみ
#else
    buildAndSend(...);                    // NotePacket バイナリ送信
#endif
```

と **コンパイル時切替** する。デバッグビルドでは音が出ない。本番は `SERIAL_DEBUG=0`。

## 落とし穴

- **`gLastLoopMs` の周期制御を消すと UNO R4 が WiFi 切断する**: CPU を WiFi スタックに譲る
  時間が確保できない。
- **`Wire.begin()` を呼ばない**: 楽器ノードは I2C を使わないので、コピペで残しておくと
  デバッグ時に混乱の元。
- **`gInputs` の順序 `gNet → gRecv` を入れ替えない**: gRecv は gNet の出力を入力にする
  ので、順序逆転すると 1 周期遅れる。
- **3 ノード（node_02/03/04）で `score_data.cpp` を完全同一に保つ**: 輪唱なので楽譜が
  違うと演奏が崩れる。
- **`SERIAL_DEBUG=1` でビルドすると音が出ない**: 本番は必ず `SERIAL_DEBUG=0`。
- **発音遅延が気になるときは `Serial.flush()` の有無を確認**: USB CDC のバッファリングで
  音がバースト化する事故が起きる。詳細は [NoteSenderModule の Serial.flush 解説](/firmware/note-sender/#serialflush-の重要性)。
- **`pending.valid` が立ったまま新しい BEAT が来ると上書きされる**: 1 個しか保持しない設計。
  実際は applyPattern が即座に判定するので滞留は稀。

## 関連ページ

- 入力モジュール → [OrcNetModule](/firmware/orc-net/) / [OrcReceiverModule](/firmware/orc-receiver/)
- 出力モジュール → [NoteSenderModule](/firmware/note-sender/) / [StatusLedModule](/firmware/status-led/)
- 指揮者ノード側 → [main フロー（指揮者）](/firmware/main-conductor/)
- 楽譜進行ロジックの数学的詳細 → [楽譜進行ロジック](/deep-dive/score-progression/)
- 時刻同期の数学 → [時刻同期メカニズム](/deep-dive/time-sync/)
- 拡張ガイド → [モジュール拡張ガイド](/deep-dive/module-extension/)
