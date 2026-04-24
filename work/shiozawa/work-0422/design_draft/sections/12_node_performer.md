# 12. 楽器ノード（node_02〜05）詳細設計

4 台の楽器ノードは **同一のコード**で動かし、差分は `ProjectConfig` と `score_data.h`
だけに閉じ込める。本章は 1 台分の設計を記し、ノード間差分を最後にまとめる（12.5）。

## 12.1 `SystemData` / `ProjectConfig`

```cpp
// firmware/node_02/src/SystemData.h
#pragma once
#include <stdint.h>

enum class PerformerState : uint8_t {
    Idle      = 0,
    WaitStart = 1,   // 演奏開始ビートを待機
    Playing   = 2,
    SelfRun   = 3,   // BEAT 断絶時の自走
};

struct SystemData {
    // F3.1 受信データ
    uint16_t last_beat_no;
    uint32_t last_beat_received_ms;
    float    current_bpm;          // CTRL から取得
    uint8_t  current_velocity;     // CTRL から取得
    uint8_t  current_state_src;    // CTRL.state（指揮者側の状態）

    // F3.3 楽譜進行
    uint32_t current_event_index;
    bool     note_on_pending;      // 次の出力フェーズで発音する
    bool     note_off_pending;

    // F3.5 パート情報
    uint8_t  part_id;              // 0x02〜0x05

    // F5 状態
    PerformerState state;
    bool wifi_connected;
    uint32_t last_ctrl_received_ms;
};
```

```cpp
// firmware/node_02/src/ProjectConfig.h
#pragma once
#include <stdint.h>

struct ProjectConfig {
    // WiFi
    const char* wifi_ssid  = "OrchestraAP";
    const char* wifi_pass  = "orchestra2026";
    uint16_t    listen_port = 5001;

    // PC 宛先（NOTE 送信）
    const char* pc_ip       = "192.168.4.2";
    uint16_t    pc_port     = 5002;

    // パート識別
    uint8_t  part_id        = 0x02;           // node_02 = パート A
    uint16_t start_beat_no  = 0;              // 輪唱の入りタイミング（例: 0 / 4 / 8 / 12）

    // 内挿フォールバック
    uint32_t beat_timeout_ms = 1500;          // これ以上 BEAT が来なければ SelfRun に入る
};
```

## 12.2 モジュール一覧

| フェーズ | モジュール | 責務 | 書込先（`SystemData`） |
|---|---|---|---|
| 入力 | `OrcNet`（共通層） | WiFi 維持 | `wifi_connected` |
| 入力 | `CtrlReceiver` | `tryRecvCtrl` / `tryRecvBeat` を呼んで取得 | `current_bpm`, `current_velocity`, `last_beat_no`, `last_beat_received_ms` 等 |
| ロジック | `ScorePlayer` | `last_beat_no` の前進を検出して `current_event_index` を進め、発音フラグを立てる | `current_event_index`, `note_on_pending`, `note_off_pending`, `state` |
| 出力 | `NoteSender` | `note_on_pending` / `note_off_pending` を見て NOTE を送信 | フラグクリア |
| 出力 | `StatusLed` | `state` / `wifi_connected` / BEAT 受信タイミングを LED で表示 | — |

## 12.3 楽譜データ形式

楽譜は **C 配列としてヘッダに埋め込む**（SD カード等に頼らない）。
[`docs/design/score_format.md`](../../../../../docs/design/score_format.md) の方針に基づく
具体化案。

```cpp
// firmware/node_02/src/score_data.h
#pragma once
#include <stdint.h>

struct ScoreEvent {
    uint16_t beat_at;          // この拍（曲頭からの beat_no）で発動
    uint8_t  note_number;      // MIDI ノート。0 なら休符
    uint8_t  velocity;          // 個別 velocity（CTRL で上書きするかは 12.4 参照）
    uint16_t duration_q8;       // 拍の 1/256 単位で長さ（256 = 1 拍）
    uint8_t  flags;             // bit0=NoteOn, bit1=NoteOff, bit2=Rest
};

extern const ScoreEvent kScore[];
extern const uint16_t   kScoreLength;

// 使用例（自動生成を想定）
// const ScoreEvent kScore[] = {
//     {0,  60, 80, 256, 0b01},  // 拍 0 で C4 を NoteOn、1 拍ぶん
//     {1,  62, 80, 256, 0b01},  // 拍 1 で D4 を NoteOn
//     ...
// };
// const uint16_t kScoreLength = sizeof(kScore) / sizeof(kScore[0]);
```

