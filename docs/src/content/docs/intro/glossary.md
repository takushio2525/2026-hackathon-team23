---
title: 用語集
description: このサイトに出てくる専門用語を 1 行ずつ説明
sidebar:
  order: 3
---

:::note[この章で分かること]
- 各ページに出てくる専門用語の意味
- 略語が何の頭文字か
:::

:::tip[読了目安]
通読は不要。**詰まったときに戻ってくる辞書として** 使ってください。
:::

## ハードウェア

**XIAO ESP32-S3 Sense**
: Seeed Studio 製の指先サイズマイコンボード。本プロジェクトでは **指揮者ノード** に採用。
  Wi-Fi 内蔵で、USB Type-C 直挿しで書き込みできる。

**Arduino UNO R4 WiFi**
: Renesas RA4M1 を搭載した Arduino。本プロジェクトでは **楽器ノード** に採用。
  Wi-Fi モジュール（ESP32-S3）を内蔵し、`WiFiUDP` ライブラリが標準で使える。

**GY-521**
: MPU6050（IMU）を実装したブレイクアウト基板。指揮者ノードに外付けして使う。
  本体内蔵 IMU が性能不足だったため、外付けに切り替えた。

**IMU**
: Inertial Measurement Unit。加速度センサとジャイロセンサを組み合わせたもの。
  本プロジェクトでは加速度ノルムだけを使って拍を検出している。

**MPU6050**
: 6 軸 IMU（加速度 3 軸 + ジャイロ 3 軸）。I2C で通信する。

## 音楽用語

**指揮者（Conductor）**
: 拍とテンポを決める役。本プロジェクトでは `node_01` がこれに当たる。

**声部（Voice / Part）**
: 多声音楽で、各楽器が担当する独立した旋律。本プロジェクトの **test_v2 は 3 声**（`node_02〜04`）で輪唱を実装済み。
  **production 想定は 5 声**（`node_02〜06`、金管 4 ＋ ドラム 1。[ADR-0004](/decisions/0004-ensemble-structure/) 改訂版）。

**輪唱（Canon / Round）**
: 同じ旋律を一定拍ずらして重ねる演奏形式。「きらきら星」「かえるのうた」など。
  本プロジェクトの `test_v2` は 3 声輪唱を採用。

**主旋律 (Main Melody)**
: 曲の中心となる旋律。輪唱の場合、すべての声部が同じ旋律を歌う。

**MIDI ノート番号**
: 音高を数値で表す国際規格。60 = C4（中央のド）。本プロジェクトの NOTE パケットで使用。

**ベロシティ (Velocity)**
: MIDI における「打鍵の強さ」を表す値（0〜127）。本プロジェクトでは音量に対応。

**ADSR**
: Attack（立ち上がり）/ Decay（減衰）/ Sustain（持続）/ Release（リリース）の頭文字。
  音色エンベロープの定番モデル。Processing 側で実装している。

**倍音 (Harmonics)**
: 基音の整数倍の周波数成分。楽器の音色を決める主因。
  本プロジェクトでは `pc_app/test_v2/orchestra_resynth/data/*.json` に倍音比を定義する
  （`sound_lab/` は試作・分析の実験場で、完成後にコピーして使う運用）。

## 通信・プロトコル

**UDP**
: User Datagram Protocol。順序保証や再送を持たない代わりに低遅延な通信方式。
  本プロジェクトの主軸（[ADR-0002](/decisions/0002-udp-original-protocol/)）。

**マルチキャスト**
: 1 つのパケットを複数の受信者に同時配信する仕組み。本プロジェクトでは `239.0.0.1:5001`。

**SoftAP**
: Soft Access Point。マイコン自身が WiFi の親機になるモード。
  本プロジェクトでは指揮者ノードが `OrchestraAP` という SSID で親機になる。

**CTRL / BEAT / NOTE**
: 本プロジェクトの 3 種類のパケット。
  - **CTRL**: 指揮者 → 楽器、20 Hz で BPM と状態を流す
  - **BEAT**: 指揮者 → 楽器、拍ごと、`playAtMasterMs` 付き
  - **NOTE**: 楽器 → PC、発音情報（MIDI ノート + 楽器番号）

