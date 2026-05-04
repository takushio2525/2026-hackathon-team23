# common/lib — 共通ライブラリ置き場

全ノードで共有するライブラリを置くディレクトリ。PlatformIO の `lib_extra_dirs`
で参照する想定。

## 現在のライブラリ

| ライブラリ | 概要 | 状態 |
|---|---|---|
| `ExampleLibrary/` | 書き方の最小サンプル（`exampleAdd(a, b)` だけ） | サンプル |

## ライブラリを追加する手順

1. `firmware/common/lib/XxxLibrary/` を作る（`Xxx` は PascalCase で分かりやすい名前）
2. `XxxLibrary.h`（宣言）と `XxxLibrary.cpp`（実装）を置く
3. 使いたいノードの `platformio.ini` に `lib_extra_dirs = ../common/lib` が
   書かれていることを確認する（書いていないノードからは読めない）
4. ノード側のコードで `#include "XxxLibrary.h"` と書いて使う
5. この README の表に追記する
6. PR を作ってチームで共有する

## コード規則（最低限）

- ヘッダ（`.h`）は `#pragma once` で先頭をガードする
- ヘッダには「**宣言**」だけを書き、実装は `.cpp` に分ける
- 依存するライブラリがあれば README に明記する

## ExampleLibrary が不要なら

`ExampleLibrary/` は単なる書き方の見本。プロジェクトで使わないなら削除してよい。
