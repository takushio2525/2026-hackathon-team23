---
title: リポジトリの使い方
description: clone後に見る場所とproductionの入口
---

## 取得

```bash
git clone https://github.com/takushio2525/2026-hackathon-team23.git
cd 2026-hackathon-team23
git status
```

## 現行実装の入口

```text
firmware/production/              本番ファームウェア
pc_app/production/                本番Processingアプリ
pc_app/common/                    Processing共通タブ
tools/verification/               MOE/MOP検証
docs/src/content/docs/            このサイトの本文
```

`firmware/test_v1/`と`test_v2/`、対応する`pc_app`は参考実装です。
新規の機能追加やバグ修正ではproductionを基準にします。

## productionの構造

```text
firmware/production/
├── common/lib/           共通モジュール
├── node_01/              指揮者
├── node_01_devkitc/      指揮者の代替ボード版
├── node_02〜05/          金管4声
└── node_06/              ドラム
```

各ノードは`src/main.cpp`、`src/applyPattern.cpp`、`include/SystemData.h`、
`include/ProjectConfig.h`の順に読むと全体を追いやすくなります。
