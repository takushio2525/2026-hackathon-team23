---
title: 音色JSON
description: instrumentIdとdataディレクトリの対応
---

## 読み込み規則

`pc_app/production/orchestra_resynth/data/`のJSONをファイル名昇順で読み込み、
配列indexを`instrumentId`として使います。番号接頭辞は順序を固定するために必要です。

| ID | ファイルの音色 | 用途 |
|---:|---|---|
| 0 | trumpet | node_02 |
| 1 | horn | node_03 |
| 2 | trombone | node_04 |
| 3 | tuba | node_05 |
| 4 | kick | node_06のドラム経路 |
| 5 | snare | ドラム素材 |
| 6 | hi-hat | ドラム素材 |
| 7 | crash | ドラム素材 |

node_06の実際の打楽器選択は`noteNumber`で行うため、NOTEの`instrumentId`は常に4です。

## 主な内容

- 倍音ごとの周波数比と振幅
- ADSR
- 倍音別エンベロープ
- 非調和性
- ビブラート／トレモロ
- 残差ノイズのパラメータ

JSONを追加・並べ替えたときは、全楽器ノードの`instrumentId`との対応を必ず確認してください。
