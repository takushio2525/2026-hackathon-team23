---
title: 楽譜進行ロジック
description: beatNoから56拍サイクルと4声の位置を計算し、Q8音価と細分音符を発火する
sidebar:
  order: 5
---

## 実体

- 金管進行：`firmware/production/node_02〜05/src/applyPattern.cpp`
- 金管楽譜：各ノードの`score_data.h/.cpp`、32イベントで同一
- ドラム楽譜：`firmware/production/node_06/src/score_data.cpp`、56イベント
- 固有値：各ノードの`ProjectConfig.h`

## なぜローカルカウンタではなくbeatNoか

各楽器が「受信したらindexを1増やす」方式では、1回の欠損が以後ずっと残ります。
productionでは指揮者の絶対拍番号から毎回位置を再計算します。

```text
位置 = f(beatNo, headRestBeats, cycleLength)
```

この方式ならBEAT 10を落としても、BEAT 11で全楽器が11の位置へ戻ります。

## `ScoreEvent`

```cpp
struct ScoreEvent {
  uint16_t beatAt;
  uint8_t noteNumber;
  uint8_t velocity;
  uint16_t durationQ8;
  uint8_t flags;
  uint8_t subNote;
  uint8_t subVelocity;
  uint16_t subOffsetQ8;
  uint16_t subDurationQ8;
};
```

| field | 意味 |
|---|---|
| `beatAt` | 人間向け1始まり拍番号。進行計算には使わない |
| `noteNumber` | MIDI、0なら休符 |
| `velocity` | 楽譜固有の強さ |
| `durationQ8` | 256=1拍 |
| `flags` | bit0=NoteOn、bit2=休符・タイ継続 |
| `sub*` | 拍途中の追加音符 |

## Q8音価

```text
beats = durationQ8 / 256
durationMs = beats × 60000 / BPM
```

100 BPMの例：

| `durationQ8` | 拍 | 長さ |
|---:|---:|---:|
| 64 | 0.25 | 150 ms |
| 128 | 0.5 | 300 ms |
| 256 | 1 | 600 ms |
| 512 | 2 | 1200 ms |

`bpm < 10`の異常値では既定100 BPMを使います。

## 金管4声と頭ずらし

| node | part | headRest | instrument |
|---|---|---:|---:|
| 02 | トランペット | 0 | 0 |
| 03 | ホルン | 8 | 1 |
| 04 | トロンボーン | 16 | 2 |
| 05 | チューバ | 24 | 3 |

4台は同じ32拍のかえるのうたを持ちます。違いは頭の休符と音色です。

## 56拍サイクル

最後の声部は24拍遅れて32拍演奏するため：

```text
CANON_CYCLE_BEATS = 24 + 32 = 56
```

毎拍の位置：

```text
cyclePos = (beatNo - 1) % 56
local = cyclePos - headRestBeats
```

判定：

```text
local < 0       入り前なので休む
0 <= local < 32 kScore[local]を処理
local >= 32     自分の演奏終了、サイクル末尾まで休む
```

先頭声部も32拍後すぐに周回せず、最後の声部が終わる56拍まで待ちます。

## 具体例

beatNo=25の場合、`cyclePos=24`です。

| node | local | 動作 |
|---|---:|---|
| 02 | 24 | 曲の25拍目 |
| 03 | 16 | 曲の17拍目 |
| 04 | 8 | 曲の9拍目 |
| 05 | 0 | 曲の1拍目 |
| 06 | 24 | ドラム25拍目 |

これが4声すべてが重なり始める瞬間です。

## 細分音符

BEATは4分音符単位ですが、かえるのうたには8分音符があります。

```text
subDelayMs = subOffsetQ8 / 256 × 60000 / BPM
```

`subOffsetQ8=128`なら半拍後です。主イベント処理時に`pendingSubAtMs=now+subDelayMs`を保存し、
2 msループの先頭で到来を確認します。

主音符と細分音符は別の`noteOut`／`noteOutSub`へ書き、同一周期での上書きを防ぎます。

## velocity合成

```text
velocityOut = scoreVelocity × ctrlVelocity / 127
```

楽譜内のアクセントと指揮者の全体強弱を掛け合わせ、0〜127へ制限します。
現在の指揮者velocityは64固定ですが、将来ジェスチャ強弱を追加しても楽譜を変更せず反映できます。

## 休符とタイ

`flags & 0x04`または`noteNumber==0`なら主音符を発火しません。
ただしsubNoteは独立に確認するため、拍頭が休符でも裏拍だけ鳴らす表現が可能です。

## ドラム譜

node_06は頭ずらし0、56イベントをすべて使用します。

- 36：キック
- 38：スネア
- 49：クラッシュ
- 0/8/16/24/32/40/48拍：主にクラッシュで区切り
- 52〜54拍：スネアフィル
- 55拍：最後のクラッシュ

ドラムの`instrumentId=4`はドラム経路を選ぶための値で、具体的な音色はnoteNumberが決めます。

## 曲を変更する手順

1. 1拍1イベントで金管譜を作る
2. 4ノードの`score_data.cpp`を同じ内容にする
3. 最後の声部遅延を含めてサイクル長を再計算
4. 4金管とドラムの`CANON_CYCLE_BEATS`を揃える
5. 8分音符を`sub*`へ変換
6. MIDIとinstrumentIdをPC側で確認
7. `tools/canon_sim/`で窓と重なりを机上検証
8. 全ノードで実機確認

## 不変条件

- `beatAt`を進行の真値にしない
- 全金管のイベント数と内容を揃える
- サイクル長をノードごとに変えない
- 配列外では鳴らさず、勝手に32拍modへ戻さない
- 欠損後の位置は直前indexではなく新しいbeatNoから決める

## デバッグ

ログへ`beatNo`、`cyclePos`、`local`、note、sub予約時刻を出し、同じ拍で各声部が期待位置か確認します。
PCの途中起動テストでは、起動直後のNOTEが現在のbeatNoに対応するかを見ます。

関連：[楽譜と輪唱](/system/score/) / [楽器main](/firmware/main-instrument/)
