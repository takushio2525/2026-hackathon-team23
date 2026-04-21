# docs — 設計ドキュメント

本チーム（Arduino オーケストラ）の設計ドキュメント置き場。

> **`report/` との違い**: `docs/` は開発中にチーム内で共有する Markdown メモ。
> `report/` は最終的に提出・印刷する報告書（LaTeX → PDF）。

## 主要ドキュメント

| パス | 内容 |
|---|---|
| [`overview.md`](overview.md) | プロジェクト概要・目標・評価軸・スケジュール |
| [`roles.md`](roles.md) | 役割分担（確定 / 未決） |
| [`design/architecture.md`](design/architecture.md) | システム全体構成（概略） |
| [`design/protocol.md`](design/protocol.md) | 通信方針（概略） |
| [`design/conductor_gesture.md`](design/conductor_gesture.md) | 指揮ジェスチャの方針 |
| [`design/score_format.md`](design/score_format.md) | 楽譜データの扱い（方針） |
| [`decisions/`](decisions/) | 設計判断記録（ADR） |

> 現時点では各設計ドキュメントは「大枠の方針」までを扱う。パケット構造・
> アルゴリズム・具体的なデータ構造などは、方針合意のあと実装フェーズで
> 各ドキュメントに追記する。

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
| [`decisions/0005-firmware-embedded-module-architecture.md`](decisions/0005-firmware-embedded-module-architecture.md) | ファームウェア設計：Embedded-Module-Architecture に準拠 |

## 更新ルール

- 設計を変更したら、対応するドキュメントを**同じ PR で**更新する
- 大きな設計判断は ADR を新規追加（既存 ADR は履歴として残す）
- 方針から詳細に落とすときは、該当ドキュメントの「未定」節を詰める形で更新する
