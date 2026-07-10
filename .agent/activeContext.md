# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- MOP4/MOP5 計測パイプラインの書き直しが完了（`b23c3e6` ファーム / `7bac5ef` スクリプト+README）。
  **実機未検証** — ユーザーが書き込んで再計測すればすぐテストできる状態。
- 新方式: 楽器ファームが BEAT 受理時に `M45R`、発火時に `M45F` を各 1 行出力
  （`partId,beatNo,playAtMasterMs,deviceMs,offsetMs,localMasterMs`、MOP_TEST=4/5 共通出力）。
  MOP4 = M45F の localMasterMs ノード間レンジ、MOP5 = 受信/発火 lateMs（lookahead 45ms 遅刻）に再定義。
  旧欠陥（M5I 二重記録・EVT BEAT 誤紐付け・ライブ計測の逐次ポーリング破綻・タブ/スペース不一致）は全て解消。
- 通常ビルドはバイナリ md5 一致を確認済み（#if MOP_TEST 完全隔離）。全ノード pio run SUCCESS
  （通常 + MOP_TEST=4 + MOP_TEST=5）。集計スクリプトはダミーログのセルフテストで期待値一致。

## 再計測の手順（ユーザー作業）

- `tools/verification/README.md` の「MOP4/MOP5 の再計測手順」に一連のコマンドあり。
  要点: `PLATFORMIO_BUILD_FLAGS="-DMOP_TEST=4"` で node_02〜06 に書き込み →
  `serial_logger.py` でログ収集 → `mop4_sync_error.py` / `mop5_comm_delay.py` に同じログを渡す。
- MOP5 の受信マージン統計は §4.3 の未解明の系統シフト（約 45〜55ms）の解明データにもなる。

## 次の一手

1. ユーザーの実機再計測（上記手順）。
2. 最終レポート・振り返り（7/15）で MOP_REPORT_20260709.md の方式・出典記載を訂正
   （根拠: `results/MOP45_latency_investigation_20260710.md` §3.3/§5-A）。再計測できれば新数値で置き換え。
3. 絶対片道遅延の実測（GPIO+ロジアナ / ping-ACK 同期）は将来課題として記載に留める。
4. 未コミットの node_02〜06 `platformio.ini`（SERIAL_DEBUG=1）はユーザーの変更として維持。触らない。

## 現フェーズで Read すべき設計書

- MOP4/5 の議論を続ける場合: `tools/verification/README.md`（新手順）、
  `tools/verification/results/MOP45_latency_investigation_20260710.md`（欠陥の経緯）を先に Read。
