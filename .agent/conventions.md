# 規約 — 命名・コミット・LaTeX・Git ワークフロー

## 言語

- すべてのドキュメント・コミットメッセージ・コードコメントは **日本語**
- 例外なし。技術用語の英字（`IModule`、`SystemData`、`UDP` 等）はそのまま英字でよい

## コードスタイル

### C++ / Arduino

- 命名:
  - 型・クラス: `PascalCase`（`SystemData`, `OrcNetModule`）
  - 関数: `camelCase`（`updateInput`, `applyPattern`）
  - 変数: `camelCase`（`bpm`, `playAtMasterMs`）
  - 定数 / マクロ: `UPPER_SNAKE_CASE`（`I2C_SDA_PIN`, `SERIAL_DEBUG`）
  - グローバル変数の接頭辞: `g`（`gData`, `gImu`, `gNet`）
- ファイル名:
  - ヘッダ: `PascalCase.h`（`SystemData.h`, `ProjectConfig.h`）
  - 実装: `camelCase.cpp` または `PascalCase.cpp`（既存に合わせる）
- インクルードガード: `#pragma once`
- インデント: スペース 4
- コメント:
  - 何をしているかを書く必要はない（コードで分かる）
  - **なぜそうしているか**（経緯・閾値の根拠・代替案を捨てた理由）を書く
  - 既存のコメントが「経緯メモ」になっているのが標準（`logic_params` の閾値解説参照）

### Processing (.pde)

- 命名は Java 同様（`camelCase`）
- 1 スケッチ 1 フォルダ（`pc_app/test_v2/orchestra_resynth/` のように）
- 設定値はファイル上部に集約

### ロギング

- `SerialDebug` ライブラリの `DBG_PRINTF` / `DBG_PRINTLN` を使う
- 直接 `Serial.print()` は避ける（`SERIAL_DEBUG=0` で消せなくなる）
- 楽器ノード（node_02〜04）はデフォルト `SERIAL_DEBUG=0`
  （NOTE バイナリパケットを PC アプリに流すため、テキスト混在を避ける）
- 指揮者ノード（node_01）はデフォルト `SERIAL_DEBUG=1`（拍検出デバッグ用）

## Git ワークフロー

### 基本ルール

- **原則 `main` 直接コミット・プッシュ**
- ブランチを切るのは次のいずれかのときのみ:
  - 大規模変更（複数ファイルにまたがる機能追加・設計変更）
  - 他メンバーが同じ箇所を触っていて衝突が予想される
  - レビューを通してから取り込みたい
- 判断に迷ったら `main` 直で OK

### 標準フロー（毎回）

1. **pull**: `git pull --rebase origin <branch>` で衝突確認（初回プッシュ時は省略可）
2. **commit**: グローバル CLAUDE.md の `[種別] 概要` フォーマット、機能単位で細かく分割
3. **push**: `git push origin <branch>`
4. ブランチ作業ならブランチ作業を**完全に終えた段階**でマージ（or PR 作成）

プッシュまでを 1 つの変更の完了条件とみなす。コミットしただけで止めない。

### PR を作るタイミング

- **会話途中・作業未完了で勝手に PR を作らない**
- 「そのブランチでやることを全部やり切って、次の話題に移る」段階で初めて PR/マージ
- 継続作業の見込みがあるうちは push までで止める

### 手動変更の取り扱い

AI が編集していないファイルにも `git status` / `git diff` で差分が残っていないか必ず確認:

1. 差分を要約してユーザーに提示
2. コミット可否・別コミット分離・破棄を確認
3. コミットする場合は AI 編集分とは**別コミット**
4. `.vscode/`, `.env`, ローカル実験ファイルなどコミット可否が迷うものは必ず確認

### GitHub 設定

- 本リポジトリは PR マージ時に **リモートブランチ自動削除** が有効
- マージ後にローカルブランチが残っていたら `git branch -d <name>` で削除してよい

## コミットメッセージ

| 種別 | 用途 |
|---|---|
| `[機能追加]` | 新機能の実装 |
| `[修正]` | バグ修正 |
| `[改善]` | 既存機能の改善 |
| `[リファクタ]` | コード整理（機能変更なし） |
| `[ドキュメント]` | ドキュメントのみの変更 |
| `[スタイル]` | 見た目・UI の変更 |
| `[設定]` | 設定ファイル変更 |
| `[追加]` | 資料・素材の追加 |

- 機能単位で細かく分割（無関係な変更を 1 コミットに混ぜない）
- コード変更とドキュメント更新は**同一コミット**に含める

## LaTeX 編集の運用ルール

このリポジトリ内のすべての `.tex` プロジェクト（`report/`、`work/shiozawa/ai_declaration/`、
`work/*/...` 配下の作業 TeX）に適用。

### 1. Docker で自動コンパイルしてエラーゼロを確認

`.tex` が置かれているディレクトリ（`main.tex` と同階層）で:

```bash
docker info > /dev/null 2>&1 || (open -a Docker && until docker info > /dev/null 2>&1; do sleep 2; done)
docker run --rm -v "$(pwd):/workspace" -w /workspace \
  ghcr.io/paperist/texlive-ja:debian latexmk main.tex
```

コンパイルが通らないままコミットするのは禁止。

### 2. LuaLaTeX のみローカルコンパイル

`% !TEX program = lualatex` 指定の `.tex` は当面 Docker ではなくローカル
`latexmk -lualatex main.tex` でコンパイル（Hiragino フォント依存のため）。

### 3. 生成 PDF も同一コミットに含める

- `main.pdf`（または提出用にリネームした PDF）を必ず `git add`
- `.tex` の変更と PDF の更新は**同一コミット**にまとめる（分けない）
- プッシュまでを 1 セットで完了

理由: Docker 環境を持たないメンバーが提出物 PDF を確認できないと提出・レビューが止まる。

### 4. 中間ファイルはコミットしない

`.gitignore` で除外済み: `*.aux` / `*.log` / `*.fls` / `*.fdb_latexmk` / `*.synctex.gz` /
`*.dvi` / `*.out` / `*.toc`。コミット対象は `.tex` 一式と `*.pdf` のみ。

## 実機未テストコードへの介入禁止

実機未テストの `.ino` / `.cpp` には Claude 起点で追加変更を入れない。
変更が必要なら必ず手元で `pio run` → 実機 upload までユーザー側で確認してから。

理由: 拍検出・WiFi・I2C は実機特性に強く依存する。机上のロジック修正で挙動が
逆転する事故が過去にあった。

## ハードウェア注意点

### XIAO ESP32-S3 の LED は active LOW

- `LED_BUILTIN = GPIO21`
- `digitalWrite(LED_BUILTIN, HIGH)` で **消灯**、`LOW` で点灯
- `StatusLedConfig` の `activeLow=true` を設定済み
- 別ボードからコピーした「HIGH=点灯」前提のコードは挙動が逆転するので注意