**`partId`**
: 楽器ノードの識別 ID。NOTE パケットに含まれる。test_v2 では `0x02`〜`0x04`（楽器 3 台）、
  production 想定では `0x02`〜`0x06`（楽器 5 台 = 金管 4 ＋ ドラム 1）。

**`instrumentId`**
: 音色 ID。PC 側は `pc_app/test_v2/orchestra_resynth/data/` 内の JSON を
  **ファイル名昇順で配列化** し、`instrumentId` を **その index** として参照する。
  ファイル名先頭の `0_`, `1_` は人間が並び順を把握するための慣例で、`<id>.json` 形式ではない。
  実体（2026-05 時点）: `0_organ.json` / `1_flute.json` / `2_bell.json` / `3_flute_tweaked.json`
  → `instrumentId = 0, 1, 2, 3` の順に対応。

**`playAtMasterMs`**
: 指揮者時計で「この時刻に発音せよ」と指示する値。ネットワーク遅延を吸収する仕組み。

## 同期・性能指標

**MOE / MOP / TPM**
: それぞれ Measure of Effectiveness（有効性指標）/ Measure of Performance（性能指標）/
  Technical Performance Measure（技術性能指標）。授業の評価フレームワーク。

**同期誤差**
: 楽器間で同じ拍を発音したときのズレ時間。本プロジェクトは ≤ 20 ms が目標
  （[ADR-0006](/decisions/0006-sync-error-moe-20ms/)）。

**マスタクロック**
: 同期の基準時計。本プロジェクトは指揮者ノードの `millis()` がマスタ。

## アーキテクチャ

**EMA（Embedded-Module-Architecture）**
: 塩澤が用意した組み込み向け設計パターン。3 フェーズループ + `IModule` + `SystemData` +
  `ProjectConfig`。本プロジェクトの firmware 全面に適用（[ADR-0005](/decisions/0005-firmware-embedded-module-architecture/)）。

**`IModule`**
: EMA の抽象基底クラス。`init` / `updateInput` / `updateOutput` / `deinit` を持つ。

**`SystemData`**
: ノード内の全モジュールが共有する状態構造体。モジュール間通信は必ずこれを介する。

**`ProjectConfig`**
: ピン配置・閾値・WiFi 設定など、ノード固有の定数を集約するヘッダ。

**3 フェーズループ**
: `loop()` を「入力 → ロジック → 出力」の順で構成する EMA の原則。

## 開発環境

**PlatformIO**
: VS Code 拡張として使えるマイコン用ビルドツール。`pio run` でビルド、`-t upload` で書き込み。

**Processing**
: 元はビジュアルアート向けの Java ベース言語。本プロジェクトでは PC 側の音色合成に使用。

**`platformio.ini`**
: PlatformIO の設定ファイル。各ノードの `firmware/.../platformio.ini` にある。

**`pio run -d <path>`**
: 指定パスのプロジェクトをビルドする PlatformIO コマンド。

**Docker**
: コンテナ仮想化ツール。本プロジェクトでは LaTeX 報告書のコンパイル環境に使用。

**latexmk**
: LaTeX のビルド自動化ツール。`docker run ... latexmk main.tex` で報告書を生成。

## Git

**clone**
: リモートリポジトリを手元にダウンロードすること。`git clone <url>`。

**commit**
: 変更をリポジトリに記録すること。本プロジェクトのフォーマットは `[種別] 概要`。

**pull / push**
: リモートと同期すること。`pull` は取り込み、`push` は送り出し。

**rebase**
: ブランチの歴史を整える操作。本プロジェクトでは `git pull --rebase` で衝突を防ぐ用途。

**PR（Pull Request）**
: GitHub 上でブランチをマージしてもらう申請。本プロジェクトはレビューが必要な変更のときだけ作る。

**ADR（Architecture Decision Record）**
: 設計判断の記録。本サイトの [意思決定の記録](/decisions/0001-template/) に 7 件。
