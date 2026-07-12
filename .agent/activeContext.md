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

- **MOP2（音階誤差）の検証プログラムを新規作成し PASS を確認**（唯一 N/A で残っていた項目）。
  `tools/verification/scripts/mop2_pitch_error.py`。Processing の加算合成
  （`SynthVoice/InstrModel/AudioManager.pde`）を Python へ忠実移植し、現在の楽器 JSON と
  発音方法で鳴るはずの波形を合成 → 基音を推定 → 平均律と比較する（実機・録音は不要）。
  - 結果: 全 24 音（4 楽器 × 6 音）の平均 |誤差| **0.737 cent**・最大 **1.907 cent** で
    基準 3.6 cent に対し PASS。誤差の正体は **`harmonics[n=1].ratio` が 1.0 でないこと**
    （ホルン 0.9989 → −1.91 cent、トランペット 0.9995 → −0.87 cent）。
    非調和性 `inharmonicity_b` の寄与は +0.04〜+0.08 cent で無視できる。
    誤差は音高によらず一定の系統オフセット（平均＝中央値＝最大）。
  - 記録: `results/mop2/evaluation.md`（CSV/summary は .gitignore 対象）。

## 次の一手

1. 発表直前には[発表の要点](../docs/src/content/docs/presentation/overview.md)を読み、
   [想定問答](../docs/src/content/docs/presentation/faq.md)の「短く答える」だけを確認する。
2. 公開は未定。GitHub Pages等への公開設定・デプロイはユーザー判断待ち。
3. スライド用グラフは同体裁 3 枚が揃った状態（平均=青棒・中央値=白抜き◇・最大=赤マーク・
   合格範囲=緑帯・短いタイトルのみ・16:9 大フォント）:
   - MOP5 `results/graphs/mop5_fire_delay_by_node_slide.png`（ジッタ吸収なし vs あり）
   - MOP4 `results/graphs/mop4_sync_error_slide.png`（各拍の最速 vs 最遅）
   - MOP2 `results/graphs/mop2_pitch_error_slide.png`（楽器別の音階誤差。誤差ばらつきが
     小さいため中央値◇・最大赤マークは削除し「音階誤差」の青棒 1 本＋緑帯のみ）

## 現フェーズで Read すべき設計書

- MOP数値の根拠: `tools/verification/results/MOP_REPORT_20260711.md`
  （MOP2 だけは別記録: `tools/verification/results/mop2/evaluation.md`）
- 発表用の説明と質問対策: `docs/src/content/docs/presentation/`
