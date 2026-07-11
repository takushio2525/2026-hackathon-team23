# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- MOP5 対策後の実機再計測（7/10 夜、183 拍 × 5 ノード）の**評価レポートを作成済み**:
  `tools/verification/results/MOP5_countermeasure_eval_20260710.md`。要点:
  - 受信側は解決（遅刻率 45.4→1.9%）。ただし**すべて lookahead 220ms の効果**で、
    ビーコン 50TU（`6642646`）は `-> OK` 応答でも**バースト周期 204.8ms を全く縮めていない**。
  - min フィルタ（`86c39f4`）は設計どおり動作。表示 lateMs が真の遅刻の下限としてほぼ正直になった。
  - 新現象①（発火 lateMs p95 47.3ms）②（MOP4 尾 p95 46ms）は**同一原因**:
    バースト到着から位相 ~120〜165ms で楽器ループが回らない「周期ストール」（実挙動、全 5 ノード共通）。
    ストール非暴露群の発火 late p95 は 9ms。50TU 化で新規発生した可能性あり（前回ログでは非観測域）。

## 次の一手

1. **ビーコン 50TU 設定ブロックは撤去済み**（OrcNetModule.cpp、通常 + MOP_TEST=4 で全 7 ノード
   ビルド SUCCESS）。**指揮者（node_01 または node_01_devkitc）だけ再書き込み** → 同条件
   （lookahead 220 + min フィルタ、集計 `--lookahead 220`）で再計測（ユーザー作業）。
   見るポイント: 発火位相 120〜165ms の空白帯が消えたか / 発火 lateMs p95 が ≈9ms（MOP5 PASS 圏）
   まで下がったか / MOP4 p95 が ≈11〜20ms へ戻ったか。楽器側は書き込み不要（変更は指揮者経路のみ）。
2. ストールが残るなら MOP8 要領のループハートビート計測でストール粒度・窓位置を確定 → 発火判定の
   ループ順序入替を検討（レポート §5(b)-2）。
3. lookahead は 220ms 維持（周期不変のため 70ms 化は不可と確定）。min フィルタ窓 2000ms も維持。
4. 最終レポート・振り返り（7/15）には「バースト配送の原因特定 → lookahead+min フィルタで
   受信解決・計測正直化 → 残るストールの特定」の流れで記載（`MOP5_countermeasure_eval` §5(c) 参照）。
5. 未コミットの node_02〜06 `platformio.ini`（SERIAL_DEBUG=1）はユーザーの変更として維持。触らない。

## 現フェーズで Read すべき設計書

- MOP5/ストール調査を続ける場合: `tools/verification/results/MOP5_countermeasure_eval_20260710.md`（今回の評価）、
  `results/MOP5_systematic_shift_analysis_20260710.md`（対策前の原因分析）、
  `firmware/production/common/lib/OrcNetModule/OrcNetModule.cpp`（撤去対象の 50TU ブロック）を先に Read。
