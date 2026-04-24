# 12. 楽器ノード（node_02〜05）詳細設計

4 台の楽器ノードは **同一のコード**で動かし、差分は `ProjectConfig` と `score_data.h`
だけに閉じ込める。本章は 1 台分の設計を記し、ノード間差分を最後にまとめる（§12.6）。

EMA 準拠の構造（モジュール → ハードウェア責務、`applyPattern()` → 判断ロジック）は
指揮者ノード（第 11 章）と同様。

> **EMA 正本**: [`../../architecture_reference/ARCHITECTURE.md`](../../architecture_reference/ARCHITECTURE.md)
> および [`../../architecture_reference/CLAUDE.md`](../../architecture_reference/CLAUDE.md)。

## 12.1 モジュール一覧と入出力分類

| モジュール | 分類 | 配列 | 責務 | 書込先 / 読出元 |
|---|---|---|---|---|
| `OrcNetModule`（共通層） | 入出力 | 両方 | WiFi 接続維持、UDP 受信ポーリング、UDP 送信キューフラッシュ | `data.orcNet` を読み書き |
| `OrcReceiverModule` | 入力専用 | `inputModules[]` | `data.orcNet.lastCtrl` / `lastBeat` を読み、自パートに必要な情報だけ整形して `data.receiver` に書く | `data.orcNet` 読み、`data.receiver` 書き |
| `NoteSenderModule` | 出力専用 | `outputModules[]` | `data.noteOut.pending*` を見て NOTE を `OrcNetModule.enqueueNote()` に投入 | `data.noteOut` 読み、フラグクリア |
| `StatusLedModule` | 出力専用 | `outputModules[]` | `data.performer.state` 等で LED パターンを表示 | `data.performer`, `data.orcNet` 読み |

**`applyPattern(SystemData&)` で実装する処理**:

| 処理 | 入力 | 出力 |
|---|---|---|
| 楽譜進行（`receiver.lastBeatNo` の前進検出 → `currentEventIndex` を進める） | `data.receiver.lastBeatNo` | `data.score.currentEventIndex`, `data.noteOut.pendingOn`, `data.noteOut.pendingNote` |
| NoteOff タイミング判定（`durationQ8` を経過したら NoteOff） | `data.noteOut.noteOffAtMs` | `data.noteOut.pendingOff` |
| 演奏状態遷移（Idle / WaitStart / Playing / SelfRun） | `data.receiver.lastBeatReceivedMs`, `data.receiver.lastBeatNo`, `data.score.startBeatNo` | `data.performer.state`, `data.score.virtualBeatNo` |
| init 失敗モジュールの再試行 | `module.enabled == false` | （`module.init()` で復帰） |

## 12.2 `SystemData`（EMA 準拠の集約）

```cpp
// firmware/node_02/include/SystemData.h
#pragma once
#include "OrcNetModule.h"
#include "OrcReceiverModule.h"
#include "NoteSenderModule.h"
#include "StatusLedModule.h"
#include "score_data.h"

enum class PerformerState : uint8_t {
    Idle      = 0,
    WaitStart = 1,
    Playing   = 2,
    SelfRun   = 3,
};

struct ScoreLogicData {
    uint32_t  currentEventIndex     = 0;
    uint16_t  virtualBeatNo         = 0;     // SelfRun 時の自走拍
    uint32_t  noteOffAtMs           = 0;
    bool      noteIsSounding        = false;
};

struct NoteOutData {
    bool        pendingOn           = false;
    bool        pendingOff          = false;
    ScoreEvent  pendingNote         = {};
    uint8_t     finalVelocity       = 0;     // applyPattern() が計算
};

struct PerformerStateData {
    PerformerState state = PerformerState::Idle;
};

struct SystemData {
    OrcNetData          orcNet;
    OrcReceiverData     receiver;
    NoteSenderData      noteSender;
    StatusLedData       led;
    ScoreLogicData      score;
    NoteOutData         noteOut;
    PerformerStateData  performer;
};
```

## 12.3 `ProjectConfig`（EMA 準拠の集約）

```cpp
// firmware/node_02/include/ProjectConfig.h
#pragma once
#include "SystemData.h"

const OrcNetConfig ORC_NET_CONFIG = {
    .ssid       = "OrchestraAP",
    .pass       = "orchestra2026",
    .listenPort = 5001,
};

const OrcReceiverConfig ORC_RECEIVER_CONFIG = {
    .partId         = 0x02,                      // node_02 = パート A
    .startBeatNo    = 0,                          // 輪唱の入り（パート毎に差分）
    .beatTimeoutMs  = 1500,                       // SelfRun 発動閾値
};

const NoteSenderConfig NOTE_SENDER_CONFIG = {
    .pcIp           = IPAddress(192, 168, 4, 2),  // 運用時差替え
    .pcPort         = 5002,
};

const StatusLedConfig STATUS_LED_CONFIG = {
    .pin              = LED_BUILTIN,
    .blinkIntervalMs  = 500,
};

struct LogicParams {
    // velocity 合成（楽譜 × CTRL）
    uint8_t  velocityCtrlFallback = 64;   // CTRL 未受信時の既定 velocity

    // 再 init リトライ
    uint32_t reinitRetryMs        = 5000;
};
constexpr LogicParams LOGIC_PARAMS = {};
```

