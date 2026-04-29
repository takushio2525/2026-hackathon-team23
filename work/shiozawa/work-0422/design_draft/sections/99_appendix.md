# 巻末

## 改訂履歴

| 版 | 日付 | 著者 | 変更内容 |
|---|---|---|---|
| 0.1 | 2026-04-24 | 塩澤匠生 | 原案作成（第I部 基本設計 / 第II部 詳細設計 / V&V / TPM まで初稿） |
| 0.2 | 2026-04-24 | 塩澤匠生 | 章単位ファイルに分割（`sections/` 構成へ） |
| 0.3 | 2026-04-24 | 塩澤匠生 | EMA（Embedded-Module-Architecture）の正本仕様に整合（IModule の 4 メソッド・入出力 2 配列・`SystemData`/`ProjectConfig` 集約方式・`include/` 配置・命名規則）。`architecture_reference/` を新設して EMA リポジトリの PDF / AI 用 Markdown を取り込み、関連ドキュメントとして参照 |

## 関連ドキュメント一覧

### 採用アーキテクチャ参照資料（本書の前提）

- [`../../architecture_reference/`](../../architecture_reference/) — Embedded-Module-Architecture
  リポジトリ由来の参照資料（README、AI 用 Markdown、PDF 3 種）を取り込み済み
  - [`../../architecture_reference/README.md`](../../architecture_reference/README.md)
  - [`../../architecture_reference/ARCHITECTURE.md`](../../architecture_reference/ARCHITECTURE.md)
  - [`../../architecture_reference/CLAUDE.md`](../../architecture_reference/CLAUDE.md)
  - [`../../architecture_reference/pdf/01_教科書.pdf`](../../architecture_reference/pdf/01_教科書.pdf)
  - [`../../architecture_reference/pdf/02_実装ガイド.pdf`](../../architecture_reference/pdf/02_実装ガイド.pdf)
  - [`../../architecture_reference/pdf/03_設計仕様書.pdf`](../../architecture_reference/pdf/03_設計仕様書.pdf)
- 採用元リポジトリ: <https://github.com/takushio2525/Embedded-Module-Architecture>

### プロジェクト内ドキュメント

- [`docs/overview.md`](../../../../docs/overview.md)
- [`docs/roles.md`](../../../../docs/roles.md)
- [`docs/design/architecture.md`](../../../../docs/design/architecture.md)
- [`docs/design/protocol.md`](../../../../docs/design/protocol.md)
- [`docs/design/conductor_gesture.md`](../../../../docs/design/conductor_gesture.md)
- [`docs/design/score_format.md`](../../../../docs/design/score_format.md)
- [`docs/decisions/0002-udp-original-protocol.md`](../../../../docs/decisions/0002-udp-original-protocol.md)
- [`docs/decisions/0003-conductor-imu.md`](../../../../docs/decisions/0003-conductor-imu.md)
- [`docs/decisions/0004-ensemble-structure.md`](../../../../docs/decisions/0004-ensemble-structure.md)
- [`docs/decisions/0005-firmware-embedded-module-architecture.md`](../../../../docs/decisions/0005-firmware-embedded-module-architecture.md)
