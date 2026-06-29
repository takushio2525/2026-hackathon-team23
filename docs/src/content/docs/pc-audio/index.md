---
title: PCアプリ・音声処理
description: production のProcessingアプリ、共有モジュール、音声解析を現行コードどおりに案内する
sidebar:
  label: 読み順ガイド
  order: 0
---

PC側は、楽器ノードから受けたNOTEを再合成し、node_02から受けたUI状態に応じて
画面を切り替えます。音色JSONを作るオフライン解析もこの章で扱います。

実行本体は `pc_app/production/orchestra_resynth/`、再利用する実装の原本は
`pc_app/common/` です。productionスケッチ内の同名タブは共有ファイルへのsymlinkです。

## 現行構成

```text
node_02〜06
  │ USB Serial 115200 bps
  │ NOTE type=3（全楽器）/ UI type=4（node_02）
  ▼
SerialCore
  ├─ ポートごとのmagic同期
  └─ 20 B完成 → packetQueue
          ▼
orchestra_resynth.pde
  ├─ OrcProtocolでNOTE/UIを復号
  ├─ stateとmodeから画面を決定
  └─ NOTEをAudioManagerへ渡す
          ├─ instrumentId 0〜3 → InstrModel + SynthVoice
          └─ instrumentId 4   → DrumEngine
                                  ▼
                           Minim / 44.1 kHz / 512 samples
```

## ファイルと責務

| ファイル | 責務 | 詳細 |
|---|---|---|
| `orchestra_resynth.pde` | production固有状態、画面遷移、入力、描画 | [メイン構造](/pc-audio/resynth-main/) |
| `OrcProtocol.pde` | 定数、NOTE/UIパーサ、状態・画面ID | [PC側プロトコル](/pc-audio/orc-protocol/) |
| `SerialCore.pde` | 複数ポート、magic同期、キュー投入 | [SerialCore](/pc-audio/serial-handling/) |
| `AudioManager.pde` | JSONロード、音色選択、発音・回収 | [AudioManager](/pc-audio/audio-manager/) |
| `InstrModel.pde` | 音色JSONを合成用配列へ変換 | [InstrModel](/pc-audio/instr-model/) |
| `SynthVoice.pde` | 金管1音分の加算合成UGen | [ResynthVoice](/pc-audio/resynth-voice/) |
| `DrumEngine.pde` | 4ドラム音色、録音・合成フォールバック | [DrumEngine](/pc-audio/drum-engine/) |
| `SharedUI.pde` | フォント、背景、パネル、波形 | [SharedUI](/pc-audio/shared-ui/) |
| `OrcLogger.pde` | カテゴリ付きログと画面ログ | [OrcLogger](/pc-audio/orc-logger/) |

## productionの固定値

| 項目 | 値 |
|---|---:|
| ウィンドウ | 1000 × 560 |
| 描画 | 90 fps |
| 音声 | stereo、44.1 kHz、512 samples |
| 金管同時発音 | 24 voice |
| ドラム合成同時発音 | 12 voice |
| Serial | 115200 bps |
| パケット | 20 B |
| UIタイムアウト | 2000 ms |
| ゲーム長 | 56拍 |
| ガイド | 0〜15拍=100%、16〜31拍で減衰、32拍以降=0% |

値を変える前に、マイコン側と共有する定数かPCだけの値かを区別してください。
`GAME_LENGTH_BEATS`、ガイド境界、状態値、パケットoffsetは両側の整合が必要です。

## 音色の対応

JSONはファイル名昇順で読み込まれ、`instrumentId` がそのindexを選びます。

| ID | ファイル接頭辞 | 音色 | PCでの処理 |
|---:|---|---|---|
| 0 | `0_` | trumpet | 加算合成、+12半音 |
| 1 | `1_` | horn | 加算合成、移調なし |
| 2 | `2_` | trombone | 加算合成、-12半音 |
| 3 | `3_` | tuba | 加算合成、-12半音 |
| 4 | `4_`以降 | drum | note番号で4音色を選択 |

ドラムJSONはkick、snare、hi-hat、crashの順です。`AudioManager` は
録音波形があれば `AudioSample`、なければ倍音＋Noise＋ADSRへフォールバックします。

## 画面の決まり方

PCは手動で「メインUI」や「アナライザ」を設定しません。

1. type=4 UIを受ける、またはpartId `0x02` のNOTEを受ける → メイン操作UI
2. それ以外のNOTEを最初に受ける → アナライザ
3. メインUIでは `state` と `mode` からMenu、Free Play、Game Play、Resultを導出
4. UIが2秒途絶える → マスター再起動とみなしWaitingへ戻し、全音停止

詳しくは [メイン構造](/pc-audio/resynth-main/) と [SharedUI](/pc-audio/shared-ui/) を参照してください。

## 推奨の読み順

### リアルタイム経路

1. [設計判断](/pc-audio/design/)
2. [NOTE/UIから音と画面まで](/pc-audio/signal-flow/)
3. [メイン構造](/pc-audio/resynth-main/)
4. [PC側プロトコル](/pc-audio/orc-protocol/)
5. [SerialCore](/pc-audio/serial-handling/)
6. [AudioManager](/pc-audio/audio-manager/)
7. [InstrModel](/pc-audio/instr-model/)
8. [ResynthVoice](/pc-audio/resynth-voice/)
9. [DrumEngine](/pc-audio/drum-engine/)

### UIと運用

10. [SharedUI](/pc-audio/shared-ui/)
11. [OrcLogger](/pc-audio/orc-logger/)

### 音色生成

12. [解析パイプライン](/pc-audio/analyzer-overview/)
13. [倍音・非調和性・残差ノイズ](/pc-audio/analyzer-harmonics/)
14. [基音・ADSR・変調](/pc-audio/analyzer-modulation/)

### 差し替え

15. [別方式へ拡張する](/pc-audio/extending/)

## 仕様と実装例の境界

守る必要があるのは、マイコンと接続する20 Bプロトコル、状態値、`instrumentId`の対応です。
音色JSONは解析と合成の内部契約です。加算合成、Processing、Minim、画面デザインは
現行実装であり、接続契約を維持すれば差し替えられます。

## 関連ページ

- システム全体: [構成](/system/overview/)
- 20 Bの詳細: [バイナリパケット](/deep-dive/binary-packet/)
- 合成数式: [加算合成](/deep-dive/additive-synthesis/)
- ファーム側NOTE: [NoteSenderModule](/firmware/note-sender/)
