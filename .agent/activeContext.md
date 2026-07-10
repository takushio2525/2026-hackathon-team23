# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- 7/10 の MOP4/MOP5 再計測（204 拍 × 5 ノード）で出た **系統シフト −42.8ms / 発火 p95=78ms 遅刻の原因分析が完了**。
  レポート: `tools/verification/results/MOP5_systematic_shift_analysis_20260710.md`。
- **根本原因**: SoftAP のマルチキャストが省電力バッファリングで **204.8ms（2 ビーコン）周期のバースト配送**
  になっており、45ms lookahead が構造的に不足。シフト −42.8ms 自体は「EMA が 20Hz CTRL の新鮮な
  サンプルに支配され、BEAT だけ平均 ≈102ms 古い」という鮮度非対称の産物（定常モデルで ±6ms 閉合）。
- 重要な含意: **M45 の lateMs は推定時計基準で真の遅刻を ~40-55ms 過小評価**。真の発火遅刻は
  平均 ≈+80 / p95 ≈+145ms（下限推定）。MOP4 が良好なのは遅延が完全共通モードのため（矛盾ではない）。
- 集計スクリプト（mop5_comm_delay.py）にバグなし → 修正・再集計は不要だった。ファーム変更もなし。

## 次の一手

1. 最終レポート・振り返り（7/15）で MOP5 の数値に「真の遅刻は p95≈145ms」併記 + 原因（バースト配送）を記載。
   MOP_REPORT_20260709.md の方式・出典記載の訂正も従来どおり必要（`MOP45_latency_investigation_20260710.md` §3.3）。
2. 対処（ファーム修正・実装未着手、ユーザー判断待ち）: 案1 = beatLookaheadMs 45→220ms（1 定数・即効）、
   案2 = 指揮者で esp_wifi_set_config により beacon_interval 100→50TU + dtim_period=1（根治寄り・要実機）。
   詳細はレポート §8。
3. 未コミットの node_02〜06 `platformio.ini`（SERIAL_DEBUG=1）はユーザーの変更として維持。触らない。

## 現フェーズで Read すべき設計書

- MOP4/5 の議論を続ける場合: `tools/verification/results/MOP5_systematic_shift_analysis_20260710.md`（原因分析・最新）、
  `tools/verification/results/MOP45_latency_investigation_20260710.md`（計測欠陥の経緯）、
  `tools/verification/README.md`（計測手順）を先に Read。
