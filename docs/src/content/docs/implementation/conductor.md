---
title: 指揮者ノード
description: node_01の入力、状態、送信、ゲーム進行
---

## 入出力

| 区分 | 内容 |
|---|---|
| 入力 | GY-521の加速度・角速度、Wi-Fi状態 |
| ロジック | キャリブレーション、拍、BPM、ナビ、ゲーム採点、状態遷移 |
| 出力 | CTRL／BEAT、LED |

## `SystemData`

主な領域は`imu`, `orcNet`, `sender`, `led`, `beat`, `tempo`, `calibration`, `conductor`, `game`です。
モジュールのデータとアプリ状態を同じ構造体へ集約しています。

## 起動

1. SoftAP `OrchestraAP`を起動
2. IMUを初期化
3. 2秒静止して重力ノルムを校正
4. Menuへ移行
5. モード決定後に拍検出と送信を開始

## 送信

- CTRL：50 msごと。BPM、velocity、状態、モード、カーソル、目標BPM、得点
- BEAT：拍イベントごと。4連送し、220 ms先の`playAtMasterMs`を載せる

## 演奏中の復帰

productionでは、IMUの一時的な瞬断で演奏が止まることを避けるため、自動Fallback遷移を無効化しています。30秒間拍を検出しない場合はMenuへ戻り、次の演奏を曲頭から始めます。`Fallback`の状態値は通信互換性のため残っていますが、通常の操作では到達しません。
