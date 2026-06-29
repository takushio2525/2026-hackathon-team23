---
title: トラブルシュート
description: productionで起きやすい問題と確認箇所
---

## ビルドできない

- PlatformIOの対象ディレクトリが`firmware/production/node_XX`か確認
- node_01は`espressif32@6.10.0`、楽器は`renesas-ra`を使う
- `lib_extra_dirs = ../common/lib`を消していないか確認

## 楽器がWi-Fiへ接続しない

- SSIDとパスワードが`OrchestraAP` / `orchestra2026`で一致しているか
- 指揮者のSoftAPが起動しているか
- 全ノードがチャネル6を使っているか

## 拍を拾わない／二重に拾う

- キャリブレーション中に指揮棒を動かしていないか
- GY-521のSDA/SCLとアドレス`0x68`を確認
- `BEAT_DYN_THRESHOLD_G`、不応期、経路長はまとめて挙動を確認する

## 音が鳴らない

- `SERIAL_DEBUG=0`か
- Processingとシリアルモニタが同じポートを奪い合っていないか
- NOTE受信数と`instrumentId`を確認
- Spaceで全停止した後にテスト音が鳴るか確認

## メニューが出ない

- node_02のUSBポートを開いているか
- UIパケットが1秒以内に届いているか
- 指揮者がMenu状態まで進んでいるか

## ドラム音がおかしい

node_06は`instrumentId=4`でドラム経路へ入り、`noteNumber`でキック・スネア・クラッシュを選びます。
音色JSONの番号だけでドラム種類を判断しないでください。
