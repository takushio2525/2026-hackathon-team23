# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- MOE/MOP 全 9 項目の検証プログラムを `tools/verification/` に新規作成
- serial_logger.py（ログ収集）+ analyze.py（解析・PASS/FAIL 判定）の 2 本構成
- MOP8 用検証ファーム（main_conductor_perf.cpp / main_instrument_perf.cpp）

## 次の一手

- 実機で全ノード SERIAL_DEBUG=1 にして検証テストを実行
- MOP2（音階誤差）は Processing 音声録音の手動テスト
- 発表会（2026-07-01）に向けた最終調整

## 現フェーズで Read すべき設計書

- プロトコル仕様: `.agent/api.md`
- ゲームモード設計: `.agent/test_v3-game-design.md`
