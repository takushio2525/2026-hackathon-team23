# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **個人最終報告書をサンプル準拠へ全面改稿済み**（`work/shiozawa/最終報告書/`，コミット `c39497b`・`ff7c235`）。
  - 章構成: はじめに→システム概要→実装→評価方法と結果→考察→おわりに→付録A（ソース）/B（関数別フローチャート）。
  - 図22枚（実測グラフ12・説明図/FC 9・計画時ガント流用1）・表11・61ページ。
  - MOP5 は「再定義」枠組みを廃し当初定義で未達報告 + 考察で原因・対策。エンタメアンケート43件の節を新設。
  - Docker latexmk エラー0・未定義参照0・Overfull 0。全数値は results/ 正本と再集計一致。全12文献の実在・引用内容を Web で確認済み。

## 次の一手

1. 報告書の提出はユーザー作業（提出要領・締切の最終確認）。
2. 追加の推敲要望（文量調整・図の差し替え）があれば対応。
3. グラフ再生成は `fig/make_report_graphs.py`（venv: `tools/verification/.venv`）。

## 現フェーズで Read すべき設計書

- 報告書本文: `work/shiozawa/最終報告書/main.tex`
- 数値の正本: `tools/verification/results/MOP_REPORT_20260711.md`・`results/mop2/evaluation.md`
- アンケート: `work/shiozawa/最終報告書/data/entertainment_survey_team23.csv`
