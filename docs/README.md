# docs — 設計ドキュメント

本チーム（Arduino オーケストラ）の設計ドキュメント置き場。

> **`report/` との違い**: `docs/` は開発中にチーム内で共有する Markdown メモ。
> `report/` は最終的に提出・印刷する報告書（LaTeX → PDF）。

## 主要ドキュメント

| パス | 内容 |
|---|---|
| [`overview.md`](overview.md) | プロジェクト概要・目標・評価軸・スケジュール |
| [`roles.md`](roles.md) | 役割分担（確定 / 未決） |
| [`design/architecture.md`](design/architecture.md) | システム全体アーキテクチャ |
| [`design/protocol.md`](design/protocol.md) | UDP 通信プロトコル仕様 |
| [`design/conductor_gesture.md`](design/conductor_gesture.md) | IMU → 指揮コマンドの写像 |
| [`design/score_format.md`](design/score_format.md) | 楽譜データフォーマット |
| [`design/data_flow.md`](design/data_flow.md) | データフロー（補足） |
| [`decisions/`](decisions/) | 設計判断記録（ADR） |

## ADR（Architecture Decision Record）

重要な設計判断を `decisions/NNNN-<title>.md` 形式で残す。
半年後に「なぜこうなっているのか」を読み返せるように、議論の背景と
代替案を残すのが目的。

| ADR | 内容 |
|---|---|
| [`decisions/0001-template.md`](decisions/0001-template.md) | テンプレート |
| [`decisions/0002-udp-original-protocol.md`](decisions/0002-udp-original-protocol.md) | 通信方式：UDP 独自プロトコル |
| [`decisions/0003-conductor-imu.md`](decisions/0003-conductor-imu.md) | 指揮入力：IMU ジェスチャ |
| [`decisions/0004-ensemble-structure.md`](decisions/0004-ensemble-structure.md) | 編成：指揮1+楽器4+輪唱曲 |

## 更新ルール

- 設計を変更したら、対応するドキュメントを**同じ PR で**更新する
- 大きな設計判断は ADR を新規追加（既存 ADR は履歴として残す）
- 仕様変更は `protocol.md` の変更履歴テーブルに必ず追記
