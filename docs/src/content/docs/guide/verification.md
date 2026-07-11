---
title: 評価・検証を行う
description: 最終MOP結果と、productionを実機ログで検証する方法
---

## 最終結果（2026-07-11）

productionの最終構成は、指揮者1台・楽器5台・PC5接続で測定しました。MOP4とMOP5は、PCへ届いた時刻ではなく、**各楽器が発火した時点**のデバイス側ログで測り直しています。

| 項目 | 最終結果 | 現在の扱い |
|---|---:|---|
| MOP1 拍検出 | 120/120、100.0% | PASS |
| MOP2 音階精度 | 未検証 | 録音評価が今後の課題 |
| MOP3 楽譜一致 | 誤ノート0件 | PASS |
| MOP4 楽器間同期 | 中央値7 ms、平均10.8 ms、最大65 ms | 最大値基準ではFAIL、実質達成として受け入れ |
| MOP5 発音予約の成立 | 受信遅刻率3.1%（対策前45.4%） | 指標を再定義して受け入れ |
| MOP6 テンポ追従 | 最大1.2拍 | PASS |
| MOP7 起動時間 | 最大2.3秒 | PASS |
| MOP8 入力処理 | 最大0.72 ms | PASS |
| MOP9 パケット欠落 | 0.0% | PASS |

:::note[MOP4とMOP5の正直な読み方]
MOP4は173拍中90.8%が20 ms以内で、中央値は7 msでしたが、周期ストールと見られる外れ値がありました。MOP5は「生の片道遅延30 ms以内」ではなく、予約発音の品質に直接関係する「予定時刻までに受信できるか」へ指標を改めています。背景と答え方は[想定問答](/presentation/faq/)を参照してください。
:::

## 何を測るか

| 項目 | 主な見方 |
|---|---|
| 拍検出 | 期待拍数に対する検出率 |
| 楽譜一致 | 楽器が送った音符と期待譜面の差 |
| 楽器間同期 | 同じ拍の発火時刻の最速・最遅差 |
| 発音予約 | BEAT受信時に予約時刻へ間に合った割合 |
| テンポ・起動・入力処理 | 目標値に対する最大値 |
| パケット欠落 | 連番と拍番号の欠落数 |

## ログ収集

```bash
cd tools/verification
python3 -m pip install -r requirements.txt
python3 scripts/serial_logger.py
```

測定では楽器を`SERIAL_DEBUG=1`にします。この状態ではNOTEバイナリを停止するため、Processingで演奏するときは`0`へ戻します。

## 解析

```bash
python3 scripts/analyze.py logs/test_YYYYMMDD_HHMMSS.log \
  --expected-bpm 120 --test-duration 60
```

MOP4/MOP5の最終方式では、楽器が出す`M45R`（BEAT受信）と`M45F`（発火）のログを使います。PC側USBの到着順に依存しないため、同期品質をより直接的に確認できます。

詳しい根拠と全データは`tools/verification/results/MOP_REPORT_20260711.md`にあります。
