---
title: リポジトリ・マップ
description: 各ディレクトリに何が置いてあるか、責務を 1 行で
sidebar:
  order: 1
---

:::note[この章で分かること]
- リポジトリ全体のディレクトリ構成
- 各ディレクトリの責務（何を置くべきか / 置いてはいけないか）
- 「あの機能どこ？」の引き先
:::

:::tip[読了目安]
**約 5 分**。通読する必要はなく、必要なときに戻ってきてください。
:::

## トップレベル

```
2026-hackathon-team23/
├── AGENTS.md            ← AI 向けガイド（このリポジトリの規約集約）
├── CLAUDE.md            ← @AGENTS.md リダイレクト（Claude Code 用）
├── .agent/              ← AI 向け詳細仕様
├── docs/                ← このドキュメントサイトのソース (Astro Starlight)
├── README.md            ← 人間向けトップページ
├── CONTRIBUTING.md      ← 初学者向け Git ガイド
├── LICENSE              ← MIT
├── firmware/            ← マイコン用ファームウェア
├── pc_app/              ← Processing アプリ
├── hardware/            ← ハードウェア資料（回路図・部品表）
├── sound_lab/           ← 音色解析・JSON 定義
├── report/              ← LaTeX 報告書
├── meetings/            ← 議事録（PDF + Markdown）
├── presentation/        ← スライド
├── references/          ← 外部資料（授業配布物・データシート）
├── work/                ← メンバー個人作業
├── tools/               ← 補助スクリプト（解析・ベンチ）
└── assets/              ← プロジェクト固有データ（音素材・画像 etc）
```

## 各ディレクトリの詳細

### `AGENTS.md` / `.agent/` / `CLAUDE.md`

