# design_draft — 事前課題（基本設計・詳細設計）の Markdown 下書き

ハッカソン1 の事前課題「担当箇所の基本設計・詳細設計 原案作成」
（2026-04-29 09:00 締切）に向けた下書き置き場。

## スコープ

- 塩澤担当: Arduino 系プログラム全般（`firmware/common/`、`firmware/node_01`〜`firmware/node_05`）
- 指揮者ノード（IMU ジェスチャ認識）と楽器ノード（パート演奏）の双方をカバーする
- 設計書としての最終提出物は **PDF + TeX ソース** だが、内容合意までは Markdown で進める

## ファイル

| ファイル / ディレクトリ | 役割 |
|---|---|
| `design.md` | 索引（タイトル・目次・トピック別参照先）。本文は持たない |
| `sections/NN_name.md` | 本文（章ごとに 1 ファイル）。LaTeX 化時は `doc/sections/*.tex` に 1 対 1 で移植する想定 |
| `figures/` | Mermaid / PlantUML / 画像素材の置き場（TeX 化時に再利用） |

## セクション一覧

| ファイル | 章 |
|---|---|
| `sections/01_overview.md` | 第1章 概要 |
| `sections/02_background.md` | 第2章 背景・課題 |
| `sections/03_purpose.md` | 第3章 目的 |
| `sections/04_requirements.md` | 第4章 要件分析（FBS / PBS / MOP） |
| `sections/05_architecture.md` | 第5章 システムアーキテクチャ |
| `sections/06_interface.md` | 第6章 共通インターフェース方針 |
| `sections/07_wbs.md` | 第7章 作業計画（WBS） |
| `sections/08_files.md` | 第8章 ファイル構成 |
| `sections/09_techstack.md` | 第9章 技術スタック |
| `sections/10_common_api.md` | 第10章 共通層 API 仕様 |
| `sections/11_node_conductor.md` | 第11章 指揮者ノード詳細設計 |
| `sections/12_node_performer.md` | 第12章 楽器ノード詳細設計 |
| `sections/13_verification.md` | 第13章 検証・妥当性確認 |
| `sections/14_limitations.md` | 第14章 制限事項・今後の課題 |
| `sections/99_appendix.md` | 巻末（改訂履歴・関連ドキュメント） |

## 進め方

1. `design.md` を章ごとに埋める（書いた → レビュー → 次章、のリズム）
2. 担当拡大や通信仕様などチーム合意が必要な論点は `docs/` 側と整合させる
3. 内容確定後、`report/` 配下で TeX 化して PDF を生成（別フェーズ）

## 不要になったら

事前課題提出・TeX 化完了後、このフォルダごと削除してよい。
