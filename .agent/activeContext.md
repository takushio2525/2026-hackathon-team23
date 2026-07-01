# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- MOP 検証システムの品質保証レビュー（MOP 別に順次実施中）
- MOP7（起動時間）レビュー完了・コミット・プッシュ済み

## 直近の観点

MOP7 レビューで修正した 4 点:
1. 指揮者 READY 条件: `beatNo>0`（ユーザー操作後）→ Calibrating 完了で Conducting/Menu 遷移（純粋な起動時間）
2. 楽器ノードに SYNC マイルストーン追加（時刻同期完了の計測が欠落していた）
3. Python が device_ms を優先して起動時間を算出するよう改善
4. evaluation.md に検証方法の妥当性評価を記載

## 次の一手

- 残りの MOP レビュー（MOP6, MOP9 等）を順次実施
- 実機テストで MOP7 の READY millis 値を確認し evaluation.md に記録

## 現フェーズで Read すべき設計書

- MOP 検証方法: `.agent/api.md` の MOP 定義
- ファーム構造: `.agent/architecture.md`