## 12.4 楽譜データ形式

楽譜は **C 配列としてヘッダに埋め込む**（SD カード等に頼らない）。
[`docs/design/score_format.md`](../../../../../docs/design/score_format.md) の方針に基づく
具体化案。

```cpp
// firmware/node_02/include/score_data.h
#pragma once
#include <stdint.h>

struct ScoreEvent {
    uint16_t beatAt;            // この拍（開始ビートからの相対 beatNo）で発動
    uint8_t  noteNumber;        // MIDI ノート。0 なら休符
    uint8_t  velocity;          // 個別 velocity（CTRL と乗算合成）
    uint16_t durationQ8;        // 拍の 1/256 単位で長さ（256 = 1 拍）
    uint8_t  flags;             // bit0=NoteOn, bit1=NoteOff, bit2=Rest
};

extern const ScoreEvent kScore[];
extern const uint16_t   kScoreLength;
```

```cpp
// firmware/node_02/src/score_data.cpp（自動生成を想定）
#include "score_data.h"
const ScoreEvent kScore[] = {
    {0,  60, 80, 256, 0b01},   // 拍 0 で C4 を NoteOn、1 拍ぶん
    {1,  62, 80, 256, 0b01},
    // ...
};
const uint16_t kScoreLength = sizeof(kScore) / sizeof(kScore[0]);
```

**補足**:

- NoteOff の管理は `durationQ8` ぶん経過時点で `applyPattern()` が `pendingOff` を立てる。
  NoteOff を個別イベントとして楽譜に並べる必要は原則ない（flags bit1 は拡張用）
- 休符は `noteNumber = 0` または `flags = 0b100`（運用で正規化）
- 楽譜の **具体的な内容**（曲・音符列）はチームで選定後に別途生成ツールで作る。本書では
  データ構造のみ規定する

## 12.5 ロジック関数 `applyPattern()`（楽譜進行 + 状態遷移）

```cpp
// firmware/node_02/src/applyPattern.cpp
#include "SystemData.h"
#include "ProjectConfig.h"
#include "score_data.h"

void applyPattern(SystemData& data) {
    const uint32_t now = millis();

    // (1) 演奏状態遷移
    if (data.performer.state == PerformerState::Idle && data.orcNet.wifiConnected) {
        data.performer.state = PerformerState::WaitStart;
    }
    if (data.performer.state == PerformerState::WaitStart &&
        data.receiver.lastBeatNo >= ORC_RECEIVER_CONFIG.startBeatNo) {
        data.performer.state = PerformerState::Playing;
    }
    if (data.performer.state == PerformerState::Playing &&
        (now - data.receiver.lastBeatReceivedMs) > ORC_RECEIVER_CONFIG.beatTimeoutMs) {
        data.performer.state = PerformerState::SelfRun;
    }
    if (data.performer.state == PerformerState::SelfRun &&
        (now - data.receiver.lastBeatReceivedMs) <= 200) {
        // 実 BEAT 復帰時は SelfRun を抜けて Playing に戻す
        data.performer.state    = PerformerState::Playing;
        data.score.virtualBeatNo = 0;
    }

    // (2) SelfRun 中は仮想 BEAT を内部で進める
    uint16_t effectiveBeatNo = data.receiver.lastBeatNo;
    if (data.performer.state == PerformerState::SelfRun && data.receiver.currentBpm > 0.0f) {
        const uint32_t elapsed = now - data.receiver.lastBeatReceivedMs;
        data.score.virtualBeatNo =
            data.receiver.lastBeatNo +
            static_cast<uint16_t>(elapsed * data.receiver.currentBpm / 60000.0f);
        effectiveBeatNo = data.score.virtualBeatNo;
    }

    // (3) 楽譜進行（startBeatNo を 0 とした相対 beat）
    if (data.performer.state == PerformerState::Playing ||
        data.performer.state == PerformerState::SelfRun) {
        const uint16_t relBeat = effectiveBeatNo - ORC_RECEIVER_CONFIG.startBeatNo;

        while (data.score.currentEventIndex < kScoreLength &&
               kScore[data.score.currentEventIndex].beatAt <= relBeat) {
            const ScoreEvent& ev = kScore[data.score.currentEventIndex];
            if (ev.flags & 0x01) {  // NoteOn
                data.noteOut.pendingOn  = true;
                data.noteOut.pendingNote = ev;

                // velocity 合成（楽譜 × CTRL / 127）
                const uint8_t ctrlVel = data.receiver.currentVelocity > 0
                                          ? data.receiver.currentVelocity
                                          : LOGIC_PARAMS.velocityCtrlFallback;
                data.noteOut.finalVelocity =
                    static_cast<uint8_t>(static_cast<uint16_t>(ev.velocity) * ctrlVel / 127);

                // NoteOff 予定時刻
                const float bpm = data.receiver.currentBpm > 0.0f
                                    ? data.receiver.currentBpm
                                    : 120.0f;
                data.noteOut.noteOffAtMs =
                    now + static_cast<uint32_t>(60000.0f * ev.durationQ8 / 256.0f / bpm);
                data.score.noteIsSounding = true;
            }
            data.score.currentEventIndex += 1;
        }

        // (4) NoteOff 判定
        if (data.score.noteIsSounding && now >= data.noteOut.noteOffAtMs) {
            data.noteOut.pendingOff   = true;
            data.score.noteIsSounding = false;
        }
    }
}
```

