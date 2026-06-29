---
title: test_v2の記録
description: 3声輪唱と加算合成を成立させた検証版
---

test_v2は、指揮者1台と楽器3台で「きらきら星」の3声輪唱を行った版です。
楽譜内蔵、`instrumentId`付きNOTE、途中参加、音色JSONによる加算合成を導入しました。

## productionへ引き継いだもの

- EMAの3フェーズループ
- 20 B固定パケット
- マスタ時計と`playAtMasterMs`
- `beatNo`基準の楽譜位置計算
- Processingの複数ポート受信
- 音色JSONと加算合成

## productionで変わったもの

- 楽器3台から5台へ拡張
- かえるのうた4声＋ドラムへ変更
- 56拍の輪唱サイクルと細分音符を追加
- CTRLの予約4 Bをゲーム情報へ割り当て
- UIパケット、メニュー、採点、結果画面を追加
- 共通Processingタブを`pc_app/common/`へ分離

test_v2は参考用で、現在の書き込み手順には使用しません。
