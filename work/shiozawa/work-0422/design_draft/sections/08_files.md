# 8. ファイル構成

`firmware/` 配下は **「共通層」と「ノード別プロジェクト」** の 2 段構造にする。
EMA（Embedded-Module-Architecture）に準拠し、PlatformIO の `lib_extra_dirs` を使って
共通層を全ノードから参照する。

> **EMA の正本**: [`../../architecture_reference/ARCHITECTURE.md`](../../architecture_reference/ARCHITECTURE.md)
> 「レイヤー構成」「新規モジュール追加チェックリスト」を参照。
> 各モジュールは必ず `.h` と `.cpp` に分離する（循環依存回避のため）。

## 8.1 ディレクトリ構成

```text
firmware/
├── README.md
├── common/
│   ├── README.md
│   └── lib/
│       ├── ModuleCore/                # コア層（プロジェクト非依存）
│       │   ├── IModule.h              # IModule 抽象基底（init / updateInput / updateOutput / deinit）
│       │   └── ModuleTimer.h          # millis() ベースのノンブロッキングタイマー
│       ├── OrcProtocol/               # CTRL / BEAT / NOTE のパケット定義（共通ヘッダ・シリアライズ）
│       │   ├── OrcProtocol.h
│       │   └── OrcProtocol.cpp
│       └── OrcNetModule/              # WiFi 接続維持 + UDP 送受信（IModule 実装、入出力両方）
│           ├── OrcNetModule.h
│           └── OrcNetModule.cpp
├── node_01/                           # 指揮者ノード
│   ├── platformio.ini                 # lib_extra_dirs = ../common/lib, build_flags = -I include
│   ├── include/
│   │   ├── SystemData.h               # 各 {Module}Data を集約した SystemData 構造体
│   │   └── ProjectConfig.h            # 全モジュールの {MODULE}_CONFIG インスタンス + 共有バスピン
│   ├── src/
│   │   ├── main.cpp                   # 入出力モジュール配列・3 フェーズループ
│   │   └── applyPattern.cpp           # ロジック関数本体（拍検出 / テンポ推定 / 強弱 / 状態遷移）
│   └── lib/
│       ├── ImuModule/                 # 入力: IMU 読み取り
│       │   ├── ImuModule.h
│       │   └── ImuModule.cpp
│       ├── OrcSenderModule/           # 出力: CTRL / BEAT 送信
│       │   ├── OrcSenderModule.h
│       │   └── OrcSenderModule.cpp
│       └── StatusLedModule/           # 出力: 状態表示 LED
│           ├── StatusLedModule.h
│           └── StatusLedModule.cpp
├── node_02/                           # 楽器ノード A
│   ├── platformio.ini
│   ├── include/
│   │   ├── SystemData.h
│   │   ├── ProjectConfig.h            # part_id = 0x02、PC IP、開始ビート等
│   │   └── score_data.h               # パート A の楽譜（C 配列）
│   ├── src/
│   │   ├── main.cpp
│   │   └── applyPattern.cpp           # 楽譜進行・SelfRun 判定・発音フラグ
│   └── lib/
│       ├── OrcReceiverModule/         # 入力: CTRL / BEAT 受信
│       │   ├── OrcReceiverModule.h
│       │   └── OrcReceiverModule.cpp
│       ├── NoteSenderModule/          # 出力: NOTE 送信（PC 宛ユニキャスト）
│       │   ├── NoteSenderModule.h
│       │   └── NoteSenderModule.cpp
│       └── StatusLedModule/           # 出力: 状態表示 LED（node_01 と同実装、コピーで開始）
│           ├── StatusLedModule.h
│           └── StatusLedModule.cpp
├── node_03/                           # 楽器ノード B（構造同じ、ProjectConfig と score_data.h が差分）
├── node_04/                           # 楽器ノード C
└── node_05/                           # 楽器ノード D
```

## 8.2 EMA 準拠のための必須ルール

[`../../architecture_reference/ARCHITECTURE.md`](../../architecture_reference/ARCHITECTURE.md)
の「新規モジュール追加チェックリスト」と一致する手順で、新規モジュールを追加する。

1. `lib/{Name}Module/{Name}Module.h` — `{Module}Config` / `{Module}Data` 構造体 + クラス宣言
   - `<Arduino.h>` + `"IModule.h"` のみ include
   - `struct SystemData;` の **前方宣言** を書く（`SystemData.h` を include しない）
2. `lib/{Name}Module/{Name}Module.cpp` — `init()` / `updateInput()` or `updateOutput()` を実装
   - `"SystemData.h"` を include する（`ProjectConfig.h` は include しない）
3. `include/SystemData.h` — `{Module}Data` フィールドを追加
4. `include/ProjectConfig.h` — `{MODULE}_CONFIG` インスタンスを追加
5. `src/main.cpp` — モジュールインスタンスを生成し、`inputModules[]` または `outputModules[]`
   に追加（入出力両方なら両方の配列に登録）

## 8.3 platformio.ini の必須設定

各ノードの `platformio.ini` には以下を必ず含める（EMA 準拠の必須要件）。

```ini
[env:uno_r4_wifi]
platform = renesas-ra
board    = uno_r4_wifi
framework = arduino

build_flags =
    -I include              ; lib/ 内から include/SystemData.h を参照するために必須

lib_extra_dirs =
    ../common/lib           ; ModuleCore / OrcProtocol / OrcNetModule を共有

lib_deps =
    arduino-libraries/Arduino_LSM6DSOX
    ; WiFiS3 はボードコアに同梱
```

- `build_flags = -I include` を忘れると、`lib/{Name}Module/{Name}Module.cpp` から
  `#include "SystemData.h"` できずビルドエラーになる
- `lib_extra_dirs = ../common/lib` で共通層を全ノードに共有

## 8.4 共通層への昇格ポリシー

楽器 4 台（node_02〜05）は当面同一実装になるが、**初期は各ノードの `lib/` にコピーを置く**。
差分が出てこない（＝完全に重複している）ことが 2 ノード以上で確認された時点で
`firmware/common/lib/` に昇格させる。

- 共通層に置くもの（最初から）: `ModuleCore`, `OrcProtocol`, `OrcNetModule`
- 各ノード `lib/` に置くもの（最初）: `ImuModule`, `OrcSenderModule`, `OrcReceiverModule`,
  `NoteSenderModule`, `StatusLedModule`
- 昇格判断: 2 ノード以上で完全一致 + 6 週時点でも差分要望なし → `common/lib/` へ移動

## 8.5 テストファイル

PlatformIO の `test/` ディレクトリは共通層のみ整備し、ノード側は最小限に留める
（第 13.1 章参照）。

```text
firmware/common/test/
├── test_ModuleTimer/
├── test_OrcProtocol/
└── ...
```

各ノード側 `test/` は「ビルドが通ることの確認」のみで運用する。
