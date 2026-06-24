# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **齋藤の発表用個人担当まとめPDFを作成・mainへ反映済み**。`work/saito/week10/saito_presentation_summary.pdf` は横長6ページで、楽譜データ設計、4声輪唱の開始拍・音域設定、ドラム／音色データ、作業の流れ、検証結果と残課題を扱う。
- 根拠は `docs/roles.md`、`work/saito/week5/`〜`week9/`、`work/saito/week9/作業ログ/`。実機で未確認の音量バランスは、未検証として明記した。
- PDFはAppleGothicを埋め込んで日本語表示を担保し、Popplerで全6ページをPNGへレンダリングしてレイアウトを目視確認済み。

## 次の一手

- 発表前に実機で4声＋ドラムを鳴らし、チューバを含む音量バランスを聴感確認する。

## 現フェーズで Read すべき設計書

- 担当範囲: `docs/roles.md`
- 楽譜方針: `docs/design/score_format.md`
- 個人成果: `work/saito/week9/README.md`、`work/saito/week9/作業ログ/作業ログ_25G1053.tex`

## ユーザーの好み

- 大規模作業は計画を作ってから着手。短い指示は行間を読み，前提のズレを感じたら着手前に指摘。
- 実機未テストの .ino/.cpp に Claude 起点で変更を入れたらコンパイル確認まで＝upload はユーザー。
