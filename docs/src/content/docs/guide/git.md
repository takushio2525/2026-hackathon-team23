---
title: チームで Git を使う
description: pull → commit → push の基本フローと、衝突・PR の扱い
sidebar:
  order: 7
---

:::note[この章で分かること]
- 毎日使う pull / commit / push の手順
- 衝突したときの対処
- いつ PR を作ればいいか
:::

:::tip[読了目安]
**約 15 分**。前提: Git をインストール済み、リポジトリを clone 済み。
:::

## このリポジトリの方針

- **原則 `main` 直接コミット・プッシュ**
- ブランチを切るのは:
  - 大規模変更（複数ファイルにまたがる機能追加・設計変更）
  - 他メンバーが同じ箇所を触っていて衝突が予想される
  - レビューを通したい
- 判断に迷ったら `main` 直で OK

## 毎日のフロー

### 1. 作業開始前: pull

ターミナルで：

```bash
cd ~/Documents/2026-hackathon-team23
git pull --rebase origin main
```

- `--rebase`: マージコミットを残さず履歴を一直線に保つ
- 何もリモート変更がなければ `Already up to date.` と出る

### 2. 編集する

普通にファイルを編集する。

### 3. 変更を確認

```bash
git status
```

赤字（未追跡）/ 緑字（ステージ済み）のファイル一覧が出る。

差分を見るなら：

```bash
git diff                    # ステージ前の差分
git diff --staged           # ステージ後の差分
```

### 4. コミット

```bash
git add path/to/changed/file
git add another/file
git commit -m "[機能追加] 楽器ノードの拍検出ロジックを追加"
```

**`git add .` は使わない**。`.env` やローカル実験ファイルが混入する事故を避けるため、
個別にファイルを指定する。

#### コミットメッセージのフォーマット

```
[種別] 変更内容の概要
```

| 種別 | 用途 |
|---|---|
| `[機能追加]` | 新機能の実装 |
| `[修正]` | バグ修正 |
| `[改善]` | 既存機能の改善 |
| `[リファクタ]` | コード整理（機能変更なし） |
| `[ドキュメント]` | ドキュメントのみの変更 |
| `[スタイル]` | 見た目・UI の変更 |
| `[設定]` | 設定ファイル変更 |

機能単位で**細かく分割** する。1 コミットに無関係な変更を混ぜない。

### 5. push

```bash
git push origin main
```

これで GitHub に反映される。**コミットしただけで止めない**。push まで実行して 1 セット。

## 衝突したとき

`git pull --rebase` で次のように出たら：

```
CONFLICT (content): Merge conflict in firmware/test_v2/node_01/src/main.cpp
```

### 1. 衝突箇所を開く

衝突したファイルには次のような目印が入る：

```cpp
<<<<<<< HEAD
constexpr float BEAT_DYN_THRESHOLD_G = 1.20f;
=======
constexpr float BEAT_DYN_THRESHOLD_G = 1.30f;
>>>>>>> origin/main
```

- `<<<<<<< HEAD` 〜 `=======`: **自分の変更**
- `=======` 〜 `>>>>>>> origin/main`: **リモート（他人）の変更**

### 2. どちらを残すか決める

両方残す、片方だけ残す、新しい値にする、好きにマージ。
**目印行（`<<<`、`===`、`>>>`）は必ず削除する**。

### 3. 衝突を解消してマーク

```bash
git add firmware/test_v2/node_01/src/main.cpp
git rebase --continue
```

### 衝突が複雑で手に負えないとき

```bash
git rebase --abort
```

で pull する前の状態に戻して、Slack やミーティングで相談する。

## ブランチを切るとき

大規模変更や、衝突が予想される作業：

```bash
git checkout -b feature/new-instrument
# ... 編集 ...
git add ...
git commit -m "[機能追加] node_05 にドラムパートを追加"
git push -u origin feature/new-instrument
```

### マージするタイミング

そのブランチでやることを**全部やり切って、次の話題に移る**段階で初めてマージ：

```bash
git checkout main
git pull --rebase origin main
git merge feature/new-instrument
git push origin main
```

または GitHub で PR を作って Squash merge。

### PR を作る基準

- レビューを通したい変更
- 履歴に経緯（議論）を残したい変更
- 取り込み前にチーム合意が必要

それ以外（小さい変更・自分で完結する変更）は直マージで OK。

### PR の作り方

```bash
gh pr create --title "feat: ドラムパート追加" --body "node_05 にドラムを実装した"
```

または GitHub ウェブ UI から作成。

## 手動変更の取り扱い

`git status` で AI が編集していないファイルにも差分が見えたら：

1. 内容を確認: `git diff path/to/file`
2. 必要なら**別コミット**でコミット（AI の変更と混ぜない）
3. 不要なら破棄: `git restore path/to/file`

`.vscode/`、`.env`、ローカル実験ファイルなど判断が迷うものは無断でコミットしない。

## よくあるパターン

### 「コミットしたけど内容を間違えた」（push 前）

```bash
git commit --amend -m "正しいメッセージ"
```

ファイル差分を直したい場合は、編集してから：

```bash
git add path/to/file
git commit --amend --no-edit
```

### 「コミットしたけど push 前にやっぱり戻したい」

```bash
git reset --soft HEAD~1
```

`--soft` は変更内容はそのままで、コミットだけ取り消す。

### 「リモートで間違えたコミットを直したい」（push 後）

`git revert`（取り消しコミットを追加）が安全：

```bash
git revert <commit-hash>
git push origin main
```

`git reset --hard` + force push は危険なのでチームで相談してから。

### 「特定のファイルだけ過去状態に戻したい」

```bash
git checkout HEAD~1 -- path/to/file
```

## やってはいけないこと

- `git push --force` を `main` に対して使う
- `.env` / `credentials.json` 等のシークレットをコミット
- `git add -A` で不要ファイルごとコミット
- 衝突箇所の目印行を残したまま `git add`
- 動かないコードをコミット（最低限ビルドが通ること）

## 次に読むべきページ

- リポジトリ全体を眺める → [リポジトリ・マップ](/code/map/)
- ハマったとき → [よく出るトラブルと対処](/code/troubleshooting/)
