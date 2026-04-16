# firmware/common — 全ノード共通コードの置き場（例）

このディレクトリは「**複数のマイコンで同じコードを共有したいときはここに置く**」という**例**として用意されている。

各ノード（`node_01` ～ `node_05`）はデフォルトでは独立したプロジェクトになっており、
**ここにあるコードを自動で参照しているわけではない**。共有したくなったら各ノードの
`platformio.ini` に1行足す、という使い方をする。

## こんなときに使う

- 複数マイコン間で同じ通信プロトコル実装を共有したい
- 定数（プロトコルIDやパケットサイズ等）を1ヶ所で管理したい
- チームで「共通基盤」を1人が作って、他の人が利用したい

## 各ノードから参照する方法

使いたいノードの `platformio.ini` に以下を追加する。

```ini
[env:uno_r4_wifi]
platform = renesas-ra
board = uno_r4_wifi
framework = arduino

; 共通ライブラリを読み込む
lib_extra_dirs = ../common/lib
```

PlatformIO は `lib_extra_dirs` で指定したディレクトリ配下のサブディレクトリを
すべてライブラリとして自動検出する。`#include "ExampleLibrary.h"` のように
ヘッダ名を直接書けばインクルードできる。

## 現在同梱されているサンプル

| パス | 内容 |
|---|---|
| `lib/ExampleLibrary/` | 最小サンプル（`exampleAdd(a, b)` だけ）。書き方の雛形 |

詳細は [lib/README.md](lib/README.md) を参照。

## 不要な班は

共通ライブラリの仕組みを使わないなら `firmware/common/` ごと削除してよい。
各ノードの `platformio.ini` も触っていなければ影響はない。
