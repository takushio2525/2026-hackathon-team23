# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **test_v3 修正 5 タスクを main 直で実施・push 済み**（2026-06-10、コミット 4 つ）。
  1. **ジャイロ 2D 表示削除**（`4b480a6`）: Processing の角速度プロット一式と
     OrcSender の Conducting 時ジャイロ透過を除去。navCursor/score は常に本来の値に。
  2. **メニューナビ重力基準化**（`9f9490c`）: 遅い LPF（α=0.01・dynNorm≥0.3 で凍結）で
     重力ベクトル推定 → 振り加速度を重力軸/水平面成分に分解、NAV_DECISION_WINDOW_MS
     (250ms) の窓積算で縦/横判定。NAV_VERT_DOMINANCE / NAV_LR_SIGN で実機調整可。
  3. **状態遷移デッドタイム**（`b656884`）: STATE_TRANSITION_DEADTIME_MS (1000ms) の間
     拍検出・ナビを無視（メニュー決定が 1 拍目に化ける／最終音符が Result 操作に化ける対策）。
  4. **4 台輪唱**（`80ec121`）: node_05 新設（partId=0x05/headRest=24/instrumentId=3=チューバ）。
     楽譜進行を CANON_CYCLE_BEATS=56（曲 32＋遅延 24）のサイクル窓方式に変更し、
     node_05 が 1 周終わるまで node_02 は次周回を始めない。Processing 4 声部表示。
     ドラム音色 (4_kick〜7_crash) は未使用。
- 全 6 ノード pio run SUCCESS・警告 0（node_03/04/05 同一サイズ）、processing-java --build 成功。

## 次の一手

- **実機検証（ユーザー作業）**: 実機確認リストは 2026-06-10 の最終報告参照。要点:
  ①ナビの縦/横判定と NAV_LR_SIGN の向き、②デッドタイム 1000ms の体感、
  ③4 台輪唱の終端（node_05 終了まで node_02 が待つか）、④Result の点数が見られるか。
- 楽器ノードの実機が 4 台ない場合、node_05 ファームは手持ちの UNO R4 に上書きして検証。

## 現フェーズで Read すべき設計書

- ゲームモード設計: `.agent/test_v3-game-design.md`
- プロトコル仕様: `.agent/api.md`（ジャイロ透過は廃止済み・輪唱サイクル追記済み）

## ユーザーの好み

- 大規模作業は計画を作ってから着手。短い指示は行間を読み，前提のズレを感じたら着手前に指摘。
- 実機未テストの .ino/.cpp に Claude 起点で変更を入れたらコンパイル確認まで＝upload はユーザー。
