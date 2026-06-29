---
title: PCアプリ概要
description: Processing production版の構成と責務
---

## 本体と共通タブ

本体は`pc_app/production/orchestra_resynth/orchestra_resynth.pde`です。
音声、通信、UIの共通実装は`pc_app/common/`にあり、スケッチフォルダからシンボリックリンクで参照します。

| 共通タブ | 役割 |
|---|---|
| `OrcProtocol.pde` | パケット定数とパース |
| `SerialCore.pde` | 複数ポートと受信キュー |
| `AudioManager.pde` | 発音、停止、ボイス管理 |
| `SynthVoice.pde` | 金管の加算合成 |
| `DrumEngine.pde` | 打楽器合成 |
| `InstrModel.pde` | JSON読み込み |
| `SharedUI.pde` | 共通描画部品 |
| `OrcLogger.pde` | 構造化ログ |

## 処理ループ

1. Serialコールバックが20 Bパケットをキューへ入れる
2. `draw()`がキューを取り出してNOTE／UIを処理
3. 画面を状態から決定
4. 音声ボイスとメトロノームを更新
5. 90 fpsでUIを描画

受信スレッドでMinimや描画を直接操作せず、描画スレッドへ集約しています。
