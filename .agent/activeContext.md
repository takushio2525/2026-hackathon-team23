# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **分岐していた Git 履歴を `main` へ統合・push 済み**（merge commit `4ba382b`）。共通祖先のない現行 `main` と退避側 398 コミットを `--allow-unrelated-histories` でマージし、week7〜9 の Processing 素材・議事録・個人作業成果物など、退避側だけにあった 112 ファイルを取り込んだ。
- 競合は `.agent/activeContext.md`、`.agent/progress.md`、`.gitignore` のみ。現行 `main` の公開化ポリシーを採用し、講義資料・昨年度スライド・計画書テンプレートなど `.gitignore` で除外される 24 件は再公開しない。
- マージ元 `codex/backup-main-before-sync-20260624-0100` は履歴保全のため維持する。

## 次の一手

- VS Code を再読み込みし、`main...origin/main` に ahead / behind がないことを確認する。
- 退避ブランチは履歴保全用として残している。不要と判断した段階で削除を検討する。

## 現フェーズで Read すべき設計書

- Git 操作: `.agent/conventions.md`
- Processing 音色データ作業: `pc_app/test_v3/orchestra_resynth/data/README.md`
- ゲームモード設計: `.agent/test_v3-game-design.md`
- プロトコル仕様: `.agent/api.md`

## ユーザーの好み

- 大規模作業は計画を作ってから着手。短い指示は行間を読み，前提のズレを感じたら着手前に指摘。
- 実機未テストの .ino/.cpp に Claude 起点で変更を入れたらコンパイル確認まで＝upload はユーザー。
