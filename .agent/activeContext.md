# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **塩澤の個人最終報告書を新規作成し完成**（`work/shiozawa/最終報告書/`、43 ページ）。
  - 構成: はじめに / システム全体 / 担当部分の設計と実装（EMA・プロトコル・拍検出・
    時計同期 min フィルタ・発音予約）/ 計画からの変更点と理由 / 評価（MOP 全 9 項目）/
    生成 AI の利用と検証 / おわりに / 参考文献 10 件 / 付録（担当分中核ソース 4 本全文）。
  - 数値の正本: `tools/verification/results/MOP_REPORT_20260711.md` と `mop2/evaluation.md`
    に全一致。図はスライド用グラフ 3 枚 + system-overview を `fig/` へコピーして流用。
  - ビルド: Docker (`ghcr.io/paperist/texlive-ja:debian`) latexmk で EXIT=0・
    未定義参照 0・Overfull 0。**配布 pckgs.sty はヒラギノ/stix2/roboto 依存のため、
    ローカルコピーのみ原ノ味 (haranoaji) 構成へ差し替え**（テンプレ原本は不変）。
    付録ソースコピーは listings が処理できない「×」「§」を「x」「Sec.」へ置換（付録に明記）。
  - チェックリスト全項目の確認結果: `work/shiozawa/最終報告書/チェックリスト確認.md`。

- 発表用の docs（presentation/overview・faq）と MOP2 検証プログラムは前ターンまでに完了済み。

## 次の一手

1. 最終報告書の提出（提出フォームへのアップロードはユーザー作業）。
   他メンバーの個人報告書は各自作成。
2. 発表直前には `docs/src/content/docs/presentation/` の要点・想定問答を確認する。
3. docs の公開（GitHub Pages 等)はユーザー判断待ち。

## 現フェーズで Read すべき設計書

- MOP数値の根拠: `tools/verification/results/MOP_REPORT_20260711.md`
  （MOP2 だけは別記録: `tools/verification/results/mop2/evaluation.md`）
- 最終報告書の本文・チェックリスト: `work/shiozawa/最終報告書/`
