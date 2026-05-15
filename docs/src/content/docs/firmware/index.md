---
title: ファームウェア モジュール詳説
description: 各モジュールの責務・内部状態・処理フローを実コード基準で解説する深掘り章
sidebar:
  label: 読み順ガイド
  order: 0
---

:::note[この章で分かること]
- ファームウェアを構成する 9 つのモジュールが、それぞれどんな役割を持ち、どの順に呼ばれるか
- 各モジュールがどのフィールドを **読み** 、どのフィールドを **書く** か（SystemData 経由の責務境界）
- `main.cpp` から `applyPattern()` まで、1 ループ 5 ms の中で何が起きているか
:::

:::tip[読了目安]
**全 12 ページで約 90 分**。前提知識として [Embedded-Module-Architecture](/architecture/ema/) と
[firmware の歩き方](/code/firmware/) を先に通読すること。
:::

この章は「コードを読む」章を 1 段深く掘ったもの。`firmware/test_v2/` を実装基準として、
**モジュール 1 つにつき 1 ページ** ＋ **main.cpp 2 ノード分** を解説する。

## なぜモジュール単位で深掘りするのか

EMA は「モジュール同士の直接呼び出し禁止 / 通信は SystemData 経由のみ」という規約を強制する。
この規約のおかげで **モジュール 1 つを切り出して読めば全体が分かる** 構造になっている。逆に言うと、
モジュールの責務境界をきちんと押さえないと、`applyPattern.cpp` の判断ロジックがなぜそこに
書かれているのかが見えなくなる。

ここでは各モジュールを以下の観点で統一的に解説する。

| 観点 | 何を書くか |
|---|---|
| 実体ファイル | `.h` / `.cpp` の絶対パス |
| 責務 | 入力か出力か、どのハードウェア / プロトコルを担当するか |
| 構成データ | `Config` 構造体（コンパイル時定数）と `Data` 構造体（実行時状態） |
| `init()` | 初期化フロー（成功条件・失敗時の挙動） |
| `updateInput()` / `updateOutput()` | 1 ループでやること（読むフィールド・書くフィールド） |
| 内部状態 | モジュール内部に閉じた変数（クラス private） |
| 落とし穴 | ハードウェア依存・タイミング依存・実機で踏んだ罠 |

## 読み順（推奨）

### Step 1 — 共通基盤（全ノードで使う 5 モジュール）

| # | ページ | 役割 |
|---|---|---|
| 1 | [IModule と ModuleTimer](/firmware/imodule/) | 全モジュールが継承する抽象基底と、周期実行用ヘルパー |
| 2 | [OrcProtocol](/firmware/orc-protocol/) | 20 B 固定 UDP / シリアルパケットの構造体定義 |
| 3 | [OrcNetModule](/firmware/orc-net/) | WiFi 接続維持 + UDP マルチキャスト送受信 |
| 4 | [StatusLedModule](/firmware/status-led/) | 状態に応じた LED 点滅出力 |
| 5 | [SerialDebug](/firmware/serial-debug/) | `SERIAL_DEBUG` マクロで切替えるデバッグログ |

### Step 2 — 指揮者ノード固有（node_01）

| # | ページ | 役割 |
|---|---|---|
| 6 | [ImuModule](/firmware/imu-module/) | MPU6050 から加速度 / 角速度を 200 Hz で取得 |
| 7 | [OrcSenderModule](/firmware/orc-sender/) | `applyPattern()` の判断結果を CTRL / BEAT パケットに組み立てて送信予約 |

### Step 3 — 楽器ノード固有（node_02〜04）

| # | ページ | 役割 |
|---|---|---|
| 8 | [OrcReceiverModule](/firmware/orc-receiver/) | CTRL / BEAT 受信 → 時計同期 EMA → 保留 BEAT キュー |
| 9 | [NoteSenderModule](/firmware/note-sender/) | `applyPattern()` の発音判断を NOTE パケットに組み立てて USB シリアル出力 |

### Step 4 — 統合（main.cpp の処理フロー）

| # | ページ | 役割 |
|---|---|---|
| 10 | [main フロー（指揮者）](/firmware/main-conductor/) | XIAO ESP32-S3 の setup() / loop() / applyPattern() の流れ |
| 11 | [main フロー（楽器）](/firmware/main-instrument/) | UNO R4 WiFi の setup() / loop() / applyPattern() の流れ |

