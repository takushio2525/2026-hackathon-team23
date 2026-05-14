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
    uint16_t beatOffset;       // 曲頭からの拍オフセット（拍 × 256 の固定小数も可）
    uint8_t  midiNote;         // MIDI ノート番号（0 = 休符、60 = C4）
    uint16_t durationBeats;    // 拍数（1.0 拍 = 256）
    uint8_t  velocity;         // 0–127
};

extern const ScoreEvent SCORE_DATA[];
extern const size_t     SCORE_LENGTH;
extern const uint16_t   SCORE_TOTAL_BEATS;
```

実体は `src/score_data.cpp` に配列リテラルで直書き：

```cpp
// 「きらきら星」抜粋（例示）
const ScoreEvent SCORE_DATA[] = {
    { /* beatOffset */ 0,   /* note */ 60, /* dur */ 256, /* vel */ 100 }, // C
    { /* beatOffset */ 256, /* note */ 60, /* dur */ 256, /* vel */ 100 }, // C
    { /* beatOffset */ 512, /* note */ 67, /* dur */ 256, /* vel */ 100 }, // G
    // ...
};
```

`SCORE_TOTAL_BEATS` は曲全体の長さ（`beatOffset` の最大値 + 最後の `durationBeats` ぶん）。

## 輪唱の「頭ずらし」

3 声輪唱では、各声部が **同じ旋律を一定拍ずらして** 入る。
本プロジェクトは `ProjectConfig.h` の `headRestBeats` で表現：

| ノード | `headRestBeats` | `INSTRUMENT_ID` | 入りタイミング |
|---|---|---|---|
| node_02 | 0 | 0（金管） | 拍 0 から開始 |
| node_03 | 8 | 1（木管） | 拍 8 から開始 |
| node_04 | 16 | 2（弦） | 拍 16 から開始 |

楽器ノードのロジック（疑似コード）：

```cpp
// 指揮者からの beatNo を自分の楽譜位置に変換
int32_t myBeat = beatNo - headRestBeats;
if (myBeat < 0) {
    // まだ自分の番じゃない（先頭の休符）
    return;
}
// 曲全体でループ
uint16_t scoreBeat = myBeat % SCORE_TOTAL_BEATS;
// scoreBeat に該当する ScoreEvent を引く
```

## 「PC を途中起動しても合流できる」仕組み

`beatNo` はリポジトリ起動から単調増加するが、楽譜は `% SCORE_TOTAL_BEATS` でループするので、
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
3. `SCORE_TOTAL_BEATS` を再計算
4. `headRestBeats` を曲構造に合わせて調整（4 声なら 0 / 8 / 16 / 24 など）

将来的に複数曲対応するなら：

- `SCORE_DATA_<song>[]` を複数並べて、`ProjectConfig.h` で選択
- CTRL に「曲 ID」フィールドを足して指揮者から切替
- などの方法がある（未実装）

## 楽器番号と音色の対応

`instrumentId` は NOTE パケットに載るが、楽譜データ側にも対応情報が必要：

- 各ノードの `ProjectConfig.h` の `INSTRUMENT_ID` で固定
- PC 側 `sound_lab/data/<id>.json` の倍音定義と対応

| `instrumentId` | 想定楽器 | JSON 例 |
|---|---|---|
| 0 | 金管 | `sound_lab/data/0.json` |
| 1 | 木管 | `sound_lab/data/1.json` |
| 2 | 弦 | `sound_lab/data/2.json` |

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