**velocity の扱い**: 楽譜の `velocity` と CTRL の `currentVelocity` を **乗算合成**する
（`final = score.velocity * ctrl.velocity / 127`）。曲想（楽譜側のアクセント等）と
指揮のダイナミクスを両立する。ストレッチ機能未実装時は CTRL velocity が固定 64 のため
曲想のみで決まる。

## 12.6 ノード間差分

4 台の楽器は `ProjectConfig.h` と `score_data.h`（および `score_data.cpp`）以外は同一
コード。ハードウェア構成も同じ。

| ノード | `partId` | `startBeatNo`（輪唱の入り） | `score_data.h` |
|---|---|---|---|
| node_02 | `0x02`（パート A） | 0 | パート A の楽譜 |
| node_03 | `0x03`（パート B） | 4 | パート B の楽譜（輪唱曲では A と同じ旋律も多い） |
| node_04 | `0x04`（パート C） | 8 | パート C |
| node_05 | `0x05`（パート D） | 12 or リズムなら 0 | パート D |

楽譜の `beatAt` は **開始ビート相対**（各パート楽譜は 0 始まり）で記述する。これにより
楽譜データの使い回しが効く。

## 12.7 実行フロー（`main.cpp`、EMA 3 フェーズループ）

```cpp
// firmware/node_02/src/main.cpp
#include <Arduino.h>
#include "IModule.h"
#include "SystemData.h"
#include "ProjectConfig.h"
#include "OrcNetModule.h"
#include "OrcReceiverModule.h"
#include "NoteSenderModule.h"
#include "StatusLedModule.h"

SystemData systemData;

OrcNetModule       orcNet     (ORC_NET_CONFIG);
OrcReceiverModule  receiver   (ORC_RECEIVER_CONFIG);
NoteSenderModule   noteSender (NOTE_SENDER_CONFIG, &orcNet);
StatusLedModule    statusLed  (STATUS_LED_CONFIG);

IModule* inputModules[] = {
    &orcNet,
    &receiver,
};
constexpr int INPUT_COUNT = sizeof(inputModules) / sizeof(inputModules[0]);

IModule* outputModules[] = {
    &noteSender,
    &statusLed,
    &orcNet,
};
constexpr int OUTPUT_COUNT = sizeof(outputModules) / sizeof(outputModules[0]);

void applyPattern(SystemData& data);

static constexpr int MAX_RETRY = 3;

template <int N>
void initModules(IModule* (&modules)[N]) {
    for (int i = 0; i < N; i++) {
        bool ok = false;
        for (int r = 0; r < MAX_RETRY; r++) {
            if (modules[i]->init()) { ok = true; break; }
            delay(100);
        }
        if (!ok) modules[i]->enabled = false;
    }
}

void setup() {
    Serial.begin(115200);
    initModules(inputModules);
    noteSender.init();
    statusLed.init();
}

void loop() {
    for (int i = 0; i < INPUT_COUNT; i++) {
        if (inputModules[i]->enabled) inputModules[i]->updateInput(systemData);
    }
    applyPattern(systemData);
    for (int i = 0; i < OUTPUT_COUNT; i++) {
        if (outputModules[i]->enabled) outputModules[i]->updateOutput(systemData);
    }
}
```

## 12.8 共通化の運用方針

`OrcReceiverModule` / `NoteSenderModule` / `StatusLedModule` は当面 node_02〜05 の
各 `lib/` に **同一コードをコピー**する運用とする（実装初期は差分が出ないが、楽器個別の
カスタマイズ余地を残す）。

- 4 ノード分の差分要望が 6 週時点でも出ていなければ `firmware/common/lib/` に昇格させる
  （EMA「新規モジュール追加チェックリスト」に従って共通層に移動）
- 昇格時は各ノードの `lib_extra_dirs = ../common/lib` 経由で参照する
