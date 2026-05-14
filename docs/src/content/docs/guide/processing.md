---
title: PC アプリを動かす
description: Processing スケッチを開いて、シリアルポートを選び、音を出すまで
sidebar:
  order: 4
---

:::note[この章で分かること]
- Processing スケッチをどう開くか
- シリアルポートをどう選ぶか
- 音色 JSON を切り替える方法
:::

:::tip[読了目安]
**約 10 分**。
前提: Processing 4 をインストール済み（[必要なものをそろえる](/guide/setup/)）。
:::

## test_v2 用スケッチを開く

Processing 4 を起動し、メニューから:

```
ファイル → 開く →
  pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde
```

スケッチが開いたら **Run ボタン**（再生マーク）を押す。

## シリアルポートを選ぶ

スケッチを起動すると、ウィンドウ上部 or コンソールに利用可能なシリアルポートが
列挙される。例：

```
[0] /dev/cu.Bluetooth-Incoming-Port
[1] /dev/cu.usbmodem14101    ← node_02
[2] /dev/cu.usbmodem14201    ← node_03
[3] /dev/cu.usbmodem14301    ← node_04
```

**どれを選ぶか**: 楽器ノードのいずれか 1 つを選択する。
スケッチ内のコード冒頭で：

```java
int PORT_INDEX = 1;   // ← ここを変える
```

または `selectPort(1)` のような関数で指定する（実装による）。

> ⚠️ 現状のスケッチは **1 つの楽器ノードからしか NOTE を受け取らない**。
> 3 声を 1 台の PC で鳴らすには、楽器側の設計が「自分の声部 + 他声部の NOTE をまとめて
> シリアルに流す」になっている必要がある（test_v2 の現在の実装はこの形）。
> 詳しくは [pc_app の歩き方](/code/pc-app/) を参照。

## 音色 JSON

スケッチが読む音色定義は `sound_lab/data/*.json`（または `pc_app/test_v2/orchestra_resynth/data/`
配下の json）：

| ファイル | 楽器番号 | 想定楽器 |
|---|---|---|
| `0.json` | 0 | 金管 |
| `1.json` | 1 | 木管 |
| `2.json` | 2 | 弦 |

スケッチは NOTE パケットの `instrumentId` を見て、該当する JSON の音色で合成する。

### JSON の例

```json
{
  "name": "金管 1",
  "harmonics": [
    { "ratio": 1.0, "amp": 1.0 },
    { "ratio": 2.0, "amp": 0.6 },
    { "ratio": 3.0, "amp": 0.3 },
    { "ratio": 4.0, "amp": 0.15 }
  ],
  "adsr": { "attack": 0.02, "decay": 0.1, "sustain": 0.7, "release": 0.2 }
}
```

- `harmonics`: 倍音比と振幅のペア。`ratio` は基音に対する比、`amp` は 0〜1 の振幅
- `adsr`: エンベロープ。秒単位

### 新しい楽器を増やすには

1. `sound_lab/data/3.json` を作る（または既存をコピー）
2. `harmonics` を編集して目的の楽器に近づける
3. 該当の楽器ノードの `ProjectConfig.h` で `INSTRUMENT_ID = 3` に変更
4. ノードを書き直して、Processing を再起動

## 音が出ない・ずれるとき

| 症状 | 確認 |
|---|---|
| 何も鳴らない | シリアルポート選択が正しいか、Run が押されているか |
| パチパチノイズ | PC スピーカ音量を下げる、ADSR の attack を大きくする |
| 音が遅れる | Processing をフォアグラウンドに、他の重いアプリを閉じる |
| 一部の楽器だけ鳴らない | 楽器ノードの `instrumentId` と JSON ファイルが揃っているか |

詳しくは [よく出るトラブルと対処](/code/troubleshooting/) 参照。

## test_v1 用スケッチ

`pc_app/test_v1/orchestra_player/orchestra_player.pde` は C major 和音用の旧版。
test_v2 と排他なので、test_v1 firmware を使うときだけこちらを起動する。

## production 用スケッチ

`pc_app/production/example_sketch/example_sketch.pde` は素テンプレ。
本実装が test_v2 で安定してから取り込む。

## 音色を自分で作る（sound_lab）

`sound_lab/` 配下には、生楽器音の録音から倍音解析して JSON 化するパイプラインがある：

- `sound_lab/analyzer/`: Python スクリプト（FFT 解析）
- `sound_lab/processing/instrument_player/`: 単独試聴用 Processing スケッチ

実音録音から JSON を作る詳細は `sound_lab/README.md` を参照。

## 次に読むべきページ

- ログを読む → [シリアルモニタでデバッグする](/guide/debug/)
- Git で変更を保存する → [チームで Git を使う](/guide/git/)
- PC アプリのコード解説 → [pc_app の歩き方](/code/pc-app/)
