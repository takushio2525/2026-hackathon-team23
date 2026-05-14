---
title: よく出るトラブルと対処
description: ビルド・書き込み・通信・音色まわりの詰まりどころと解決
sidebar:
  order: 5
---

:::note[この章で分かること]
- 「動かない」と思ったとき何を確認するか
- エラーメッセージから原因を推定する手順
- リカバリ方法
:::

:::tip[読了目安]
**約 8 分**。詰まったときに該当箇所だけ読めば OK。
:::

## ビルド

### `fatal error: Network.h: No such file or directory`

- 原因: `platformio.ini` の `platform` バージョンが新しすぎて Arduino-ESP32 v3.x が
  要求する `Network.h` が解決できていない。
- 対処: `platform = espressif32@6.10.0` に固定する。

### `'IModule' does not name a type`

- 原因: 共通層 (`common/lib/ModuleCore/`) のヘッダパスが通っていない。
- 対処: `platformio.ini` の `build_flags` に `-I ../common/lib/ModuleCore` を追加、
  `lib_extra_dirs = ../common/lib` を確認。

### `multiple definition of ...`

- 原因: ヘッダに関数の実体を書いてしまった（`inline` 忘れ）。
- 対処: `.h` には宣言、`.cpp` に実体。インライン関数化したいなら `inline` を付ける。

### ライブラリのダウンロードが終わらない

- 原因: 初回ビルドで PlatformIO が依存を取得中。
- 対処: 5〜10 分待つ。それでも進まないなら `~/.platformio/` を一度消して再試行。

## 書き込み

### `Could not open port /dev/cu.usbmodem...`

- 原因: 他のターミナル / Processing がポートを開いている。
- 対処: `pio device monitor` を `Ctrl+C` で閉じる、Processing を停止する。

### XIAO がポートに出てこない

- 原因 1: BOOT ボタンを押した状態で USB を挿してフラッシュモードに入っている。
- 対処 1: BOOT を離した状態で USB を抜き挿し。

- 原因 2: USB ケーブルが充電専用。
- 対処 2: データ通信対応のケーブルに交換。

### Arduino UNO R4 WiFi が反応しない

- ボード上の RESET ボタンを 2 回素早く押すと DFU モードに入る。
- それでもダメなら PlatformIO の `.pio/` を削除して再ビルド。

### 書き込みが「Connecting...」で止まる（XIAO）

- 内蔵 USB Serial/JTAG が一時的に応答しないとき：
  1. BOOT ボタンを押しながら RESET を押す
  2. BOOT を離す（フラッシュモード）
  3. `pio run -d ... -t upload` を再実行
  4. 完了後 RESET ボタンを押して通常起動

## 通信・同期

### 楽器の LED が高速点滅したまま

- 原因 1: 指揮者の SoftAP が立ち上がっていない。
- 対処 1: 指揮者ノードを先に起動。`pio device monitor` で `[N1 EVT WIFI] connected=1` を待つ。

- 原因 2: SSID / pass のミスマッチ。
- 対処 2: `ProjectConfig.h` の `ORC_NET_CONFIG` を全ノードで確認。デフォルト値は
  SSID `OrchestraAP`、pass `orchestra2026`。

- 原因 3: WiFi チャネル 6 の混雑。
- 対処 3: `ORC_NET_CONFIG.channel` を 1 or 11 に変更（全ノード一斉に）。

### 拍が検出されない

シリアルログ（`SERIAL_DEBUG=1`）を見ながら：

| 観測 | 原因 | 対処 |
|---|---|---|
| `imu=0` | IMU との I2C 通信失敗 | 配線確認、AD0 が GND につながっているか |
| `dyn` がずっと 0 付近 | キャリブレーション値がずれている | 静止状態でリセット |
| `dyn` が 1.0 程度で頭打ち | 振りが弱い or 閾値が高い | `BEAT_DYN_THRESHOLD_G` を下げる |
| Armed に入るが `path` が伸びない | 振りが短い | 大きく振る or `BEAT_FIRE_PATH_M` を下げる |

### 楽器の発音が遅れる・ずれる

