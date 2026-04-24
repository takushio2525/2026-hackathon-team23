# 2026 ハッカソン1 事前課題 — 基本設計・詳細設計 原案

- **対象**: 2026 ハッカソン1 チーム23 「Arduino オーケストラ」 firmware 全般
- **担当**: 塩澤匠生（学番: TODO）
- **版**: 0.2（2026-04-24、章単位ファイルに分割）
- **関連資料**:
  - プロジェクト全体像: [`docs/overview.md`](../../../../docs/overview.md)
  - 全体アーキ: [`docs/design/architecture.md`](../../../../docs/design/architecture.md)
  - 通信方針: [`docs/design/protocol.md`](../../../../docs/design/protocol.md)
  - 指揮ジェスチャ方針: [`docs/design/conductor_gesture.md`](../../../../docs/design/conductor_gesture.md)
  - 採用判断: [`docs/decisions/`](../../../../docs/decisions/)

## このファイルの役割

本ファイルは **索引（目次）** のみを保持する。各章の本文は
[`sections/`](sections/) 配下に章番号プレフィックス付きで 1 ファイルずつ配置している。
LaTeX 化時には `doc/sections/*.tex` に 1 対 1 で移植し、`\input{sections/xx_name}` で
並べる構成を想定している。

## 目次

### 第I部 基本設計（What / Why）

1. [概要](sections/01_overview.md)
2. [背景・課題](sections/02_background.md)
3. [目的](sections/03_purpose.md)
4. [要件分析（FBS / PBS / MOP）](sections/04_requirements.md)
5. [システムアーキテクチャ](sections/05_architecture.md)
6. [共通インターフェース方針](sections/06_interface.md)
7. [作業計画（WBS）とマイルストーン](sections/07_wbs.md)

### 第II部 詳細設計（How）

8. [ファイル構成](sections/08_files.md)
9. [技術スタック](sections/09_techstack.md)
10. [共通層 API 仕様](sections/10_common_api.md)
11. [指揮者ノード（node_01）詳細設計](sections/11_node_conductor.md)
12. [楽器ノード（node_02〜05）詳細設計](sections/12_node_performer.md)
13. [検証・妥当性確認（V&V / TPM）](sections/13_verification.md)
14. [制限事項・今後の課題](sections/14_limitations.md)

### 巻末

- [改訂履歴 / 関連ドキュメント一覧](sections/99_appendix.md)

## 全章の読み順

章は番号順に読むことを想定している（基本 → 詳細 → 検証 → 制限）。
個別の論点を参照したい場合は、以下のトピック索引を参照。

| 知りたいこと | 参照先 |
|---|---|
| 担当範囲・スコープ | [§1.2](sections/01_overview.md) |
| 担当拡大の経緯 | [§2.3](sections/02_background.md) |
| 全体ブロック図・データフロー | [§5](sections/05_architecture.md) |
| Embedded-Module-Architecture の採用方針 | [§5.4](sections/05_architecture.md), [§6](sections/06_interface.md) |
| UDP パケット形式（CTRL / BEAT / NOTE） | [§10.3](sections/10_common_api.md) |
| 拍検出・テンポ推定アルゴリズム | [§11.5, §11.6](sections/11_node_conductor.md) |
| 楽譜データ形式 | [§12.3](sections/12_node_performer.md) |
| 同期誤差などの目標値 | [§4.3 MOP](sections/04_requirements.md), [§13.4 TPM](sections/13_verification.md) |
| 未確定項目・リスク | [§14](sections/14_limitations.md) |
