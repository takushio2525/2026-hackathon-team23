# `.agent/` — AI 向け詳細仕様

このディレクトリは AI エージェント（Claude Code 等）が実装中に参照する
詳細仕様の置き場。**人間向けの解説**は `docs/`（Astro Starlight）にある。

## 構成

### 静的な仕様（プロジェクトの不変部分）

| ファイル | 内容 |
|---|---|
| `architecture.md` | Embedded-Module-Architecture、3 段階開発（test_v1/test_v2/production）、各ノードの責務、同期戦略 |
| `conventions.md` | 命名規則、コメント言語、ログ、Git ワークフロー、LaTeX 編集ルール |
| `api.md` | UDP プロトコル（CTRL/BEAT/NOTE）、SystemData/ProjectConfig 構造、score_data フォーマット |

### 動的な作業文脈（毎ターン参照・更新）

| ファイル | 内容 | 更新モード |
|---|---|---|
| `activeContext.md` | 現在の対象・直近の観点・次の一手 | 毎ターン**上書き** |
| `progress.md` | 完了タスクの時系列 | 毎ターン**追記** |

詳細運用ルールは AGENTS.md の「作業履歴メモ」節、およびグローバル CLAUDE.md
（`~/.claude/CLAUDE.md`）の「プロジェクト作業履歴メモ」節を参照。
