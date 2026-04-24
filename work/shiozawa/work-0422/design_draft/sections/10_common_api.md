# 10. 共通層 API 仕様

本章は `firmware/common/lib/` に配置する共通インターフェースの詳細仕様を定義する。
署名・返り値・呼び出し条件まで踏み込み、実装者（塩澤本人）が本章を見ればそのまま
ヘッダを書き始められる水準を目指す。

> **EMA 正本との対応**:
> - `IModule` / `ModuleTimer` は EMA リファレンスの `lib/ModuleCore/` をそのまま流用する
>   （[`../../architecture_reference/ARCHITECTURE.md`](../../architecture_reference/ARCHITECTURE.md)
>   「IModule インターフェース」「モジュールの構造（.h/.cpp 分離）」を参照）。
> - 本ハッカソン固有のモジュール（`OrcProtocol` / `OrcNetModule`）は EMA の通信バス
>   パターン・命名規則に準拠して新規実装する。

## 10.1 `IModule`（EMA コア層・流用）

EMA リファレンスから流用する。本プロジェクトで再定義はしない。

```cpp
// firmware/common/lib/ModuleCore/IModule.h
#pragma once

struct SystemData;  // 前方宣言のみ（プロジェクト依存を避ける）

class IModule {
public:
    bool enabled = true;

    virtual bool init() = 0;                        // 初期化（純粋仮想）
    virtual void updateInput(SystemData& data) {}   // 入力フェーズ（デフォルト空実装）
    virtual void updateOutput(SystemData& data) {}  // 出力フェーズ（デフォルト空実装）
    virtual void deinit() {}                        // リソース解放（デフォルト空実装）
    virtual ~IModule() {}
};
```

| メソッド | 呼び出し条件 | 契約 |
|---|---|---|
| `init()` | `setup()` 内で各モジュールに対し 1 回だけ呼ばれる | H/W 初期化を行い、成功なら `true`、失敗なら `false`。失敗時は `setup()` 側で MAX_RETRY 回リトライ → それでも失敗なら `enabled = false` |
| `updateInput(SystemData&)` | 入力フェーズで `inputModules[]` の登録順に呼ばれる | センサ / 受信データを `SystemData` に書き込む。1 周期 ≤ 1 ms 目標（MOP-6） |
| `updateOutput(SystemData&)` | 出力フェーズで `outputModules[]` の登録順に呼ばれる | `SystemData` を読み出して H/W 制御 / 送信を行う |
| `deinit()` | スリープ突入前等、必要時のみ手動で呼ぶ | リソース解放。本プロジェクトでは基本的に未使用 |
| 例外 / エラー | — | `IModule` は例外を投げない。失敗は `SystemData` のサブ構造体のフラグ（例: `data.imu.isValid = false`）で伝搬する |

**enabled フラグ**: モジュールの有効/無効をフェーズループ側がチェックする
（`if (m->enabled) m->updateInput(...)`）。`init()` 失敗時は `enabled = false` とし、
ロジックフェーズ内で定期的に再 `init()` を試みる（§11 で詳述）。

## 10.2 `ModuleTimer`（EMA コア層・流用）

`millis()` ベースのノンブロッキング周期判定。EMA リファレンスから流用。

```cpp
// firmware/common/lib/ModuleCore/ModuleTimer.h
#pragma once
#include <Arduino.h>

class ModuleTimer {
public:
    void setTime();                       // 現在時刻を起点としてセット
    uint32_t getNowTime() const;          // setTime() からの経過時間（ms）
private:
    uint32_t _startMs = 0;
};
```

**典型的な使い方**:

```cpp
// モジュール内（updateInput / updateOutput）
if (_timer.getNowTime() < _config.intervalMs) return;
_timer.setTime();
// この先が実際の処理
```

用途: サンプリング周期（例: 200 Hz → `intervalMs = 5`）、CTRL 送信周期（20 Hz → 50 ms）、
診断 LED の点滅、拍検出の不応期、SelfRun タイムアウト判定 等。

> EMA 仕様書（`../../architecture_reference/pdf/03_設計仕様書.pdf`）の `ModuleTimer` API に
> 完全準拠する。本書で API を再定義しない。

## 10.3 通信プロトコル詳細（`OrcProtocol` / `OrcNetModule`）

本節が本設計書で最も新規度が高い部分。指揮者 → 楽器 → PC の通信フォーマットを定義する。
`OrcProtocol` はパケット定義とシリアライズ、`OrcNetModule` は EMA の `IModule` を実装した
WiFi + UDP ラッパ。

### 10.3.1 ネットワーク構成

| 項目 | 設計 |
|---|---|
| WiFi モード | 全ノード **STA**。外部 AP（スマホテザリング or 専用ルータ）に接続 |
| IP 割り当て | DHCP（初期）。静的 IP が必要になれば `OrcNetConfig` で切替え可能にする |
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

### 10.3.6 `OrcNetModule`（EMA 準拠の入出力モジュール）

