# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **test_v3 3重大修正を実施**（2026-06-08、main 直プッシュ）。
  1. **マスターリセット復帰高速化**: UI_TIMEOUT_MS 5000→2000ms、onScreenChange() に
     Waiting 遷移時のゲーム状態リセット（gameStartMs/lastMetroBeat/uiScore/metroClicks）を追加。
  2. **指揮棒モーション 2D グラフ化**: OrcSenderModule で Conducting 時に navCursor/score バイトを
     IMU dynAcc[0]/[1] × 40 の int8 加速度データで上書き。Processing 側は state==Conducting で
     buf[14]/[16] を signed int8 として解釈し、右上に 170×170 の 2D XY プロット（80 フレーム
     リングバッファ、clip 描画、NOTE パルス演出）。Menu/Result は従来通り navCursor/score。
     node_01_devkitc にも /bin/cp -f で同期。
  3. **楽譜 8 分音符修正**: score_data.cpp の 8 分音符 durationQ8 120→128、subDurationQ8 120→128
     に修正（3 ノード同一）。120 だと 0.47 拍で subOffset=0.5 拍との間に 0.03 拍のギャップが生じ
     途切れて聞こえていた。128=0.5 拍でギャップ解消。MIDI 音程自体は正しかった。

## 次の一手

- **実機検証（ユーザー作業）**: 全5ノードを upload して動作確認。
  - 指揮棒 2D プロットの加速度スケール（×40）が適切か実機で要確認。
  - 8 分音符のギャップ解消で「ゲロゲロ」が滑らかに聞こえるか確認。
  - マスターリセット後 2 秒で Waiting に戻りメニューに復帰するか確認。
- 追加の画面改善やパラメータ調整があればユーザー指示で対応。

## 現フェーズで Read すべき設計書

- ゲームモード設計: `.agent/test_v3-game-design.md`
- プロトコル仕様: `.agent/api.md`（UI type=4 表）

## ユーザーの好み

- 大規模作業は計画を作ってから着手。短い指示は行間を読み，前提のズレを感じたら着手前に指摘。
- 実機未テストの .ino/.cpp に Claude 起点で変更を入れたらコンパイル確認まで＝upload はユーザー。
