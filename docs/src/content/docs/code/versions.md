---
title: test_v1 / test_v2 / production の差分
description: 3 つのバージョンを横並びで比較する
sidebar:
  order: 4
---

:::note[この章で分かること]
- 3 つのバージョンが何を担当しているか
- どこに新しい変更を入れるべきか
- 過去の検証結果を参照したいときどこを見るか
:::

:::tip[読了目安]
**約 5 分**。
:::

## 概要表

| 項目 | `test_v1` | `test_v2` | `production` |
|---|---|---|---|
| **状態** | 完了・凍結 | **現行・開発中** | 雛形のみ |
| **曲** | C major 圏内の和音 | きらきら星 3 声輪唱 | （未定） |
| **コード規模** | 小（各 node 100〜200 行） | 中（各 node 300〜500 行 + 楽譜） | 極小（雛形のみ） |
| **EMA 適用** | ✅ 適用 | ✅ 適用 | ❌ 未適用 |
| **指揮者ハードウェア** | Arduino UNO R4 WiFi（内蔵 IMU） | XIAO ESP32-S3 Sense + GY-521 | （未定） |
| **楽器ハードウェア** | Arduino UNO R4 WiFi | Arduino UNO R4 WiFi | Arduino UNO R4 WiFi |
| **楽譜内蔵** | ❌ なし | ✅ あり（`score_data.cpp`） | ❌ |
| **輪唱の頭ずらし** | ❌ | ✅（`headRestBeats`） | ❌ |
| **`instrumentId`** | ❌ | ✅（NOTE に追加） | ❌ |
| **拍番号同期** | ❌ | ✅（途中起動対応） | ❌ |
| **初期テンポ** | 120 BPM | 100 BPM | — |
| **デフォルト `SERIAL_DEBUG`** | 楽器も 1（テキスト混在） | 楽器は 0（バイナリのみ） | — |
| **PC アプリ** | サイン波 1 個 | 倍音 JSON + ADSR | 雛形のみ |
| **本実装の対象** | ❌ | ✅ | （将来） |

## どこに変更を入れるか

| やりたい変更 | 入れるべき場所 |
|---|---|
| 新しい曲を試す | `test_v2/node_0{2,3,4}/src/score_data.cpp` |
| 拍検出の閾値調整 | `test_v2/node_01/include/ProjectConfig.h` |
| 新しい楽器（音色）を追加 | `sound_lab/data/<id>.json` + 該当ノードの `INSTRUMENT_ID` |
| 通信プロトコル拡張 | `test_v2/common/lib/OrcProtocol/` |
| 新しいモジュール | `test_v2/common/lib/<NewModule>/` or `test_v2/<node>/lib/<NewModule>/` |
| 本番ハードに移植 | test_v2 で安定 → `production/` に取り込む |

## 共通層の独立性

3 段階の `common/lib/` は **互いに独立** している：

```
firmware/test_v1/common/lib/   ← test_v1 専用
firmware/test_v2/common/lib/   ← test_v2 専用
firmware/production/?          ← まだない
```

これにより：

- test_v2 のプロトコル拡張が test_v1 を壊さない
- test_v1 のコードを参照しやすい（完了状態の参照実装）
- production を本格化する際に、test_v2 → production にコピーで取り込める

将来 production が動き出したら、`production/common/lib/` を新設して
test_v2 から成熟したライブラリを取り込む流れ。

## test_v1 のコードを読む価値

test_v1 は **完了して動いている** ので、

- 同期の最小実装がどんな形か知りたい
- 「test_v2 で増えた複雑さ」を引き算したい
- 拍検出の素朴版を参考にしたい

ときに有用。新しい機能の検討時は test_v2 と並べて比較するといい。

## production が手薄な理由

[ADR-0005](/decisions/0005-firmware-embedded-module-architecture/) より：

> `firmware/production/` 配下は PlatformIO 新規プロジェクト相当の素テンプレで、
> EMA はまだ適用していない（テスト系で十分に検証してから取り込む運用）

「結合検証が済んでから production に取り込む」運用なので、現状は
雛形だけ用意して、test_v2 が安定したら一気に取り込む計画。

## pc_app の対応関係

| firmware | 対応する pc_app |
|---|---|
| `firmware/test_v1/` | `pc_app/test_v1/orchestra_player/` |
| `firmware/test_v2/` | `pc_app/test_v2/orchestra_resynth/` |
| `firmware/production/` | `pc_app/production/example_sketch/` |

**バージョンを跨いで動かしてはいけない**。
test_v1 firmware + test_v2 PC アプリの組み合わせは NOTE フォーマットが違うので
動かない（test_v2 は `instrumentId` が追加されている）。

## まとめ

- **今動かす**: `test_v2`
- **昔の検証結果を見る**: `test_v1`
- **これから本格化**: `production`（test_v2 が安定したあと）

## 次に読むべきページ

- 現行コードを読む → [firmware の歩き方](/code/firmware/) / [pc_app の歩き方](/code/pc-app/)
- 困ったら → [よく出るトラブルと対処](/code/troubleshooting/)
- アーキの全体像 → [全体図](/architecture/overview/)
