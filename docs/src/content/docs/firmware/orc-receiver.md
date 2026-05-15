---
title: OrcReceiverModule — 受信側の時計同期と重複排除
description: CTRL / BEAT の生ペイロードから時計オフセットを EMA で推定し、保留 BEAT キューに整形する入力モジュール
sidebar:
  label: 楽器 — OrcReceiverModule
  order: 8
---

:::note[この章で分かること]
- 受信した `timestampMs` から「指揮者時計 − 自時計」のオフセットを EMA で追跡する仕組み
- BEAT の **重複排除** が `beatNo` 比較だけで成立する設計
- なぜ `data.orcNet.lastCtrl` を直接見ずに、このモジュールを噛ませているのか
:::

## 実体

| ファイル | 行数 | 内容 |
|---|---|---|
| `firmware/test_v2/node_02/lib/OrcReceiverModule/OrcReceiverModule.h` | 45 | Config / Data / クラス宣言 |
| `firmware/test_v2/node_02/lib/OrcReceiverModule/OrcReceiverModule.cpp` | 65 | 時計同期 + 重複排除実装 |

楽器ノード（Arduino UNO R4 WiFi）専用の **入力モジュール**。`updateOutput()` は持たない。
node_03 / node_04 にも完全に同じファイルがコピーされている（partId だけ Config で変える）。

## 役割と責務

| 観点 | 内容 |
|---|---|
| **入力責務** | `data.orcNet.lastCtrl / lastBeat` (OrcNetModule が書いた生パケット) を読んで、楽器ノードのロジックが扱いやすい形に整形する |
| **書くフィールド** | `data.sync.offsetMs / sampleCount / converged`, `data.ctrl.bpm / velocity / state / lastReceivedMs`, `data.receiver.pending / lastBeatNo / hasFirstBeat / lastBeatMs` |
| **読むフィールド** | `data.orcNet.hasNewCtrl / lastCtrl`, `data.orcNet.hasNewBeat / lastBeat` |
| **境界** | パケットの「中身を解釈する」「整形する」だけ。発音判断や状態遷移は `applyPattern()` |

## OrcReceiverConfig

```cpp
struct OrcReceiverConfig {
    uint8_t  partId;
    uint16_t headRestBeats;
    float    clockSyncEmaAlpha;
    uint8_t  clockSyncMinSamples;
    uint16_t loopIntervalMs;
};
```

### 設定値（`ProjectConfig.h` の例: node_02）

```cpp
inline const OrcReceiverConfig ORC_RECEIVER_CONFIG = {
    /*partId=*/              0x02,    // 輪唱 声部 1
    /*headRestBeats=*/       0,       // 先頭から入る
    /*clockSyncEmaAlpha=*/   0.10f,
    /*clockSyncMinSamples=*/ 5,
    /*loopIntervalMs=*/      5,
};
```

### `partId` — 輪唱の声部番号

| ノード | partId | 役割 |
|---|---|---|
| node_02 | 0x02 | 声部 1（先頭から入る） |
| node_03 | 0x03 | 声部 2（8 拍遅れて入る） |
| node_04 | 0x04 | 声部 3（16 拍遅れて入る） |

NOTE パケットの `partId` フィールドにそのまま埋め込まれる。Processing 側で「どのノードから
来た NoteOn か」を識別するキー。

### `headRestBeats` — 輪唱の頭ずらし

声部ごとに「何拍待ってから入るか」を決める：

| ノード | headRestBeats | 入り方 |
|---|---|---|
| node_02 | 0 | 拍 1 から `kScore[0]` を鳴らす |
| node_03 | 8 | 拍 1〜8 を読み飛ばし、拍 9 から `kScore[0]` を鳴らす |
| node_04 | 16 | 拍 1〜16 を読み飛ばし、拍 17 から `kScore[0]` を鳴らす |

`applyPattern()` 内で `firedBeatNo - 1 - headRestBeats` の式で楽譜インデックスを計算する。
このモジュール自体は `headRestBeats` を保持しているだけ（実際の参照は `applyPattern()`）。

### `clockSyncEmaAlpha = 0.10` — 時計同期 EMA の係数

オフセット推定の指数移動平均係数：

| α 値 | 追従性 | ノイズ耐性 |
|---|---|---|
| 0.05 | 遅い（数百サンプル後に収束） | 高い |
| **0.10** | **中程度（数十サンプル後）** | **十分** |
| 0.30 | 速い（数サンプル後） | ジッタに敏感 |

