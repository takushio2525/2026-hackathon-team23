# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **VS Code の Git 同期状態を復旧済み**。ローカル `main` と `origin/main` は共通祖先を持たない別履歴だったため、共有リポジトリの現行履歴である `origin/main`（`1dcdb4b`）へローカル `main` を合わせた。
- 同期前のローカル履歴（先頭 `3b16b5b`、398 コミット）は `codex/backup-main-before-sync-20260624-0100` に完全退避済み。必要なファイルだけ戻す場合はこのブランチを参照する。
- 現在 `git status --short --branch` は `## main...origin/main`（ahead / behind なし）。未コミット変更なし。

## 次の一手

- VS Code のソース管理ビューを再読み込みすれば、同期ボタンの `371↓ 398↑` 表示は消える。
- 退避ブランチ上だけに必要な変更が見つかった場合は、対象コミットまたはファイルを選んで現行 `main` へ取り込む。

## 現フェーズで Read すべき設計書

- Git 操作: `.agent/conventions.md`
- Processing 音色データ作業: `pc_app/test_v3/orchestra_resynth/data/README.md`
- ゲームモード設計: `.agent/test_v3-game-design.md`
- プロトコル仕様: `.agent/api.md`

## ユーザーの好み

- 大規模作業は計画を作ってから着手。短い指示は行間を読み，前提のズレを感じたら着手前に指摘。
- 実機未テストの .ino/.cpp に Claude 起点で変更を入れたらコンパイル確認まで＝upload はユーザー。