**補足**:

- NoteOff の管理は `duration_q8` ぶん経過時点で `ScorePlayer` が自動的に発火する。
  NoteOff を個別イベントとして楽譜に並べる必要は原則ない（flags bit1 は拡張用）。
- 休符は `note_number = 0` または `flags = 0b100`（どちらかに正規化して運用）。
- 楽譜の **具体的な内容**（曲・音符列）はチームで選定後に別途生成ツールで作る。
  本設計書ではデータ構造のみ規定する。

## 12.4 発音タイミング補正

楽譜は拍番号 (`beat_at`) で配置されている。実際の発音時刻は「最新 BEAT 受信時刻」を
基準に内挿する。

```text
if (state == Playing):
    while kScore[current_event_index].beat_at <= last_beat_no:
        // このイベントは発音すべき
        if kScore[current_event_index].flags & NoteOn:
            note_on_pending = true
            pending_note    = kScore[current_event_index]
            note_off_at_ms  = now + (60000 / bpm) * (duration_q8 / 256.0)
        current_event_index += 1

    if now >= note_off_at_ms && note_is_sounding:
        note_off_pending = true
```

**velocity の扱い**: 楽譜内の `velocity` と CTRL の `current_velocity` のどちらを使うか。

| 方式 | 挙動 |
|---|---|
| 楽譜 velocity を使う | 曲想（アクセント等）を固定 |
| CTRL velocity を使う | 指揮者のダイナミクスがそのまま乗る |
| 乗算（両者の積で正規化） | 曲想 × 指揮の両立（**推奨**） |

採用: **乗算方式**。`final_velocity = score.velocity * ctrl.velocity / 127`。
ストレッチ機能未実装時は CTRL velocity が固定 64 なので、曲想のみで決まる。

**内挿フォールバック（SelfRun）**:

```text
if now - last_beat_received_ms > beat_timeout_ms:
    state = SelfRun
    # 直前の BPM で自走する（仮想的な BEAT を内部で刻む）
    virtual_beat_no = last_beat_no + (now - last_beat_received_ms) * bpm / 60000
```

SelfRun 中に BEAT が再着信したら、`virtual_beat_no` を破棄して実 BEAT に乗り換える。

## 12.5 ノード間差分

4 台の楽器は `ProjectConfig` と `score_data.h` 以外は同一コード。

| ノード | `part_id` | `start_beat_no`（輪唱の入り） | `score_data.h` |
|---|---|---|---|
| node_02 | `0x02`（パート A） | 0 | パート A の楽譜 |
| node_03 | `0x03`（パート B） | 4 | パート B の楽譜（多くの輪唱曲では A と同じ旋律） |
| node_04 | `0x04`(パート C) | 8 | パート C |
| node_05 | `0x05`(パート D) | 12 or リズムなら 0 | パート D |

**輪唱の入り**は `start_beat_no` で遅延させる:

```text
if (last_beat_no < start_beat_no):
    state = WaitStart
    # 発音しない
else:
    state = Playing
    # 通常処理（ただし楽譜の beat_at は「開始ビートからの相対」で書く運用）
```

楽譜の `beat_at` は曲頭起点・開始ビート相対のどちらにするかで運用が変わる。
**開始ビート相対**（各パート楽譜は 0 始まり）のほうが楽譜データの使い回しが効くため
こちらを採用する。

**コード共通化の実装**:

- `firmware/node_02/lib/` の共通モジュール（`CtrlReceiver`, `ScorePlayer`, `NoteSender`）は、
  実装が固まった時点で `firmware/common/lib/` に昇格させても良い
- 当面は各ノード `lib/` にコピーを置き、差分が出た時点でリファクタリング（YAGNI）
