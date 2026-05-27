# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **test_v2 の 3 台を実機書き込み済み**（2026-05-27、ユーザー指示で実施）。
  ポート割当:
  - DevKitC (CH343 ブリッジ、`/dev/cu.usbmodem5B7A1660211`) ← `node_01_devkitc`
    (RAM 14.0% / Flash 21.6%・esptool 12.80 秒・Hash verified)
  - Arduino UNO R4 WiFi シリアル 34B7DA64482C (location 1-1、
    `/dev/cu.usbmodem34B7DA64482C2`) ← `node_02` (声部 1、5.50 秒)
  - Arduino UNO R4 WiFi シリアル F412FAA08558 (location 0-1、
    `/dev/cu.usbmodemF412FAA085582`) ← `node_03` (声部 2、5.55 秒)
  これで test_v2 が DevKitC 指揮者 + Arduino 楽器 2 台 (声部 1・2) で起動可能。
  node_04 (声部 3) は今回未書き込み。
- **注意**: 楽器側 (`node_02` / `node_03`) の `platformio.ini` は `ac8c5ff デバック`
  以降 `-DSERIAL_DEBUG=1` のまま。このモードは **NOTE バイナリパケットを抑止**
  して人間可読テキストを Serial に流す調査用設定で、Processing
  (`pc_app/test_v2/orchestra_resynth/`) で音を鳴らすには `=0` に戻して再ビルド・
  再書き込みが必要。AGENTS.md「楽器ノードはデフォルト SERIAL_DEBUG=0」とは
  乖離した現状。

## 次の一手

- 動作モード次第で 2 系統:
  - **パケロス検証 (Serial ログ)**: 現状 `SERIAL_DEBUG=1` のまま、楽器ノード
    `pio device monitor` でテキストを読みパケロス率を XIAO 版 (`node_01`) と
    比較。改善が顕著なら ADR-0007 (DevKitC 移行) を起票。
  - **3 声輪唱で音を鳴らす**: `node_02`/`node_03` の `platformio.ini` を
    `-DSERIAL_DEBUG=0` に戻して再ビルド・再書き込み + Processing 起動。
    ただし `SERIAL_DEBUG=1` 設定の経緯 (`ac8c5ff`) を踏まえ、ユーザー判断で。
- いずれにせよ node_04 (声部 3) は別途書き込みが必要。今回は接続されていなかった。

## 現フェーズで Read すべき設計書

- 作業ログ本体: `work/shiozawa/work-0525/作業ログ0525/作業ログ0525.tex`、
  教員配布テンプレ `report/作業ログテンプレート/作業ログ.tex`。
- パケロス対策の技術背景: `.agent/architecture.md`（プロトコル設計節）、
  `.agent/api.md`（UDP マルチキャスト構造・CTRL/BEAT/NOTE 仕様）。
- ADR-0007（パケロス対策方針）は起票予定で未存在。本格起票時は
  `report/計画書_中間発表/23_計画書・設計書.tex` の ADR 既存節フォーマットを参照。

## draw.io ワークフロー（再修正時の参照）

- 書き出し: `/Applications/draw.io.app/Contents/MacOS/draw.io --export --format png
  --scale 2 --crop --border 14 --output 出力.png 入力.drawio`
- `.drawio` と `.png` を両方コミットする。`.png` を手で描き換えない。

## ガント図の整合基準（再修正時の参照）

- バー週数は **アロー図 `arrow.drawio` が正**: 110/120=各1.5週，210=0.5，220=1.0，
  230=0.5，240=1.0，250/260=各1.5，310/320=1.0，330=1.0，510=1.0週。図上 1週=66px。
- 絶対日付は授業スケジュール: 計画発表5/20・実装5/27〜・評価会6/24・発表会7/1。
- フェーズ工数は WBS 表: 設計3週・製造2週・テスト2週。
- クリティカルパスは逐次（階段配置）。240/250/260 は製造期間に並行・フロートあり。

## ユーザーの好み

- 大規模作業は計画を作ってから着手。設計章は大まかに（内容が伝われば可）。
- 図は draw.io に一本化（TikZ 廃止済み）。表が読みやすければ図を表化してよい。
- 短い指示は行間を読み，前提のズレを感じたら着手前に指摘する。

## 既知の論点

- 本体ページ数は **53頁が許容範囲**（§7「53〜54頁は許容範囲・無理な圧縮不要」）。
  図表が `[H]` 固定配置のため本文を数行足すと図の押し出しでページが増えやすい。
- 本体 .tex の句点は **「．」**（origin コミット 19edb91 で「。→．」一括統一済み）。
  本体 .tex を編集するときは句点を「．」で書く。.agent/ や .md 類は「。」のまま。
- CTRL state は現行ファーム整合で `0=Idle/1=Calibrating/2=Conducting/3=Fallback/4=ModeSelect`。
- ADR-0004 は楽器5台構成（金管4＋ドラム・全体6台）に改訂済み。改訂履歴を本文に明記。
- 状態遷移図はユーザー決定でシーケンス図を主図とし，節名「状態遷移図」は現状維持で決着（低⑪）。
  課題曲「かえるのうた」はチーム判断で確定（中⑦）。
- `.gitignore` に例外 `!report/計画書_中間発表/23_計画書・設計書.pdf` あり。本体 PDF はコミット対象。
- 図インベントリは全10点 draw.io（`_作業計画.md` §8）。