CTRL は 20 Hz で来るので、α=0.10 なら 1〜2 秒で実用レベルに収束する。
詳しい数学は [時刻同期メカニズム](/deep-dive/time-sync/) を参照。

### `clockSyncMinSamples = 5`

EMA が **「収束した」と宣言する** ためのサンプル下限。これ未満は `converged = false`。
ただし演奏遷移条件（`PerformerState::WaitStart → Playing`）には使っていない（後述）。

### `loopIntervalMs = 5`

楽器ノードのメインループ周期。これは `main.cpp` のループ周期制御で使う。
`OrcReceiverModule` 内部では参照しないが、`Config` にまとめて持つことで一元管理。

## PendingBeat / ReceiverLogicData

```cpp
struct PendingBeat {
    bool     valid = false;
    uint16_t beatNo = 0;
    uint32_t playAtMasterMs = 0;
    uint32_t enqueuedAtMs = 0;
};

struct ReceiverLogicData {
    bool        hasFirstBeat = false;
    uint16_t    lastBeatNo = 0;
    uint32_t    lastBeatMs = 0;
    PendingBeat pending;
};
```

### PendingBeat — 「次に発音すべき拍」の予約

`pending.valid = true` で、`applyPattern()` がその拍を発音するか判断する。
発音したら `pending.valid = false` でクリア。

| フィールド | 意味 |
|---|---|
| `valid` | 予約中か |
| `beatNo` | どの拍か |
| `playAtMasterMs` | 指揮者時計でいつ発音するか |
| `enqueuedAtMs` | 受信した自時計時刻（診断用） |

### ReceiverLogicData — 受信状態の累積

| フィールド | 意味 |
|---|---|
| `hasFirstBeat` | 最初の BEAT を受信したか（演奏開始フラグ） |
| `lastBeatNo` | 直近受信した BEAT 番号（重複排除用） |
| `lastBeatMs` | 直近受信時の自時計時刻（タイムアウト診断用） |
| `pending` | 上記の保留 BEAT |

## init() — 何もしない

```cpp
bool init() override { return true; }
```

ハードウェア初期化は不要（パケットの解釈ロジックだけ）。常に true。

## updateInput() — 1 ループでやること

```cpp
void OrcReceiverModule::updateInput(SystemData& data) {
    // 1. CTRL を受信していれば時計同期 + 状態取り込み
    if (data.orcNet.hasNewCtrl) {
        updateClockOffset(data,
                          data.orcNet.lastCtrl.header.timestampMs,
                          cfg_.clockSyncEmaAlpha,
                          cfg_.clockSyncMinSamples);

        data.ctrl.bpm = data.orcNet.lastCtrl.payload.bpmQ8 / 8.0f;
        data.ctrl.velocity = data.orcNet.lastCtrl.payload.velocity;
        data.ctrl.state = data.orcNet.lastCtrl.payload.state;
        data.ctrl.lastReceivedMs = millis();
    }

    // 2. BEAT を受信していれば時計同期 + 重複排除 + 保留キュー
    if (data.orcNet.hasNewBeat) {
        updateClockOffset(data,
                          data.orcNet.lastBeat.header.timestampMs,
                          cfg_.clockSyncEmaAlpha,
                          cfg_.clockSyncMinSamples);

        const uint16_t bn = data.orcNet.lastBeat.payload.beatNo;
        const bool isDuplicate = data.receiver.hasFirstBeat &&
                                 (bn == data.receiver.lastBeatNo);
        if (!isDuplicate) {
            data.receiver.pending.valid = true;
            data.receiver.pending.beatNo = bn;
            data.receiver.pending.playAtMasterMs =
                data.orcNet.lastBeat.payload.playAtMasterMs;
            data.receiver.pending.enqueuedAtMs = millis();
            data.receiver.lastBeatNo = bn;
            data.receiver.hasFirstBeat = true;
        }
        data.receiver.lastBeatMs = millis();
    }
}
```

### CTRL 処理

#### 1. 時計同期

```cpp
updateClockOffset(data, data.orcNet.lastCtrl.header.timestampMs, ...);
```

CTRL の `timestampMs`（指揮者時計）と現在の自時計 `millis()` を比較して、
オフセットを EMA で更新する（実装は後述）。

#### 2. BPM デコード

```cpp
data.ctrl.bpm = data.orcNet.lastCtrl.payload.bpmQ8 / 8.0f;
```

