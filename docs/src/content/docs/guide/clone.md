---
title: リポジトリを手元に持ってくる
description: clone、SSH 鍵の登録、ディレクトリ構成の確認まで
sidebar:
  order: 2
---

:::note[この章で分かること]
- GitHub からこのリポジトリを clone する手順
- SSH 鍵の作り方と登録方法
- clone 後の最初の動作確認
:::

:::tip[読了目安]
**約 15 分**（SSH 鍵を初めて作る場合）。
前提: Git をインストール済み（[必要なものをそろえる](/guide/setup/)）。
:::

## 1. リポジトリの URL を確認

GitHub のリポジトリページ右上の **「Code」** ボタンを押すと、HTTPS / SSH の URL が出る。

- HTTPS: `https://github.com/takushio2525/2026-hackathon-team23.git`
- SSH:   `git@github.com:takushio2525/2026-hackathon-team23.git`

**push する予定があるなら SSH 推奨**（毎回パスワードを聞かれない）。
clone だけで読み取り専用なら HTTPS で十分。

## 2. SSH 鍵を作る（初めての人向け）

### 2-1. 鍵を生成

ターミナルで：

```bash
ssh-keygen -t ed25519 -C "your.email@example.com"
```

質問が 3 つ出るが、すべて Enter で OK：

- `Enter file in which to save the key`: そのまま Enter（既定で `~/.ssh/id_ed25519`）
- `Enter passphrase`: 空 Enter or 任意のパスフレーズ
- `Enter same passphrase again`: 同上

完了後、`~/.ssh/id_ed25519`（秘密鍵）と `~/.ssh/id_ed25519.pub`（公開鍵）の 2 ファイルが
できる。**`.pub` の方だけを GitHub に登録する**。

### 2-2. 公開鍵をコピー

macOS:
```bash
pbcopy < ~/.ssh/id_ed25519.pub
```

Linux:
```bash
xclip -selection clipboard < ~/.ssh/id_ed25519.pub
```

Windows (PowerShell):
```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | Set-Clipboard
```

### 2-3. GitHub に登録

1. <https://github.com/settings/keys> を開く
2. 「**New SSH key**」ボタンを押す
3. **Title** に PC を識別できる名前（例: `MacBook Pro 2024`）
4. **Key** にクリップボードからペースト
5. 「**Add SSH key**」

### 2-4. 接続テスト

```bash
ssh -T git@github.com
```

`Hi <username>! You've successfully authenticated, ...` と出れば OK。
（初回は `Are you sure you want to continue connecting?` と聞かれるので `yes`）

## 3. リポジトリを clone する

### 推奨場所

```bash
mkdir -p ~/Documents
cd ~/Documents
```

任意の場所で良いが、本ドキュメントは `~/Documents/2026-hackathon-team23/` を前提に書く。

### clone コマンド

```bash
git clone git@github.com:takushio2525/2026-hackathon-team23.git
cd 2026-hackathon-team23
```

HTTPS の場合：

```bash
git clone https://github.com/takushio2525/2026-hackathon-team23.git
cd 2026-hackathon-team23
```

clone には 1 分前後かかる（リポジトリサイズによる）。

## 4. ディレクトリ構成を眺める

```bash
ls -la
```

主要なフォルダ：

| フォルダ | 中身 |
|---|---|
| `AGENTS.md` | AI 向けガイド |
| `README.md` | 人間向けトップ |
| `firmware/` | マイコン用コード（test_v1 / test_v2 / production） |
| `pc_app/` | Processing アプリ |
| `hardware/` | ハードウェア資料 |
| `docs/` | このドキュメントサイトのソース |
| `report/` | LaTeX 報告書 |
| `meetings/` | 議事録 |
| `work/` | メンバー個人の作業フォルダ |
| `sound_lab/` | 音色 JSON 定義・合成実験 |

詳しくは [リポジトリ・マップ](/code/map/) を参照。

## 5. ブランチを確認

```bash
git branch
# 出力例: * main
```

`main` ブランチにいるはず。本リポジトリは原則 `main` 直接コミットの運用なので、
**ブランチを切らずに作業して OK**（大規模変更時のみブランチ）。

詳しくは [チームで Git を使う](/guide/git/) を参照。

## 6. リモート確認

```bash
git remote -v
# 出力例:
# origin  git@github.com:takushio2525/2026-hackathon-team23.git (fetch)
# origin  git@github.com:takushio2525/2026-hackathon-team23.git (push)
```

`origin` という名前で GitHub が登録されている。

## 7. 最新状態に追従する

clone 直後は最新だが、しばらく作業を離れていたら：

```bash
git pull --rebase origin main
```

`--rebase` は本プロジェクトの推奨フロー。マージコミットを残さず履歴がきれいになる。

## トラブル

### `Permission denied (publickey)` と言われる

- SSH 鍵が GitHub に登録されていない
- 別の鍵を生成してしまった（`~/.ssh/id_ed25519` 以外）

確認：
```bash
ssh -vT git@github.com
```

ログを見ると「どの鍵を試しているか」が分かる。

### clone が途中で止まる

ネットワーク不安定 or リポジトリが大きい場合：

```bash
git clone --depth 1 git@github.com:takushio2525/2026-hackathon-team23.git
```

`--depth 1` で履歴を最新 1 つだけ取得すると軽い。
履歴が必要になったら `git fetch --unshallow`。

### Windows で改行コードの警告

`warning: LF will be replaced by CRLF` が出ても無視で OK。
本リポジトリは `.gitattributes` で適切に管理している。

## 次に読むべきページ

- Arduino を書き換える → [Arduino を書き換える](/guide/firmware/)
- PC アプリを動かす → [PC アプリを動かす](/guide/processing/)
- Git の使い方 → [チームで Git を使う](/guide/git/)
