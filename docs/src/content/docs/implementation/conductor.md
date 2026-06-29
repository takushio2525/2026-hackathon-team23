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
- BEAT：拍イベントごと。4連送し、45 ms先の`playAtMasterMs`を載せる

## Fallback

IMUまたはWi-Fiの異常でFallbackへ入り、直前のMenu／Conducting／Resultを保存します。
復旧後は保存した状態へ戻るため、常にMenuへ巻き戻るわけではありません。