`bpmQ8` (Q8 固定小数) を float に戻す。例：`bpmQ8 = 964` → `bpm = 120.5`。

#### 3. velocity / state / lastReceivedMs

```cpp
data.ctrl.velocity = data.orcNet.lastCtrl.payload.velocity;
data.ctrl.state = data.orcNet.lastCtrl.payload.state;
data.ctrl.lastReceivedMs = millis();
```

そのまま `data.ctrl` にコピー。`lastReceivedMs` で「CTRL タイムアウト」を診断可能に。

### BEAT 処理

#### 1. 時計同期

```cpp
updateClockOffset(data, data.orcNet.lastBeat.header.timestampMs, ...);
```

BEAT の `timestampMs` でも同じく時計同期を更新する。CTRL/BEAT 両方からサンプルを取って
EMA の収束を速める設計。

#### 2. 重複排除

```cpp
const uint16_t bn = data.orcNet.lastBeat.payload.beatNo;
const bool isDuplicate = data.receiver.hasFirstBeat &&
                         (bn == data.receiver.lastBeatNo);
if (!isDuplicate) {
    // ...
}
```

`beatNo` が `lastBeatNo` と等しいなら **同じ拍** とみなして捨てる。
これにより：
- 2 連送（`beatRedundancy = 2`）の片方を破棄
- ネットワーク経由で偶発的に 2 回届いたパケットを破棄

ただし最初の BEAT は `hasFirstBeat = false` なので無条件で受理（`isDuplicate = false`）。

#### 3. 保留 BEAT キューに登録

```cpp
data.receiver.pending.valid = true;
data.receiver.pending.beatNo = bn;
data.receiver.pending.playAtMasterMs = data.orcNet.lastBeat.payload.playAtMasterMs;
data.receiver.pending.enqueuedAtMs = millis();
data.receiver.lastBeatNo = bn;
data.receiver.hasFirstBeat = true;
```

`pending` 構造体に詰めて「次に `applyPattern()` で発音判定する」状態にする。
`lastBeatNo` も更新して次回の重複判定に備える。

#### 4. lastBeatMs は重複でも更新

```cpp
data.receiver.lastBeatMs = millis();
```

重複でも `lastBeatMs` は更新する。これは「BEAT 受信タイムアウト監視」のため：
- もし重複でこれを更新しないと、2 連送の片方を捨てた後に「もう BEAT が来ていない」と
  誤判定する
- 「受信した時刻」と「処理した時刻」を分けて管理する

## updateClockOffset() — EMA 実装

```cpp
namespace {

void updateClockOffset(SystemData& data, uint32_t timestampMs, float alpha,
                       uint8_t minSamples) {
    const int32_t sample = (int32_t)(timestampMs - millis());
    if (data.sync.sampleCount == 0) {
        data.sync.offsetMs = sample;
    } else {
        const float prev = (float)data.sync.offsetMs;
        const float next = (1.0f - alpha) * prev + alpha * (float)sample;
        data.sync.offsetMs = (int32_t)next;
    }
    if (data.sync.sampleCount < 0xFFFF) data.sync.sampleCount++;
    if (data.sync.sampleCount >= minSamples) data.sync.converged = true;
}

}
```

### サンプルの計算

```cpp
const int32_t sample = (int32_t)(timestampMs - millis());
```

`timestampMs` は **送信時の指揮者時計**、`millis()` は **受信処理時の自時計**。
両者の差が「指揮者時計 − 自時計」のオフセット。

例：
- 指揮者の時計が 10000 ms
- パケットが届いて自時計を見ると 9950 ms
- `sample = 10000 - 9950 = 50` → 「指揮者時計の方が 50 ms 進んでいる」

ネットワーク遅延込みで誤差を含むが、たくさんサンプルを取れば EMA が中央値に収束する。

### 符号付き int への変換

```cpp
const int32_t sample = (int32_t)(timestampMs - millis());
```

`timestampMs` と `millis()` は両方 `uint32_t`。引き算は `uint32_t` で行われ、
**自然なラップアラウンドで** ±約 2^31 ms 範囲の符号付き値に解釈できる。

`(int32_t)` キャストで明示的に符号付きに。これで負のオフセット（自時計の方が進んでいる）も
正しく扱える。

### EMA の更新

```cpp
if (data.sync.sampleCount == 0) {
    data.sync.offsetMs = sample;
} else {
    const float prev = (float)data.sync.offsetMs;
    const float next = (1.0f - alpha) * prev + alpha * (float)sample;
    data.sync.offsetMs = (int32_t)next;
}
```

