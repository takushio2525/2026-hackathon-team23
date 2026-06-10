# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **test_v3 品質向上ブランチ `shiozawa-test_v3-polish` を作成し PR を提出**（2026-06-10、7 コミット）。
  机上レビューで見つけたバグ修正＋ロジック改善＋UI 改善。マージはまだ（実機検証待ち）。
  1. **node_01 状態遷移修正**: Menu/Result に IMU 喪失監視追加（Fallback へ、復帰は
     sStateBeforeFallback で元の状態へ）。Menu→Conducting で resetTempoTracking()
     ＋ beatNo=0 リセット（毎セッション曲頭から）。Fallback 遷移時 sLastBeatMs=0。
  2. **楽器クロック同期スナップ**: offset サンプルが現 EMA から 1000ms 超飛んだら即時採用
     （clockSyncSnapThresholdMs）。指揮者リセットを 1 パケットで追従。スナップ時は
     pending/hasFirstBeat/lastBeatNo も破棄。OrcReceiver/SystemData/applyPattern を
     3 楽器ノード完全同一に統一（差分は ProjectConfig と UiRelay の有無のみに）。
  3. **Processing**: ジャイロ軌跡の重複 push 修正（蓄積を handlePacket 30Hz 側へ、
     LEN 120→90）、Conducting 外で軌跡非表示＋画面離脱でクリア。全画面に接続ステータス
     （役割/UI 鮮度/声部別 NOTE インジケータ）＋ヘルプパネル整備。
  4. **ビルド設定**: 指揮者 2 ノード -std=gnu++17（inline 変数警告 8 件解消）。
  5. **ドキュメント**: README 2 本を test_v3 実態へ全面書き直し、api.md を現行値に同期
     （ジャイロ透過・30Hz・beatLookahead 30・スナップ閾値）。

## 次の一手

- **PR レビューと実機検証（ユーザー作業）**: 全 5 ノード upload して動作確認後にマージ。
  実機確認リスト（PR 本文）: ①Menu→演奏開始で曲頭から＆BPM 100 リセット、②指揮者リセット
  後の楽器追従が 1 秒以内か、③Menu 中に IMU 線を抜いて Fallback 点滅→復帰で Menu に戻るか、
  ④ジャイロ軌跡の滑らかさ（30Hz 化後）、⑤声部インジケータの動き。
- 仕様判断の保留点（最終報告に列挙済み）: ゲーム途中中断ジェスチャなし／ライブスコア未送出
  ／アナライザ FFT 未実装は要件外として見送り。

## 現フェーズで Read すべき設計書

- ゲームモード設計: `.agent/test_v3-game-design.md`
- プロトコル仕様: `.agent/api.md`（UI type=4 表・ジャイロ透過注記を更新済み）

## ユーザーの好み

- 大規模作業は計画を作ってから着手。短い指示は行間を読み，前提のズレを感じたら着手前に指摘。
- 実機未テストの .ino/.cpp に Claude 起点で変更を入れたらコンパイル確認まで＝upload はユーザー。