AI（Claude Code 等）向けの規約と詳細仕様。詳細は [AGENTS.md](https://github.com/takushio2525/2026-hackathon-team23/blob/main/AGENTS.md) 参照。

### `docs/`

このサイト（Astro Starlight）のソース。

| サブパス | 中身 |
|---|---|
| `docs/astro.config.mjs` | Starlight 設定（サイドバー定義） |
| `docs/src/content/docs/` | 全 Markdown ページ |
| `docs/src/styles/glass-pastel.css` | Glass Pastel カスタムテーマ |
| `docs/public/` | favicon 等の静的アセット |
| `docs/_migration/` | 旧 docs/ の Markdown（後日削除） |

### `firmware/`

マイコン用ファームウェア。3 段階構成（[三段階開発](/architecture/three-stages/) 参照）：

| サブパス | 中身 |
|---|---|
| `firmware/test_v1/` | 最初の同期検証版（C major 和音）|
| `firmware/test_v2/` | **現行・推奨**（きらきら星 3 声輪唱） |
| `firmware/production/` | 本番想定の素テンプレ |

各バージョン下の構造（test_v2 を例に）：

```
firmware/test_v2/
├── common/
│   └── lib/             ← 全ノード共有ライブラリ
│       ├── ModuleCore/
│       ├── OrcProtocol/
│       ├── OrcNetModule/
│       ├── StatusLedModule/
│       └── SerialDebug/
├── node_01/             ← 指揮者
│   ├── platformio.ini
│   ├── include/
│   │   ├── ProjectConfig.h
│   │   └── SystemData.h
│   ├── src/
│   │   ├── main.cpp
│   │   └── applyPattern.cpp
│   └── lib/             ← ノード固有モジュール（ImuModule, OrcSenderModule）
├── node_02/             ← 楽器 声部 1
├── node_03/             ← 楽器 声部 2
└── node_04/             ← 楽器 声部 3
```

詳しくは [firmware の歩き方](/code/firmware/) 参照。

### `pc_app/`

PC 側 Processing アプリ。firmware と同じ 3 段階構成：

| サブパス | 中身 |
|---|---|
| `pc_app/test_v1/orchestra_player/` | 旧版・サイン波合成 |
| `pc_app/test_v2/orchestra_resynth/` | **現行**・倍音 JSON + ADSR |
| `pc_app/production/example_sketch/` | 素テンプレ |

詳しくは [pc_app の歩き方](/code/pc-app/) 参照。

### `hardware/`

ハードウェア資料：

| サブパス | 中身 |
|---|---|
| `hardware/schematics/` | 回路図（KiCad） |
| `hardware/wiring/` | 配線図（Fritzing / 写真） |
| `hardware/datasheets/` | 部品データシート PDF |

### `sound_lab/`

音色合成の実験場：

| サブパス | 中身 |
|---|---|
| `sound_lab/analyzer/` | Python の FFT 解析スクリプト |
| `sound_lab/data/` | 音色 JSON 定義（`pc_app/test_v2` が読む） |
| `sound_lab/processing/instrument_player/` | 単音試聴用 Processing |
| `sound_lab/studio/` | ブラウザ編集 UI（実験中） |

### `report/`

公式報告書（LaTeX）：

| サブパス | 中身 |
|---|---|
| `report/main.tex` | 報告書本体 |
| `report/sections/` | 章別 TeX |
| `report/template/` | 提出テンプレ |
| `report/計画書テンプレート/` | 計画書テンプレ（zip 同梱） |

PDF はここでは中間生成物扱い（`.gitignore` で除外）。
詳しくは [LaTeX 報告書をコンパイルする](/guide/latex/) 参照。

### `meetings/`

議事録：

| サブパス | 中身 |
|---|---|
| `meetings/0415_1回/` | 第 1 回（キックオフ） |
| `meetings/0422_2回/` | 第 2 回（案の一本化） |
| `meetings/0429_3回/` | 第 3 回（事前課題共有） |
| `meetings/0506_4回/` | 第 4 回 |
| ... | 以降の回 |

各回に正規 PDF と AI 要約 Markdown が置かれる。

### `presentation/`

ハッカソン発表用スライド。発表ごとにフォルダを切る。

### `references/`

外部から与えられた参考資料（読み取り専用扱い）：

| サブパス | 中身 |
|---|---|
| `references/lectures/` | 授業配布資料 |
| `references/papers/` | 参考論文 |
| `references/datasheets/` | 部品データシート |

`docs/`（自分たちが書く）と `references/`（外から与えられる）の使い分けを徹底する。

### `work/`

メンバー個人の作業フォルダ：

```
work/
├── shiozawa/
│   ├── ai_declaration/         ← 生成 AI 利用申告書
│   ├── work-0422/
│   │   ├── architecture_reference/
│   │   ├── design_draft/
│   │   ├── wbs_proposal/
│   │   └── README.md
│   ├── work-0429/
│   └── work-0513/
├── umezawa/
└── ...
```

各メンバーが自由に使う。**他人のフォルダは勝手に触らない**。

### `tools/`

補助スクリプト：

| サブパス | 中身 |
|---|---|
| `tools/example_benchmark/` | 性能測定（同期誤差計測など）|
| `tools/example_analysis/` | データ解析 |

中身は使うときに実装。

### `assets/`

プロジェクト固有のデータアセット（音素材・画像・テストデータ等）。
用途に合わせて自由にリネームしても OK。

### `.github/workflows/`

CI 設定：

| ファイル | 内容 |
|---|---|
| `pio-build.yml` | `firmware/` 変更時に全ノードをビルド検証 |

## どこに何を置くか迷ったら

| やりたいこと | 置き場所 |
|---|---|
| マイコンコード | `firmware/test_v2/<node>/` |
| 共通ライブラリ | `firmware/test_v2/common/lib/<ModuleName>/` |
| PC アプリ | `pc_app/test_v2/<sketch>/` |
| 音色 JSON | `sound_lab/data/<id>.json` |
| メモ・個人作業 | `work/<your-name>/` |
| 報告書 | `report/` または `work/<your-name>/<task>/` |
| 議事録 | `meetings/<date>_<n>回/` |
| 外部資料の保管 | `references/` |
| スライド | `presentation/<date>/` |
| 解析スクリプト | `tools/` |

## 次に読むべきページ

- firmware の中身 → [firmware の歩き方](/code/firmware/)
- pc_app の中身 → [pc_app の歩き方](/code/pc-app/)
- バージョン差分 → [test_v1 / test_v2 / production の差分](/code/versions/)
