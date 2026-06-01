---
title: 楽譜進行ロジック
description: firedBeatNo から楽譜インデックスを引く式、輪唱の headRestBeats、ループ再生、細分音符の予約発火、途中起動への耐性
sidebar:
  order: 5
---

:::note[この章で分かること]
- `firedBeatNo`（指揮者拍番号）から楽器ごとの `scoreIndex` を求める式
- 輪唱の「頭ずらし」を `headRestBeats` 1 値で表現できる理由
- 細分音符（8 分音符）を「拍頭からのオフセット予約」で扱う方法
- PC・楽器のどれを途中で再起動しても合流できる仕組み
- 曲を差し替えるときの作業手順
:::

:::tip[読了目安]
**約 10 分**。前提: [拍検出アルゴリズム](/deep-dive/beat-detection/) と [時刻同期メカニズム](/deep-dive/time-sync/) を読み終えていること。
:::

実装本体:
- 楽譜進行: `firmware/test_v2/node_02/src/applyPattern.cpp`
- 楽譜定義: `firmware/test_v2/node_0{2,3,4}/include/score_data.h`
- 楽譜本体: `firmware/test_v2/node_0{2,3,4}/src/score_data.cpp`（3 台同一）

## なぜ拍番号で進めるか

楽譜の進め方には大きく 2 方式ある。

| 方式 | 仕組み | 弱点 |
|---|---|---|
| **時間駆動** | 起動からの経過時刻で「今は X 秒目」と決め、X 秒目の音符を引く | テンポ変化に弱い、再起動で 0 秒に戻る |
| **拍番号駆動**（採用） | 指揮者の `beatNo` で「今は N 拍目」と決め、N に対応する音符を引く | 指揮者の `beatNo` を共有する仕組みが必要 |

本プロジェクトは BEAT パケットで `beatNo` を全楽器に配信できる仕組み（[UDP マルチキャスト](/deep-dive/udp-multicast/)）が既にあるので、**拍番号駆動** が自然。

メリット：

- テンポが変動しても、同じ拍では必ず同じ音符が出る
- 楽器を再起動しても、次の BEAT で `beatNo` を得て即座に正しい位置から鳴る
- 拍が 1 つ落ちても、次の拍で正しい位置に追いつく（自己補正）

## `ScoreEvent` の構造

`firmware/test_v2/node_02/include/score_data.h`：

```cpp
struct ScoreEvent {
    uint16_t beatAt;          // 1 始まりの拍番号（ログ可読性のため。進行は index 駆動）
    uint8_t  noteNumber;      // MIDI ノート番号（0 = 休符）
    uint8_t  velocity;        // 0-127
    uint16_t durationQ8;      // 1/256 拍単位（256 = 1 拍）
    uint8_t  flags;           // bit0=NoteOn / bit2=休符（タイの続き）
    // ── 細分音符（拍頭からのオフセットで予約発火する 2 音目）──
    uint8_t  subNote;
    uint8_t  subVelocity;
    uint16_t subOffsetQ8;
    uint16_t subDurationQ8;
};

extern const ScoreEvent kScore[];
extern const size_t     kScoreLength;
```

### `durationQ8` の Q8 固定小数

「1 拍 = 256」とすることで、`uint16_t` の範囲で 0〜256 拍を 1/256 拍刻みで表現できる：

| `durationQ8` | 拍 |
|---|---|
| `256` | 1.0 拍（4 分音符の素直な長さ） |
| `240` | ≒ 0.94 拍（4 分音符を実際にはちょっと短めに鳴らす） |
| `128` | 0.5 拍（8 分音符） |
| `64` | 0.25 拍（16 分音符） |
| `480` | ≒ 1.9 拍（2 分音符を短めに） |
| `512` | 2.0 拍 |

なぜ `256` を「1 拍」に選んだか：

- 2 のべき乗なので、乗除算がシフトで近似できる（マイコンに優しい）
- 0.5 拍 / 0.25 拍 / 0.125 拍 / 0.0625 拍がすべて整数で表せる
- 0.94 拍のような「装飾的な隙間」も整数化できる（240 = 256 × 0.9375）

### `flags` の意味

`uint8_t` のビットを以下のように使う：

