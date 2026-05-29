---
title: 楽譜フォーマット
description: 楽譜データの構造と、輪唱の「頭ずらし」「途中起動対応」の仕組み
sidebar:
  order: 4
---

:::note[この章で分かること]
- 楽譜データがどう格納されているか
- 輪唱の声部間ずらしをどう表現しているか
- なぜ PC を途中起動しても合流できるか
:::

:::tip[読了目安]
**約 5 分**。
:::

## 楽譜データの位置づけ

- 楽譜は **各楽器マイコン内部に保持**（SD カードや外部ストレージに頼らない）
- パートごとに別ファイル……ではなく、**輪唱なので全パート同一**
  → `node_02/03/04` で完全に同じ `score_data.cpp` を使う
- 楽器マイコンは指揮者からの `beatNo` を見て、自パートの楽譜位置を計算する

詳しい決定経緯: [ADR-0004](/decisions/0004-ensemble-structure/)

## `ScoreEvent` 構造

`firmware/test_v2/node_0{2,3,4}/include/score_data.h`：

```cpp
struct ScoreEvent {
    uint16_t beatAt;         // 参考値: 1 始まりの拍番号（進行は index 駆動なのでログ用）
    uint8_t  noteNumber;     // MIDI ノート番号（0 = 休符）
    uint8_t  velocity;       // 0-127
    uint16_t durationQ8;     // 1/256 拍単位（256 = 1 拍、240 = ≒0.94 拍、480 = ≒1.9 拍）
    uint8_t  flags;          // bit0=NoteOn / bit2=休符（タイの続き）

    // ── 細分音符（拍頭からのオフセットで予約発火する 2 音目）──
    uint8_t  subNote;        // 0 のときは予約しない
    uint8_t  subVelocity;
    uint16_t subOffsetQ8;    // 拍頭からのオフセット（128 = 半拍 = 8 分音符）
    uint16_t subDurationQ8;
};

extern const ScoreEvent kScore[];
extern const size_t     kScoreLength;
```

**1 拍 = 1 ScoreEvent** が原則。指揮者の BEAT を 1 個受けるたびにインデックスを 1 個進める。
2 拍ぶん伸ばす音は `durationQ8 = 480` を 1 行に書き、続く 1 拍は `flags = 0x04`（休符 = タイの続き）で
表現する。実体は `src/score_data.cpp`：

```cpp
// 「きらきら星」抜粋
const ScoreEvent kScore[] = {
    // {beatAt, noteNumber, velocity, durationQ8, flags, subNote, subVel, subOffQ8, subDurQ8}
    {  1, 60, 100, 240, 0x01, 0, 0, 0, 0 },  // ド   C4
    {  2, 60, 100, 240, 0x01, 0, 0, 0, 0 },  // ド   C4
    {  7, 67, 100, 480, 0x01, 0, 0, 0, 0 },  // ソー G4（2 拍）
    {  8,  0,   0,   0, 0x04, 0, 0, 0, 0 },  //       タイの続き（休符扱い）
    // ...
};
const size_t kScoreLength = sizeof(kScore) / sizeof(kScore[0]);
```

きらきら星は細分音符を使わないので `sub*` は全行 0。8 分音符付きの曲を扱うときに
`subNote != 0` を立てると、`fireScoreEvent()` が拍頭から `subOffsetQ8 / 256` 拍ぶん遅らせて
2 音目を予約発火する。

## 輪唱の「頭ずらし」

3 声輪唱では、各声部が **同じ旋律を一定拍ずらして** 入る。
本プロジェクトは `ProjectConfig.h` の `headRestBeats` で表現：

| ノード | `headRestBeats` | `instrumentId` | 入りタイミング |
|---|---|---|---|
| node_02 | 0 | 0（オルガン） | 拍 0 から開始 |
| node_03 | 8 | 1（フルート） | 拍 8 から開始 |
| node_04 | 16 | 2（ベル） | 拍 16 から開始 |

（楽器名は `pc_app/test_v2/orchestra_resynth/data/*.json` の中身に依存する。
JSON を増やせば対応関係も増える。下の「楽器番号と音色の対応」表が正典）

楽器ノードのロジック（`firmware/test_v2/node_02/src/applyPattern.cpp` 実装）：

