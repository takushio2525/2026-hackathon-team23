# 2026-hackathon-team23 — エージェント向けガイド

Arduino オーケストラ（指揮者ノード 1 台 ＋ 楽器ノード 3〜5 台 ＋ Processing PC アプリ）を
ハッカソンで実装するための共同開発リポジトリ。本ファイルは AI エージェント向けの
規約集約点。詳細仕様は `.agent/` に分割してある。

> 楽器ノードの台数は段階で異なる: **test_v2（現行）は 3 台**（`node_02〜04`、輪唱 3 声部）、
> **production（本番想定）は 5 台**（`node_02〜06`、金管 4＋ドラム）。新規ドキュメントは
> 「現行 3 台／本番想定 5 台」を併記する。

> 人間向けの解説（プロジェクト概要・開発手順・コード読み方）は `docs/` 配下の
> Astro Starlight サイトを参照。`cd docs && npm run dev` で http://localhost:4321 に立ち上がる。

## 概要

- 目的: 指揮者の IMU ジェスチャを起点に、楽器ノード 3〜5 台と PC 音色合成を UDP で同期させる
  （test_v2 は 3 台で輪唱を実装済み、production 想定は 5 台）
- 対象: 千葉工業大学 情報変革科学部 情報工学科 2 年生のハッカソン課題（チーム 23）
- 状況: test_v2 で「きらきら星」3 声輪唱が成立、production は素テンプレ。発表会 2026-07-01

## 技術スタック

| 領域 | 採用 | 補足 |
|---|---|---|
| ファームウェア | C++ (Arduino framework) | 指揮者: XIAO ESP32-S3 Sense + GY-521 / 楽器: Arduino UNO R4 WiFi |
| ビルドツール | PlatformIO | `platform = espressif32@6.10.0`（指揮者） |
| アーキテクチャ | Embedded-Module-Architecture | 3 フェーズループ・`IModule`・`SystemData`・`ProjectConfig` |
| 通信 | UDP マルチキャスト | `239.0.0.1:5001`、SoftAP `OrchestraAP/orchestra2026` |
| PC アプリ | Processing 4 | 音色合成・加算合成・JSON 楽器定義 |
| 報告書 | LaTeX (paperist/texlive-ja) | 一部 LuaLaTeX（Hiragino 依存） |
| 文書サイト | Astro Starlight | `docs/` 配下、Glass Pastel デザイン |
| CI | GitHub Actions | `.github/workflows/pio-build.yml` で全ノードビルド |

## ディレクトリ規約

```
2026-hackathon-team23/
├── AGENTS.md            ← AI 向けガイド（このファイル）
├── CLAUDE.md            ← @AGENTS.md リダイレクト
├── .agent/              ← AI 向け詳細仕様（このファイルから @import）
├── docs/                ← ユーザー向け Astro Starlight サイト
├── README.md            ← 人間向けトップ
├── CONTRIBUTING.md      ← Git 初学者向け開発ルール
├── firmware/            ← マイコンファーム
│   ├── test_v1/         ← 最初の同期検証版（C major 和音）
│   ├── test_v2/         ← きらきら星 輪唱（現行・推奨）
│   │   ├── common/lib/  ← 全ノード共有ライブラリ（ModuleCore, OrcProtocol, OrcNetModule 等）
│   │   ├── node_01/     ← 指揮者
│   │   └── node_02〜04/ ← 楽器（声部 1/2/3）
│   └── production/      ← 本番想定の素テンプレ（EMA 未適用）
├── pc_app/              ← Processing 4 アプリ（test_v1/test_v2/production 同構成）
├── hardware/            ← ハードウェア資料・回路図
├── sound_lab/           ← 音色定義 JSON・合成実験
├── report/              ← LaTeX 報告書テンプレ
├── meetings/            ← 議事録（PDF + Markdown）
├── presentation/        ← スライド
├── references/          ← 授業資料・先行調査
├── work/                ← メンバー個人の作業フォルダ（ai_declaration 等）
├── tools/               ← スクリプト・補助ツール
└── assets/              ← 共通画像など
```

各サブディレクトリには README.md があり、責務と「ここに置かないもの」を 1 行で示す。

## コマンド