| bit | 値 | 意味 |
|---|---|---|
| 0 | `0x01` | NoteOn（通常の音符） |
| 1 | `0x02` | NoteOff（拡張用、現状未使用） |
| 2 | `0x04` | 休符（タイの続き）— 2 拍以上伸ばす音の 2 拍目以降 |

きらきら星では `0x01`（通常音符）と `0x04`（タイ続き）の 2 種類だけ使う。

#### タイの続きの仕組み

2 拍ぶん伸ばす音（例: 最後の「ソー」）は次のように書く：

```cpp
{  7, 67, 100, 480, 0x01, 0, 0, 0, 0 },  // ソー G4 (2 拍ぶん発音)
{  8,  0,   0,   0, 0x04, 0, 0, 0, 0 },  //      (タイの続き = 休符として扱う)
```

7 拍目の `ScoreEvent` で `durationQ8 = 480`（≒1.9 拍）の音を発火。
8 拍目の `ScoreEvent` は `flags = 0x04` で「ここでは何も鳴らさない」と指示。

これで「**1 拍 = 1 ScoreEvent**」の規約を保ったまま、長音符を表現できる。

## 「きらきら星」全曲のレイアウト

`kScore[]` 配列は 48 要素：

```
インデックス: 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
拍番号:        1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16
音:           ド ド ソ ソ ラ ラ ソー (続) ファ ファ ミ ミ レ レ ドー (続)

インデックス: 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31
拍番号:       17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32
音:           ソ ソ ファ ファ ミ ミ レー (続) ソ ソ ファ ファ ミ ミ レー (続)

インデックス: 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47
拍番号:       33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48
音:           ド ド ソ ソ ラ ラ ソー (続) ファ ファ ミ ミ レ レ ドー (続)
```

`kScoreLength = 48`。次の 49 拍目では `% 48 = 0` になり、最初のド C4 に戻る。

## 拍番号 → 楽譜インデックスの変換

楽器ノードのロジック（実装は `applyPattern.cpp:applyPattern()` 末尾）：

```cpp
if (fired && kScoreLength > 0) {
    const int32_t effective =
        (int32_t)firedBeatNo - 1 - (int32_t)ORC_RECEIVER_CONFIG.headRestBeats;
    if (effective >= 0) {
        const uint32_t scoreIndex = (uint32_t)effective % (uint32_t)kScoreLength;
        fireScoreEvent(data, kScore[scoreIndex], now);
        data.score.currentEventIndex = (uint16_t)scoreIndex;   // 診断ログ用
    }
}
```

3 つのステップで `firedBeatNo` を `scoreIndex` に変換している。

### ステップ 1: 拍番号を 0 オリジン化

`firedBeatNo` は **1 始まり**（最初の拍が 1）。配列は **0 始まり**なので、`-1` する：

```
firedBeatNo:  1  2  3  4  ...
zero-based:   0  1  2  3  ...
```

### ステップ 2: 頭ずらしを引く

`headRestBeats` だけ「自分の出番が始まる前」を引く：

```
node_02 (headRestBeats=0):    1 拍目から自分の楽譜開始
node_03 (headRestBeats=8):    9 拍目で「自分の」1 拍目
node_04 (headRestBeats=16): 17 拍目で「自分の」1 拍目
```

`effective = firedBeatNo - 1 - headRestBeats`

- `effective < 0`: まだ自分の番じゃない（先頭の休符）→ **何もしない**
- `effective >= 0`: 自分の楽譜の `effective` 番目を引く

### ステップ 3: 曲全体でループ

`effective` は曲全体で単調増加するので、`kScoreLength` で `mod` を取って循環させる：

$$
\text{scoreIndex} = \text{effective} \bmod \text{kScoreLength}
$$

```cpp
const uint32_t scoreIndex = (uint32_t)effective % (uint32_t)kScoreLength;
```

`effective` を `uint32_t` にキャストしてから `%` を取るのがポイント。
C の `%` は **符号付き整数の負数** に対して実装定義の動作になることがあるので、
`>= 0` であることを保証してから符号無しで割る。

## 輪唱の頭ずらし

3 声輪唱は「同じ旋律を一定拍ずらして開始する」だけで成立する。本プロジェクトでは
`headRestBeats` という 1 つの整数だけで完全に表現される：

