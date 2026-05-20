# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **結合レポート全面リライト**（大規模・複数セッション）。`report/計画書_中間発表/` 配下に
  **50 ページ以内** の計画書・設計書を再構築する。実行計画の正典は
  `report/計画書_中間発表/_作業計画.md`。
- **Phase 0・1・2 完了**（Phase 2 は 2026-05-21）。次は **Phase 3（Chapter 3「システムの詳細設計」）**。

## 直近の観点

1. **正典は `report/計画書_中間発表/_作業計画.md`**。再開時は §11 と §6 Phase 3 を読む。
2. 現状: 本体 `report/計画書_中間発表/23_計画書・設計書.tex` は Ch1・Ch2 執筆済み・Ch3〜4 は骨格のみ。
   `latexmk -lualatex` 成功・**29 ページ**（Ch1=11・Ch2≈8）・Overfull/Underfull 0・未定義参照なし。
3. **ベースライン = 97 ページ**。目標 ≤50。現在 29 ページ。
4. **楽器台数は 5 で確定**（2026-05-21 ユーザー決定）。最終構成 = 指揮者 1（XIAO ESP32-S3）＋
   楽器 5（金管 4＋ドラム、node\_02〜06、partId 0x02–0x06）＋PC 5（各楽器に 1 対 1）。
5. draw.io 図ワークフロー確立済み: Claude が `.drawio` 直書き → CLI で書き出し
   `/Applications/draw.io.app/Contents/MacOS/draw.io --export --format png --scale 2 --crop --border 14
   --output 出力.png 入力.drawio`。`.drawio` と `.png` は両方 `fig/` に置きコミット。
6. **編集対象は `report/計画書_中間発表/` 配下のみ**。`計画書結合/` 等は参照専用。本体 PDF も同一コミット。
7. **ページ予算は柔軟運用**。≤50 確定は Phase 4。各 Phase 末にページ数を報告。

## 次の一手

- **Phase 3（Chapter 3「システムの詳細設計」）に着手**。入力（_作業計画.md §6 Phase 3）:
  `23_計画書・設計書_24G1075.tex` 行 1210–3056、`.agent/api.md`、`.agent/architecture.md`。
- Block A/B を Block B 土台に統合。**最大の削減対象** — 長い API 表・コード例（`lstlisting`/`verbatim`）は
  要点の散文＋小図表に置換。`ProjectConfig`/`SystemData` の全項目列挙は代表値のみ。
- 図: クラス図・処理フロー・HW 接続図を整理。崩れていれば draw.io 化、正常なら TikZ 据え置き。
- 楽器台数 5・partId 0x02–0x06・楽器名は金管系 で統一（論点は Phase 2 で解消済み）。

## 現フェーズで Read すべき設計書

- **必ず最初に**: `report/計画書_中間発表/_作業計画.md`（§6 Phase 3・§7・§8・§9・付録 A）
- Phase 3 実行時: `.agent/api.md`（プロトコル・SystemData・ProjectConfig の正典）、
  `.agent/architecture.md`、`23_` 行 1210–3056

## ユーザーの今回の好み

- **大規模作業は計画を作ってから着手**。`/clear` しつつフェーズ単位で順次実行。
- 設計章は「事細かに書かず大まか、内容が伝われば可」。図は draw.io へ移行。
- 表が読みやすければ図を表化してよい。

## 既知の論点

- **楽器名/音色・台数は確定済み**（金管 4＋ドラム、楽器 5 台、partId 0x02–0x06）。Phase 2 で解消。
- **AGENTS.md・architecture.md**: 本番想定の楽器台数を 2026-05-21 に 4→5 へ更新済み。
- **api.md・ADR-0004**: 「楽器 4 台」「partId 0x02–0x05」「PC 1 台」のまま未追従。Phase 3 着手時に
  api.md の partId 範囲を要確認。ADR-0004 は記録なので新 ADR での追補が筋（チーム判断）。
- **整合チェックリスト**は計画書 §9 に集約。Phase 4 で全消化する。
