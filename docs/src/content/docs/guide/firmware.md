---
title: ファームウェアを書き込む
description: PlatformIOでproductionの各ノードをビルド・書き込みする
---

## ビルド

```bash
pio run -d firmware/production/node_01
pio run -d firmware/production/node_02
```

node_03〜06も同じ形式です。指揮者の代替ボード版は`node_01_devkitc`です。

## 書き込み

```bash
pio run -d firmware/production/node_01 -t upload
pio run -d firmware/production/node_02 -t upload
```

複数のUNO R4を接続している場合は、意図したポートへ書き込まれることを確認してください。

## シリアルログ

```bash
pio device monitor -d firmware/production/node_01 -b 115200
```

楽器ノードでは`SERIAL_DEBUG=0`が通常運用です。`1`にすると人間向けログへ切り替わり、
Processing用のNOTEバイナリは出ません。

## 変更する場所

| 変更 | 場所 |
|---|---|
| 閾値、ピン、ノード固有値 | `include/ProjectConfig.h` |
| 共有状態 | `include/SystemData.h` |
| 判断ロジック | `src/applyPattern.cpp` |
| 入出力処理 | `lib/<Module>/`または`common/lib/` |
| 楽譜 | `src/score_data.cpp` |

実機を使う変更は、ビルドだけで完了扱いにせず、書き込み後に動作を確認してください。