| ノード | `headRestBeats` | `instrumentId` | `partId` |
|---|---|---|---|
| node_02 | 0 | 0（オルガン） | 0x02 |
| node_03 | 8 | 1（フルート） | 0x03 |
| node_04 | 16 | 2（ベル） | 0x04 |

`headRestBeats` は `OrcReceiverConfig` の引数、`instrumentId` は `NoteSenderConfig`
の引数で、`partId` は両方に同値を入れる（各ノードの `include/ProjectConfig.h` 参照）。
差分はこれだけ。`score_data.cpp` の中身は **3 台で完全に同一**。

### 1〜8 拍目の各楽器の挙動

| 拍 | node_02 (rest=0) | node_03 (rest=8) | node_04 (rest=16) |
|---|---|---|---|
| 1 | ド (kScore[0]) | 休止 | 休止 |
| 2 | ド (kScore[1]) | 休止 | 休止 |
| 3 | ソ (kScore[2]) | 休止 | 休止 |
| ... | ... | ... | ... |
| 8 | タイ続き | 休止 | 休止 |
| 9 | ファ (kScore[8]) | ド (kScore[0]) | 休止 |
| 10 | ファ (kScore[9]) | ド (kScore[1]) | 休止 |
| ... | ... | ... | ... |
| 17 | ソ (kScore[16]) | ファ (kScore[8]) | ド (kScore[0]) |

各声部が「自分の楽譜の 1 拍目」を別の拍番号で始めることで、輪唱が成立する。

### 4 声以上に増やすには

`headRestBeats = 24` の node_05 を足せば 4 声になる。フレーズ長 8 拍に合わせるなら、
0 / 8 / 16 / 24 で 4 声がきれいに重なる（曲によって変える）。

production 想定（[ADR-0004](/decisions/0004-ensemble-structure/) 改訂版・楽器 5 台 = 金管 4 ＋ ドラム 1）
では `node_02〜06` の 5 ノードに `headRestBeats` を割り振る運用（ドラム声部はピッチを持たない
代わりに別の楽譜表現を採る想定）。

## 細分音符の予約発火

きらきら星には登場しないが、「8 分音符が拍と拍の間に挟まる曲」のために、
**1 つの `ScoreEvent` に 2 音目を予約する** 仕組みがある。

```cpp
struct ScoreEvent {
    // ── 拍頭の音 ──
    uint8_t  noteNumber;
    uint8_t  velocity;
    uint16_t durationQ8;
    uint8_t  flags;

    // ── 拍頭から subOffsetQ8/256 拍ぶん遅れて鳴る音 ──
    uint8_t  subNote;        // 0 のときは予約しない
    uint8_t  subVelocity;
    uint16_t subOffsetQ8;    // 128 = 半拍 = 8 分音符
    uint16_t subDurationQ8;
};
```

実装は `applyPattern.cpp:fireScoreEvent()` 内：

```cpp
// 細分音符の予約
if (ev.subNote != 0) {
    const float bpm = (data.ctrl.bpm >= 1.0f) ? data.ctrl.bpm : DEFAULT_BPM;
    const float beats = (float)ev.subOffsetQ8 / 256.0f;
    const uint32_t subDelayMs = (uint32_t)(beats * 60000.0f / bpm);
    data.score.pendingSub          = true;
    data.score.pendingSubAtMs      = now + subDelayMs;
    data.score.pendingSubNote      = ev.subNote;
    // ...
}
```

毎ループの先頭で予約時刻が来ているかを判定：

```cpp
void firePendingSub(SystemData& data, uint32_t now) {
    if (!data.score.pendingSub) return;
    if ((int32_t)(now - data.score.pendingSubAtMs) < 0) return;
    // 発火
    data.noteOut.noteNumber = data.score.pendingSubNote;
    // ...
    data.noteOut.pendingOn = true;
    data.score.pendingSub = false;
}
```

1 BEAT につき **高々 1 個** の細分音符。連続する 8 分音符を表現したい場合は、
1 拍ごとに `ScoreEvent` で「拍頭 + 半拍後の音」を書く構成。

### 制約

