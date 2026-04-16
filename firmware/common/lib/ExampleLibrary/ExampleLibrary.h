// ExampleLibrary.h — 共通ライブラリの最小サンプル
//
// このファイルは「複数のマイコンで同じコードを共有したいとき、
// どういう形でライブラリを書けばよいか」の一例です。
//
// 使い方（例）:
//   #include "ExampleLibrary.h"
//   int v = exampleAdd(1, 2);
//
// 必要なくなったら ExampleLibrary/ ごと削除して、
// 自分たちのライブラリ名のディレクトリを新しく作ってください。
#pragma once

#include <stdint.h>

// 2つの整数を足した値を返すだけのサンプル関数
int32_t exampleAdd(int32_t a, int32_t b);
