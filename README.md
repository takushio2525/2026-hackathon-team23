# hackathon-team23 — Arduino オーケストラ

2026年度 千葉工大 ハッカソン1 **チーム23** のリポジトリ。

## 本チームの取り組み

**テーマ**: Arduino UNO R4 WiFi × 5台による **Arduino オーケストラ**

**システム構成**:

- **指揮者マイコン × 1**（IMU でジェスチャ認識・UDP で楽器へコマンド配信）
- **楽器マイコン × 4**（音符データ送出、金管楽器4声の輪唱）
- **PC (Processing)**（楽器マイコンから音符を受け取り音色合成・再生）

**独創性のポイント**: 指揮者 Arduino 内蔵の IMU で指揮棒ジェスチャを認識し、
**振る速度でテンポ・振幅で強弱・振動でビブラート**を表現する。

**通信方式**: UDP マルチキャスト（`239.0.0.1:5001`）。詳細は `docs/` サイトの「アーキテクチャ > 通信プロトコル」参照。

### チームメンバーと役割

| メンバー | 担当 |
|---|---|
| 塩澤匠生 | Arduino 系全般（node_01〜05 の firmware + 共通層） |
| 齋藤翔太 | 楽譜データ・音階生成ロジック検討 |
| 梅澤颯太 | Processing（音色合成・演奏再生） |
| 片岡聖・地曵賢人・御代川稜 | 議事録（持ち回り）|

詳細は `docs/` サイトの「役割と運用 > チーム役割」を参照。

### 📖 ドキュメントサイト（Astro Starlight）

プロジェクトの全体像・アーキテクチャ・開発手順・コード解説は
**`docs/` 配下に Astro Starlight サイト** として整備してある。

```bash
cd docs
npm install
npm run dev      # http://localhost:4321 を開く
```

サイト構成：

| セクション | 内容 |
|---|---|
| **はじめに** | プロジェクト概要・クイックスタート・用語集 |
| **コンセプト** | なぜ作るか・シナリオと体験・ゴールとスコープ |
| **アーキテクチャ** | 全体図・EMA・通信プロトコル・楽譜・同期戦略・三段階開発 |
| **開発ガイド** | 環境構築から書き込み・PC アプリ・Git まで初学者向けに |
| **コードを読む** | リポジトリマップ・firmware/pc_app の歩き方・トラブル集 |
| **意思決定の記録（ADR）** | 設計判断 7 件（プロトコル選択・IMU 採用・MOE 等） |
| **役割と運用** | チーム役割・ミーティングと提出スケジュール |

GitHub 上で Markdown ソースを直接読む場合は
[`docs/src/content/docs/`](docs/src/content/docs/) 配下を辿る。

---

## このリポジトリの土台について

本リポジトリは「共同開発のためのフォルダ構成」テンプレートを土台にしている。
以下はテンプレートとしての説明（Git/共同開発が初めてのメンバー向けの読み物）。

---

## 初めての人はここから

Git や共同開発が初めてなら、以下の順番で読むとスムーズに始められる。

| 順番 | 読むもの | 内容 |
|:---:|---|---|
| 1 | **この README** | テンプレートの全体像・クイックスタート |
| 2 | [CONTRIBUTING.md](CONTRIBUTING.md) | Git の初期設定・ブランチの使い方・PR の出し方（**初心者向けに丁寧に書いてある**） |
| 3 | 使うフォルダの `README.md` | 各フォルダの使い方（例: [`firmware/README.md`](firmware/README.md)、[`report/README.md`](report/README.md)） |

