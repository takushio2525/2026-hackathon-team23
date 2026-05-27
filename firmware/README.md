# firmware — マイコン用ファームウェア（例）

このディレクトリは「**複数のマイコンを分担して開発するときのプロジェクト構成の例**」。

「ハッカソンで Arduino を何台か使い、それぞれ別の役割（センサ担当・表示担当・
通信担当など）をチームで分担したい」というケースを想定した雛形。ハードウェアを
使わない班は [`firmware/` ごと削除してよい](#使わない班は)。

## コーディング方針（本チームの決定事項）

本チームのファームウェアは、以下のリファレンス実装に**必ず**従って書く。

> **Embedded-Module-Architecture**
> <https://github.com/takushio2525/Embedded-Module-Architecture>

- **3 フェーズループ**（入力 → ロジック → 出力）で `loop()` を構成する
- 各機能は `IModule` インターフェース（`setup()` / `update()`）を実装した
  モジュールとして書く
- ノード内の共有状態は `SystemData` 構造体に集約する
- ピン・定数・閾値などノード固有設定は `ProjectConfig` に集約する
- 周期実行は `ModuleTimer` を使い、`delay()` でブロックしない
- 新規モジュール追加時はリファレンスの `ARCHITECTURE.md` のチェックリストに従う

共通コード（UDP 層・時間管理・共有プロトコル定義など）は [`common/lib/`](common/lib/) に置き、
各ノードの `platformio.ini` から `lib_extra_dirs = ../common/lib` で参照する。

詳細と判断の背景は [ADR-0005](../docs/decisions/0005-firmware-embedded-module-architecture.md) を参照。

Arduino をベタ書きした経験しかないメンバーは、先にリファレンスの
`ARCHITECTURE.md` と `example/` 系コードを読んでから実装を始めること。

## 構成

```
firmware/
├── common/            # 全ノード共通のコード（例: 共有ライブラリ）
│   └── lib/
│       └── ExampleLibrary/   # 共通ライブラリの書き方サンプル
└── node_01〜05/       # 各マイコン 1台ごとの PlatformIO プロジェクト
    ├── platformio.ini     # ビルド設定
    ├── src/main.cpp       # エントリーポイント
    ├── include/           # ヘッダファイル置き場
    ├── lib/               # このノード固有のライブラリ
    └── test/              # ユニットテスト置き場
```

各ノードは **PlatformIO の新規プロジェクトを作った直後と同じクリーンな状態**
で用意してある。中身は自分たちのプロジェクトに合わせて書き換えていく。

## ノード数の調整

| 使う台数 | どうする |
|---|---|
| 5台 | そのまま |
| 3台 | `node_04/` `node_05/` を削除 |
| 1台 | `node_02/` 〜 `node_05/` を削除。`node_01/` を好きな名前にリネームしてもよい |
| 6台以上 | `node_05/` をコピーして `node_06/` などを作る |

## 役割分担表

| ノード | 役割 | ハードウェア | 担当者 | 備考 |
|---|---|---|---|---|
| node_01 | 指揮者 | Arduino Uno R4 WiFi（暫定） | 未定 | テンポ・拍の送信側 |
| node_02 | トランペット / 主旋律1 | Arduino Uno R4 WiFi（暫定） | 未定 | 0拍開始 |
| node_03 | ホルン / 主旋律2 | Arduino Uno R4 WiFi（暫定） | 未定 | 8拍開始 |
| node_04 | トロンボーン / 主旋律3 | Arduino Uno R4 WiFi（暫定） | 未定 | 16拍開始 |
| node_05 | チューバ / 低音伴奏 | Arduino Uno R4 WiFi（暫定） | 未定 | 0拍開始、40拍低音 |

楽器ノードの `include/score_data.h` はパートの音色IDと開始拍を持ち、
`src/score_data.cpp` は「かえるのうた」の楽譜を保持します。`node_02`〜`node_04`
は32拍の主旋律を共有し、`node_05` はホルンの終了まで続く40拍の低音を持ちます。

## ビルド方法

PlatformIO は VSCode 拡張として入れるのが簡単。

```bash
# 例: node_01 をビルドする
cd firmware/node_01
pio run                 # ビルドのみ
pio run -t upload       # 書き込み
pio device monitor      # シリアルモニタ
```

各ノードの詳細は `firmware/node_XX/README.md` を参照。

## 共通ライブラリ

複数ノードで同じコードを共有したいときに [`common/lib/`](common/lib/) を使う。
詳細は [`common/README.md`](common/README.md)。

## 使わない班は

ハードウェアを使わない班・Arduino 以外を使う班は、**`firmware/` ディレクトリを
丸ごと削除してよい**。削除後に必要なら、自分たちの技術スタック用のフォルダを
作り直す（例: `app/`, `src/`, `backend/` など）。