- 同じ拍内で 3 音以上の予約は不可（`pendingSub` は 1 個分しか持たない）
- 細分音符の発音時刻は **自時計の `millis()` 基準**で、`playAtMasterMs` の遅延吸収は
  受けない（拍頭の音は揃うが、細分音符は ±5 ms 程度のズレが出る可能性あり）

## 「PC や楽器を途中起動しても合流できる」仕組み

### シナリオ 1: PC を再起動

- 楽器は生き続けて NOTE を USB Serial で流し続ける
- PC を起動 → orchestra_resynth がシリアルポートを開く
- シリアルが繋がった瞬間から NOTE が PC に届き、音が出る
- 曲のどこから再開するかは「いま流れている `firedBeatNo`」次第（曲の途中から自然に鳴り始める）

### シナリオ 2: 楽器を再起動

- 指揮者は生き続けて CTRL/BEAT を流し続ける
- 楽器が起動 → SoftAP に接続 → 数回 CTRL を受信して時刻オフセットが収束
- 次の BEAT で `firedBeatNo` を取得
- `firedBeatNo - 1 - headRestBeats` から自分の楽譜位置を計算、即座に発音

### シナリオ 3: 指揮者だけが生きている状態で他全部再起動

- 楽器・PC を順に起動するだけで、現在進行中の曲の現在位置から自然に鳴り始める
- プレゼンで「失敗したのでやり直し」が可能

### シナリオ 4: 拍が 1 つ落ちる

- BEAT の連送（`beatRedundancy` 連、暫定 4）がすべて届かない（極めて稀）
- 次の BEAT で `firedBeatNo` が 1 進んでいる
- `scoreIndex` も 1 進むので、楽譜の流れに復帰
- 1 拍ぶん演奏が抜けるが、ズレは残らない（自己補正）

## 曲を差し替える手順

新しい曲を入れたいときの作業：

1. **楽譜を `ScoreEvent` 配列に書き起こす**
   - 各拍に対応する 1 行を書く
   - 2 拍以上伸ばす音は「最初の行に `durationQ8 = 240×拍数`、続く行に `flags = 0x04`」
   - 8 分音符が必要なら `subNote / subOffsetQ8 = 128` を使う
2. **`node_02/03/04/src/score_data.cpp` を 3 台分とも書き換える**
   - 配列の内容は完全に同一
   - `kScoreLength` は `sizeof / sizeof` で自動算出されるので変更不要
3. **`headRestBeats` をフレーズ構造に合わせる**
   - 8 拍周期フレーズなら 0 / 8 / 16 のままで OK
   - 4 拍周期なら 0 / 4 / 8、16 拍周期なら 0 / 16 / 32
4. **`NoteSenderConfig::instrumentId` を合わせる**
   - 楽器番号と音色 JSON（ファイル名昇順 index）を合わせる（後段の合成側）
5. **`pio run` でビルドが通ることを確認**
6. **3 台に書き込み、実機で同期確認**

3 台同一にするのが面倒なら、共通ヘッダ `score_kirakira.h` などに切り出して
`#include` する手もある。本プロジェクトでは直書きしている（試行錯誤しやすいため）。

## 楽譜データの SSOT

`score_data.cpp` 1 ファイルが楽譜の SSOT（Single Source of Truth）。
- ドキュメント側に「楽譜は 48 拍」とは書かない（実装が更新されたとき乖離する）
- 拍数を知りたい人は `kScoreLength` で計算する

## デバッグの観点

楽器側で `SERIAL_DEBUG=1` で書き込むと、発音時にこう出る：

```
[N2 FIRE  beatNo=42 scoreIndex=10 note=67 dur=560]
```

`scoreIndex` が想定と違うなら：

- `headRestBeats` が間違っている
- 曲長が変わったのに別ノードを更新し忘れた
- BEAT が 1 つ落ちた直後（次の BEAT で復帰するはず）

## 次に読むべきページ

- 楽器 → PC の流れ → [加算合成エンジン](/deep-dive/additive-synthesis/)
- 拍そのものの作り方 → [拍検出アルゴリズム](/deep-dive/beat-detection/)
- 楽譜データを増やすときの SystemData 拡張 → [モジュール拡張ガイド](/deep-dive/module-extension/)
