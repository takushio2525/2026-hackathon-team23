# 10. 共通層 API 仕様

本章は `firmware/common/lib/` に配置する共通インターフェースの詳細仕様を定義する。
署名・返り値・呼び出し条件まで踏み込み、実装者（塩澤本人）が本章を見ればそのまま
ヘッダを書き始められる水準を目指す。

## 10.1 `IModule`

すべての機能単位が実装する抽象基底クラス。

```cpp
// firmware/common/lib/IModule/IModule.h
#pragma once

class IModule {
public:
    virtual ~IModule() = default;

    // 電源投入直後に 1 回だけ呼ばれる。H/W 初期化・状態クリアを行う。
    virtual void setup() = 0;

    // loop() から周期的に呼ばれる。1 ステップぶんの処理のみを行い、
    // ブロッキング呼び出し（delay など）は避ける。
    virtual void update() = 0;
};
```

| 呼び出し条件 | 契約 |
|---|---|
| `setup()` | ノード起動後の `main.cpp` で登録順に 1 度だけ呼ばれる。ここで `delay` を使ってよい（起動時のみ） |
| `update()` | 3 フェーズループの各フェーズ内で、そのフェーズに属するモジュールが登録順に呼ばれる。1 回の呼び出しは **1 ms 以内** を目標（MOP-6） |
| 例外 / エラー | `IModule` は例外を投げない。失敗は `SystemData` のフラグで伝搬する |

## 10.2 `ModuleTimer`

`delay()` を使わずに「X ms ごとに true を返す」周期判定を行うユーティリティ。

```cpp
// firmware/common/lib/ModuleTimer/ModuleTimer.h
#pragma once
#include <Arduino.h>

class ModuleTimer {
public:
    // period_ms ごとに ready() が true を返すようにする。
    void begin(uint32_t period_ms);

    // 前回 ready() が true を返した時点から period_ms 経過していたら true。
    // true を返した呼び出しで内部のマーカーを更新する（連続呼び出し安全）。
    bool ready();

    // 最後に ready() が true を返してからの経過時間（ms）
    uint32_t elapsed() const;

private:
    uint32_t period_ms_ = 0;
    uint32_t last_ms_   = 0;
};
```

用途: サンプリング周期（1 kHz）、CTRL 送信周期（20 Hz）、診断 LED の点滅など。

## 10.3 通信プロトコル詳細（OrcProtocol / OrcNet）

本節が本設計書で最も新規度が高い部分。指揮者 → 楽器 → PC の通信フォーマットを定義する。

### 10.3.1 ネットワーク構成

| 項目 | 設計 |
|---|---|
| WiFi モード | 全ノード **STA**。外部 AP（スマホテザリング or 専用ルータ）に接続 |
| IP 割り当て | DHCP（初期）。静的 IP が必要になれば `ProjectConfig` で切替え可能にする |
| ポート | 指揮者 → 楽器: **UDP/5001**、楽器 → PC: **UDP/5002** |
| 宛先 | 指揮者 → 楽器: ブロードキャスト（`255.255.255.255`）。楽器 → PC: PC の IP にユニキャスト |
| エンディアン | リトルエンディアン（UNO R4 の `ARM Cortex-M4` ネイティブ） |

### 10.3.2 共通ヘッダ

全パケットの先頭に付与する。12 バイト固定。

| オフセット | フィールド | 型 | 説明 |
|---|---|---|---|
| 0 | `magic` | `uint16_t` | 固定値 `0x4F52`（ASCII "OR"）プロトコル識別 |
| 2 | `version` | `uint8_t` | プロトコルバージョン（初期値 `0x01`） |
| 3 | `type` | `uint8_t` | メッセージ種別（`1=CTRL`, `2=BEAT`, `3=NOTE`） |
| 4 | `seq` | `uint32_t` | 送信側で単調増加。パケロス検出用 |
| 8 | `timestamp_ms` | `uint32_t` | 送信側 `millis()`。ノード間同期は取らないが、相対差分比較に使う |

### 10.3.3 CTRL パケット（type = 1）

指揮者が定期送信する **冪等な状態情報**。取りこぼしてもすぐ次が来る。