```cpp
// 指揮者の拍番号 firedBeatNo（1 始まり）→ 自分の楽譜インデックス
const int32_t effective = (int32_t)firedBeatNo - 1 - (int32_t)cfg.headRestBeats;
if (effective < 0) {
    // まだ「頭の休符」期間 → 何も鳴らさない（拍を消費するだけ）
    return;
}
// 曲長で剰余を取り、kScore の該当イベントを発火
const uint32_t scoreIndex = (uint32_t)effective % (uint32_t)kScoreLength;
fireScoreEvent(data, kScore[scoreIndex], now);
```

`kScoreLength` 個の `ScoreEvent` が並ぶ配列を、拍番号で巡回参照する。曲長 `SCORE_TOTAL_BEATS`
のような別変数は存在しない（1 ScoreEvent = 1 拍が固定なので `kScoreLength` がそのまま曲の拍数）。

## 「PC を途中起動しても合流できる」仕組み

`beatNo` は指揮者起動から単調増加するが、楽譜は `effective % kScoreLength` でループするので、
**任意のタイミングで楽器が立ち上がっても、その瞬間の `beatNo` から正しい位置を計算できる**。

実例:

- 演奏が始まって 100 拍経過したところで PC を再起動 → 楽器ノードは生き続けている
- 楽器ノードは `beatNo=100` を保持しており、即座に「曲頭から 100 拍目」の音を出せる
- PC は USB Serial が再開した瞬間から NOTE を受け取って音を鳴らす

これは「**指揮者が止まらない限り、デモを何度でもやり直せる**」を意味する。
プレゼン本番でも安心。

## 楽譜を増やすには

1. 新しい曲の `ScoreEvent` 配列を作る（DAW のエクスポートや手打ち）
2. `node_0{2,3,4}/src/score_data.cpp` を 3 台分とも置き換える（または共通ヘッダに切り出して include させる）
3. `kScoreLength` は `sizeof(kScore) / sizeof(kScore[0])` で自動算出されるので再計算不要
4. `headRestBeats` を曲構造に合わせて調整（5 声（[ADR-0004](/decisions/0004-ensemble-structure/)）なら 0 / 8 / 16 / 24 / 32 など）

将来的に複数曲対応するなら：

- `SCORE_DATA_<song>[]` を複数並べて、`ProjectConfig.h` で選択
- CTRL に「曲 ID」フィールドを足して指揮者から切替
- などの方法がある（未実装）

## 楽器番号と音色の対応

`instrumentId` は NOTE パケットに載るが、楽譜データ側にも対応情報が必要：

- 各ノードの `ProjectConfig.h` の `NoteSenderConfig::instrumentId`（楽器ノードの構造体リテラルの第 3 引数）で固定
- PC 側 `pc_app/test_v2/orchestra_resynth/data/` 内の JSON を **ファイル名昇順で配列化** し、
  `instrumentId` を **その配列の index** として参照する

| `instrumentId` | 想定楽器 | 実体ファイル（2026-05 時点） |
|---|---|---|
| 0 | オルガン | `pc_app/test_v2/orchestra_resynth/data/0_organ.json` |
| 1 | フルート | `pc_app/test_v2/orchestra_resynth/data/1_flute.json` |
| 2 | ベル | `pc_app/test_v2/orchestra_resynth/data/2_bell.json` |
| 3 | フルート（調整版） | `pc_app/test_v2/orchestra_resynth/data/3_flute_tweaked.json` |

ファイル名先頭の `0_`, `1_` は人間が並び順を把握するための慣例。実コードは
**ファイル名そのもの** ではなく **ソート順の index** で参照する点に注意。

JSON フォーマット例:

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

詳しくは [pc_app の歩き方](/code/pc-app/) を参照。

## 次に読むべきページ

- 通信形式 → [通信プロトコル](/architecture/protocol/)
- 拍検出 → [同期戦略](/architecture/sync/)
- PC 側合成 → [pc_app の歩き方](/code/pc-app/)

### さらに深掘りしたい

- `firedBeatNo → scoreIndex` 変換式、輪唱、細分音符、途中起動耐性 → [楽譜進行ロジック](/deep-dive/score-progression/)
