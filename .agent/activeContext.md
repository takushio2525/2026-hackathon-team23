# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- MOP 検証システムの全面リファクタを実施（3層: ファーム / Python / ディレクトリ構造）
- 全コミット完了・main にプッシュ済み

## 完了した作業

1. `tools/verification/results/mop{1,3-9}/` にディレクトリ構造と evaluation.md テンプレを作成
2. `tools/verification/scripts/common.py` — ポート検出・NodeMapper（[N1 等から自動判定）・CSV/summary 書き出し
3. `tools/verification/scripts/mop{1,3-9}_*.py` — MOP ごとの専用計測スクリプト（全8本）
4. `firmware/production/common/lib/SerialDebug/MopTest.h` — MOP_TEST=N フラグ共通ヘッダ
5. 共通ライブラリに MOP3/4/5/6/9 出力を追加（OrcReceiverModule / NoteSenderModule）
6. 各ノード main.cpp に MOP1/5C/7/8 出力を追加
7. 全7ノード pio run SUCCESS 確認

## 次の一手

- platformio.ini に `-DMOP_TEST=N` を追加してビルド → 実機テスト（master 側作業）
- 実機テスト後に evaluation.md に結果を記録

## 現フェーズで Read すべき設計書

- MOP 検証方法: `.agent/api.md` の MOP 定義
- ファーム構造: `.agent/architecture.md`
