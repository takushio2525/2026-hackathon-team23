---
title: 三段階開発
description: test_v1 → test_v2 → production の使い分け
sidebar:
  order: 6
---

:::note[この章で分かること]
- なぜ 3 つのバージョンが並列に存在するか
- 新しい変更はどこに入れるか
- production が完成するのはいつか
:::

:::tip[読了目安]
**約 3 分**。
:::

`firmware/` 配下は 3 段階に分かれている：

| 段階 | パス | 目的 | 状態 |
|---|---|---|---|
| `test_v1` | `firmware/test_v1/` | 最初の同期検証（C major 和音） | 完了・参照用 |
| `test_v2` | `firmware/test_v2/` | きらきら星 3 声輪唱 + 楽器番号 | **現行・開発中** |
| `production` | `firmware/production/` | 本番想定の素テンプレ | 雛形のみ・EMA 未適用 |

## test_v1（最初の同期検証）

- **目的**: 「指揮者から拍を投げると、楽器が音を出す」が同期するかの検証
- **曲**: C major 圏内の和音（C-E-G）を 4 ノードで分担
- **状態**: 完了。今後の変更は基本入れない（参照用に残置）
- **コード量**: 各ノード 100〜200 行程度の最小実装

ここで以下を確立：

- EMA の 3 フェーズループパターン
- UDP マルチキャストでの 1 対多配信
- 指揮者 → 楽器の時刻同期

## test_v2（現行・推奨）

- **目的**: 楽曲性とエンタメ性を盛り込んだ実装の本命
- **曲**: 「きらきら星」3 声輪唱
- **状態**: 開発中（**新しい変更は基本これに入れる**）
- **コード量**: 各ノード 300〜500 行 + 楽譜データ

test_v1 からの主な変更点：

1. **楽譜内蔵**: `score_data.cpp` に「きらきら星」全曲を持つ（3 台同一内容）
2. **輪唱の頭ずらし**: `headRestBeats` で 0 / 8 / 16 拍ずれて入る
3. **`instrumentId` 追加**: NOTE に楽器番号、PC 側で音色切替
4. **拍番号同期**: 楽器が指揮者の `beatNo` から自分の楽譜位置を計算
   → PC を曲の途中で起動しても合流できる
5. **初期テンポ 100 BPM**: 1 拍目から音が出る（2 拍目で簡易テンポ確定）
6. **シリアルデバッグ切替**: 楽器は `SERIAL_DEBUG=0` でバイナリのみ送出

## production（本番想定）

- **目的**: 結合検証後の本実装の置き場
- **状態**: 素テンプレ（EMA 未適用、各 node が `pio` 新規プロジェクト相当）
- **コード量**: ほぼ空

[ADR-0005](/decisions/0005-firmware-embedded-module-architecture/) で
「テスト系で十分に検証してから取り込む」と決めた運用に従う。
test_v2 で 4 声化・強弱・ビブラート等が安定したら production に取り込む。

## バージョン使い分けのフロー

```
1. 新しいアイデアを試したい
   ↓
2. test_v2 で実装・検証
   ↓
3. 実機で 3 台同期確認、同期誤差 ≤ 20 ms
   ↓
4. production に取り込む（最終工程）
```

途中で構造を大きく変えたいなら `test_v3/` を新規に切ることも検討する。

## ディレクトリ構成（簡略）

```
firmware/
├── test_v1/
│   ├── common/lib/      ← test_v1 専用の共通層
│   ├── node_01/         ← 指揮者
│   ├── node_02/         ← 楽器 1
│   ├── node_03/         ← 楽器 2
│   └── node_04/         ← 楽器 3
├── test_v2/
│   ├── common/lib/      ← test_v2 専用の共通層
│   ├── node_01/         ← 指揮者（XIAO ESP32-S3 Sense + GY-521）
│   ├── node_02/         ← 楽器 声部 1（Arduino UNO R4 WiFi）
│   ├── node_03/         ← 楽器 声部 2
│   └── node_04/         ← 楽器 声部 3
└── production/
    ├── node_01/         ← 雛形のみ
    ├── node_02/
    ├── node_03/
    ├── node_04/
    └── node_05/         ← ドラム想定（未実装）
```

共通層は **バージョンごとに独立** している。
これは「test_v2 の変更が test_v1 を壊さない」「production が安定するまで test は自由に
壊せる」を担保するため。

## ハードウェアの違い

| ノード | test_v1 | test_v2 |
|---|---|---|
| node_01（指揮者） | Arduino UNO R4 WiFi（内蔵 IMU） | **XIAO ESP32-S3 Sense + GY-521** |
| node_02〜04（楽器） | Arduino UNO R4 WiFi | Arduino UNO R4 WiFi |

test_v1 で内蔵 IMU の性能不足が判明したため、test_v2 で指揮者だけ XIAO + 外付け IMU に
切り替えた。楽器側は UNO R4 WiFi のまま（送受信に内蔵 IMU は不要）。

## pc_app も 3 段階

`pc_app/` も同じ 3 段階構成：

| 段階 | パス | 内容 |
|---|---|---|
| test_v1 | `pc_app/test_v1/orchestra_player/` | 和音を再生するシンプル版 |
| test_v2 | `pc_app/test_v2/orchestra_resynth/` | 倍音 JSON + ADSR + `instrumentId` 切替 |
| production | `pc_app/production/example_sketch/` | 素テンプレ |

## 次に読むべきページ

- 全体図 → [全体図](/architecture/overview/)
- 設計パターン → [Embedded-Module-Architecture](/architecture/ema/)
- コードを実際に読む → [firmware の歩き方](/code/firmware/)