- 原因 1: `playAtMasterMs` 先読みが届かない（ネットワーク遅延 > 50 ms）。
- 対処 1: 同じ WiFi ルータ下にいるか、混雑していないか確認。

- 原因 2: 楽器の時刻オフセット EMA が収束していない（起動直後）。
- 対処 2: 起動から 2〜3 秒待ってから振り始める。

### 音が二重に鳴る

- 原因: BEAT 2 連送の重複検知が効いていない。
- 対処: 楽器側で `beatNo` の重複チェックが入っているか確認。`OrcReceiverModule` の
  処理を見直す。

### CTRL / BEAT は届いているが NOTE が来ない

- 原因: 楽器ノードの `SERIAL_DEBUG` が 1 になっていて、テキスト出力がバイナリと混在。
- 対処: 楽器ノードの `platformio.ini` で `-DSERIAL_DEBUG=0` を確認、書き直す。

## PC アプリ

### Processing でシリアルポートが空

- 原因 1: ボードを USB で繋いでいない。
- 対処 1: USB ケーブルを挿す。

- 原因 2: macOS のセキュリティで「未承認デバイス」になっている。
- 対処 2: システム設定 → セキュリティとプライバシー → 「許可」をクリック。

### 音が出ない

- 原因 1: シリアルポート選択が間違っている。
- 対処 1: `pio device list` で楽器ノードのポートを確認し、スケッチの `PORT_INDEX` を合わせる。

- 原因 2: Minim / Sound ライブラリが入っていない。
- 対処 2: Processing → スケッチ → ライブラリをインポート → Minim / Sound を追加。

- 原因 3: PC のオーディオデバイスが間違っている。
- 対処 3: PC の音声出力を内蔵スピーカに設定。

### パチパチノイズが入る

- 原因: ADSR の `attack` が短すぎて発音立ち上がりがクリップ。
- 対処: 音色 JSON の `adsr.attack` を 0.01 → 0.03 程度に伸ばす。

### 音が割れる

- 原因: 複数 `Voice` を重ねたときに合計振幅が 1.0 を超える。
- 対処: 全体ゲインを 0.5 に下げる、`Voice` 数の上限を制限。

## LaTeX 報告書

### Docker が起動していない

```bash
docker info > /dev/null 2>&1 || (open -a Docker && until docker info > /dev/null 2>&1; do sleep 2; done)
```

を `latexmk` の前に挟めば自動起動。

### 日本語フォントエラー（LuaLaTeX）

`% !TEX program = lualatex` 指定のファイルは Docker でなく **ローカルで** コンパイル：

```bash
latexmk -lualatex main.tex
```

macOS で LaTeX が入っていなければ `brew install --cask mactex`。

### 図が見つからない

`\includegraphics{path}` の path は `main.tex` から見た相対パス。
階層がズレていないか確認。

## Git

### `Permission denied (publickey)`

SSH 鍵が登録されていない or 別の鍵が使われている。
→ [リポジトリを手元に持ってくる](/guide/clone/) の SSH 鍵節を参照。

### 衝突解消で迷子

```bash
git rebase --abort
```

で pull する前に戻して、Slack で相談。

### `git push` が `non-fast-forward` で拒否される

リモートに自分が持っていないコミットがある：

```bash
git pull --rebase origin main
# 衝突解消して
git push origin main
```

### 間違えて `git add .` してしまった

```bash
git reset                # 全部ステージ解除
git add 必要なファイル    # 個別に追加
```

`git commit` 前なら破壊的でないので安全。

## それでも解決しないとき

- Slack の `#team23` で具体的なエラーログを貼って相談
- ミーティングで議題にする
- AGENTS.md の規約に従って ADR / 議事録に記録（再発防止）

ログを貼るときは：

- 何をしようとしたか（コマンド）
- 何が起きたか（出力）
- どんな状態（OS、ボード、ネット環境）

の 3 点セットで投げると解決が早い。

## 次に読むべきページ

- 全体に戻る → [ようこそ](/)
- リポジトリの全体像 → [リポジトリ・マップ](/code/map/)