| オフセット | フィールド | 型 | 説明 |
|---|---|---|---|
| 12 | `bpm_q8` | `uint16_t` | 現在の BPM を 8 倍して整数化したもの（例: 120.5 BPM → 964） |
| 14 | `velocity` | `uint8_t` | 0〜127（MIDI 互換）。ストレッチ未実装時は固定 `64` |
| 15 | `state` | `uint8_t` | `0=Idle`, `1=Calibrating`, `2=Conducting`, `3=Fallback` |
| 16 | （予約） | `uint8_t[4]` | 将来拡張用にゼロ埋め |

送信周期: **20 Hz**（50 ms 周期）。

### 10.3.4 BEAT パケット（type = 2）

指揮者が **拍検出時に即時送信** するイベント。

| オフセット | フィールド | 型 | 説明 |
|---|---|---|---|
| 12 | `beat_no` | `uint16_t` | 曲頭からの拍番号（曲開始時に 0 リセット） |
| 14 | `phase_q8` | `uint16_t` | 拍内位相（0〜255 で 1 拍を表現）。通常は 0 |
| 16 | （予約） | `uint8_t[4]` | ゼロ埋め |

送信ポリシー:

- 通常は拍検出時に 1 発。確実性を上げたい場合は **同一 BEAT を 2〜3 発連送**（seq は全て同じで構わないが、受信側で冪等処理する）
- 楽器側は受信した `beat_no` が既知ならスキップ、未知なら楽譜ポインタを前進させる

### 10.3.5 NOTE パケット（type = 3）

楽器が PC（Processing）へ送る **発音依頼**。

| オフセット | フィールド | 型 | 説明 |
|---|---|---|---|
| 12 | `part_id` | `uint8_t` | 送信元パート（`0x02`〜`0x05` = node_02〜05） |
| 13 | `note_number` | `uint8_t` | MIDI ノート番号（0〜127、`60` = C4） |
| 14 | `velocity` | `uint8_t` | 0〜127 |
| 15 | `gate` | `uint8_t` | `1=NoteOn`, `0=NoteOff` |
| 16 | `duration_ms` | `uint16_t` | 発音予定長さ（参考値、Processing 側が使うかは任意） |
| 18 | （予約） | `uint8_t[2]` | ゼロ埋め |

NoteOn / NoteOff を `gate` で区別することで、Processing 側は MIDI 的な扱いができる。

### 10.3.6 `OrcNet` ラッパ API

WiFi 接続と UDP 送受信の定型処理を集約する。ノード側は低レベルソケット操作を
直接書かずに済む。

```cpp
// firmware/common/lib/OrcNet/OrcNet.h
#pragma once
#include <WiFiS3.h>
#include "OrcProtocol.h"

class OrcNet {
public:
    bool begin(const char* ssid, const char* pass, uint16_t listen_port);
    void update();  // WiFi 再接続・受信ポーリングなど

    // 送信（成功時 true）
    bool sendCtrl(const CtrlPacket& p);   // 宛先: ブロードキャスト:5001
    bool sendBeat(const BeatPacket& p);   // 宛先: ブロードキャスト:5001
    bool sendNote(IPAddress pc_ip, const NotePacket& p);  // 宛先: PC:5002

    // 受信（1 件取れた時 true、データは out に書き込む）
    bool tryRecvCtrl(CtrlPacket* out);
    bool tryRecvBeat(BeatPacket* out);
};
```

楽器側は `tryRecvCtrl` / `tryRecvBeat` を **入力フェーズ**でポーリングする。

### 10.3.7 パケロス・ジッタ対策

| 観点 | 対策 |
|---|---|
| CTRL 取りこぼし | 冪等かつ定期送信（20 Hz）なので設計上問題にならない |
| BEAT 取りこぼし | 同一 BEAT を **2〜3 連発** + 楽器側で `beat_no` 重複排除。さらに直前の BPM から予測時刻を内挿し、**一定時間 BEAT が来なかったら自走** |
| ジッタ | BEAT 受信時刻で楽譜ポインタを前進させる（内挿は最後の手段） |
| プロトコル不整合 | `magic` / `version` 不一致のパケットは破棄 + 診断 LED に反映 |