| 用途 | コマンド |
|---|---|
| ファーム build（指揮者・test_v2） | `pio run -d firmware/test_v2/node_01` |
| ファーム upload | `pio run -d firmware/test_v2/node_01 -t upload` |
| シリアル監視 | `pio device monitor -d firmware/test_v2/node_01` |
| PC アプリ実行 | Processing 4 で `pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde` を開いて Run |
| LaTeX 報告書 build (Docker) | `cd report && docker run --rm -v "$(pwd):/workspace" -w /workspace ghcr.io/paperist/texlive-ja:debian latexmk main.tex` |
| LaTeX (LuaLaTeX, ローカル) | `latexmk -lualatex main.tex`（`% !TEX program = lualatex` 指定の .tex のみ） |
| 文書サイト dev | `cd docs && npm install && npm run dev` |
| 文書サイト build | `cd docs && npm run build`（`docs/dist/` 生成） |

CI（`.github/workflows/pio-build.yml`）が `firmware/` 変更時に全ノードを自動ビルドする。

## AI 向け詳細仕様

実装中に都度参照する詳細は `.agent/` に置いてある。**`@import` で常時展開すると毎ターン約 550 行をロードしてトークンを浪費するため、各仕様書はバックティック参照に留め、必要なときに Read で開く運用**。

- アーキテクチャ全体（EMA・3 段階開発・各ノード責務）: `.agent/architecture.md`
- 命名・コミット・LaTeX 運用・Git ワークフロー: `.agent/conventions.md`
- UDP プロトコル / SystemData / ProjectConfig: `.agent/api.md`

**読み込み指針**: タスクに直接関係するファイルだけ Read する。例えば「拍検出を調整する」なら `architecture.md` の拍検出節と `api.md` の `logic_params` 表を、「コミット規約を確認する」なら `conventions.md` を開く。全文を予防的にロードしない。

### 作業履歴メモ（毎ターン参照・更新）

- 現在の作業状況（毎ターン上書き）: @.agent/activeContext.md
- 完了タスクの時系列（毎ターン追記）: @.agent/progress.md

セッション開始時に必ず両方読み、応答終了前に `activeContext` を最新状態で**上書き**、
作業が一段落していれば `progress` の末尾に **1〜3 行で追記**する。
単発質問への回答やタイポ修正のみのターンでは更新しない。
詳細ルールはグローバル CLAUDE.md の「プロジェクト作業履歴メモ」節を参照。

## 組み込み固有ルール

- ターゲット:
  - 指揮者 `node_01`: **XIAO ESP32-S3 Sense**（`espressif32@6.10.0`、`seeed_xiao_esp32s3`）
  - 楽器 `node_02〜06`: **Arduino UNO R4 WiFi**
- ビルド: `pio run -d firmware/<version>/<node>`
- 書き込み: `-t upload` を付与。XIAO は USB Serial/JTAG（`upload_protocol = esp-builtin`）
- シリアル: `pio device monitor -d <path> -b 115200`、`SERIAL_DEBUG` マクロでログ出力切替
- LED: XIAO ESP32-S3 の `LED_BUILTIN`（GPIO21）は **active LOW**。HIGH 書き込みで消灯
- IMU 配線: D4(GPIO5)=SDA, D5(GPIO6)=SCL, AD0=GND（I2C 0x68 固定）

実機未テストの `.ino` / `.cpp` に Claude 起点で追加変更を入れないこと。
変更が必要なら必ず手元で `pio run` → 実機 upload までユーザー側で確認してから。

## 仕様書（ユーザー向け）

`docs/` に Astro Starlight で人間向けサイトを置く。

- 開発: `cd docs && npm run dev` → http://localhost:4321
- ビルド: `cd docs && npm run build` → `docs/dist/`
- 公開: 未定（GitHub Pages 採用時は `astro.config.mjs` の `site` / `base` を要設定）
- 規約: グローバル CLAUDE.md の Glass Pastel ニュートラル系（紙質感）に従う

## コミット規約

グローバル CLAUDE.md（`~/.claude/CLAUDE.md`）の「Git コミット」節に従う。
本リポジトリは原則 `main` 直プッシュ。詳細フロー（pull → commit → push）は
@.agent/conventions.md の Git 節を参照。
