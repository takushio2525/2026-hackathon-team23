# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **2026-05-14**: AGENTS.md 中心構成への全面移行 + docs/ の Astro Starlight 化が完了。
  プレゼン本番（2026-07-01 成果発表会）に向けて、解説サイトの公開準備フェーズ。

## 直近の観点

1. AGENTS.md / `.agent/` / CLAUDE.md=`@AGENTS.md` への移行は push 済み（commit `b3f3b67`）
2. docs/ Starlight サイト（35 ページ）の初版が push 済み（commit `dc3da4f`）、ローカルで
   `cd docs && npm run dev` 起動可能
3. ルート README・CONTRIBUTING・サブ README は新 docs に整合済み（commit `09c530d`）

## 次の一手

- **公開先の決定**: GitHub Pages か Vercel か。決まれば `docs/astro.config.mjs` の
  `site` / `base` を埋め、GitHub Actions のデプロイワークフローを追加
- **チームレビュー**: 5/14 以降のミーティングでドキュメントサイトを共有し、
  メンバー視点でのフィードバックを反映
- **未公開 ADR**: 第 3 〜 4 回ミーティングで新規に決まった事項（MOP / V&V / TPM）が
  あれば、`docs/src/content/docs/decisions/0008-*.md` を追加
- **コンテンツ追補**: pc_app/test_v2 のスケッチを直接読みながら、`code/pc-app.md` の
  コード例を実装と完全一致させる（現状は読みやすさ優先で疑似コード気味）

## ユーザーの今回の好み

- 「ガッツリ行く」方針。プレゼン本番に耐える品質の解説サイトが必要
- チーム外＋初学者を主な聴衆に想定
- 既存資産（ADR 7 件・design/ 4 本）は活かして拡充

## 既知の論点

- 過去ログ（`work/` 配下・`meetings/0429_3回/事前課題共有/`）の旧 `docs/*.md` リンクは
  時系列スナップショットとして残置（リンク切れ許容）
- GitHub Pages 公開可否は未定（`astro.config.mjs` の `site` / `base` は当面コメントアウト）
- CONTRIBUTING.md は Git 特化版として残し、開発ガイド全般は Starlight 側を SSOT
- `code/pc-app.md` は実装と完全一致していない疑似コードを含む。スケッチが安定したら
  実コードに置き換える
