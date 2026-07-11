# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **成果発表向けのdocs更新を完了**。既存のproduction解説を最終実装・最終MOP検証へ同期し、発表用の入口を追加した。
  - 新設: `docs/src/content/docs/presentation/overview.md`（30秒説明・発表の流れ）と
    `presentation/faq.md`（想定問答・根拠・限界・答え方）。サイドバーとトップから到達できる。
  - 同期仕様: 45ms/時計EMAの旧説明を、220ms発音予約・2秒窓の最小遅延に近い時計同期へ更新。
  - 検証: MOP4（中央値7ms、平均10.8ms、最大65ms、20ms以内90.8%）とMOP5（予約受信遅刻率45.4%→3.1%）を、限界も含めて更新。
  - Fallbackの自動遷移がproductionでは無効である点も、状態遷移・指揮者・LEDの説明へ反映。
  - `cd docs && npm run build` SUCCESS（86ページ）。

## 次の一手

1. 発表直前には[発表の要点](../docs/src/content/docs/presentation/overview.md)を読み、
   [想定問答](../docs/src/content/docs/presentation/faq.md)の「短く答える」だけを確認する。
2. 公開は未定。GitHub Pages等への公開設定・デプロイはユーザー判断待ち。

## 現フェーズで Read すべき設計書

- MOP数値の根拠: `tools/verification/results/MOP_REPORT_20260711.md`
- 発表用の説明と質問対策: `docs/src/content/docs/presentation/`
