# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **DevKitC 派生ファームを test_v2 にも追加**（2026-05-27、
  `firmware/test_v2/node_01_devkitc/`）。test_v1/node_01_devkitc でユーザーが実機
  検証してパケロスが顕著に改善したため (= XIAO ESP32-S3 Sense の外付け IPEX
  アンテナ接触不良が主因と判明)、test_v2 でも同じ派生を用意して本番運用候補と
  する。`firmware/test_v2/node_01` をディレクトリごとコピー (.pio/.vscode 除外)、
  差分はビルド設定とコメントのみ:
  - `platformio.ini`: board=`esp32-s3-devkitc-1` / USB CDC マクロ無効化 /
    `upload_protocol = esp-builtin` をコメントアウトして PIO デフォルト (UART 側
    esptool) に変更。
  - `include/ProjectConfig.h`: 冒頭・I2C ピン・StatusLedConfig のコメントを
    DevKitC 用に更新。WS2812 (GPIO48) は `digitalWrite` で光らないため
    `activeLow=false` に変更 (test_v1 と同様の理由)。
  - `README.md`: 差分表・配線・ビルド/書き込み手順・LED 注意点・切り分け実験
    プランを DevKitC 用に書き直し。
  - `src/` `lib/` `include/SystemData.h` はバイト単位で同一 (拍検出・テンポ
    推定・3 声輪唱の頭ずらしロジックは未変更)。
  `pio run` で RAM 14.0%・Flash 21.6%・警告 0・11.54 秒でビルド通過。実機書き
  込み・XIAO 版との比較検証はユーザー側 (CLAUDE.md ルール)。
- 直前: test_v1/node_01_devkitc を作成 (e5a09fd・2026-05-27) → ユーザー実機検証
  で改善確認 → 本ターンで test_v2 にも展開。

## 次の一手

- ユーザー側で `firmware/test_v2/node_01_devkitc` を ESP32-S3-DevKitC-1 (PCB
  内蔵アンテナ N 版) に書き込み、楽器 3 ノード (node_02〜04) + Processing
  `pc_app/test_v2/orchestra_resynth/` 起動で 3 声輪唱を回して NOTE 受信ログ
  からパケロス率を XIAO 版と比較。test_v1 と同じく改善するはず。
- DevKitC 採用が確定したら ADR-0007（パケロス対策方針＝DevKitC 移行）を起票。

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
