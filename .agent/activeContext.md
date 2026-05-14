# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **2026-05-14**: グローバル CLAUDE.md の AGENTS.md 中心構成に追従する全面リファクタリング
- 同時にプレゼン本番（2026-07-01 成果発表会）に向けた解説資料整備

## 直近の観点

1. AGENTS.md と `.agent/` 体系を構築し、CLAUDE.md を `@AGENTS.md` リダイレクトに切替
2. `docs/` を Astro Starlight 化し、既存 Markdown（overview / roles / design / decisions）を統合
3. 初学者（チーム外・Git/PlatformIO/Processing 未経験）でも追える深さの解説ページ群を新規執筆
4. ルート README / CONTRIBUTING / .gitignore / 各サブ README を新 docs に整合

## 次の一手

- Phase A（AGENTS / `.agent/` 構築）→ 完了見込み
- Phase B（Starlight 化・既存退避・コンテンツ移植）
- Phase C（新規ページ執筆）
- Phase D（ビルド検証 & 整合性）
- Phase E（機能単位でコミット & プッシュ）

## ユーザーの今回の好み

- 「ガッツリ行く」方針。プレゼン本番に耐える品質の解説サイトが必要
- チーム外＋初学者を主な聴衆に想定
- 既存資産（ADR 7 件・design/ 4 本）は活かして拡充

## 既知の論点

- 過去ログ（`work/` 配下・`meetings/0429_3回/事前課題共有/`）の旧 `docs/*.md` リンクは
  時系列スナップショットとして残置（リンク切れ許容）
- GitHub Pages 公開可否は未定（`astro.config.mjs` の `site` / `base` は当面コメントアウト）
- CONTRIBUTING.md は Starlight 側「開発ガイド」を SSOT としつつ、誘導文書として残す