## モジュール一覧マップ

```
firmware/test_v2/
├── common/lib/                       (全ノード共有)
│   ├── ModuleCore/  ─────── IModule.h, ModuleTimer.h
│   ├── OrcProtocol/ ─────── 20 B パケット定義（Ctrl / Beat / Note）
│   ├── OrcNetModule/ ────── WiFi + UDP マルチキャスト
│   ├── StatusLedModule/ ── LED 点滅
│   └── SerialDebug/ ─────── デバッグマクロ
│
├── node_01/                          (指揮者: XIAO ESP32-S3 Sense)
│   ├── lib/ImuModule/        ─────── MPU6050 I2C 読み取り
│   ├── lib/OrcSenderModule/  ─────── CTRL / BEAT 送信
│   ├── include/SystemData.h
│   ├── include/ProjectConfig.h
│   └── src/{main.cpp, applyPattern.cpp}
│
└── node_02〜04/                      (楽器: Arduino UNO R4 WiFi)
    ├── lib/OrcReceiverModule/ ────── CTRL / BEAT 受信 + 時計同期
    ├── lib/NoteSenderModule/  ────── NOTE シリアル送信
    ├── include/SystemData.h
    ├── include/ProjectConfig.h
    ├── include/score_data.h
    └── src/{main.cpp, applyPattern.cpp, score_data.cpp}
```

## モジュールがフェーズに登場するタイミング

EMA の 3 フェーズループでは、各モジュールがどのフェーズで呼ばれるかが固定されている。
全モジュールを一覧にすると次のとおり。

| モジュール | ノード | 入力フェーズ | 出力フェーズ | 備考 |
|---|---|---|---|---|
| OrcNetModule | 共通 | ✓ | ✓ | 入力で受信、出力で送信。配列に 2 回入る |
| ImuModule | node_01 | ✓ | — | 5 ms 周期サンプル |
| OrcSenderModule | node_01 | — | ✓ | BEAT 発火 / 50 ms ごと CTRL |
| OrcReceiverModule | node_02〜04 | ✓ | — | 受信ペイロード → SystemData |
| NoteSenderModule | node_02〜04 | — | ✓ | pendingOn を NotePacket 化 |
| StatusLedModule | 共通 | — | ✓ | solidOn or 点滅周期に従う |

ロジック（`applyPattern()`）は入力フェーズと出力フェーズの **間** で 1 回だけ走る。
ここで状態機械の遷移、拍検出、楽譜進行などすべての判断が完結する。

## 各ページで読み解くポイント

### 「設定」と「状態」の二項対立

各モジュールには必ず 2 種類の構造体がペアで存在する。

| 役割 | 命名 | スコープ | 例 |
|---|---|---|---|
| **コンパイル時定数** | `〜Config` | `ProjectConfig.h` の `inline const` | `ImuConfig`、`OrcNetConfig` |
| **実行時状態** | `〜Data` | `SystemData` のフィールド | `ImuData`、`OrcNetData` |

`Config` を変えればハードウェアの挙動が変わる。`Data` は他モジュールが読み書きする共有ストレージ。
モジュール本体（`.cpp`）にハードコード値があってはいけない、というのが EMA の鉄則。

### 「読む / 書く」の方向性

モジュールは原則として **入力モジュールは Data に書く**、**出力モジュールは Data から読む**。
通信モジュール（OrcNetModule）と一部のロジック系モジュールだけが両方を持つ。

各ページでは「このモジュールはどのフィールドを書き、どのフィールドを読むか」を必ず列挙する。
責務境界を破ったコードを書きたくなったときに、この一覧を見れば矛盾が分かる。

### 落とし穴セクション

実機で踏んだ罠（USB CDC のホスト待機、UNO R4 の `Serial.printf` 不在、I2C クロックの初期化順、
LED の active LOW、`Wire.endTransmission(false)` の意味など）は各ページの末尾に「落とし穴」として
まとめてある。**ここを飛ばさないこと**。実装変更時に必ず引っかかる箇所。

## さらに深掘りしたい場合

- 内部アルゴリズム（拍検出・時刻同期・楽譜進行）の理論的根拠は
  [アルゴリズム詳説](/deep-dive/) を参照
- 新しいモジュールを追加する手順は [モジュール拡張ガイド](/deep-dive/module-extension/)
- バージョン差分（test_v1 → test_v2 → production）は [versions](/code/versions/)
