---
title: アルゴリズム詳説 — 読み順ガイド
description: プログラム系の中核ロジックを掘り下げる章のインデックス。概要編を読んだ後、ここから順々に深掘りしていく
sidebar:
  order: 0
---

:::note[この章で分かること]
- 「アーキテクチャ」「コードを読む」の次に何を読むべきか
- 各深掘りページの位置づけ・前提・読了目安
- ロジックや数式が出てくる順番
:::

:::tip[読了目安]
**約 4 分**。この章自体は読み順の地図。それぞれの詳説は各 8〜15 分。
:::

## この章の位置づけ

ドキュメントは 3 層構成になっている。

| 層 | 目的 | 該当章 |
|---|---|---|
| **コンセプト** | 何を作るか、なぜ作るか | `intro/` `concept/` |
| **アーキテクチャ概要** | システムの構造と各モジュールの責務 | `architecture/` `code/` |
| **アルゴリズム詳説** | 個々のロジックを「式」「状態遷移」「コード断片」で深掘り | `deep-dive/` ← **この章** |

上の層を読んでから降りてくる前提で書いてある。先に
[全体図](/architecture/overview/) と
[Embedded-Module-Architecture](/architecture/ema/) を通しておくと、
ここで出てくる `SystemData` / `IModule` / `applyPattern()` の呼ばれ方が腑に落ちる。

## 推奨の読み順

順に縦読みすると、信号の流れ（センサ → 拍 → 通信 → 楽譜 → 合成）に沿って理解が積み上がる。

1. [拍検出アルゴリズム](/deep-dive/beat-detection/)
   IMU の生加速度から「拍が振られた瞬間」を取り出す全工程。
   LPF・動加速度ノルム・状態機械・経路長積分・不応期・閾値の根拠まで。
   前提: 高校数学（ベクトル・積分）と C++ の基本構文。

2. [時刻同期メカニズム](/deep-dive/time-sync/)
   5 台のマイコンの `millis()` を揃える仕掛け。EMA で
   オフセットを推定し、`playAtMasterMs` 先読みでネットワーク遅延を吸収する。
   前提: 拍検出を読み終えていること。

3. [UDP マルチキャスト](/deep-dive/udp-multicast/)
   なぜ TCP でなく UDP か、なぜ SoftAP か、マルチキャストアドレスの意味、
   IGMP の振る舞い。`OrcNetModule` の送受信実装も追う。
   前提: TCP/IP の超基本（IP/ポートを知っていれば OK）。

4. [バイナリパケット](/deep-dive/binary-packet.md)
   20 B 固定の CTRL/BEAT/NOTE がメモリ上でどう並ぶか。
   `#pragma pack`、エンディアン、`memcpy` での復元、`static_assert` の使い方。
   前提: C/C++ の構造体とポインタの基礎。

5. [楽譜進行ロジック](/deep-dive/score-progression/)
   `firedBeatNo` から楽譜インデックスを引く式、輪唱の `headRestBeats`、
   ループ再生（mod 演算）、細分音符の予約発火、PC 途中起動への耐性。
   前提: 拍検出と時刻同期を読み終えていること。

6. [加算合成エンジン](/deep-dive/additive-synthesis/)
   PC 側 Processing の音作り。基音 × 倍音の合成式、非調和性、
   ADSR エンベロープ、ボイスプール、スペクトル整形ノイズ、
   ビブラート / トレモロ。
   前提: 三角関数とサンプリングの基礎（44.1 kHz とは何か）。

7. [モジュール拡張ガイド](/deep-dive/module-extension/)
   新しい `IModule` を足したいときの手順と落とし穴。
   `SystemData` を拡張する／`ProjectConfig.h` の組み立て／
   3 フェーズに混ぜないコツ。
   前提: 1〜6 のどれか + EMA 章。

## 飛ばし読みの指針

| やりたいこと | 直接見るページ |
|---|---|
| 拍検出の閾値を調整したい | [拍検出アルゴリズム](/deep-dive/beat-detection/) §「閾値の根拠」 |
| 楽器がズレて鳴る | [時刻同期メカニズム](/deep-dive/time-sync/) §「ジッタの主因」 |
| 新しいパケット型を足したい | [バイナリパケット](/deep-dive/binary-packet/) §「拡張時のチェックリスト」 |
| 新しい曲を入れたい | [楽譜進行ロジック](/deep-dive/score-progression/) §「曲を差し替える」 |
| 楽器音を作りたい | [加算合成エンジン](/deep-dive/additive-synthesis/) §「JSON フォーマット」 |
| 新しいセンサを足したい | [モジュール拡張ガイド](/deep-dive/module-extension/) §「足し方ステップ」 |

## ここで使う表記の約束

- **コード断片**は実コードの抜粋。コメントの大半は実コードからそのまま引いている
- 「実装: `firmware/test_v2/.../foo.cpp`」と書かれていたら、そのファイルが SSOT
- 数式に出てくる記号は、各ページの冒頭の表で意味を明示する
- 「閾値は `ProjectConfig.h` の `logic_params` で調整」と書かれていたら、
  モジュール本体をいじってはいけない（EMA の原則）

次へ: [拍検出アルゴリズム](/deep-dive/beat-detection/)
