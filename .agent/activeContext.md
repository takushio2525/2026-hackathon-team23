# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- MOP5 分析レポートの対処案を **production ファームに実装済み・全ノードビルド緑・push 済み**（実機未検証）。
  - 案1: `beatLookaheadMs` 45→220ms（node_01 + node_01_devkitc、`35f70f0`）
  - 案2: SoftAP ビーコン間隔 100→50TU 短縮試行（common/lib OrcNetModule、`6642646`）。
    **IDF 4.4 (arduino-esp32 2.0.17) の `wifi_ap_config_t` に `dtim_period` フィールドが無い**（IDF 5.x で追加）
    ため DTIM=1 の明示は不可。また 50TU はヘッダ記載レンジ (100〜60000) 外で実機拒否の可能性あり
    → 拒否時は既定 100TU のままフォールバック（SERIAL_DEBUG=1 で `[NET] softAP beacon_interval` ログが出る）。
  - 案4 (min フィルタ): 楽器の時計同期を EMA → 窓 2000ms の最大 offset サンプル追従へ（`86c39f4`）。
    スナップ 1 パケット追従は維持。`OrcReceiverConfig` から `clockSyncEmaAlpha/Dup` を削除し
    `clockSyncWindowMs` を新設（node_02〜06 の ProjectConfig 追従済み）。
- 通常 + MOP_TEST=4 の両ビルドで production 全 7 ディレクトリ（node_01/devkitc/02〜06）SUCCESS 確認済み。

## 次の一手

1. **実機再計測（master + ユーザー）**: 書き込み対象は `firmware/production/` の
   node_01（実機は DevKitC なら `node_01_devkitc`）+ node_02〜06。手順は `tools/verification/README.md`。
   集計時は `mop5_comm_delay.py --lookahead 220` を指定（既定 45 のまま、スクリプトは未変更・変更はスコープ外）。
   見るポイント: (a) 指揮者起動ログで beacon 50TU が OK/REJECTED か、(b) BEAT 到着周期が 204.8→~51ms に
   縮んだか、(c) 受信マージンが +220ms 側に戻り発火 lateMs ≈0 になったか、(d) M45R の offsetMs が
   最小遅延線に張り付いたか（min フィルタ効果）。
2. 案2 が効いていれば lookahead 220ms は過剰 → 70ms 程度へ短縮を検討（ProjectConfig コメントに明記済み）。
3. 最終レポート・振り返り（7/15）に「原因特定 → 対策 → 実測で改善確認」を記載
   （MOP_REPORT_20260709.md の方式・出典訂正も従来どおり必要）。
4. 未コミットの node_02〜06 `platformio.ini`（SERIAL_DEBUG=1）はユーザーの変更として維持。触らない。

## 現フェーズで Read すべき設計書

- MOP4/5 の議論・再計測を続ける場合: `tools/verification/results/MOP5_systematic_shift_analysis_20260710.md`（原因分析）、
  `tools/verification/README.md`（計測手順）、`firmware/production/common/lib/OrcReceiverModule/OrcReceiverModule.cpp`
  （min フィルタ実装）を先に Read。
