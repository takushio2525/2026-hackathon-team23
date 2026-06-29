---
title: ファームウェア概要
description: productionファームの共通構造と読み方
---

## ディレクトリ

`firmware/production/`には指揮者、代替指揮者、楽器5台、共通ライブラリがあります。

各ノードは同じ骨格です。

```text
node_XX/
├── include/ProjectConfig.h  固有設定
├── include/SystemData.h     共有状態
├── src/main.cpp             初期化と3フェーズループ
├── src/applyPattern.cpp     判断ロジック
├── lib/                     ノード固有モジュール
└── platformio.ini           ビルド設定
```

## 3フェーズループ

```cpp
void loop() {
  // 1. 入力モジュール
  // 2. applyPattern(SystemData&)
  // 3. 出力モジュール
}
```

入力は外界から`SystemData`へ書き、ロジックは`SystemData`だけを更新し、出力は状態を外界へ反映します。
モジュール同士を直接呼び出さないことで、通信・センサー・判断を分離しています。

## 読む順番

1. `README.md`でノードの目的を確認
2. `ProjectConfig.h`で固有値を見る
3. `SystemData.h`でデータの流れを把握
4. `main.cpp`でモジュール順を確認
5. `applyPattern.cpp`で状態遷移を追う
6. 必要なモジュールだけ読む