初回は「素のサンプルをそのまま採用」。2 回目以降は：

$$
\text{offset}_{n} = (1 - \alpha) \cdot \text{offset}_{n-1} + \alpha \cdot \text{sample}_n
$$

α=0.10 なら：
- 新サンプルの寄与: 10%
- 前回値の寄与: 90%

ジッタの影響を弱め、滑らかにオフセットを追跡する。

### `sampleCount` のオーバーフロー保護

```cpp
if (data.sync.sampleCount < 0xFFFF) data.sync.sampleCount++;
```

`uint16_t` の最大値 65535 で停止する。65535 サンプル取った後はそれ以上数えないが、
`converged = true` のまま EMA は更新され続ける。

### `converged` フラグ

```cpp
if (data.sync.sampleCount >= minSamples) data.sync.converged = true;
```

`minSamples = 5` 以上のサンプルを取ったら `converged = true` で固定。
診断ログでの表示に使われる（演奏開始の条件には使わない、後述）。

## 「整形層」を噛ませる意義

`OrcReceiverModule` を経由せず、`applyPattern()` で直接 `data.orcNet.lastCtrl` を見ても
動作はする。なぜ整形層を挟むのか：

| 観点 | 整形層なし | 整形層あり |
|---|---|---|
| applyPattern の責務 | パケット解釈 + 発音判断 + 状態遷移 | **発音判断 + 状態遷移のみ** |
| 時計同期の所在 | 数か所に散る | このモジュールに集約 |
| 重複排除の所在 | applyPattern が `lastBeatNo` を管理 | このモジュールに集約 |
| テストしやすさ | パケット解釈と判断を同時にテスト | 別々にテスト可能 |
| 拡張性 | 通信プロトコル変更でロジックも巻き込まれる | OrcReceiverModule だけ書き換えれば済む |

EMA は「責務を一段階分ける」のが鉄則。`OrcReceiverModule` は **生パケット → 楽器ロジックが
扱いやすい形** に整形する純粋な変換層。

## `clockSyncMinSamples` が Playing 遷移に使われない理由

コードコメントに：
> `clockSyncMinSamples = 5` （デバッグ表示用. Playing 遷移条件には使わない）

楽器ノードの状態遷移は：

```cpp
case PerformerState::WaitStart:
    if (data.receiver.hasFirstBeat) {
        data.performer.state = PerformerState::Playing;
    }
    break;
```

「最初の BEAT を受信したら即 Playing」になる。`sync.converged` は条件に入らない。

理由：

- BEAT を 1 個でも受信できれば「指揮者は生きていて、楽器の方向に届く経路がある」
- 時計同期は徐々に収束するが、最初は粗くてもいい（最初の数拍は同期誤差が大きいだけ）
- `sync.converged = false` を Playing の条件にすると、初回起動時に「振り始めたのに音が出ない」
  症状が出る（数秒間収束待ち）

体験を優先して、**時計同期がまだ収束していなくても演奏を始める** 設計にしてある。
収束は走りながら EMA で改善していく。

## 落とし穴

- **`updateInput()` で `hasNewCtrl / hasNewBeat` をクリアしない**。これらは `OrcNetModule` が
  毎周期頭でクリアする責任を持つ。OrcReceiverModule は読むだけ。
- **`pending` が valid のまま新しい BEAT が来ると上書きされる**: 設計上 1 個しか保持しないので
  注意。実際は `applyPattern()` が即座に発音判定するので滞留は稀。
- **`millis()` のラップアラウンドで `int32_t sample` が異常値になる懸念**: `uint32_t - uint32_t` の
  ラップアラウンド差分を `int32_t` にキャストするので、±約 25 日範囲なら正しく扱える。
  ハッカソンスケールでは問題なし。
- **EMA の α を 0.10 から大きく変えると挙動が一変する**: 大きくするとジッタを拾い、小さくすると
  収束が遅くなる。実機で検証して 0.10 に決めた値。

## 関連ページ

- 受信パケットを生で取る側 → [OrcNetModule](/firmware/orc-net/)
- パケットを発音判断に使う側 → [main フロー（楽器）](/firmware/main-instrument/)
- 時計同期の数学的詳細 → [時刻同期メカニズム](/deep-dive/time-sync/)
- 楽譜進行ロジック → [楽譜進行ロジック](/deep-dive/score-progression/)