WiFi 接続維持と UDP 送受信ポーリングを集約する **`IModule` 実装**。
入出力両方を持つため、`inputModules[]` と `outputModules[]` の **両方** に登録する
（[`../../architecture_reference/ARCHITECTURE.md`](../../architecture_reference/ARCHITECTURE.md)
「モジュールの入出力分類」「3 フェーズ実行モデル」のルールに準拠）。

```cpp
// firmware/common/lib/OrcNetModule/OrcNetModule.h
#pragma once
#include <Arduino.h>
#include "IModule.h"
#include "ModuleTimer.h"
#include "OrcProtocol.h"

struct OrcNetConfig {
    const char* ssid;
    const char* pass;
    uint16_t    listenPort;        // 受信用 UDP ポート（5001 等）
    uint32_t    reconnectIntervalMs = 2000;
};

struct OrcNetData {
    bool      wifiConnected   = false;
    uint8_t   sendQueueDepth  = 0;
    // 受信バッファ（OrcReceiverModule が読み出すか、OrcNet 自身がイベントを SystemData に展開）
    bool      hasNewCtrl      = false;
    bool      hasNewBeat      = false;
    CtrlPacket lastCtrl       = {};
    BeatPacket lastBeat       = {};
};

class OrcNetModule : public IModule {
public:
    explicit OrcNetModule(const OrcNetConfig& config);

    bool init() override;                            // WiFi.begin() + Udp.begin()
    void updateInput(SystemData& data) override;     // WiFi 状態更新 + UDP 受信ポーリング
    void updateOutput(SystemData& data) override;    // 送信キューフラッシュ
    void deinit() override;                          // WiFi 切断（基本未使用）

    // applyPattern() / 他モジュールから呼ばれる送信 API
    bool enqueueCtrl(const CtrlPacket& p);                 // 宛先: ブロードキャスト:5001
    bool enqueueBeat(const BeatPacket& p);                 // 宛先: ブロードキャスト:5001
    bool enqueueNote(IPAddress pcIp, const NotePacket& p); // 宛先: PC:5002

private:
    OrcNetConfig _config;
    ModuleTimer  _reconnectTimer;
    // 内部送信キュー（数件分のリングバッファ）
};
```

**ルール**:

- `enqueueXxx()` はロジックフェーズで呼び、実際の送信は `updateOutput()` 内でまとめて
  行う（EMA の「Config 変更や副作用はフェーズ内で」原則を踏襲）
- `tryRecv*` のような外向き API は持たず、受信結果は `OrcNetData` 内のフラグ + 直近パケット
  バッファで `SystemData` 経由で渡す（モジュール間直接呼び禁止のため）
- 楽器側でフィルタが必要なら、入力モジュールとして別途 `OrcReceiverModule` を作り、
  `OrcNetModule` の `data.orcNet.lastBeat` を読んで `data.receiver.*` に整形して渡す

### 10.3.7 `ProjectConfig` への登録例

```cpp
// firmware/node_01/include/ProjectConfig.h（抜粋）
const OrcNetConfig ORC_NET_CONFIG = {
    .ssid       = "OrchestraAP",       // 運用時差替え
    .pass       = "orchestra2026",     // 運用時差替え
    .listenPort = 5001,
};
```

### 10.3.8 パケロス・ジッタ対策

| 観点 | 対策 |
|---|---|
| CTRL 取りこぼし | 冪等かつ定期送信（20 Hz）なので設計上問題にならない |
| BEAT 取りこぼし | 同一 BEAT を **2〜3 連発** + 楽器側で `beat_no` 重複排除。さらに直前の BPM から予測時刻を内挿し、**一定時間 BEAT が来なかったら自走** |
| ジッタ | BEAT 受信時刻で楽譜ポインタを前進させる（内挿は最後の手段） |
| プロトコル不整合 | `magic` / `version` 不一致のパケットは破棄 + 診断 LED に反映（`StatusLedModule` が `data.orcNet` を読んで点滅パターンを変える） |

## 10.4 init 失敗とリカバリ（EMA 準拠）

`setup()` 内で各モジュールの `init()` を MAX_RETRY 回リトライし、それでも失敗した
モジュールは `enabled = false` にする。ロジックフェーズで定期的に再 `init()` を試みる。

```cpp
// setup() での初期化（EMA 仕様書「init失敗とリカバリ」に準拠）
for (int r = 0; r < MAX_RETRY; r++) {
    if (module.init()) break;
    delay(100);
}
if (!moduleInitialized) module.enabled = false;

// applyPattern() 内（ロジックフェーズ）での定期再試行
if (!module.enabled && retryTimer.getNowTime() > 5000) {
    retryTimer.setTime();
    if (module.init()) module.enabled = true;
}
```

## 10.5 ログ出力フォーマット（EMA 準拠）

すべてのログは `[ModuleName] msg` 形式で `Serial` に出力する。デバッグ詳細ログは
`#ifdef DEBUG` で切り替え可能とする。

| 例 | 用途 |
|---|---|
| `[OrcNet] init failed: WiFi.begin timeout` | エラー |
| `[OrcNet] reconnecting (attempt 3)` | 状態変化 |
| `[Imu] init ok (LSM6DSOX detected)` | 起動完了 |
| `[Beat] beat_no=42 bpm=119.7` | デバッグ（`#ifdef DEBUG`） |
