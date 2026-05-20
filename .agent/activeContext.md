# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **結合レポート全面リライト**（大規模・複数セッション）。`report/計画書_中間発表/` 配下に
  計画書・設計書を再構築する。実行計画の正典は `report/計画書_中間発表/_作業計画.md`。
- **Phase 0〜3・Phase 4A・4B 完了**。次は **Phase 4C（Ch1（計画書）へのゲーム反映と図の作り直し）**。

## 直近の観点

1. **正典は `report/計画書_中間発表/_作業計画.md`**。再開時は §4-2（ゲーム方針）・§6 Phase 4C・
   §7・§8・§9 を読む。
2. 現状: 本体 `23_計画書・設計書.tex` は Ch1〜3 執筆済み・ゲーム機能を Ch2/Ch3 へ織り込み済み・
   Processing 記述拡充済み・Ch4 は骨格のみ。`latexmk -lualatex` 成功・**47 ページ**・
   Overfull/Underfull 0・未定義参照なし。
3. **Phase 4C のスコープ**（_作業計画 §6 Phase 4C）:
   - Ch1 の目的・成果物・対象範囲・リスク管理にゲームモードを反映。
   - `fbs.drawio` に「ゲーム進行・採点（F7）」機能群，`pbs.drawio` に「ゲーム UI」を追加し再描画。
     WBS 表にゲーム実装タスクを追加し，`arrow`・`gantt` を追従。全 PNG を再書き出し。
4. **Phase 4B の成果**（Phase 4C の前提）: Ch3 §3.3.6 を「PC 側ソフトウェア（Processing）」へ
   改題・増量（フレーム同期／Serial スレッド分離＋受信キュー／Voice 管理／音色合成／JSON 外部化）。
   §3.3.7「画面とゲーム UI の設計」新設（ModeWait／Playing／メトロノーム／Result，表 `tab:pc-screens`）。
   Ch2 `tab:state-pc` を 6 状態（PortSelect/ModeWait/Playing/Result/Muted/Error）へ更新。
   新ラベル `sec:pc-software`・`sec:pc-ui`・`tab:pc-screens`。CTRL は楽器ノードが専用 PC へ中継。
5. **Phase 4A の成果**: 2 モード構成を Ch2/Ch3 へ織り込み済み。CTRL ペイロードは `mode`（1B）・
   `targetBpmQ8`（2B）・`score`（1B・0–100）。指揮者状態に ModeSelect。F7「ゲーム進行・採点」
   ＝node\_01。メトロノームガイド＝固定フェードスケジュール（強度 1.0→0，通信不要）。
6. **全図 draw.io 化・TikZ 廃止**（_作業計画 §8）。残る TikZ は 2 図（class-diagram／flow）。
   Phase 4D で draw.io 化し preamble の `tikz` を除去。Phase 4B では図を新設せず表で対応。
7. **ページ上限 = 60 未満**（50 以内が望ましいが超過可。2026-05-21 ユーザー指示）。現状 47 頁。
8. draw.io 書き出し: `/Applications/draw.io.app/Contents/MacOS/draw.io --export --format png
   --scale 2 --crop --border 14 --output 出力.png 入力.drawio`。`.drawio` と `.png` を両方コミット。
9. 編集対象は `report/計画書_中間発表/` 配下のみ。ページオフセット: PDF 頁 = 印刷頁 + 6。

## 次の一手

- **Phase 4C に着手**（_作業計画 §6 Phase 4C）。本体 `.tex` の Ch1 全文と `fig/` の各 `.drawio`
  （`fbs`・`pbs`・`arrow`・`gantt`）を Read。
- Ch1: 目的・成果物・対象範囲・リスク管理にゲームモードを反映。
- 図: `fbs.drawio` に「ゲーム進行・採点（F7）」を追加，`pbs.drawio` に「ゲーム UI」を追加して
  再描画。WBS 表にゲーム実装タスクを追加し，`arrow`・`gantt` を追従。全 PNG を再書き出し。
- ビルド成功確認 → コミット → push → activeContext/progress 更新。

## 現フェーズで Read すべき設計書

- **必ず最初に**: `report/計画書_中間発表/_作業計画.md`（§4-2・§6 Phase 4C・§7・§8・§9）
- Phase 4C 実行時: 本体 `23_計画書・設計書.tex` の Ch1 全文，`fig/fbs.drawio`・`pbs.drawio`・
  `arrow.drawio`・`gantt.drawio`

## ユーザーの今回の好み

- **大規模作業は計画を作ってから着手**。`/clear` しつつフェーズ単位で順次実行。
- 設計章は「事細かに書かず大まか，内容が伝われば可」。図は draw.io に一本化（TikZ 廃止）。
- 表が読みやすければ図を表化してよい。長い API 表・コード例は要点の散文＋小表へ圧縮。

## 既知の論点

- ゲームモードの設計骨子は _作業計画 §4-2，Phase 4A・4B の成果は progress.md に確定記録。
- 前回レビューで判明した本体 `.tex` の不整合 6 件（同期誤差の根拠／`ref:beat` 未引用／NOTE
  `gate`／CPU 時間／magic エンディアン／相互参照・用語・数値）は _作業計画 §9 に集約。Phase 4D で消化。
- `.agent/api.md` の CTRL 予約 4B は未修正（現行ファームの事実）。ゲーム拡張は報告書側の将来設計。
- ADR-0004（5 台構成）は当時の記録なので書き換えない。