> 慣れている人は「[ブランチ戦略](CONTRIBUTING.md#2-ブランチ戦略)」以降を斜め読みでOK。

---

## 🚨 一番大事なこと

> **コード編集を始める前に、必ず `git pull` でリポジトリを最新化してください。**
>
> チームメンバーが push した変更を取り込まずに作業を始めると、
> 後でコンフリクト（衝突）が大量発生して時間を浪費します。
> 作業の最初に pull、これを徹底してください。
>
> 詳しい理由と具体的な手順は [CONTRIBUTING.md](CONTRIBUTING.md) を読んでください。

---

## このテンプレートの考え方

- 各フォルダは「**こう分担すると開発がしやすい**」という**例**
- 中身のコードは空 or 最小サンプル。**自分たちのプロジェクトに合わせて書き換える**
- いらないフォルダは削除してよい（`firmware/`、`pc_app/`、`hardware/`、`assets/` など、テーマ次第で不要になる）
- 各フォルダの `README.md` に「何のフォルダか・どう使うか・不要なら削除OK」が書いてあるので、迷ったらまずそれを読む

---

## クイックスタート

### Step 1. このテンプレートから新しいリポジトリを作る

1. GitHub でこのテンプレートリポジトリを開く
2. 右上の緑の **「Use this template」** → **「Create a new repository」** をクリック
3. Owner（組織 or 個人）とリポジトリ名を入力 → **「Create repository」**

### Step 2. 手元に clone する

```bash
cd ~/Documents               # 好きな場所に移動
git clone https://github.com/<あなたの組織名>/<新しいリポジトリ名>.git
cd <新しいリポジトリ名>
```

### Step 3. チームでルールに合意する

[CONTRIBUTING.md](CONTRIBUTING.md) をチーム全員で読み、ブランチ戦略と
コミットメッセージ規約に合意する。

### Step 4. 不要なフォルダを削除する

テーマ・技術スタックに合わせて**使わないフォルダを削除**する。
各フォルダの `README.md` の末尾に「不要な班は丸ごと削除してよい」と
書いてあるので、チームで相談して決める。

例：
- Web アプリ中心 → `firmware/`, `hardware/`, `pc_app/`, `assets/` を削除
- Arduino 中心 → `pc_app/` は残すかどうかチーム判断、`assets/` は設定値置き場に流用
- ゲーム中心 → `firmware/`, `hardware/` を削除、`assets/` は「マップ・シナリオ置き場」に流用

### Step 5. 自分たちのコードを書き始める

- WBS・ガントチャートの記入 → [`meetings/`](meetings/)
- 設計ドキュメント → [`docs/`](docs/)
- 実装 → 各フォルダの README を読んで、自分たちのプロジェクトに合うフォルダ構成に書き換えていく
- 報告書 → [`report/`](report/)（LaTeX）

---

## ディレクトリ構成

| ディレクトリ | 用途 | 例として示していること |
|---|---|---|
| [`firmware/`](firmware/) | マイコン用ファームウェア | **複数マイコンを分担開発**するときの構成（PlatformIO、node_01〜05） |
| [`pc_app/`](pc_app/) | PC 側のサブシステム | 本体とは別言語で GUI・可視化を作る場合の置き場 |
| [`sound_lab/`](sound_lab/) | 楽器音の解析・再現実験 | 音源を Python で解析 → インストゥルメント定義(JSON) → Processing で本物っぽく再合成 |
| [`hardware/`](hardware/) | 回路図・配線図・部品表 | ハードを使うときの資料一式の管理例 |
| [`assets/`](assets/) | プロジェクト固有のデータ | マップ・シナリオ・設定ファイル・テストデータなどの置き場 |
| [`tools/`](tools/) | 補助スクリプト | ベンチマーク・解析スクリプトの置き場 |
| [`docs/`](docs/) | 設計ドキュメント・ADR | 開発中の設計判断を Markdown で残す（チーム内共有用） |
| [`meetings/`](meetings/) | 議事録・WBS・ガント | 進捗管理ドキュメントのテンプレ |
| [`references/`](references/) | 外部から与えられた参考資料 | 授業資料・データシート・論文など（著作権に注意） |
| [`report/`](report/) | LaTeX 報告書 | 提出用 PDF 報告書の雛形（`docs/` とは別物。提出・印刷用） |
| `.devcontainer/` | LaTeX コンパイル環境 | VSCode の Dev Container 設定 |
| `.github/` | PR / Issue テンプレ、GitHub Actions | 自動化の例 |
| `.vscode/` | VSCode 推奨拡張・設定 | エディタ環境の共有 |

---

## 自動ビルドについて

### LaTeX 報告書

報告書の PDF は**手元で Docker を使ってコンパイル**する運用。

```bash
cd report
docker run --rm -v "$(pwd):/workspace" -w /workspace \
  ghcr.io/paperist/texlive-ja:debian latexmk main.tex
```

VSCode の Dev Container（`.devcontainer/`）を使えば、コンテナ内で自動コンパイルもできる。

### PlatformIO（Arduino ビルド）

`firmware/` の内容を push すると、全ノード（node_01〜05）のビルドが走る。
ビルドに失敗すると PR がブロックされる。

Arduino を使わない班は `.github/workflows/pio-build.yml` を削除してよい。

---

## 手元でのビルド

### ファームウェア（Arduino 使う班のみ）

VSCode に [PlatformIO 拡張](https://platformio.org/install/ide?install=vscode) を入れ、
`firmware/test_v2/node_01/`（きらきら星 輪唱の検証版）または
`firmware/production/node_01/`（素テンプレ）をフォルダとして開く。または：

```bash
# きらきら星 輪唱の検証版（指揮者: XIAO ESP32-S3 Sense + GY-521）
pio run -d firmware/test_v2/node_01
# 楽器ノードは node_02 / node_03 / node_04（PC 側は pc_app/test_v2/orchestra_resynth）
# 最初の同期検証版は firmware/test_v1/ にある

# 本番想定の素テンプレ
pio run -d firmware/production/node_01
```

### LaTeX 報告書

VSCode で `.devcontainer/` を **「Reopen in Container」** で開くのが一番楽
（LaTeX 環境がすべて含まれている）。または Docker を直接使う：

```bash
cd report
docker run --rm -v "$(pwd):/workspace" -w /workspace \
  ghcr.io/paperist/texlive-ja:debian latexmk main.tex
```

---

## 開発ルール

[CONTRIBUTING.md](CONTRIBUTING.md) を参照。Git / 共同開発が初めての人向けに、
clone から PR、コンフリクト解消までを丁寧に書いてある。

---

## その他のファイル

| ファイル | 内容 |
|---|---|
| [`AGENTS.md`](AGENTS.md) | AI エージェント（Claude Code 等）向けの規約集約点。技術スタック・コマンド表・コミット規約 |
| [`.agent/`](.agent/) | AI 向け詳細仕様（architecture / conventions / api / activeContext / progress） |
| `CLAUDE.md` | `@AGENTS.md` への 1 行リダイレクト |

---

## ライセンス

[MIT License](LICENSE)
